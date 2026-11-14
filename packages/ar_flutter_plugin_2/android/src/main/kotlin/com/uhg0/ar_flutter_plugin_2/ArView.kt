package com.uhg0.ar_flutter_plugin_2

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.media.Image
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.lifecycle.Lifecycle
import com.google.ar.core.Anchor.CloudAnchorState
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.NotTrackingException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.uhg0.ar_flutter_plugin_2.Serialization.deserializePoseParts
import com.uhg0.ar_flutter_plugin_2.Serialization.serializeHitResult
import com.uhg0.ar_flutter_plugin_2.Serialization.serializePose
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.arcore.canHostCloudAnchor
import io.github.sceneview.ar.arcore.fps
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.ar.node.CloudAnchorNode
import io.github.sceneview.ar.node.HitResultNode
import io.github.sceneview.gesture.MoveGestureDetector
import io.github.sceneview.gesture.RotateGestureDetector
import io.github.sceneview.math.Position
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import io.github.sceneview.model.ModelInstance
import io.github.sceneview.node.ModelNode
import io.github.sceneview.node.Node
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import io.github.sceneview.math.Position as ScenePosition
import io.github.sceneview.math.Rotation as SceneRotation
import io.github.sceneview.math.Scale as SceneScale
import io.github.sceneview.texture.ImageTexture
import io.github.sceneview.material.setTexture
import io.github.sceneview.ar.scene.PlaneRenderer
import io.flutter.FlutterInjector
import io.github.sceneview.node.CylinderNode
import io.github.sceneview.math.Direction
import io.github.sceneview.math.Rotation
import io.github.sceneview.math.Scale
import io.github.sceneview.math.colorOf
import io.github.sceneview.loaders.MaterialLoader
import com.google.ar.core.exceptions.SessionPausedException
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

