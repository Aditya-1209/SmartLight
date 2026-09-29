package com.aditya.smartlight.smart_light

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TuyaPairingBridge(activity: Activity) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "available" -> result.success(false)
            "close", "cancel" -> result.success(null)
            else -> result.error("not_configured", "This build does not include Tuya pairing.", null)
        }
    }
    fun onPermissions(code: Int, grants: IntArray) {}
    fun close() {}
}
