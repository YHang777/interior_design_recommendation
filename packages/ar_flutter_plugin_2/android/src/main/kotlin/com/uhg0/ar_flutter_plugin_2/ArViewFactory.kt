package com.uhg0.ar_flutter_plugin_2

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import androidx.lifecycle.Lifecycle

class ArViewFactory(
    private val messenger: BinaryMessenger,
    private val activity: Activity,
    private val lifecycle: Lifecycle
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        NativeTrace.log(context, "factory: create begin id=$viewId")
        return try {
            val view = ArView(context, activity, lifecycle, messenger, viewId)
            NativeTrace.log(context, "factory: create done id=$viewId")
            view
        } catch (e: Throwable) {
            // ARSceneView/Filament/ARCore construction failure (bad GPU
            // driver, OOM, unsupported ARCore) — surface it to Dart instead
            // of letting the Throwable kill the whole app.
            NativeTrace.log(context, "factory: create FAILED id=$viewId: $e")
            FallbackArView(context, messenger, viewId, e)
        }
    }
}

private class FallbackArView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    cause: Throwable,
) : PlatformView {
    private val root = FrameLayout(context)
    private val channels = listOf(
        MethodChannel(messenger, "arsession_$id"),
        MethodChannel(messenger, "arobjects_$id"),
        MethodChannel(messenger, "aranchors_$id"),
    )
    private val message = "AR couldn't start on this device " +
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
        val handler = MethodChannel.MethodCallHandler { _, result ->
            // Dart's handlers are registered before the first call arrives,
            // so push the error alongside the first reply.
            if (!errorSent) {
                errorSent = true
                Handler(Looper.getMainLooper()).post {
                    channels[0].invokeMethod("onError", listOf(message))
                }
            }
            result.error("AR_INIT_ERROR", message, null)
        }
        channels.forEach { it.setMethodCallHandler(handler) }
    }

    override fun getView(): View = root

    override fun dispose() {
        channels.forEach { it.setMethodCallHandler(null) }
    }
}