class ArView(
    context: Context,
    private val activity: Activity,
    private val lifecycle: Lifecycle,
    messenger: BinaryMessenger,
    id: Int,
) : PlatformView {
    private val TAG: String = ArView::class.java.name

    companion object {
        // Quaternion.fromAxisAngle takes DEGREES in kotlin-math 1.5.x (it
        // multiplies by π/180 internally); gesture angles are radians.
        private const val RADIANS_TO_DEGREES = 57.2957795f
    }
    private val viewContext: Context = context
    private var sceneView: SafeARSceneView
    private val mainScope = CoroutineScope(Dispatchers.Main)
    private var worldOriginNode: Node? = null

    private val rootLayout: ViewGroup = FrameLayout(context)

    private val sessionChannel: MethodChannel = MethodChannel(messenger, "arsession_$id")
    private val objectChannel: MethodChannel = MethodChannel(messenger, "arobjects_$id")
    private val anchorChannel: MethodChannel = MethodChannel(messenger, "aranchors_$id")
    private val nodesMap = mutableMapOf<String, ModelNode>()
    private var planeCount = 0
    private var selectedNode: Node? = null
    private val detectedPlanes = mutableSetOf<Plane>()
    private val anchorNodesMap = mutableMapOf<String, AnchorNode>()
    private var showAnimatedGuide = true
    private var showFeaturePoints = false
    private val pointCloudNodes = mutableListOf<PointCloudNode>()
    private var lastPointCloudTimestamp: Long? = null
    private var lastPointCloudFrame: Frame? = null
    private var pointCloudModelInstances = mutableListOf<ModelInstance>()
    private var handlePans = false
    private var handleRotation = false
    private var isSessionPaused = false

    // Plane-finding mode the app asked for (handleInit). SceneView's
    // sessionConfiguration lambda re-applies this whenever it (re)creates
    // the session — a session born after handleInit, or recreated on
    // resume, must not boot back into DISABLED or no plane ever appears.
    private var desiredPlaneFindingMode = Config.PlaneFindingMode.DISABLED

    // Last ARCore frame produced by this view's own session.update() call
    // (see the onFrame lambda in handleInit). Gesture callbacks run on the
    // same UI thread between two frame updates, so this frame is still
    // valid while a drag hit-tests against it — used to glue moved nodes
    // back onto real planes.
    private var latestFrame: Frame? = null

    // Wall-clock stamp of the last delivered frame. Once frames stop
    // (camera/ARCore stall) the stale latestFrame poisons every acquire*
    // and hitTest call: a device run hung ~10 s inside acquirePointCloud
    // on a frame the render loop had stopped refreshing, and a
    // post-dispose acquireDepthImage segfaulted — both take the
    // frame==null path via freshFrame() instead.
    private var lastFrameAtMs = 0L
    private var lastStaleLogAt = 0L

    // Live TRACKING-plane snapshot for the onPlanesUpdate telemetry (Bug 2).
    // Keyed by the ARCore Plane (stable per-session reference). A fully-formed
    // floor stops appearing in getUpdatedTrackables once it is stable, but must
    // keep counting as "seen" — so we persist each plane here when it updates
    // and only drop it once it stops tracking. Read/merged on the frame thread.
    private val livePlanes = mutableMapOf<Plane, Map<String, Any>>()

    // Stable integer id per ARCore Plane, so the app's PlaneMemory can keep
    // per-plane history (smoothing + reclassification) across telemetry
    // frames. ARCore exposes no public trackable id, so we mint our own.
    // Keyed by value: ARCore hands out a NEW Plane wrapper for the same
    // native plane on every call (equals/hashCode compare the native
    // handle), so an identity map minted a fresh id every frame and broke
    // every per-id smoothing, lock and classification streak in Dart.
    private val planeIds = HashMap<Plane, Int>()
    private var nextPlaneId = 1

    // Last time each plane genuinely appeared in getUpdatedTrackables.
    // Stable planes keep re-emitting from the cache; freshMs tells Dart
    // which observations are real updates (see the payload builder).
    private val planeLastFreshAt = HashMap<Plane, Long>()

    // Sliding point-cloud buffer feeding refinePlane — a single frame's cloud
    // is too sparse for a confident RANSAC fit on weak sensors. Same
    // UI-thread-only contract as latestFrame / livePlanes.
    private val pointAccumulator = PointCloudAccumulator()
    private var lastAccumCloudTimestamp = -1L
    private var accumFrameCounter = 0

    // onPlanesUpdate goes out every 3rd rendered frame (10–20 Hz): the
    // Dart overlay rebuild is capped at 66 ms anyway, and decoding the
    // full plane payload at 30 Hz was measurable codec/gc pressure for
    // no visible gain.
    private var planesFrameCounter = 0
    private var firstFrameTraced = false
    private var frameErrorTraced = false
    private var frameErrorCount = 0

    // ── perf diagnostics (5 s summaries in ar_native_trace.log) ──
    private var perfWindowStartMs = 0L
    private var perfLastCallbackMs = 0L
    private var perfMaxGapMs = 0L
    private var perfStalls = 0
    private var perfCallbacks = 0
    private var perfCamFrames = 0
    private var perfLastCamTs = -1L
    private var perfLastTracking: TrackingState? = null

    private fun perfFrame(frame: Frame) {
        val now = SystemClock.elapsedRealtime()
        if (perfLastCallbackMs > 0) {
            val gap = now - perfLastCallbackMs
            if (gap > perfMaxGapMs) perfMaxGapMs = gap
            if (gap > 50) perfStalls++
        }
        perfLastCallbackMs = now
        perfCallbacks++
        if (frame.timestamp != perfLastCamTs) {
            perfLastCamTs = frame.timestamp
            perfCamFrames++
        }
        val tracking = frame.camera.trackingState
        if (tracking != perfLastTracking) {
            NativeTrace.log(
                viewContext,
                "arview: tracking ${perfLastTracking} -> $tracking reason=${frame.camera.trackingFailureReason} live=${livePlanes.size}",
            )
            perfLastTracking = tracking
        }
        if (perfWindowStartMs == 0L) perfWindowStartMs = now
        val win = now - perfWindowStartMs
        if (win >= 5000) {
            NativeTrace.log(
                viewContext,
                "arview: perf cbFps=${perfCallbacks * 1000 / win} camFps=${perfCamFrames * 1000 / win} maxGapMs=$perfMaxGapMs stalls=$perfStalls live=${livePlanes.size}",
            )
            perfWindowStartMs = now
            perfMaxGapMs = 0
            perfStalls = 0
            perfCallbacks = 0
            perfCamFrames = 0
        }
    }

    // Session identity for the config-time cache clears — see the
    // sessionConfiguration lambda. Plus diagnostic cadence counters and
    // one-shot wall logs (NativeTrace, ~5s cadence, never per-frame).
    private var lastConfiguredSession: Session? = null
    private var cloudLogFrameCounter = 0
    private var planeSnapFrameCounter = 0
    private var firstWallLogged = false
    private var firstPausedWallLogged = false

    private fun planeIdFor(plane: Plane): Int =
        planeIds.getOrPut(plane) { nextPlaneId++ }

    private class PointCloudNode(
        modelInstance: ModelInstance,
        var id: Int,
        var confidence: Float,
    ) : ModelNode(modelInstance)

    private val onSessionMethodCall =
        MethodChannel.MethodCallHandler { call, result ->
            val callStart = SystemClock.elapsedRealtime()
            handleSessionCall(call, result)
            val callMs = SystemClock.elapsedRealtime() - callStart
            if (callMs > 20) {
                NativeTrace.log(viewContext, "arview: slow call ${call.method} ${callMs}ms")
            }
        }

    private fun handleSessionCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "init" -> handleInit(call, result)
                "showPlanes" -> handleShowPlanes(call, result)
                "dispose" -> dispose()
                "getAnchorPose" -> handleGetAnchorPose(call, result)
                "getCameraPose" -> handleGetCameraPose(result)
                "getCameraMatrices" -> handleGetCameraMatrices(result)
                "snapshot" -> handleSnapshot(result)
                "disableCamera" -> handleDisableCamera(result)
                "enableCamera" -> handleEnableCamera(result)
                "refinePlane" -> handleRefinePlane(call, result)
                "probeFloorY" -> handleProbeFloorY(call, result)
                "getCloudPoints" -> handleCloudPoints(result)
                "getDepthPoints" -> handleDepthPoints(result)
                "hitTest" -> handleHitTest(call, result)
                else -> result.notImplemented()
            }
    }
    // ~25 rendered frames of grace: during normal tracking the stamp is
    // refreshed at 30–60 Hz, so this never fires. When the frame loop has
    // stalled (or the session is being torn down) callers get null and
    // take their cheap early-return instead of entering ARCore with dead
    // state. Throttled trace so a 50 ms poll can't flood the log.
    private fun freshFrame(): Frame? {
        val f = latestFrame ?: return null
        val age = SystemClock.elapsedRealtime() - lastFrameAtMs
        if (age > 800) {
            val now = SystemClock.elapsedRealtime()
            if (now - lastStaleLogAt > 2000) {
                lastStaleLogAt = now
                NativeTrace.log(viewContext, "arview: stale frame age=${age}ms")
            }
            return null
        }
        return f
    }

    private fun handleDisableCamera(result: MethodChannel.Result) {
        try {
            isSessionPaused = true
            // Points gathered before a pause may sit in a shifted world once
            // tracking resumes — start the buffer fresh.
            pointAccumulator.clear()
            lastAccumCloudTimestamp = -1L
            // Frames stop here; a pre-pause frame must not outlive the
            // pause (acquire* on it hangs or crashes ARCore).
            latestFrame = null
            lastFrameAtMs = 0L
            sceneView.session?.pause()
            result.success(null)
        } catch (e: Exception) {
            result.error("DISABLE_CAMERA_ERROR", e.message, null)
        }
    }
    private fun handleEnableCamera(result: MethodChannel.Result) {
        try {
            isSessionPaused = false
            sceneView.session?.resume()
            result.success(null)
        } catch (e: Exception) {
            result.error("ENABLE_CAMERA_ERROR", e.message, null)
        }
    }
    private val onObjectMethodCall =
        MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "addNode" -> {
                    val nodeData = call.arguments as? Map<String, Any>
                    nodeData?.let {
                        handleAddNode(it, result)
                    } ?: result.error("INVALID_ARGUMENTS", "Node data is required", null)
                }
                "addNodeToPlaneAnchor" -> handleAddNodeToPlaneAnchor(call, result)
                "addNodeToScreenPosition" -> handleAddNodeToScreenPosition(call, result)
                "removeNode" -> {
                    handleRemoveNode(call, result)
                }
                "transformationChanged" -> {
                    handleTransformNode(call, result)
                }
                "rotateNode" -> {
                    handleRotateNode(call, result)
                }
                else -> result.notImplemented()
            }
        }

    private val onAnchorMethodCall =
        MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "addAnchor" -> handleAddAnchor(call, result)
                "removeAnchor" -> {
                    val anchorName = call.argument<String>("name")
                    handleRemoveAnchor(anchorName, result)
                }
                "initGoogleCloudAnchorMode" -> handleInitGoogleCloudAnchorMode(result)
                "uploadAnchor" -> handleUploadAnchor(call, result)
                "downloadAnchor" -> handleDownloadAnchor(call, result)
                else -> result.notImplemented()
            }
        }

    init {
        NativeTrace.log(viewContext, "arview: init start")
        sceneView = SafeARSceneView(
            context = viewContext,
            sharedLifecycle = lifecycle,
            sessionConfiguration = { session, config ->
                // Depth from the very first apply: handleInit races session
                // creation, and a session born with DISABLED stayed that way
                // for its whole life (nothing re-applies after creation).
                config.apply {
                    depthMode = if (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                        Config.DepthMode.AUTOMATIC
                    } else {
                        Config.DepthMode.DISABLED
                    }
                    instantPlacementMode = Config.InstantPlacementMode.DISABLED
                    lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                    focusMode = Config.FocusMode.AUTO
                    planeFindingMode = desiredPlaneFindingMode
                }
                // SceneView fires this on EVERY ARSession.configure — each
                // app resume included. Only wipe the telemetry when the
                // session object itself is new: a resume wipe emptied
                // livePlanes and stable (white-floor) planes never re-appear
                // as "updated", blanking the overlay until geometry moved.
                // A (re)created session mints new Plane objects, so stale
                // keys must go.
                val newSession = session !== lastConfiguredSession
                if (newSession) {
                    livePlanes.clear()
                    planeLastFreshAt.clear()
                    planeIds.clear()
                    detectedPlanes.clear()
                    latestFrame = null
                    lastFrameAtMs = 0L
                    lastConfiguredSession = session
                }
                NativeTrace.log(
                    viewContext,
                    "arview: cfg pf=${config.planeFindingMode} depth=${config.depthMode} live=${livePlanes.size} wiped=${if (newSession) 1 else 0}",
                )
            }
        )
        NativeTrace.log(viewContext, "arview: scene view created")
        sceneView.onFrameError = { e ->
            frameErrorCount++
            if (frameErrorCount == 1 || frameErrorCount % 120 == 0) {
                NativeTrace.log(viewContext, "arview: frame error #$frameErrorCount ${e.javaClass.simpleName}: ${e.message}")
            }
        }

        rootLayout.addView(sceneView)

        sessionChannel.setMethodCallHandler(onSessionMethodCall)
        objectChannel.setMethodCallHandler(onObjectMethodCall)
        anchorChannel.setMethodCallHandler(onAnchorMethodCall)
    }

    

    private suspend fun buildModelNode(nodeData: Map<String, Any>): ModelNode? {
        var fileLocation = nodeData["uri"] as? String ?: return null
        when (nodeData["type"] as Int) {
                0 -> { // GLTF2 Model from Flutter asset folder
                    // Get path to given Flutter asset
                    val loader = FlutterInjector.instance().flutterLoader()
                    fileLocation = loader.getLookupKeyForAsset(fileLocation)
                }
                1 -> { // GLB Model from the web
                    fileLocation = fileLocation
                }
                2 -> { // fileSystemAppFolderGLB
                    fileLocation = fileLocation
                }
                 3 -> { //fileSystemAppFolderGLTF2
                    val documentsPath = viewContext.getApplicationInfo().dataDir
                    val fileLocation = documentsPath + "/app_flutter/" + nodeData["uri"] as String
                 }
                else -> {
                    return null
                }
        }
        
        if (fileLocation == null) {
            return null
        }
        val transformation = nodeData["transformation"] as? ArrayList<Double>
        if (transformation == null) {
            return null
        }

        // Floor furniture / floor finishes opt out of vertical drag
        // surfaces: when true, onMove re-hit-tests HORIZONTAL planes only,
        // so a dragged item can never climb a wall or float up a fridge.
        val horizontalOnly =
            ((nodeData["data"] as? Map<*, *>)
                ?.get("horizontalOnly") as? Boolean) ?: false

        // World-meter geometry footprint embedded at placement (Dart's
        // tap-time gate). Missing keys → no drag clamp; wall items
        // (horizontalOnly=false) never clamp.
        val fpData = nodeData["data"] as? Map<*, *>
        val fpW = (fpData?.get("footprintWidthM") as? Number)?.toDouble()
        val fpD = (fpData?.get("footprintDepthM") as? Number)?.toDouble()
        val fpCx = (fpData?.get("footprintCenterX") as? Number)?.toDouble()
        val fpCz = (fpData?.get("footprintCenterZ") as? Number)?.toDouble()

        return try {
            sceneView.modelLoader.loadModelInstance(fileLocation)?.let { modelInstance ->
                object : ModelNode(
                    modelInstance = modelInstance,
                    scaleToUnits = transformation.first().toFloat(),
                ) {
                    // Rotation teleport guard + twist-seam baseline (see
                    // onRotate / onRotateEnd below).
                    var lastAppliedWorldQ: Quaternion? = null
                    var prevGestureAngle: Float? = null

                    // Drag = re-hit-test the finger against REAL tracked
                    // planes and glue the parent AnchorNode to that surface
                    // point. SceneView's default move snaps to the parent's
                    // collision surface; an AnchorNode has no geometry, so
                    // the default was a no-op and anchored furniture could
                    // not be dragged at all. Forwarding begin/end to the
                    // AnchorNode lets it detach the AR anchor while moving
                    // and re-anchor at the final pose (its built-in
                    // detach-drag-reattach lifecycle).

                    override fun onMoveBegin(
                        detector: MoveGestureDetector,
                        e: MotionEvent
                    ): Boolean {
                        if (!handlePans) return false
                        parent?.onMoveBegin(detector, e)
                        objectChannel.invokeMethod("onPanStart", name)
                        return true
                    }

                    override fun onMove(
                        detector: MoveGestureDetector,
                        e: MotionEvent
                    ): Boolean {
                        if (!handlePans) return false
                        val anchorNode = parent as? AnchorNode
                        if (anchorNode != null) {
                            try {
                                // SceneView 2.2.1's GestureDetector forwards
                                // the STORED BEGIN event to node.onMove on
                                // every frame (moveBeginEvent.component1),
                                // so `e` is frozen at the touch-down point —
                                // hit-testing with it never moves anything.
                                // The live finger position is on the detector.
                                val moveEvent = detector.currentMotionEvent ?: e
                                freshFrame()?.hitTest(moveEvent.x, moveEvent.y)
                                    ?.firstOrNull { hit ->
                                        val trackable = hit.trackable
                                        if (trackable !is Plane ||
                                            trackable.trackingState !=
                                            TrackingState.TRACKING ||
                                            !trackable.isPoseInPolygon(hit.hitPose)
                                        ) {
                                            return@firstOrNull false
                                        }
                                        if (horizontalOnly) {
                                            // Floor-bound item: ONLY real
                                            // upward-facing horizontal
                                            // planes are valid drag
                                            // targets.
                                            trackable.type ==
                                                Plane.Type.HORIZONTAL_UPWARD_FACING
                                        } else {
                                            trackable.type ==
                                                Plane.Type.HORIZONTAL_UPWARD_FACING ||
                                                trackable.type ==
                                                Plane.Type.VERTICAL
                                        }
                                    }
                                    ?.let { hit ->
                                        val t = hit.hitPose.translation
                                        // Floor items with a known footprint
                                        // may not overhang the plane they are
                                        // glued to — position-only; rotation
                                        // lives on this node and is never
                                        // restored from a cached matrix here.
                                        var allowed = true
                                        if (horizontalOnly && fpW != null && fpD != null &&
                                            fpCx != null && fpCz != null && fpW > 0 && fpD > 0
                                        ) {
                                            val wt = worldTransform.toFloatArray()
                                            allowed = footprintWithinPlane(
                                                t[0], t[1], t[2],
                                                atan2(wt[8], wt[10]),
                                                fpW.toFloat(), fpD.toFloat(),
                                                fpCx.toFloat(), fpCz.toFloat(),
                                                hit.trackable as? Plane,
                                            )
                                        }
                                        if (allowed) {
                                            anchorNode.worldPosition =
                                                Position(t[0], t[1], t[2])
                                        }
                                    }
                            } catch (ex: Exception) {
                                // Frame went stale mid-drag — keep the last
                                // glued position instead of jumping.
                            }
                            objectChannel.invokeMethod("onPanChange", name)
                            return true
                        }
                        return false
                    }

                    override fun onMoveEnd(
                        detector: MoveGestureDetector,
                        e: MotionEvent
                    ) {
                        if (handlePans) {
                            // SceneView's detach-drag-reattach lifecycle
                            // re-anchors from PoseNode.pose at gesture end,
                            // and the drag only ever wrote worldPosition —
                            // sync the pose to the dragged spot first or
                            // createAnchor() rebuilds the anchor at the
                            // ORIGINAL placement and the model teleports
                            // back. Rotation never moves (it lives on this
                            // node), so keep the placement orientation.
                            (parent as? AnchorNode)?.let { anchorNode ->
                                val p = anchorNode.worldPosition
                                anchorNode.pose = Pose(
                                    floatArrayOf(p.x, p.y, p.z),
                                    anchorNode.pose.rotationQuaternion,
                                )
                            }
                            parent?.onMoveEnd(detector, e)
                            // World, not local: the drag moved the parent
                            // anchor, which the local matrix never sees.
                            val transformMap = mapOf(
                                "name" to name,
                                "transform" to worldTransform.toFloatArray().toList()
                            )
                            objectChannel.invokeMethod("onPanEnd", transformMap)
                        }
                    }

                    override fun onRotateBegin(detector: RotateGestureDetector, e: MotionEvent): Boolean {
                        if (handleRotation) {
                            prevGestureAngle = null
                            lastAppliedWorldQ = null
                            val defaultResult = super.onRotateBegin(detector, e)
                            objectChannel.invokeMethod("onRotationStart", name)
                            return defaultResult
                        }
                        return false
                    }

                    override fun onRotate(detector: RotateGestureDetector, e: MotionEvent): Boolean {
                        if (!handleRotation) return false
                        // SceneView's default composes the twist delta in
                        // the node's LOCAL frame around its local Y — once
                        // the anchor carries any plane tilt that delta
                        // accumulates into visible furniture tilt, and the
                        // gesture feels unresponsive. Apply the delta as a
                        // WORLD-space yaw instead: left-multiply a
                        // +Y-axis rotation onto the world quaternion, so
                        // furniture turns like a turntable and can never
                        // pitch or roll.
                        val cur = detector.currentAngle
                        val prev = prevGestureAngle
                        prevGestureAngle = cur
                        if (prev == null) return true // first frame: baseline only
                        var deltaRad = cur - prev
                        // atan2 seam: the absolute twist angle jumps ±2π at
                        // the branch cut — wrap so a full circle never
                        // hiccups backwards by ~358°.
                        if (deltaRad > Math.PI.toFloat()) {
                            deltaRad -= (2.0 * Math.PI).toFloat()
                        } else if (deltaRad < -Math.PI.toFloat()) {
                            deltaRad += (2.0 * Math.PI).toFloat()
                        }
                        if (deltaRad != 0f) {
                            // fromAxisAngle takes DEGREES in this kotlin-math
                            // build (it internally multiplies by π/180).
                            val deltaYawDeg =
                                -deltaRad * RADIANS_TO_DEGREES
                            val deltaQ = Quaternion.fromAxisAngle(
                                Float3(0f, 1f, 0f),
                                deltaYawDeg
                            )
                            worldQuaternion = deltaQ * worldQuaternion
                            lastAppliedWorldQ = worldQuaternion
                        }
                        objectChannel.invokeMethod("onRotationChange", name)
                        return true
                    }

                    override fun onRotateEnd(detector: RotateGestureDetector, e: MotionEvent) {
                        if (handleRotation) {
                            super.onRotateEnd(detector, e)
                            // The end-of-gesture path (move END runs first on
                            // touch-up) can clobber the twist — re-assert what
                            // this gesture applied or it teleports back.
                            lastAppliedWorldQ?.let { applied ->
                                worldQuaternion = applied
                                rootLayout.postDelayed({
                                    try {
                                        val later = worldQuaternion
                                        NativeTrace.log(
                                            viewContext,
                                            "arview: rotateEnd later=$later applied=$applied match=${qStr(later) == qStr(applied)}",
                                        )
                                    } catch (_: Exception) {
                                    }
                                }, 500)
                            }
                            // World matrix: after a drag the footprint needs
                            // the anchor's position too, not just this
                            // node's local rotation.
                            val transformMap = mapOf(
                                "name" to name,
                                "transform" to worldTransform.toFloatArray().toList()
                            )
                            objectChannel.invokeMethod("onRotationEnd", transformMap)
                        }
                    }
                }.apply {
                    isPositionEditable = handlePans
                    isRotationEditable = handleRotation
                    name = nodeData["name"] as? String
                }
            } ?: run {
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun handleAddNodeToPlaneAnchor(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val nodeData = call.arguments as? Map<String, Any>
            val dict_node = nodeData?.get("node") as? Map<String, Any>
            val dict_anchor = nodeData?.get("anchor") as? Map<String, Any>
            if (dict_node == null || dict_anchor == null) {
                result.success(false)
                return
            }

            val anchorName = dict_anchor["name"] as? String
            val anchorNode = anchorNodesMap[anchorName]
            if (anchorNode != null) {
                mainScope.launch {
                    try {
                        buildModelNode(dict_node)?.let { node ->
                            anchorNode.addChildNode(node)
                            sceneView.addChildNode(anchorNode)
                            node.name?.let { nodeName ->
                                nodesMap[nodeName] = node
                            }
                            result.success(true)
                        } ?: result.success(false)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleAddNodeToScreenPosition(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val nodeData = call.arguments as? Map<String, Any>
            val screenPosition = call.argument<Map<String, Double>>("screenPosition")

            if (nodeData == null || screenPosition == null) {
                result.error("INVALID_ARGUMENT", "Node data or screen position is null", null)
                return
            }

            mainScope.launch {
                val node = buildModelNode(nodeData) ?: return@launch
                val hitResultNode =
                    HitResultNode(
                        engine = sceneView.engine,
                        xPx = screenPosition["x"]?.toFloat() ?: 0f,
                        yPx = screenPosition["y"]?.toFloat() ?: 0f,
                    ).apply {
                        addChildNode(node)
                    }

                sceneView.addChildNode(hitResultNode)
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("ADD_NODE_TO_SCREEN_ERROR", e.message, null)
        }
    }

    private fun handleInit(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        NativeTrace.log(
            viewContext,
            "arview: handleInit begin sessionNull=${sceneView.session == null}",
        )
        try {
            val argShowAnimatedGuide = call.argument<Boolean>("showAnimatedGuide") ?: true
            val argShowFeaturePoints = call.argument<Boolean>("showFeaturePoints") ?: false
            val argPlaneDetectionConfig: Int? = call.argument<Int>("planeDetectionConfig")
            val argShowPlanes = call.argument<Boolean>("showPlanes") ?: true
            val customPlaneTexturePath = call.argument<String>("customPlaneTexturePath")
            val showWorldOrigin = call.argument<Boolean>("showWorldOrigin") ?: false
            val handleTaps = call.argument<Boolean>("handleTaps") ?: true
            handlePans = call.argument<Boolean>("handlePans") ?: false
            handleRotation = call.argument<Boolean>("handleRotation") ?: false

            desiredPlaneFindingMode = when (argPlaneDetectionConfig) {
                1 -> Config.PlaneFindingMode.HORIZONTAL
                2 -> Config.PlaneFindingMode.VERTICAL
                3 -> Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                else -> Config.PlaneFindingMode.DISABLED
            }
            sceneView.session?.let { session ->
                session.configure(session.config.apply {
                    depthMode = when (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                        true -> Config.DepthMode.AUTOMATIC
                        else -> Config.DepthMode.DISABLED
                    }
                    planeFindingMode = desiredPlaneFindingMode
                })
                NativeTrace.log(viewContext, "arview: handleInit depthMode=${session.config.depthMode} pf=${session.config.planeFindingMode} arg=$argPlaneDetectionConfig")
                // Probe only. ARCore's SemanticLabel set is outdoor categories
                // (SKY/ROAD/BUILDING/… — no furniture/floor/table labels), so
                // semantic mode can never mask indoor objects; logged so the
                // device-side answer is visible in logcat. Guarded — a stale
                // ARCore runtime may not know the API at all.
                try {
                    Log.d(
                        TAG,
                        "semanticSupported=" +
                            session.isSemanticModeSupported(Config.SemanticMode.ENABLED)
                    )
                } catch (e: Throwable) {
                    NativeTrace.log(viewContext, "arview: semantic probe failed: $e")
                }
            }

            handleShowWorldOrigin(showWorldOrigin)
            
            sceneView.apply {
                // Cosmetic lighting only — decode failure (missing asset, OOM
                // on a low-RAM device) must degrade to default lighting, not
                // take the session down.
                try {
                    environmentLoader.createHDREnvironment(
                        assetFileLocation = "environments/evening_meadow_2k.hdr"
                    )?.let { environment = it }
                } catch (e: Throwable) {
                    NativeTrace.log(viewContext, "arview: env load failed: $e")
                }

                planeRenderer.isEnabled = argShowPlanes
                planeRenderer.isVisible = argShowPlanes
                planeRenderer.planeRendererMode = PlaneRenderer.PlaneRendererMode.RENDER_ALL

                onTrackingFailureChanged = { reason ->
                    mainScope.launch {
                        sessionChannel.invokeMethod("onTrackingFailure", reason?.name)
                    }
                }

                if (argShowFeaturePoints == true) {
                    showFeaturePoints = true
                } else {
                    showFeaturePoints = false
                    pointCloudNodes.toList().forEach { removePointCloudNode(it) }
                }

                // SceneView's ARSceneView.onFrame() ALREADY calls
                // session.update() once per rendered frame and delivers the
                // result here via onSessionUpdated. Calling update() again in
                // an onFrame lambda (as this plugin used to) advances ARCore
                // TWICE per frame — ARCore's contract is exactly one update()
                // per frame, and breaking it destabilizes tracking, making
                // detected planes jitter and float above the real floor. Never
                // call session.update() here; just consume `frame`.
                onSessionUpdated = { _, frame ->
                    perfFrame(frame)
                    try {
                        if (!isSessionPaused) {
                            run {
                                latestFrame = frame
                                lastFrameAtMs = SystemClock.elapsedRealtime()
                                if (!firstFrameTraced) {
                                    firstFrameTraced = true
                                    NativeTrace.log(viewContext, "arview: first frame")
                                }
                                // Feed the refinePlane point buffer — roughly
                                // every 2nd frame keeps the cost low while
                                // still tracking the cloud as the phone moves.
                                accumFrameCounter++
                                if (accumFrameCounter % 2 == 0) {
                                    frame.acquirePointCloud()?.let { cloud ->
                                        try {
                                            if (cloud.timestamp != lastAccumCloudTimestamp) {
                                                lastAccumCloudTimestamp = cloud.timestamp
                                                // White floors starve every
                                                // point-cloud consumer (probe,
                                                // refine) — log the raw yield so
                                                // the next device run shows it.
                                                cloudLogFrameCounter++
                                                if (cloudLogFrameCounter % 150 == 0) {
                                                    NativeTrace.log(
                                                        viewContext,
                                                        "arview: cloud pts=${cloud.points.limit() / 4}",
                                                    )
                                                }
                                                pointAccumulator.ingest(
                                                    cloud.points,
                                                    frame.timestamp / 1_000_000L,
                                                )
                                            }
                                        } finally {
                                            cloud.release()
                                        }
                                    }
                                }
                                if (showAnimatedGuide) {
                                    frame.getUpdatedTrackables(Plane::class.java).forEach { plane ->
                                        if (plane.trackingState == TrackingState.TRACKING) {
                                            rootLayout.findViewWithTag<View>("hand_motion_layout")?.let { handMotionLayout ->
                                                rootLayout.removeView(handMotionLayout)
                                                showAnimatedGuide = false
                                            }
                                        }
                                    }
                                }

                                if (showFeaturePoints) {
                                    val currentFps = frame.fps(lastPointCloudFrame)
                                    if (currentFps < 10) {
                                        frame.acquirePointCloud()?.let { pointCloud ->
                                            // Release on EVERY acquire — the
                                            // unchanged-timestamp path used to
                                            // leak the cloud.
                                            try {
                                                if (pointCloud.timestamp != lastPointCloudTimestamp) {
                                                    lastPointCloudFrame = frame
                                                    lastPointCloudTimestamp = pointCloud.timestamp

                                                    val pointsSize = pointCloud.ids?.limit() ?: 0

                                                    if (pointCloudNodes.isNotEmpty()) {
                                                    }
                                                    pointCloudNodes.toList().forEach { removePointCloudNode(it) }

                                                    val pointsBuffer = pointCloud.points
                                                    for (index in 0 until pointsSize) {
                                                        val pointIndex = index * 4
                                                        val position =
                                                            Position(
                                                                pointsBuffer[pointIndex],
                                                                pointsBuffer[pointIndex + 1],
                                                                pointsBuffer[pointIndex + 2],
                                                            )
                                                        val confidence = pointsBuffer[pointIndex + 3]
                                                        addPointCloudNode(index, position, confidence)
                                                    }
                                                }
                                            } finally {
                                                pointCloud.release()
                                            }
                                        }
                                    }
                                }

                                frame.getUpdatedTrackables(Plane::class.java).forEach { plane ->
                                    if (plane.trackingState == TrackingState.TRACKING &&
                                        !detectedPlanes.contains(plane)
                                    ) {
                                        detectedPlanes.add(plane)
                                        if (detectedPlanes.size == 1) {
                                            NativeTrace.log(viewContext, "arview: first plane")
                                        }
                                        mainScope.launch {
                                            sessionChannel.invokeMethod("onPlaneDetected", detectedPlanes.size)
                                        }
                                    }
                                }

                                // Live plane telemetry for the app's floor gate (Bug 2).
                                // Merge this frame's UPDATED trackables into the persistent
                                // livePlanes map so a stable, fully-formed floor — which
                                // drops out of getUpdatedTrackables once it stops being
                                // refined — keeps counting as "seen" until it stops
                                // tracking. Payload is center + type + extent only (cheap).
                                frame.getUpdatedTrackables(Plane::class.java).forEach { plane ->
                                    // Subsumed planes are absorbed into a larger
                                    // one. They stay in the payload flagged
                                    // `subsumed`: an absorbed table top is
                                    // exactly the object mask the overlay needs
                                    // to punch furniture out of the floor paint
                                    // (Dart routes subsumed planes to masks and
                                    // keeps them out of floor coverage).
                                    when (plane.trackingState) {
                                        TrackingState.TRACKING -> {
                                            livePlanes[plane] =
                                                planeTelemetry(plane) + ("tracking" to true)
                                            planeLastFreshAt[plane] =
                                                SystemClock.elapsedRealtime()
                                            if (plane.type == Plane.Type.VERTICAL &&
                                                !firstWallLogged
                                            ) {
                                                firstWallLogged = true
                                                NativeTrace.log(
                                                    viewContext,
                                                    "arview: first wall id=${planeIdFor(plane)} extents=${plane.extentX}x${plane.extentZ}",
                                                )
                                            }
                                        }
                                        // PAUSED = ARCore found it but lacks views to
                                        // refine — common on white walls. Emit it for
                                        // RENDER/memory (freshMs grows: last genuinely
                                        // updated when it was TRACKING). Every
                                        // placement gate stays TRACKING-only, so a
                                        // paused plane can never become placeable.
                                        TrackingState.PAUSED -> {
                                            val wasPresent = livePlanes.containsKey(plane)
                                            livePlanes[plane] =
                                                planeTelemetry(plane) + ("tracking" to false)
                                            if (!wasPresent) {
                                                planeLastFreshAt.putIfAbsent(
                                                    plane,
                                                    SystemClock.elapsedRealtime(),
                                                )
                                                if (plane.type == Plane.Type.VERTICAL &&
                                                    !firstPausedWallLogged
                                                ) {
                                                    firstPausedWallLogged = true
                                                    NativeTrace.log(
                                                        viewContext,
                                                        "arview: first pausedWall id=${planeIdFor(plane)} extents=${plane.extentX}x${plane.extentZ}",
                                                    )
                                                }
                                            }
                                        }
                                        else -> {
                                            livePlanes.remove(plane)
                                            planeLastFreshAt.remove(plane)
                                            planeIds.remove(plane)
                                        }
                                    }
                                }

                                // ~5s diagnostic snapshot: how many planes ARCore
                                // actually holds per state (the white-wall question),
                                // how many the payload carries, and the feature-map
                                // quality — the single best white-surface health
                                // signal ARCore exposes.
                                planeSnapFrameCounter++
                                if (planeSnapFrameCounter % 150 == 0) {
                                    sceneView.session?.let { s ->
                                        val all = s.getAllTrackables(Plane::class.java)
                                        var track = 0
                                        var paused = 0
                                        var stopped = 0
                                        var vertical = 0
                                        var subsumed = 0
                                        for (p in all) {
                                            when (p.trackingState) {
                                                TrackingState.TRACKING -> track++
                                                TrackingState.PAUSED -> paused++
                                                else -> stopped++
                                            }
                                            if (p.type == Plane.Type.VERTICAL) vertical++
                                            if (p.subsumedBy != null) subsumed++
                                        }
                                        val fmq = try {
                                            when (s.estimateFeatureMapQualityForHosting(frame.camera.pose)) {
                                                Session.FeatureMapQuality.GOOD -> "GOOD"
                                                Session.FeatureMapQuality.SUFFICIENT -> "SUFFICIENT"
                                                else -> "INSUFFICIENT"
                                            }
                                        } catch (e: Throwable) {
                                            "n/a"
                                        }
                                        NativeTrace.log(
                                            viewContext,
                                            "arview: planeSnap all=${all.size} track=$track paused=$paused stopped=$stopped vertical=$vertical subsumed=$subsumed live=${livePlanes.size} fmq=$fmq",
                                        )
                                    }
                                }

                                // Stream the snapshot with THIS frame's render
                                // matrices (planes and pose stay same-frame, so
                                // the overlay never trails), every 3rd rendered
                                // frame — the Dart overlay rebuild is capped at
                                // 66 ms anyway, so faster sends only burn
                                // codec/gc pressure for no visible gain.
                                planesFrameCounter++
                                if (planesFrameCounter % 3 == 0) {
                                    // freshMs = time since ARCore last genuinely
                                    // updated this plane; stable ones would
                                    // otherwise look fresh forever.
                                    val nowMs = SystemClock.elapsedRealtime()
                                    val planesPayload = ArrayList<Map<String, Any>>(livePlanes.size)
                                    for ((plane, telemetry) in livePlanes) {
                                        val freshAt = planeLastFreshAt[plane] ?: nowMs
                                        planesPayload.add(telemetry + ("freshMs" to (nowMs - freshAt)))
                                    }
                                    // Freshest 48 only: livePlanes grows for as
                                    // long as ARCore keeps a plane tracking, so
                                    // the codec cost of this message would grow
                                    // forever with the area scanned. Planes you
                                    // walk away from age out of freshMs first
                                    // and re-enter the moment ARCore updates
                                    // them again (turning back).
                                    val planesOut: List<Map<String, Any>> =
                                        if (planesPayload.size <= 48) {
                                            planesPayload
                                        } else {
                                            planesPayload
                                                .sortedBy {
                                                    (it["freshMs"] as Number).toLong()
                                                }
                                                .take(48)
                                        }
                                    val projection = FloatArray(16)
                                    frame.camera.getProjectionMatrix(projection, 0, 0.1f, 100f)
                                    val view = FloatArray(16)
                                    frame.camera.getViewMatrix(view, 0)
                                    mainScope.launch {
                                        sessionChannel.invokeMethod(
                                            "onPlanesUpdate",
                                            mapOf(
                                                "planes" to planesOut,
                                                "projection" to projection.map { it.toDouble() },
                                                "view" to view.map { it.toDouble() },
                                            ),
                                        )
                                    }
                                }
                            }
                        }
                    } catch (e: Throwable) {
                        when (e) {
                            is SessionPausedException -> {
                                // Ignorer silencieusement cette exception quand la session est en pause
                                Log.d(TAG, "Session paused, skipping frame update")
                            }
                            else -> {
                                Log.e(TAG, "Error during frame update", e)
                                e.printStackTrace()
                                // Throwable, not Exception — an Error (e.g.
                                // OutOfMemoryError under pressure) must skip a
                                // frame, not kill the app from the render loop.
                                if (!frameErrorTraced) {
                                    frameErrorTraced = true
                                    NativeTrace.log(viewContext, "arview: frame error: $e")
                                }
                            }
                        }
                    }
                }

                setOnGestureListener(
                    onSingleTapConfirmed = { motionEvent: MotionEvent, node: Node? ->
                        if (node != null) {
                            var anchorName: String? = null
                            var currentNode: Node? = node
                            while (currentNode != null) {
                                anchorNodesMap.forEach { (name, anchorNode) ->
                                    if (currentNode == anchorNode) {
                                        anchorName = name
                                        return@forEach
                                    }
                                }
                                if (anchorName != null) break
                                currentNode = currentNode.parent
                            }
                            if (anchorName != null && handleTaps) {
                                objectChannel.invokeMethod("onNodeTap", listOf(anchorName))
                                true
                            } else {
                                // Feature-point / renderer nodes are not
                                // furniture — a tap on one must hit-test the
                                // surface behind it, not be swallowed as a
                                // phantom node tap (that killed placement
                                // the moment showFeaturePoints went on).
                                freshFrame()?.let { frame ->
                                    val hitResults = frame.hitTest(motionEvent)
                                    val planeHits = hitResults
                                        .filter { hit ->
                                            val trackable = hit.trackable
                                            trackable is Plane &&
                                                    trackable.trackingState ==
                                                    TrackingState.TRACKING
                                        }.map { hit -> serializePlaneHit(hit) }
                                    notifyPlaneOrPointTap(planeHits)
                                }
                                true
                            }
                        } else {
                            // Hit-test against the frame the render loop already
                            // produced. Calling session.update() here (as this
                            // used to) is an EXTRA update ARCore never expects
                            // mid-gesture — it desyncs tracking. `latestFrame` is
                            // refreshed every frame by onSessionUpdated above.
                            freshFrame()?.let { frame ->
                                val hitResults = frame.hitTest(motionEvent)
                                val planeHits = hitResults
                                    .filter { hit ->
                                        val trackable = hit.trackable
                                        trackable is Plane &&
                                                trackable.trackingState ==
                                                TrackingState.TRACKING
                                    }.map { hit -> serializePlaneHit(hit) }
                                notifyPlaneOrPointTap(planeHits)
                            }
                            true
                        }
                    },
                )

                if (argShowAnimatedGuide == true && showAnimatedGuide == true) {
                    val handMotionLayout =
                        LayoutInflater
                            .from(context)
                            .inflate(R.layout.sceneform_hand_layout, rootLayout, false)
                            .apply {
                                tag = "hand_motion_layout"
                            }
                    rootLayout.addView(handMotionLayout)
                }

                if (customPlaneTexturePath != null) {
                    try {
                        val loader = FlutterInjector.instance().flutterLoader()
                        val assetKey = loader.getLookupKeyForAsset(customPlaneTexturePath)
                        val customPlaneTexture =
                            ImageTexture
                                .Builder()
                                .bitmap(materialLoader.assets, assetKey)
                                .build(engine)
                        planeRenderer.planeMaterial.defaultInstance.apply {
                            setTexture(PlaneRenderer.MATERIAL_TEXTURE, customPlaneTexture)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Erreur lors de l'application de la texture personnalisée: ${e.message}")
                        Log.e(TAG, "Stack trace:", e)
                    }
                } else {
                    Log.i(TAG, "ℹ️ Utilisation de la texture par défaut")
                }
            }
            NativeTrace.log(viewContext, "arview: handleInit done")
            result.success(null)
        } catch (e: Throwable) {
            // Throwable, not Exception — OutOfMemoryError from the HDR/model
            // loads must surface as a channel error, not a process death.
            NativeTrace.log(viewContext, "arview: handleInit FAILED: $e")
            result.error("AR_VIEW_ERROR", e.toString(), null)
        }
    }

    private fun handleAddNode(
        nodeData: Map<String, Any>,
        result: MethodChannel.Result,
    ) {
        try {
            mainScope.launch {
                val node = buildModelNode(nodeData)
                if (node != null) {
                    sceneView.addChildNode(node)
                    node.name?.let { nodeName ->
                        nodesMap[nodeName] = node
                    }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleRemoveNode(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val nodeData = call.arguments as? Map<String, Any>
            val nodeName = nodeData?.get("name") as? String
            
            if (nodeName == null) {
                result.error("INVALID_ARGUMENT", "Node name is required", null)
                return
            }
            
            Log.d(TAG, "Attempting to remove node with name: $nodeName")
            Log.d(TAG, "Current nodes in map: ${nodesMap.keys}")
            
            nodesMap[nodeName]?.let { node ->
                // Détacher d'abord le nœud de son parent s'il en a un
                node.parent?.removeChildNode(node)
                // Puis le retirer de la scène principale
                sceneView.removeChildNode(node)
                // Nettoyer les ressources du nœud
                node.destroy()
                // Enfin le retirer de notre Map
                nodesMap.remove(nodeName)
                
                Log.d(TAG, "Node removed successfully and destroyed")
                result.success(nodeName)
            } ?: run {
                Log.e(TAG, "Node not found in nodesMap")
                result.error("NODE_NOT_FOUND", "Node with name $nodeName not found", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing node", e)
            result.error("REMOVE_NODE_ERROR", e.message, null)
        }
    }

    /// Rotates the named node by [deltaYawRadians] around the WORLD's up
    /// (+Y) axis — yaw only, so the node can never tilt. Used by the
    /// viewer's ↺/↻ buttons; the two-finger twist applies the same
    /// world-Yaw constraint (see ModelNode.onRotate in buildModelNode).
    private fun handleRotateNode(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            if (!handleRotation) {
                // Rotation disabled for this session — treat as a no-op
                // instead of silently mutating the scene.
                result.success(false)
                return
            }
            val name = call.argument<String>("name")
            val deltaYawRad = call.argument<Double>("deltaYawRadians")
            if (name == null || deltaYawRad == null) {
                result.error(
                    "INVALID_ARGUMENT",
                    "name and deltaYawRadians are required",
                    null
                )
                return
            }
            val node = nodesMap[name]
            if (node == null) {
                result.error("NODE_NOT_FOUND", "Node with name $name not found", null)
                return
            }
            val deltaYawDeg = (deltaYawRad.toFloat()) * RADIANS_TO_DEGREES
            val deltaQ = Quaternion.fromAxisAngle(
                Float3(0f, 1f, 0f),
                deltaYawDeg
            )
            node.worldQuaternion = deltaQ * node.worldQuaternion
            result.success(true)
        } catch (e: Exception) {
            result.error("ROTATE_NODE_ERROR", e.message, null)
        }
    }

    private fun handleTransformNode(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    try {
        if (handlePans || handleRotation) {
            val name = call.argument<String>("name")
            val newTransformation: ArrayList<Double>? = call.argument<ArrayList<Double>>("transformation")

            if (name == null) {
                result.error("INVALID_ARGUMENT", "Node name is required", null)
                return
            }
            nodesMap[name]?.let { node ->
                newTransformation?.let { transform ->
                    if (transform.size != 16) {
                        result.error("INVALID_TRANSFORMATION", "Transformation must be a 4x4 matrix (16 values)", null)
                        return
                    }

                    node.apply {
                        transform(
                            position = ScenePosition(
                                x = transform[12].toFloat(),
                                y = transform[13].toFloat(),
                                z = transform[14].toFloat()
                            ),
                            rotation = SceneRotation(
                                x = kotlin.math.atan2(transform[6].toFloat(), transform[10].toFloat()),
                                y = kotlin.math.atan2(-transform[2].toFloat(), 
                                    kotlin.math.sqrt(transform[6].toFloat() * transform[6].toFloat() + 
                                    transform[10].toFloat() * transform[10].toFloat())),
                                z = kotlin.math.atan2(transform[1].toFloat(), transform[0].toFloat())
                            ),
                            scale = SceneScale(
                                x = kotlin.math.sqrt((transform[0] * transform[0] + transform[1] * transform[1] + transform[2] * transform[2]).toFloat()),
                                y = kotlin.math.sqrt((transform[4] * transform[4] + transform[5] * transform[5] + transform[6] * transform[6]).toFloat()),
                                z = kotlin.math.sqrt((transform[8] * transform[8] + transform[9] * transform[9] + transform[10] * transform[10]).toFloat())
                            )
                        )
                    }
                    result.success(null)
                } ?: result.error("INVALID_TRANSFORMATION", "Transformation is required", null)
            } ?: result.error("NODE_NOT_FOUND", "Node with name $name not found", null)
        }
    } catch (e: Exception) {
        result.error("TRANSFORM_NODE_ERROR", e.message, null)
    }
}

    private fun handleHostCloudAnchor(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val anchorId = call.argument<String>("anchorId")
            if (anchorId == null) {
                result.error("INVALID_ARGUMENT", "Anchor ID is required", null)
                return
            }

            val session = sceneView.session
            if (session == null) {
                result.error("SESSION_ERROR", "AR Session is not available", null)
                return
            }

            if (!session.canHostCloudAnchor(sceneView.cameraNode)) {
                result.error("HOSTING_ERROR", "Insufficient visual data to host", null)
                return
            }

            val anchor = session.allAnchors.find { it.cloudAnchorId == anchorId }
            if (anchor == null) {
                result.error("ANCHOR_NOT_FOUND", "Anchor with ID $anchorId not found", null)
                return
            }

            val cloudAnchorNode = CloudAnchorNode(sceneView.engine, anchor)
            cloudAnchorNode.host(session) { cloudAnchorId, state ->
                if (state == CloudAnchorState.SUCCESS && cloudAnchorId != null) {
                    result.success(cloudAnchorId)
                } else {
                    result.error("HOSTING_ERROR", "Failed to host cloud anchor: $state", null)
                }
            }
            sceneView.addChildNode(cloudAnchorNode)
        } catch (e: Exception) {
            result.error("HOST_CLOUD_ANCHOR_ERROR", e.message, null)
        }
    }

    private fun handleResolveCloudAnchor(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val cloudAnchorId = call.argument<String>("cloudAnchorId")
            if (cloudAnchorId == null) {
                result.error("INVALID_ARGUMENT", "Cloud Anchor ID is required", null)
                return
            }

            val session = sceneView.session
            if (session == null) {
                result.error("SESSION_ERROR", "AR Session is not available", null)
                return
            }

            CloudAnchorNode.resolve(
                sceneView.engine,
                session,
                cloudAnchorId,
            ) { state, node ->
                if (!state.isError && node != null) {
                    sceneView.addChildNode(node)
                    result.success(null)
                } else {
                    result.error("RESOLVE_ERROR", "Failed to resolve cloud anchor: $state", null)
                }
            }
        } catch (e: Exception) {
            result.error("RESOLVE_CLOUD_ANCHOR_ERROR", e.message, null)
        }
    }

    private fun handleRemoveAnchor(
        anchorName: String?,
        result: MethodChannel.Result,
    ) {
        try {
            if (anchorName == null) {
                result.error("INVALID_ARGUMENT", "Anchor name is required", null)
                return
            }

            val anchor = anchorNodesMap[anchorName]
            if (anchor != null) {
                sceneView.removeChildNode(anchor)
                anchor.anchor?.detach()
                result.success(null)
            } else {
                result.error("ANCHOR_NOT_FOUND", "Anchor with name $anchorName not found", null)
            }
        } catch (e: Exception) {
            result.error("REMOVE_ANCHOR_ERROR", e.message, null)
        }
    }

    private fun handleGetCameraPose(result: MethodChannel.Result) {
        try {
            // Read the current camera pose from the frame the render loop
            // already updated. Calling session.update() here (as this used to)
            // injects an unsolicited extra update and desyncs tracking.
            // A stale frame answers null (Dart treats it as "pose gap")
            // instead of erroring every 50 ms poll through a stall.
            val frame = freshFrame()
            val cameraPose = frame?.camera?.pose
            if (cameraPose != null) {
                // Column-major 4x4 — the exact format the Dart side
                // (MatrixConverter.fromJson) expects. This handler used to
                // return a {position, rotation} map, which the cast rejected,
                // so getCameraPose() silently returned null every call.
                result.success(serializePose(cameraPose).toList())
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("CAMERA_POSE_ERROR", e.message, null)
        }
    }

    // Cheap center + type + extent + yaw snapshot for the app's plane memory
    // and overlay. Extents are remapped so extentX always spans the yaw
    // direction: for a vertical plane that is the horizontal span, with
    // extentZ as the vertical span.
    private fun planeTelemetry(plane: Plane): Map<String, Any> {
        val c = plane.centerPose.translation
        val m = FloatArray(16)
        plane.centerPose.toMatrix(m, 0)
        val type = when (plane.type) {
            Plane.Type.HORIZONTAL_UPWARD_FACING -> 1
            Plane.Type.VERTICAL -> 2
            else -> 0
        }
        var extentX = plane.extentX.toDouble()
        var extentZ = plane.extentZ.toDouble()
        val yaw = if (type == 2) {
            // Vertical plane: local +Y is the outward normal; yaw is the
            // normal's world yaw, so the wall spans width along
            // (cos yaw, 0, -sin yaw) and height along world up.
            val xIsHeight = abs(m[1]) > abs(m[9])
            if (xIsHeight) {
                extentX = plane.extentZ.toDouble()
                extentZ = plane.extentX.toDouble()
            }
            atan2(m[4].toDouble(), m[6].toDouble())
        } else {
            // Horizontal plane: yaw of the local +Z axis — +Z maps to
            // (sin yaw, 0, cos yaw), matching the app's footprint convention.
            atan2(m[8].toDouble(), m[10].toDouble())
        }
        return mapOf(
            "id" to planeIdFor(plane),
            "planeType" to type,
            "centerX" to c[0].toDouble(),
            "centerY" to c[1].toDouble(),
            "centerZ" to c[2].toDouble(),
            "extentX" to extentX,
            "extentZ" to extentZ,
            "yaw" to yaw,
            "polygon" to planePolygonWorld(plane, m),
            "subsumed" to (plane.subsumedBy != null),
        )
    }

    // ARCore's real outline in world space (local x-z verts × centerPose) so
    // the overlay draws the true shape instead of a bounding rectangle.
    // Capped at 64 points — ARCore polygons are convex and usually far
    // smaller; the cap bounds the channel payload on pathological planes.
    private fun planePolygonWorld(plane: Plane, m: FloatArray): List<Double> {
        val poly = try {
            plane.polygon
        } catch (e: Exception) {
            return emptyList()
        }
        poly.rewind()
        val total = poly.remaining() / 2
        if (total < 3) return emptyList()
        val step = maxOf(1, (total + 63) / 64)
        val out = ArrayList<Double>(((total + step - 1) / step) * 3)
        var i = 0
        while (i < total) {
            val lx = poly.get()
            val lz = poly.get()
            if (i % step == 0) {
                // Column-major pose: world = R·(lx, 0, lz) + t.
                out.add((m[0] * lx + m[8] * lz + m[12]).toDouble())
                out.add((m[1] * lx + m[9] * lz + m[13]).toDouble())
                out.add((m[2] * lx + m[10] * lz + m[14]).toDouble())
            }
            i++
        }
        return out
    }

    // The render-ready camera pair: getViewMatrix() incorporates the display
    // orientation and getProjectionMatrix() the display rotation (both
    // column-major), so projection * view maps world → clip exactly like the
    // camera feed the AR content is drawn over.
    private fun handleGetCameraMatrices(result: MethodChannel.Result) {
        try {
            val camera = freshFrame()?.camera
            if (camera == null) {
                result.error("NO_CAMERA", "Camera is not available", null)
                return
            }
            val projection = FloatArray(16)
            camera.getProjectionMatrix(projection, 0, 0.1f, 100f)
            val view = FloatArray(16)
            camera.getViewMatrix(view, 0)
            result.success(
                mapOf(
                    "projection" to projection.map { it.toDouble() },
                    "view" to view.map { it.toDouble() },
                )
            )
        } catch (e: Exception) {
            result.error("CAMERA_MATRICES_ERROR", e.message, null)
        }
    }

    /**
     * Fits a plane to ARCore's raw point cloud around a seed point, so the app
     * can place on a freshly-fitted surface instead of ARCore's jittery plane
     * polygon. Returns null fields when there isn't enough data to fit.
     * Args: seedX/seedY/seedZ (world), radiusM, wantHorizontal (bool).
     */
    private fun serializePlaneHit(hit: HitResult): Map<String, Any> {
        val plane = hit.trackable as Plane
        val pose = hit.hitPose
        return mapOf(
            "type" to 1,
            "distance" to hit.distance.toDouble(),
            "position" to
                mapOf(
                    "x" to pose.tx().toDouble(),
                    "y" to pose.ty().toDouble(),
                    "z" to pose.tz().toDouble(),
                ),
            // REAL surface orientation — without this every
            // hit looked horizontally-flat to the app.
            "rotation" to
                mapOf(
                    "x" to pose.qx().toDouble(),
                    "y" to pose.qy().toDouble(),
                    "z" to pose.qz().toDouble(),
                    "w" to pose.qw().toDouble(),
                ),
            // 1 = horizontal (upward-facing), 2 = vertical,
            // 0 = downward-facing (ceiling) / unknown.
            "planeType" to when (plane.type) {
                Plane.Type.HORIZONTAL_UPWARD_FACING -> 1
                Plane.Type.VERTICAL -> 2
                else -> 0
            },
            // Polygon extent — lets the app refuse still-tiny
            // newborn planes (anchors on them drift later).
            "planeExtent" to
                mapOf(
                    "x" to plane.extentX.toDouble(),
                    "z" to plane.extentZ.toDouble(),
                ),
        )
    }

    private fun handleHitTest(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>
            val x = (args?.get("x") as? Number)?.toFloat()
            val y = (args?.get("y") as? Number)?.toFloat()
            val frame = freshFrame()
            if (x == null || y == null || frame == null) {
                result.success(emptyList<Map<String, Any>>())
                return
            }
            val hits = frame
                .hitTest(x, y)
                .filter { hit ->
                    hit.trackable is Plane &&
                        hit.trackable.trackingState == TrackingState.TRACKING
                }
                .map { hit -> serializePlaneHit(hit) }
            result.success(hits)
        } catch (e: Exception) {
            result.error("HIT_TEST_ERROR", e.message, null)
        }
    }

    private fun handleRefinePlane(call: MethodCall, result: MethodChannel.Result) {
        try {
            val seedX = (call.argument<Number>("seedX"))?.toFloat()
            val seedY = (call.argument<Number>("seedY"))?.toFloat()
            val seedZ = (call.argument<Number>("seedZ"))?.toFloat()
            val radiusM = (call.argument<Number>("radiusM"))?.toFloat() ?: 0.6f
            val wantHorizontal = call.argument<Boolean>("wantHorizontal") ?: true

            if (seedX == null || seedY == null || seedZ == null) {
                result.error("INVALID_ARGUMENT", "seedX/seedY/seedZ required", null)
                return
            }

            // Use the frame the render loop already produced — never call
            // session.update() here (that desyncs tracking; see onSessionUpdated).
            val frame = freshFrame()
            if (frame == null) {
                result.success(null)
                return
            }

            val cloud = frame.acquirePointCloud()
            if (cloud == null) {
                NativeTrace.log(viewContext, "arview: refinePlane null cloud")
                result.success(null)
                return
            }
            try {
                val points = cloud.points
                // Fold this frame into the sliding buffer, then fit against
                // the accumulated surface — far more inliers than any single
                // frame, especially on weak sensors. Single-frame path is
                // only the fallback for the first moments of a session.
                pointAccumulator.ingest(points, frame.timestamp / 1_000_000L)
                val gathered = pointAccumulator.gather(seedX, seedY, seedZ, radiusM)
                val fit = PlaneRefiner.fit(
                    gathered = gathered,
                    seedX = seedX,
                    seedY = seedY,
                    seedZ = seedZ,
                    wantHorizontal = wantHorizontal,
                ) ?: PlaneRefiner.refine(
                    points = points,
                    seedX = seedX,
                    seedY = seedY,
                    seedZ = seedZ,
                    radiusM = radiusM,
                    wantHorizontal = wantHorizontal,
                )
                if (fit == null) {
                    result.success(null)
                } else {
                    result.success(
                        mapOf(
                            "centerX" to fit.centerX,
                            "centerY" to fit.centerY,
                            "centerZ" to fit.centerZ,
                            "normalX" to fit.normalX,
                            "normalY" to fit.normalY,
                            "normalZ" to fit.normalZ,
                            "inlierCount" to fit.inlierCount,
                            "pointCount" to fit.pointCount,
                            "rmsError" to fit.rmsError,
                            "confidence" to fit.confidence,
                        )
                    )
                }
            } finally {
                cloud.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "refinePlane failed", e)
            NativeTrace.log(viewContext, "arview: refinePlane failed: $e")
            result.error("REFINE_PLANE_ERROR", e.message, null)
        }
    }

    // Low-percentile Y of point-cloud samples near the live floor estimate.
    // Plane telemetry freezes once ARCore stops refining a stable plane, but
    // raw depth keeps arriving — this is the refocus signal that drags a
    // wrong floorY down to the real floor without any plane update.
    private fun handleProbeFloorY(call: MethodCall, result: MethodChannel.Result) {
        try {
            val floorY = (call.argument<Number>("floorY"))?.toFloat()
            val radiusM = (call.argument<Number>("radiusM"))?.toFloat() ?: 2.5f
            val minPoints = (call.argument<Number>("minPoints"))?.toInt() ?: 12
            if (floorY == null) {
                result.error("INVALID_ARGUMENT", "floorY required", null)
                return
            }
            val frame = freshFrame()
            if (frame == null) {
                result.success(null)
                return
            }
            val cloud = frame.acquirePointCloud()
            if (cloud == null) {
                NativeTrace.log(viewContext, "arview: probeFloorY null cloud")
                result.success(null)
                return
            }
            try {
                pointAccumulator.ingest(cloud.points, frame.timestamp / 1_000_000L)
                val cam = frame.camera.pose.translation
                val gathered = pointAccumulator.gather(cam[0], floorY, cam[2], radiusM)
                // Keep only the band a real floor can occupy under the phone:
                // never above the estimate (a table up there must not drag
                // floorY the wrong way) and not deep noise under it.
                val band = ArrayList<Float>(gathered.size)
                for (p in gathered) {
                    val y = p[1]
                    if (y >= floorY - 2.0f && y <= floorY + 0.6f) band.add(y)
                }
                if (band.size < minPoints) {
                    NativeTrace.log(
                        viewContext,
                        "arview: probeFloorY starved gathered=${gathered.size} band=${band.size}",
                    )
                    result.success(null)
                    return
                }
                band.sort()
                val p20 = band[((band.size - 1) * 0.2).toInt()]
                NativeTrace.log(
                    viewContext,
                    "arview: probeFloorY y=$p20 band=${band.size}",
                )
                result.success(mapOf("y" to p20.toDouble(), "pointCount" to band.size))
            } finally {
                cloud.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "probeFloorY failed", e)
            NativeTrace.log(viewContext, "arview: probeFloorY failed: $e")
            result.error("PROBE_FLOOR_Y_ERROR", e.message, null)
        }
    }

    private fun handleCloudPoints(result: MethodChannel.Result) {
        try {
            val gathered = pointAccumulator.gather(0f, 0f, 0f, 1000f)
            if (gathered.isEmpty()) {
                result.success(emptyList<Double>())
                return
            }
            val stride = (gathered.size / 400).coerceAtLeast(1)
            val out = ArrayList<Double>(((gathered.size + stride - 1) / stride) * 3)
            var i = 0
            while (i < gathered.size) {
                val p = gathered[i]
                out.add(p[0].toDouble())
                out.add(p[1].toDouble())
                out.add(p[2].toDouble())
                i += stride
            }
            result.success(out)
        } catch (e: Exception) {
            Log.e(TAG, "getCloudPoints failed", e)
            NativeTrace.log(viewContext, "arview: getCloudPoints failed: $e")
            result.error("GET_CLOUD_POINTS_ERROR", e.message, null)
        }
    }

    // Depth image → world xyz. Depth is dense geometry, so unlike the
    // feature-point cloud it still returns points on white/textureless
    // walls, where ARCore's plane finder has no visual features to track.
    private fun handleDepthPoints(result: MethodChannel.Result) {
        try {
            val session = sceneView.session
            // Devices without depth (or an app that never enabled it) must
            // degrade to an empty list, never throw at Dart.
            if (session == null || session.config.depthMode == Config.DepthMode.DISABLED) {
                NativeTrace.log(viewContext, "arview: getDepthPoints depth off")
                result.success(emptyList<Double>())
                return
            }
            // Same frame the render loop already produced — never call
            // session.update() here (that desyncs tracking).
            val frame = freshFrame()
            if (frame == null) {
                result.success(emptyList<Double>())
                return
            }
            val depth = try {
                frame.acquireDepthImage()
            } catch (e: NotYetAvailableException) {
                NativeTrace.log(viewContext, "arview: getDepthPoints not yet available")
                result.success(emptyList<Double>())
                return
            } catch (e: NotTrackingException) {
                NativeTrace.log(viewContext, "arview: getDepthPoints not tracking")
                result.success(emptyList<Double>())
                return
            }
            // Compute first, reply second: an exception out of close() must
            // not race an already-submitted success into result.error.
            val points = try {
                depthWorldPoints(frame, depth)
            } finally {
                // A leaked depth image makes ARCore fail within seconds.
                depth.close()
            }
            result.success(points)
        } catch (e: Exception) {
            Log.e(TAG, "getDepthPoints failed", e)
            NativeTrace.log(viewContext, "arview: getDepthPoints failed: $e")
            result.error("GET_DEPTH_POINTS_ERROR", e.message, null)
        }
    }

    // Stride-samples the depth grid (≤ ~500 raw candidates), unprojects each
    // valid pixel to world space, and returns flat xyz triplets downsampled
    // to at most ~400 points — the same contract as handleCloudPoints.
    private fun depthWorldPoints(frame: Frame, depth: Image): List<Double> {
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) {
            NativeTrace.log(viewContext, "arview: getDepthPoints camera untracked")
            return emptyList()
        }
        val intrinsics = camera.imageIntrinsics
        val focal = intrinsics.focalLength
        val principal = intrinsics.principalPoint
        val camDims = intrinsics.imageDimensions
        val fx = focal[0]
        val fy = focal[1]
        val cx = principal[0]
        val cy = principal[1]
        val camW = camDims[0]
        val camH = camDims[1]
        if (fx <= 0f || fy <= 0f || camW <= 0 || camH <= 0) return emptyList()

        val pose = camera.pose
        val tx = pose.tx()
        val ty = pose.ty()
        val tz = pose.tz()
        // Hamilton quaternion → row-major rotation matrix; world = R·p + t.
        val qx = pose.qx()
        val qy = pose.qy()
        val qz = pose.qz()
        val qw = pose.qw()
        val r00 = 1f - 2f * (qy * qy + qz * qz)
        val r01 = 2f * (qx * qy - qz * qw)
        val r02 = 2f * (qx * qz + qy * qw)
        val r10 = 2f * (qx * qy + qz * qw)
        val r11 = 1f - 2f * (qx * qx + qz * qz)
        val r12 = 2f * (qy * qz - qx * qw)
        val r20 = 2f * (qx * qz - qy * qw)
        val r21 = 2f * (qy * qz + qx * qw)
        val r22 = 1f - 2f * (qx * qx + qy * qy)

        val depthW = depth.width
        val depthH = depth.height
        if (depthW <= 0 || depthH <= 0) return emptyList()
        val plane = depth.planes.getOrNull(0) ?: return emptyList()
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        // DEPTH16 is little-endian but a fresh ByteBuffer declares
        // BIG_ENDIAN — read through a duplicate pinned to native order.
        val buffer = plane.buffer.duplicate().order(ByteOrder.nativeOrder())

        fun worldAt(col: Int, row: Int): DoubleArray? {
            val mm = buffer.getShort(row * rowStride + col * pixelStride).toInt() and 0xFFFF
            if (mm == 0) return null
            val d = mm / 1000.0
            if (d <= 0.0 || d > 8.0) return null
            // The depth image can be a crop of the camera image, so its
            // pixels only become rays after ARCore maps them into the CPU
            // image — plain intrinsics scaling would skew every angle.
            val tex = floatArrayOf((col + 0.5f) / depthW, (row + 0.5f) / depthH)
            val img = FloatArray(2)
            frame.transformCoordinates2d(
                Coordinates2d.TEXTURE_NORMALIZED, tex,
                Coordinates2d.IMAGE_PIXELS, img,
            )
            val px = img[0].toDouble()
            val py = img[1].toDouble()
            if (px < 0.0 || py < 0.0 || px >= camW || py >= camH) return null
            val xn = (px - cx) / fx
            val yn = (py - cy) / fy
            // Depth is z-depth along the optical axis (millimetres), not
            // radial range. ARCore's camera frame is x right, y up, −z
            // forward, so a forward distance d maps to (xn·d, −yn·d, −d).
            val lx = xn * d
            val ly = -yn * d
            val lz = -d
            val wx = r00 * lx + r01 * ly + r02 * lz + tx
            val wy = r10 * lx + r11 * ly + r12 * lz + ty
            val wz = r20 * lx + r21 * ly + r22 * lz + tz
            if (!wx.isFinite() || !wy.isFinite() || !wz.isFinite()) return null
            return doubleArrayOf(wx, wy, wz, d)
        }

        val step = max(4, sqrt(depthW.toDouble() * depthH / 500.0).toInt())
        val raw = ArrayList<Double>(512 * 3)
        var sumDist = 0.0
        var row = 0
        while (row < depthH) {
            var col = 0
            while (col < depthW) {
                val p = worldAt(col, row)
                if (p != null) {
                    raw.add(p[0])
                    raw.add(p[1])
                    raw.add(p[2])
                    val vx = p[0] - tx
                    val vy = p[1] - ty
                    val vz = p[2] - tz
                    sumDist += sqrt(vx * vx + vy * vy + vz * vz)
                }
                col += step
            }
            row += step
        }
        val n = raw.size / 3
        // Sanity invariant: the depth-image centre must land ahead of the
        // camera (world forward = R·(0,0,−1)); a flipped rotation would put
        // every point behind the phone.
        val centre = worldAt(depthW / 2, depthH / 2)
        var ahead = 0
        if (centre != null) {
            val vx = centre[0] - tx
            val vy = centre[1] - ty
            val vz = centre[2] - tz
            if (vx * -r02 + vy * -r12 + vz * -r22 > 0.0) ahead = 1
        }
        NativeTrace.log(
            viewContext,
            "arview: getDepthPoints n=$n mean=${if (n > 0) sumDist / n else 0.0} ahead=$ahead step=$step",
        )
        if (n == 0) return emptyList()
        val stride = (n / 400).coerceAtLeast(1)
        val out = ArrayList<Double>(((n + stride - 1) / stride) * 3)
        var i = 0
        while (i < raw.size) {
            out.add(raw[i])
            out.add(raw[i + 1])
            out.add(raw[i + 2])
            i += stride * 3
        }
        return out
    }

    private fun qStr(q: Quaternion) = "(${q.x},${q.y},${q.z},${q.w})"

    // True while every sample of the yawed footprint rect sits inside the
    // glue plane's polygon — the drag-side twin of Dart's footprintFitsInZones.
    private fun footprintWithinPlane(
        px: Float,
        py: Float,
        pz: Float,
        yaw: Float,
        widthM: Float,
        depthM: Float,
        centerX: Float,
        centerZ: Float,
        plane: Plane?,
    ): Boolean {
        if (plane == null || plane.trackingState != TrackingState.TRACKING) return false
        val c = cos(yaw)
        val s = sin(yaw)
        val halfW = widthM * 0.5f
        val halfD = depthM * 0.5f
        // 4 corners + 4 edge midpoints + center, same sample set as Dart.
        val offsets = floatArrayOf(
            -1f, -1f, 1f, -1f, 1f, 1f, -1f, 1f,
            0f, -1f, 1f, 0f, 0f, 1f, -1f, 0f,
            0f, 0f,
        )
        var i = 0
        while (i < offsets.size) {
            val lx = centerX + offsets[i] * halfW
            val lz = centerZ + offsets[i + 1] * halfD
            i += 2
            val wx = px + lx * c + lz * s
            val wz = pz - lx * s + lz * c
            val pose = Pose(
                floatArrayOf(wx, py, wz),
                floatArrayOf(0f, 0f, 0f, 1f),
            )
            if (!plane.isPoseInPolygon(pose)) return false
        }
        return true
    }

    private fun handleGetAnchorPose(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val anchorId = call.argument<String>("anchorId")
            if (anchorId == null) {
                result.error("INVALID_ARGUMENT", "Anchor ID is required", null)
                return
            }

            val anchor = sceneView.session?.allAnchors?.find { it.cloudAnchorId == anchorId }
            if (anchor != null) {
                // Column-major 4x4, matching MatrixConverter.fromJson on the
                // Dart side (this used to send a {position, rotation} map that
                // the cast rejected, so getPose() always returned null).
                result.success(serializePose(anchor.pose).toList())
            } else {
                result.error("ANCHOR_NOT_FOUND", "Anchor with ID $anchorId not found", null)
            }
        } catch (e: Exception) {
            result.error("ANCHOR_POSE_ERROR", e.message, null)
        }
    }

    private fun handleSnapshot(result: MethodChannel.Result) {
        try {
            mainScope.launch {
                val bitmap =
                    withContext(Dispatchers.Main) {
                        val bitmap =
                            Bitmap.createBitmap(
                                sceneView.width,
                                sceneView.height,
                                Bitmap.Config.ARGB_8888,
                            )

                        try {
                            val listener =
                                PixelCopy.OnPixelCopyFinishedListener { copyResult ->
                                    if (copyResult == PixelCopy.SUCCESS) {
                                        val byteStream = java.io.ByteArrayOutputStream()
                                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteStream)
                                        val byteArray = byteStream.toByteArray()
                                        result.success(byteArray)
                                    } else {
                                        result.error("SNAPSHOT_ERROR", "Failed to capture snapshot", null)
                                    }
                                }

                            PixelCopy.request(
                                sceneView,
                                bitmap,
                                listener,
                                Handler(Looper.getMainLooper()),
                            )
                        } catch (e: Exception) {
                            result.error("SNAPSHOT_ERROR", e.message, null)
                        }
                    }
            }
        } catch (e: Exception) {
            result.error("SNAPSHOT_ERROR", e.message, null)
        }
    }

    private fun handleShowPlanes(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val showPlanes = call.argument<Boolean>("showPlanes") ?: false
            sceneView.apply {
                planeRenderer.isEnabled = showPlanes
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("SHOW_PLANES_ERROR", e.message, null)
        }
    }

    private fun handleAddAnchor(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val anchorType = call.argument<Int>("type")
            if (anchorType == 0) { // Plane Anchor
                val transform = call.argument<ArrayList<Double>>("transformation")
                val name = call.argument<String>("name")

                if (name != null && transform != null) {
                    try {
                        // Position + UNIT quaternion from the full matrix —
                        // the old path built the Pose with quaternion w = 1
                        // (wrong for any non-identity rotation) and then
                        // overwrote the AnchorNode's transform with a
                        // quaternion misread as Euler angles.
                        val parts = deserializePoseParts(transform)

                        val pose =
                            Pose(
                                floatArrayOf(
                                    parts.position.x,
                                    parts.position.y,
                                    parts.position.z
                                ),
                                parts.quaternion,
                            )

                        val anchor = sceneView.session?.createAnchor(pose)
                        if (anchor != null) {
                            // AnchorNode syncs its transform from anchor.pose
                            // (and re-syncs while TRACKING) — no manual
                            // transform override here.
                            val anchorNode = AnchorNode(sceneView.engine, anchor)

                            sceneView.addChildNode(anchorNode)
                            anchorNodesMap[name] = anchorNode
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in transform calculation: ${e.message}")
                        result.success(false)
                    }
                } else {
                    result.success(false)
                }
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleAddAnchor: ${e.message}")
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun handleInitGoogleCloudAnchorMode(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔄 Initialisation du mode Cloud Anchor...")
            sceneView.session?.let { session ->
                session.configure(session.config.apply {
                    cloudAnchorMode = Config.CloudAnchorMode.ENABLED
                })
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Erreur lors de l'initialisation du mode Cloud Anchor", e)
            mainScope.launch {
                sessionChannel.invokeMethod("onError", listOf("Error initializing cloud anchor mode: ${e.message}"))
            }
            result.error("CLOUD_ANCHOR_INIT_ERROR", e.message, null)
        }
    }

    private fun handleUploadAnchor(call: MethodCall, result: MethodChannel.Result) {
        try {
            val anchorName = call.argument<String>("name")
            Log.d(TAG, "⚓ Début de l'upload de l'ancre: $anchorName")
            
            // Vérifier si le mode Cloud Anchor est initialisé
            val session = sceneView.session
            if (session == null) {
                Log.e(TAG, "❌ Erreur: session AR non disponible")
                result.error("SESSION_ERROR", "AR Session is not available", null)
                return
            }

            // Vérifier et initialiser le mode Cloud Anchor si nécessaire
            Log.d(TAG, "🔄 Vérification de la configuration Cloud Anchor...")
            try {
                sceneView.configureSession { session, config ->
                    config.cloudAnchorMode = Config.CloudAnchorMode.ENABLED
                    config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                }
                Log.d(TAG, "✅ Mode Cloud Anchor configuré avec succès")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Erreur lors de la configuration du mode Cloud Anchor", e)
                result.error("CLOUD_ANCHOR_CONFIG_ERROR", e.message, null)
                return
            }

            // Continuer avec le reste du code existant...
            if (anchorName == null) {
                Log.e(TAG, "❌ Erreur: nom de l'ancre manquant")
                result.error("INVALID_ARGUMENT", "Anchor name is required", null)
                return
            }

            Log.d(TAG, "📱 Vérification de la capacité à héberger l'ancre cloud...")
            if (!session.canHostCloudAnchor(sceneView.cameraNode)) {
                Log.e(TAG, "❌ Erreur: données visuelles insuffisantes pour héberger l'ancre cloud")
                result.error("HOSTING_ERROR", "Insufficient visual data to host", null)
                return
            }

            val anchorNode = anchorNodesMap[anchorName]
            if (anchorNode == null) {
                Log.e(TAG, "❌ Erreur: ancre non trouvée: $anchorName")
                Log.d(TAG, "📍 Ancres disponibles: ${anchorNodesMap.keys}")
                result.error("ANCHOR_NOT_FOUND", "Anchor not found: $anchorName", null)
                return
            }

            Log.d(TAG, "🔄 Création du CloudAnchorNode...")
            val cloudAnchorNode = CloudAnchorNode(sceneView.engine, anchorNode.anchor!!)
            
            Log.d(TAG, "☁️ Début de l'hébergement de l'ancre cloud...")
            cloudAnchorNode.host(session) { cloudAnchorId, state ->
                Log.d(TAG, "📡 État de l'hébergement: $state, ID: $cloudAnchorId")
                mainScope.launch {
                    if (state == CloudAnchorState.SUCCESS && cloudAnchorId != null) {
                        Log.d(TAG, "✅ Ancre cloud hébergée avec succès: $cloudAnchorId")
                        val args = mapOf(
                            "name" to anchorName,
                            "cloudanchorid" to cloudAnchorId
                        )
                        anchorChannel.invokeMethod("onCloudAnchorUploaded", args)
                        result.success(true)
                    } else {
                        Log.e(TAG, "❌ Échec de l'hébergement de l'ancre cloud: $state")
                        sessionChannel.invokeMethod("onError", listOf("Failed to host cloud anchor: $state"))
                        result.error("HOSTING_ERROR", "Failed to host cloud anchor: $state", null)
                    }
                }
            }
            
            Log.d(TAG, "➕ Ajout du CloudAnchorNode à la scène...")
            sceneView.addChildNode(cloudAnchorNode)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception lors de l'upload de l'ancre", e)
            Log.e(TAG, "Stack trace:", e)
            result.error("UPLOAD_ANCHOR_ERROR", e.message, null)
        }
    }

    private fun handleDownloadAnchor(call: MethodCall, result: MethodChannel.Result) {
        try {
            val cloudAnchorId = call.argument<String>("cloudanchorid")
            if (cloudAnchorId == null) {
                mainScope.launch {
                    sessionChannel.invokeMethod("onError", listOf("Cloud Anchor ID is required"))
                }
                result.error("INVALID_ARGUMENT", "Cloud Anchor ID is required", null)
                return
            }

            val session = sceneView.session
            if (session == null) {
                mainScope.launch {
                    sessionChannel.invokeMethod("onError", listOf("AR Session is not available"))
                }
                result.error("SESSION_ERROR", "AR Session is not available", null)
                return
            }

            CloudAnchorNode.resolve(
                sceneView.engine,
                session,
                cloudAnchorId
            ) { state, node ->
                mainScope.launch {
                    if (!state.isError && node != null) {
                        sceneView.addChildNode(node)
                        val anchorData = mapOf(
                            "type" to 0,
                            "cloudanchorid" to cloudAnchorId
                        )
                        anchorChannel.invokeMethod(
                            "onAnchorDownloadSuccess",
                            anchorData,
                            object : MethodChannel.Result {
                                override fun success(result: Any?) {
                                    val anchorName = result.toString()
                                    anchorNodesMap[anchorName] = node
                                }

                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                    sessionChannel.invokeMethod("onError", listOf("Error registering downloaded anchor: $errorMessage"))
                                }

                                override fun notImplemented() {
                                    sessionChannel.invokeMethod("onError", listOf("Error registering downloaded anchor: not implemented"))
                                }
                            }
                        )
                        result.success(true)
                    } else {
                        sessionChannel.invokeMethod("onError", listOf("Failed to resolve cloud anchor: $state"))
                        result.error("RESOLVE_ERROR", "Failed to resolve cloud anchor: $state", null)
                    }
                }
            }
        } catch (e: Exception) {
            mainScope.launch {
                sessionChannel.invokeMethod("onError", listOf("Error downloading anchor: ${e.message}"))
            }
            result.error("DOWNLOAD_ANCHOR_ERROR", e.message, null)
        }
    }

    override fun getView(): View = rootLayout

    override fun dispose() {
        Log.i(TAG, "dispose")
        NativeTrace.log(viewContext, "arview: dispose")
        sessionChannel.setMethodCallHandler(null)
        objectChannel.setMethodCallHandler(null)
        anchorChannel.setMethodCallHandler(null)
        // Dart's ticker can still have a call in flight here; without this
        // it landed in frame.acquireDepthImage on a destroyed session and
        // SIGSEGV'd in libarcore_c (device tombstone 2026-11-10 21:21:08).
        latestFrame = null
        lastFrameAtMs = 0L
        nodesMap.clear()
        livePlanes.clear()
        planeLastFreshAt.clear()
        planeIds.clear()
        pointAccumulator.clear()
        sceneView.destroy()
        pointCloudNodes.toList().forEach { removePointCloudNode(it) }
        pointCloudModelInstances.clear()
    }

    private fun notifyError(error: String) {
        mainScope.launch {
            sessionChannel.invokeMethod("onError", listOf(error))
        }
    }

    private fun notifyCloudAnchorUploaded(args: Map<String, Any>) {
        mainScope.launch {
            anchorChannel.invokeMethod("onCloudAnchorUploaded", args)
        }
    }

    private fun notifyAnchorDownloadSuccess(
        anchorData: Map<String, Any>,
        result: MethodChannel.Result,
    ) {
        mainScope.launch {
            anchorChannel.invokeMethod(
                "onAnchorDownloadSuccess",
                anchorData,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val anchorName = result.toString()
                        // Mettre à jour l'ancre avec le nom reçu
                    }

                    override fun error(
                        errorCode: String,
                        errorMessage: String?,
                        errorDetails: Any?,
                    ) {
                        notifyError("Error while registering downloaded anchor: $errorMessage")
                    }

                    override fun notImplemented() {
                        notifyError("Error while registering downloaded anchor")
                    }
                },
            )
        }
    }

    private fun notifyPlaneOrPointTap(hitResults: List<Map<String, Any>>) {
        mainScope.launch {
            try {
                val serializedResults = ArrayList<HashMap<String, Any>>()
                hitResults.forEach { hit ->
                    serializedResults.add(serializeHitResult(hit))
                }
                sessionChannel.invokeMethod("onPlaneOrPointTap", serializedResults)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun getPointCloudModelInstance(): ModelInstance? {
        if (pointCloudModelInstances.isEmpty()) {
            pointCloudModelInstances =
                sceneView.modelLoader
                    .createInstancedModel(
                        assetFileLocation = "models/point_cloud.glb",
                        count = 1000,
                    ).toMutableList()
        }
        return pointCloudModelInstances.removeLastOrNull()
    }

    private fun addPointCloudNode(
        id: Int,
        position: Position,
        confidence: Float,
    ) {
        if (pointCloudNodes.size < 1000) { // Limite max de points
            getPointCloudModelInstance()?.let { modelInstance ->
                val pointCloudNode =
                    PointCloudNode(
                        modelInstance = modelInstance,
                        id = id,
                        confidence = confidence,
                    ).apply {
                        this.position = position
                    }
                pointCloudNodes += pointCloudNode
                sceneView.addChildNode(pointCloudNode)
            }
        }
    }

    private fun removePointCloudNode(pointCloudNode: PointCloudNode) {
        pointCloudNodes -= pointCloudNode
        sceneView.removeChildNode(pointCloudNode)
        pointCloudNode.destroy()
    }

    private fun makeWorldOriginNode(context: Context): Node {
        val axisSize = 0.1f
        val axisRadius = 0.005f
        
        // Utilisation de l'engine de sceneView
        val engine = sceneView.engine
        val materialLoader = MaterialLoader(engine, context)
        
        // Création du noeud racine
        val rootNode = Node(engine = engine)
        
        // Création des cylindres avec leurs matériaux respectifs
        val xNode = CylinderNode(
            engine = engine,
            radius = axisRadius,
            height = axisSize,
            materialInstance = materialLoader.createColorInstance(
                color = colorOf(1f, 0f, 0f, 1f),
                metallic = 0.0f,
                roughness = 0.4f
            )
        )
        
        val yNode = CylinderNode(
            engine = engine,
            radius = axisRadius,
            height = axisSize,
            materialInstance = materialLoader.createColorInstance(
                color = colorOf(0f, 1f, 0f, 1f),
                metallic = 0.0f,
                roughness = 0.4f
            )
        )
        
        val zNode = CylinderNode(
            engine = engine,
            radius = axisRadius,
            height = axisSize,
            materialInstance = materialLoader.createColorInstance(
                color = colorOf(0f, 0f, 1f, 1f),
                metallic = 0.0f,
                roughness = 0.4f
            )
        )

        rootNode.addChildNode(xNode)
        rootNode.addChildNode(yNode)
        rootNode.addChildNode(zNode)

        // Positionnement des axes
        xNode.position = Position(axisSize / 2, 0f, 0f)
        xNode.rotation = Rotation(0f, 0f, 90f)  // Rotation autour de l'axe Z

        yNode.position = Position(0f, axisSize / 2, 0f)
        // Pas besoin de rotation pour l'axe Y car il est déjà orienté correctement

        zNode.position = Position(0f, 0f, axisSize / 2)
        zNode.rotation = Rotation(90f, 0f, 0f)  // Rotation autour de l'axe X

        return rootNode
    }

    private fun handleShowWorldOrigin(show: Boolean) {
        if (show) {
            // Création du nouveau node seulement si nécessaire
            if (worldOriginNode == null) {
                worldOriginNode = makeWorldOriginNode(viewContext)
            }
            // Utilisation du safe call operator
            worldOriginNode?.let { node ->
                sceneView.addChildNode(node)
            }
        } else {
            // Utilisation du safe call operator
            worldOriginNode?.let { node ->
                sceneView.removeChildNode(node)
            }
            // Optionnel : remettre à null après suppression
            worldOriginNode = null
        }
    }

    
}