package com.uhg0.ar_flutter_plugin_2

import android.content.Context
import androidx.lifecycle.Lifecycle
import com.google.ar.core.Config
import com.google.ar.core.Session
import io.github.sceneview.ar.ARSceneView

// ARCore throws FatalException out of Session.update() when a new AR screen
// opens while the previous session is still releasing the camera (device
// 2026-11-14: reopen within ~1 s → whole-app exit). SceneView calls update
// from its Choreographer callback with no handler, so the exception killed
// the process. Here a failed frame is skipped and reported instead; frames
// after destroy() never touch the session at all.
class SafeARSceneView(
    context: Context,
    sharedLifecycle: Lifecycle?,
    sessionConfiguration: ((Session, Config) -> Unit)?,
) : ARSceneView(
    context = context,
    sharedLifecycle = sharedLifecycle,
    sessionConfiguration = sessionConfiguration,
) {
    var onFrameError: ((Throwable) -> Unit)? = null

    @Volatile
    private var destroyed = false

    override fun onFrame(frameTimeNanos: Long) {
        if (destroyed) return
        try {
            super.onFrame(frameTimeNanos)
        } catch (e: Exception) {
            onFrameError?.invoke(e)
        }
    }

    override fun destroy() {
        destroyed = true
        super.destroy()
    }
}
