package com.uhg0.ar_flutter_plugin_2

import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class Scene3DViewFactory(
    private val messenger: BinaryMessenger,
    private val lifecycle: Lifecycle
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return try {
            Scene3DPlatformView(context, messenger, viewId, lifecycle)
        } catch (e: Throwable) {
            // Filament/GPU construction failure must never take the app
            // down — surface the error to Dart instead.
            FallbackScene3DView(context, messenger, viewId, e)
        }
    }
}

private class FallbackScene3DView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    cause: Throwable,
) : PlatformView {
    private val root = FrameLayout(context)
    private val channel = MethodChannel(messenger, "scene3d_$id")
    private val message = "3D view couldn't start on this device " +
        "(${cause.javaClass.simpleName})."
    private var errorSent = false

    init {
        root.setBackgroundColor(Color.BLACK)
        root.addView(
            TextView(context).apply {
                text = message
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setPadding(48, 48, 48, 48)
            },
        )
        channel.setMethodCallHandler { _, result ->
            if (!errorSent) {
                errorSent = true
                Handler(Looper.getMainLooper()).post {
                    channel.invokeMethod("onError", listOf(message))
                }
            }
            result.error("SCENE3D_INIT_ERROR", message, null)
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
