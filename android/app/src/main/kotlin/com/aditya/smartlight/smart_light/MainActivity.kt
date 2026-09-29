package com.aditya.smartlight.smart_light

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pairing: TuyaPairingBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pairing = TuyaPairingBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartlight/tuya_pairing")
            .setMethodCallHandler { call, result -> pairing?.handle(call, result) }
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        pairing?.onPermissions(code, grants)
    }
    override fun onDestroy() {
        pairing?.close()
        super.onDestroy()
    }
}
