package com.uhg0.ar_flutter_plugin_2

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
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
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.TrackingState
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
import kotlin.math.abs
import kotlin.math.atan2

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
    private var sceneView: ARSceneView
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

    // Last ARCore frame produced by this view's own session.update() call
    // (see the onFrame lambda in handleInit). Gesture callbacks run on the
    // same UI thread between two frame updates, so this frame is still
    // valid while a drag hit-tests against it — used to glue moved nodes
    // back onto real planes.
    private var latestFrame: Frame? = null

    // Live TRACKING-plane snapshot for the onPlanesUpdate telemetry (Bug 2).
    // Keyed by the ARCore Plane (stable per-session reference). A fully-formed
    // floor stops appearing in getUpdatedTrackables once it is stable, but must
    // keep counting as "seen" — so we persist each plane here when it updates
    // and only drop it once it stops tracking. Read/merged on the frame thread.
    private val livePlanes = mutableMapOf<Plane, Map<String, Any>>()

    // Stable integer id per ARCore Plane, so the app's PlaneMemory can keep
    // per-plane history (smoothing + reclassification) across telemetry
    // frames. ARCore exposes no public trackable id, so we mint our own.
    private val planeIds = java.util.IdentityHashMap<Plane, Int>()
    private var nextPlaneId = 1

    private fun planeIdFor(plane: Plane): Int =
        planeIds.getOrPut(plane) { nextPlaneId++ }

    // Throttle for the onPlanesUpdate telemetry: stream the live plane
    // snapshot to Flutter every ~3rd frame (not every frame) to keep the
    // channel traffic cheap. Counter is only touched on the frame thread.
    private var planesFrameCounter = 0

    private class PointCloudNode(
        modelInstance: ModelInstance,
        var id: Int,
        var confidence: Float,
    ) : ModelNode(modelInstance)

    private val onSessionMethodCall =
        MethodChannel.MethodCallHandler { call, result ->
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
                "hitTest" -> handleHitTest(call, result)
                else -> result.notImplemented()
            }
        }
    private fun handleDisableCamera(result: MethodChannel.Result) {
        try {
            isSessionPaused = true
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
        sceneView = ARSceneView(
            context = viewContext,
            sharedLifecycle = lifecycle,
            sessionConfiguration = { session, config ->
                config.apply {
                    depthMode = Config.DepthMode.DISABLED
                    instantPlacementMode = Config.InstantPlacementMode.DISABLED
                    lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                    focusMode = Config.FocusMode.AUTO
                    planeFindingMode = Config.PlaneFindingMode.DISABLED
                }
            }
        )
        
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

        return try {
            sceneView.modelLoader.loadModelInstance(fileLocation)?.let { modelInstance ->
                object : ModelNode(
                    modelInstance = modelInstance,
                    scaleToUnits = transformation.first().toFloat(),
                ) {
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
                                latestFrame?.hitTest(moveEvent.x, moveEvent.y)
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
                                        anchorNode.worldPosition =
                                            Position(t[0], t[1], t[2])
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
                            parent?.onMoveEnd(detector, e)
                            val transformMap = mapOf(
                                "name" to name,
                                "transform" to transform.toFloatArray().toList()
                            )
                            objectChannel.invokeMethod("onPanEnd", transformMap)
                        }
                    }

                    override fun onRotateBegin(detector: RotateGestureDetector, e: MotionEvent): Boolean {
                        if (handleRotation) {
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
                        val deltaRad = detector.currentAngle - detector.lastAngle
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
                        }
                        objectChannel.invokeMethod("onRotationChange", name)
                        return true
                    }

                    override fun onRotateEnd(detector: RotateGestureDetector, e: MotionEvent) {
                        if (handleRotation) {
                            super.onRotateEnd(detector, e)
                            val transformMap = mapOf(
                                "name" to name,
                                "transform" to transform.toFloatArray().toList()
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

            sceneView.session?.let { session ->
                session.configure(session.config.apply {
                    depthMode = when (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                        true -> Config.DepthMode.AUTOMATIC
                        else -> Config.DepthMode.DISABLED
                    }
                    planeFindingMode = when (argPlaneDetectionConfig) {
                        1 -> Config.PlaneFindingMode.HORIZONTAL
                        2 -> Config.PlaneFindingMode.VERTICAL
                        3 -> Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                        else -> Config.PlaneFindingMode.DISABLED
                    }
                })
            }

            handleShowWorldOrigin(showWorldOrigin)
            
            sceneView.apply {
                environment = environmentLoader.createHDREnvironment(
                    assetFileLocation = "environments/evening_meadow_2k.hdr"
                )!!

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
                    try {
                        if (!isSessionPaused) {
                            run {
                                latestFrame = frame
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
                                    // one — drop them so the app never counts a
                                    // table top twice (once alone, once inside
                                    // the floor polygon it merged into).
                                    if (plane.trackingState == TrackingState.TRACKING &&
                                        plane.subsumedBy == null
                                    ) {
                                        livePlanes[plane] = planeTelemetry(plane)
                                    } else {
                                        livePlanes.remove(plane)
                                    }
                                }

                                // Stream the snapshot to Flutter every ~3rd frame (throttled).
                                planesFrameCounter++
                                if (planesFrameCounter % 3 == 0) {
                                    val planesPayload = ArrayList(livePlanes.values)
                                    mainScope.launch {
                                        sessionChannel.invokeMethod("onPlanesUpdate", planesPayload)
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        when (e) {
                            is SessionPausedException -> {
                                // Ignorer silencieusement cette exception quand la session est en pause
                                Log.d(TAG, "Session paused, skipping frame update")
                            }
                            else -> {
                                Log.e(TAG, "Error during frame update", e)
                                e.printStackTrace()
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
                            if(handleTaps) {
                                objectChannel.invokeMethod("onNodeTap", listOf(anchorName))
                            }
                            true
                        } else {
                            // Hit-test against the frame the render loop already
                            // produced. Calling session.update() here (as this
                            // used to) is an EXTRA update ARCore never expects
                            // mid-gesture — it desyncs tracking. `latestFrame` is
                            // refreshed every frame by onSessionUpdated above.
                            latestFrame?.let { frame ->
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
            result.success(null)
        } catch (e: Exception) {
            result.error("AR_VIEW_ERROR", e.message, null)
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
            val cameraPose = latestFrame?.camera?.pose
            if (cameraPose != null) {
                // Column-major 4x4 — the exact format the Dart side
                // (MatrixConverter.fromJson) expects. This handler used to
                // return a {position, rotation} map, which the cast rejected,
                // so getCameraPose() silently returned null every call.
                result.success(serializePose(cameraPose).toList())
            } else {
                result.error("NO_CAMERA_POSE", "Camera pose is not available", null)
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
        )
    }

    // The render-ready camera pair: getViewMatrix() incorporates the display
    // orientation and getProjectionMatrix() the display rotation (both
    // column-major), so projection * view maps world → clip exactly like the
    // camera feed the AR content is drawn over.
    private fun handleGetCameraMatrices(result: MethodChannel.Result) {
        try {
            val camera = latestFrame?.camera
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
            val frame = latestFrame
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
            val frame = latestFrame
            if (frame == null) {
                result.success(null)
                return
            }

            val cloud = frame.acquirePointCloud()
            try {
                val points = cloud.points
                val fit = PlaneRefiner.refine(
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
            result.error("REFINE_PLANE_ERROR", e.message, null)
        }
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
        sessionChannel.setMethodCallHandler(null)
        objectChannel.setMethodCallHandler(null)
        anchorChannel.setMethodCallHandler(null)
        nodesMap.clear()
        livePlanes.clear()
        planesFrameCounter = 0
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