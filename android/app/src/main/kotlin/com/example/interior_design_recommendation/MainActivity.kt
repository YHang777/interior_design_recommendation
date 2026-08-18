package com.example.interior_design_recommendation

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Exposes ARCore (Google Play Services for AR) availability to Dart so
        // the AR screen can show a helpful message instead of a dead camera.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.interior_design_recommendation/arcore",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isArCoreAvailable" -> {
                    result.success(isArCoreAvailable())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isArCoreAvailable(): Boolean {
        val pm = packageManager
        return try {
            // Google Play Services for AR must be installed. Note: we only
            // check the package — devices outside Google's official ARCore
            // whitelist often do NOT declare the "android.hardware.camera.ar"
            // system feature even when a sideloaded ARCore works, so the
            // feature check would wrongly report "unavailable".
            pm.getPackageInfo("com.google.ar.core", 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }
}
