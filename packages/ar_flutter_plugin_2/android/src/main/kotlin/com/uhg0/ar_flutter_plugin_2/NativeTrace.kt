package com.uhg0.ar_flutter_plugin_2

import android.content.Context
import java.io.File

// Breadcrumb file for devices where logcat is redacted (Honor). Read with
//   adb shell run-as com.example.interior_design_recommendation cat files/ar_native_trace.log
// The last line before a crash says how far the AR open path got.
object NativeTrace {
    fun log(context: Context, message: String) {
        try {
            File(context.filesDir, "ar_native_trace.log")
                .appendText("[${System.currentTimeMillis()}] $message\n")
        } catch (_: Exception) {
        }
    }
}
