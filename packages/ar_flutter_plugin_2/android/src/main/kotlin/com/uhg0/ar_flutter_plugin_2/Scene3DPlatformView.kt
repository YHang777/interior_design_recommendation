package com.uhg0.ar_flutter_plugin_2

import android.content.Context
import android.view.View
import androidx.lifecycle.Lifecycle
import com.google.android.filament.Skybox
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.github.sceneview.SceneView
import io.github.sceneview.collision.Vector3
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

// Non-AR SceneView host: real 3D room preview. Camera math lives in Dart
// (OrbitRig/FirstPersonRig) and arrives as setCamera poses — this side only
// renders. Touches stay with Flutter's gesture layer, so the native
// camera manipulator is never enabled.
class Scene3DPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    lifecycle: Lifecycle,
) : PlatformView {

    private val sceneView = SceneView(context = context, sharedLifecycle = lifecycle)
    private val channel = MethodChannel(messenger, "scene3d_$id")
    private val nodesMap = mutableMapOf<String, ModelNode>()
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var disposed = false

    init {
        loadEnvironment()
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    override fun getView(): View = sceneView

    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        mainScope.cancel()
        nodesMap.values.toList().forEach { sceneView.removeChildNode(it) }
        nodesMap.clear()
        sceneView.destroy()
    }

    // ── environment ──

    // Neutral studio IBL ships inside the sceneview AAR (merged into the APK
    // assets root). Warm HDR from the AR path is the fallback; last resort is
    // the default main light only — lighting is cosmetic, never fatal.
    private fun loadEnvironment() {
        try {
            sceneView.environment = sceneView.environmentLoader.createKTX1Environment(
                "environments/neutral/neutral_ibl.ktx",
                "environments/neutral/neutral_skybox.ktx",
            )
            applyToyModelLook()
            return
        } catch (e: Throwable) {
            NativeTrace.log(viewContextOf(), "scene3d: neutral env failed: $e")
        }
        try {
            sceneView.environmentLoader.createHDREnvironment(
                assetFileLocation = "environments/evening_meadow_2k.hdr"
            )?.let { sceneView.environment = it }
        } catch (e: Throwable) {
            NativeTrace.log(viewContextOf(), "scene3d: hdr env failed: $e")
        }
        applyToyModelLook()
    }

    // Dollhouse studio look: a warm key from upper-right-behind the default
    // opening view casts contact shadows to the screen's lower right, the
    // neutral IBL fills the cut faces, and a dark grey skybox floats the room
    // like a miniature. Setting environment re-applies its own skybox, so this
    // must run after every environment assignment. Cosmetic only — each step
    // is individually guarded and never fatal.
    private fun applyToyModelLook() {
        try {
            sceneView.skybox = Skybox.Builder()
                .color(0.14f, 0.15f, 0.17f, 1.0f)
                .build(sceneView.engine)
        } catch (e: Throwable) {
            NativeTrace.log(viewContextOf(), "scene3d: skybox failed: $e")
        }
        try {
            sceneView.mainLightNode?.let { light ->
                light.lightDirection = Float3(-0.45f, -1.3f, -0.95f)
                light.color = Float4(1.0f, 0.955f, 0.88f, 1.0f)
                light.isShadowCaster = true
            }
        } catch (e: Throwable) {
            NativeTrace.log(viewContextOf(), "scene3d: key light failed: $e")
        }
    }

    private fun viewContextOf(): Context = sceneView.context

    // ── method channel ──

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "setCamera" -> handleSetCamera(call, result)
                "addModel" -> handleAddModel(call, result)
                "updateModel" -> handleUpdateModel(call, result)
                "removeModel" -> handleRemoveModel(call, result)
                "clearModels" -> {
                    nodesMap.values.toList().forEach { sceneView.removeChildNode(it) }
                    nodesMap.clear()
                    result.success(null)
                }
                "hitTest" -> handleHitTest(call, result)
                "worldToScreen" -> handleWorldToScreen(call, result)
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            result.error("SCENE3D_ERROR", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun handleSetCamera(call: MethodCall, result: MethodChannel.Result) {
        val eye = float3Of(call.argument<List<Any?>>("eye")) ?: Float3(0.0f, 1.6f, 3.0f)
        val target = float3Of(call.argument<List<Any?>>("target")) ?: Float3(0.0f)
        val up = float3Of(call.argument<List<Any?>>("up")) ?: Float3(0.0f, 1.0f, 0.0f)
        val fovDeg = numOf(call.argument<Any?>("fovDeg")) ?: 55.0f
        sceneView.cameraNode.lookAt(eye, target, up)
        // Vertical FOV; aspect follows the laid-out surface, with a sane
        // placeholder before the first layout pass.
        val w = sceneView.width
        val h = sceneView.height
        val aspect = if (w > 0 && h > 0) w.toDouble() / h.toDouble() else 16.0 / 9.0
        sceneView.cameraNode.setLensProjection(fovDeg.toDouble(), aspect, 0.05, 100.0)
        result.success(null)
    }

    private fun handleAddModel(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val source = call.argument<String>("source")
        if (id == null || source == null) {
            result.error("INVALID_ARGUMENTS", "id and source are required", null)
            return
        }
        val fileLocation = when (call.argument<String>("sourceType")) {
            "asset" -> FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(source)
            else -> source
        }
        val transform = readTransform(call)
        sceneView.modelLoader.loadModelInstanceAsync(fileLocation) { instance ->
            mainScope.launch {
                if (disposed) return@launch
                if (instance == null) {
                    result.error("MODEL_LOAD_ERROR", "failed to load $source", null)
                    return@launch
                }
                nodesMap.remove(id)?.let { sceneView.removeChildNode(it) }
                val node = ModelNode(modelInstance = instance, autoAnimate = false)
                node.name = id
                applyTransform(node, transform)
                nodesMap[id] = node
                sceneView.addChildNode(node)
                result.success(null)
            }
        }
    }

    private fun handleUpdateModel(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val node = id?.let { nodesMap[it] }
        if (node == null) {
            result.error("UNKNOWN_MODEL", "no model with id $id", null)
            return
        }
        applyTransform(node, readTransform(call))
        result.success(null)
    }

    private fun handleRemoveModel(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val node = id?.let { nodesMap.remove(it) }
        if (node != null) {
            sceneView.removeChildNode(node)
        }
        result.success(null)
    }

    private fun handleHitTest(call: MethodCall, result: MethodChannel.Result) {
        val x = numOf(call.argument<Any?>("x")) ?: 0.0f
        val y = numOf(call.argument<Any?>("y")) ?: 0.0f
        val hits = sceneView.cameraNode.hitTest(x, y).mapNotNull { hit ->
            val name = hit.node?.name ?: return@mapNotNull null
            if (!nodesMap.containsKey(name)) return@mapNotNull null
            val p = hit.worldPosition
            mapOf(
                "id" to name,
                "distance" to hit.distance.toDouble(),
                "x" to p.x.toDouble(),
                "y" to p.y.toDouble(),
                "z" to p.z.toDouble(),
            )
        }.sortedBy { it["distance"] as Double }
        result.success(hits)
    }

    private fun handleWorldToScreen(call: MethodCall, result: MethodChannel.Result) {
        val p = float3Of(listOf(call.argument<Any?>("x"), call.argument<Any?>("y"), call.argument<Any?>("z")))
            ?: Float3(0.0f)
        val s = sceneView.cameraNode.worldToScreenPoint(Vector3(p.x, p.y, p.z))
        result.success(mapOf("x" to s.x.toDouble(), "y" to s.y.toDouble()))
    }

    // ── transforms ──

    // x/y/z meters, yawDeg euler degrees around +Y, scale per-axis. y is the
    // FLOOR height the model's feet rest on — the node is grounded so its
    // scaled bounding box minimum sits exactly at y.
    private class Transform(
        val x: Float,
        val y: Float,
        val z: Float,
        val yawDeg: Float,
        val sx: Float,
        val sy: Float,
        val sz: Float,
    )

    private fun readTransform(call: MethodCall): Transform {
        val scale = call.argument<List<Any?>>("scale")
        return Transform(
            x = numOf(call.argument<Any?>("x")) ?: 0.0f,
            y = numOf(call.argument<Any?>("y")) ?: 0.0f,
            z = numOf(call.argument<Any?>("z")) ?: 0.0f,
            yawDeg = numOf(call.argument<Any?>("yawDeg")) ?: 0.0f,
            sx = numOf(scale?.getOrNull(0)) ?: 1.0f,
            sy = numOf(scale?.getOrNull(1)) ?: 1.0f,
            sz = numOf(scale?.getOrNull(2)) ?: 1.0f,
        )
    }

    private fun applyTransform(node: ModelNode, t: Transform) {
        node.scale = Float3(t.sx, t.sy, t.sz)
        // Bounding box is model-space and unscaled; ground the scaled min-Y.
        val minModelY = node.center.y - node.halfExtent.y
        node.position = Float3(t.x, t.y - minModelY * t.sy, t.z)
        node.rotation = Float3(0.0f, t.yawDeg, 0.0f)
    }

    private fun numOf(v: Any?): Float? = (v as? Number)?.toFloat()

    private fun float3Of(list: List<Any?>?): Float3? {
        if (list == null || list.size < 3) return null
        val x = numOf(list[0]) ?: return null
        val y = numOf(list[1]) ?: return null
        val z = numOf(list[2]) ?: return null
        return Float3(x, y, z)
    }
}
