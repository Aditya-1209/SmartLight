package com.aditya.smartlight.smart_light

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.bean.HomeBean
import com.thingclips.smart.home.sdk.callback.IThingGetHomeListCallback
import com.thingclips.smart.home.sdk.callback.IThingHomeResultCallback
import com.thingclips.smart.android.user.api.ILoginCallback
import com.thingclips.smart.android.user.bean.User
import com.thingclips.smart.sdk.api.IThingActivator
import com.thingclips.smart.sdk.api.IThingActivatorGetToken
import com.thingclips.smart.sdk.api.IThingSmartActivatorListener
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.enums.ActivatorModelEnum
import com.thingclips.smart.home.sdk.builder.ActivatorBuilder
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The SDK is used only in the user-opened pairing flow; Dart handles normal LAN control. */
class TuyaPairingBridge(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var initialized = false
    private var pending: MethodChannel.Result? = null
    private var epoch = 0
    private var homeId = 0L
    private var token: String? = null
    private var tokenAt = 0L
    private var permissionOperation: Int? = null
    private var activator: IThingActivator? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "available") { result.success(true); return }
        if (call.method == "close") { close(); result.success(null); return }
        if (call.method == "cancel") { cancel(); result.success(null); return }
        if (call.method == "wifiSettings") {
            activity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)); result.success(null); return
        }
        if (pending != null) { result.error("busy", "Another setup operation is in progress.", null); return }
        pending = result
        val operation = ++epoch
        handler.postDelayed({
            if (live(operation)) fail(operation, "timeout", "Setup timed out. Check Wi-Fi and try again.")
        }, if (call.method == "pair") 130_000L else 45_000L)
        try {
            when (call.method) {
                "prepare" -> {
                    val uid = call.argument<String>("uid").orEmpty()
                    val password = call.argument<String>("password").orEmpty()
                    if (uid.length < 20 || password.length < 20) {
                        fail(operation, "invalid_profile", "The secure pairing profile is missing."); return
                    }
                    if (!initialized) {
                        ThingHomeSdk.setDebugMode(false)
                        ThingHomeSdk.init(activity.application)
                        initialized = true
                    }
                    ThingHomeSdk.getUserInstance().loginOrRegisterWithUid("91", uid, password,
                        object : ILoginCallback {
                            override fun onSuccess(user: User?) { onMain(operation) { loadHomes(operation) } }
                            override fun onError(code: String?, error: String?) {
                                sdkError(operation, code, "Could not prepare the pairing account")
                            }
                        })
                }
                "permissions" -> {
                    if (activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                        succeed(operation, true)
                    } else {
                        permissionOperation = operation
                        activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION), 7421)
                    }
                }
                "token" -> {
                    if (!initialized || homeId == 0L) { fail(operation, "not_ready", "Prepare setup first."); return }
                    ThingHomeSdk.getActivatorInstance().getActivatorToken(homeId, object : IThingActivatorGetToken {
                        override fun onSuccess(value: String?) { onMain(operation) {
                            token = value; tokenAt = android.os.SystemClock.elapsedRealtime()
                            succeed(operation, null)
                        } }
                        override fun onFailure(code: String?, error: String?) { sdkError(operation, code, "Could not start pairing") }
                    })
                }
                "pair" -> pair(call, operation)
                else -> fail(operation, "unsupported", "Unknown setup operation.")
            }
        } catch (_: Exception) {
            fail(operation, "setup_error", "Could not start setup. Check the SDK configuration and try again.")
        }
    }

    private fun loadHomes(operation: Int) {
        ThingHomeSdk.getHomeManagerInstance().queryHomeList(object : IThingGetHomeListCallback {
            override fun onSuccess(homes: MutableList<HomeBean>?) { onMain(operation) {
                val home = homes?.firstOrNull()
                if (home != null) readHome(operation, home.homeId)
                else ThingHomeSdk.getHomeManagerInstance().createHome("SmartLight", 0.0, 0.0, "", emptyList(),
                    object : IThingHomeResultCallback {
                        override fun onSuccess(bean: HomeBean?) { onMain(operation) {
                            if (bean == null) fail(operation, "missing_home", "Tuya did not return a home.")
                            else readHome(operation, bean.homeId)
                        } }
                        override fun onError(code: String?, error: String?) { sdkError(operation, code, "Could not create setup home") }
                    })
            } }
            override fun onError(code: String?, error: String?) { sdkError(operation, code, "Could not load paired lights") }
        })
    }
    private fun readHome(operation: Int, id: Long) {
        homeId = id
        ThingHomeSdk.newHomeInstance(id).getHomeDetail(object : IThingHomeResultCallback {
            override fun onSuccess(bean: HomeBean?) { onMain(operation) {
                succeed(operation, bean?.deviceList?.map { deviceMap(it) } ?: emptyList<Any>())
            } }
            override fun onError(code: String?, error: String?) { sdkError(operation, code, "Could not load paired lights") }
        })
    }
    private fun pair(call: MethodCall, operation: Int) {
        val ssid = call.argument<String>("ssid").orEmpty()
        val password = call.argument<String>("password").orEmpty()
        val mode = call.argument<String>("mode")
        if (ssid.isEmpty() || ssid.toByteArray().size > 32 || password.toByteArray().size > 63 || mode !in listOf("EZ", "AP")) {
            fail(operation, "wifi_details", "Enter the Wi-Fi name and password."); return
        }
        val pairingToken = token
        if (pairingToken.isNullOrEmpty() || android.os.SystemClock.elapsedRealtime() - tokenAt > 540_000) {
            fail(operation, "expired", "Pairing session expired. Rejoin your home Wi-Fi and prepare pairing again."); return
        }
        token = null // Each pairing attempt must obtain a fresh token.
        val builder = ActivatorBuilder().setContext(activity).setSsid(ssid).setPassword(password)
            .setToken(pairingToken).setTimeOut(120)
            .setActivatorModel(if (mode == "AP") ActivatorModelEnum.THING_AP else ActivatorModelEnum.THING_EZ)
            .setListener(object : IThingSmartActivatorListener {
                override fun onError(code: String?, error: String?) { sdkError(operation, code, "The light could not be paired") }
                override fun onActiveSuccess(device: DeviceBean?) { onMain(operation) {
                    if (device == null) fail(operation, "missing_device", "Tuya did not return the paired light.")
                    else succeed(operation, deviceMap(device))
                } }
                override fun onStep(step: String?, data: Any?) {}
            })
        activator = ThingHomeSdk.getActivatorInstance().newActivator(builder)
        activator?.start()
    }
    private fun deviceMap(bean: DeviceBean): Map<String, Any?> = mapOf(
        "deviceId" to bean.devId, "name" to bean.name, "host" to bean.ip,
        "localKey" to bean.localKey, "version" to bean.pv,
        "dpIds" to (bean.schemaMap?.keys?.toList() ?: emptyList<String>())
    )
    fun onPermissions(code: Int, grants: IntArray) {
        if (code != 7421) return
        val operation = permissionOperation ?: return
        permissionOperation = null
        if (!live(operation)) return
        if (activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) succeed(operation, true)
        else fail(operation, "permission", "Allow location access during pairing so Android can use the Wi-Fi network.")
    }
    private fun live(operation: Int) = operation == epoch && pending != null
    private fun onMain(operation: Int, block: () -> Unit) = activity.runOnUiThread { if (live(operation)) block() }
    private fun sdkError(operation: Int, code: String?, label: String) = onMain(operation) {
        // Raw vendor messages can contain request data. Expose only a bounded error code.
        val safeCode = code?.take(80)?.replace(Regex("[^A-Za-z0-9_-]"), "") ?: "unknown"
        fail(operation, safeCode, "$label ($safeCode).")
    }
    private fun stopPairing() { activator?.stop(); activator?.onDestroy(); activator = null }
    private fun succeed(operation: Int, value: Any?) {
        if (!live(operation)) return
        val result = pending; pending = null
        handler.removeCallbacksAndMessages(null); stopPairing(); result?.success(value)
    }
    private fun fail(operation: Int, code: String, message: String) {
        if (!live(operation)) return
        val result = pending; pending = null
        handler.removeCallbacksAndMessages(null); stopPairing(); result?.error(code, message, null)
    }
    private fun cancel() { fail(epoch, "cancelled", "Pairing cancelled."); epoch++; token = null }
    fun close() {
        cancel(); homeId = 0L
        if (initialized) { ThingHomeSdk.onDestroy(); initialized = false }
    }
}
