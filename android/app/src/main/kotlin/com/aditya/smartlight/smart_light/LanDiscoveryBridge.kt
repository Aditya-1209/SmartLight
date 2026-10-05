package com.aditya.smartlight.smart_light

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Permit Wi-Fi broadcasts only during a bounded foreground discovery search.
// Lease IDs prevent an old search from releasing a newer search's lock.
class LanDiscoveryBridge(context: Context) {
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private var lock: WifiManager.MulticastLock? = null
    private var nextId = 0L
    private val leases = mutableSetOf<Long>()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                if (leases.size >= 32) {
                    result.error("busy", "Discovery is already busy.", null)
                    return
                }
                try {
                    if (lock?.isHeld != true) {
                        val candidate = wifi.createMulticastLock("SmartLight:TuyaDiscovery")
                        candidate.setReferenceCounted(false)
                        candidate.acquire()
                        lock = candidate
                    }
                    val id = ++nextId
                    leases.add(id)
                    result.success(id)
                } catch (_: Exception) {
                    result.error("unavailable", "Wi-Fi discovery could not be enabled.", null)
                }
            }
            "release" -> {
                val id = (call.arguments as? Number)?.toLong()
                if (id != null) leases.remove(id)
                if (leases.isEmpty()) close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun close() {
        leases.clear()
        if (lock?.isHeld == true) lock?.release()
        lock = null
    }
}
