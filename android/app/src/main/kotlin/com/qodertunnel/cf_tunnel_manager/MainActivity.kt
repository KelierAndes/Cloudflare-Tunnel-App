package com.qodertunnel.cf_tunnel_manager

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_CHANNEL = "cf_tunnel/device"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android 10+ 只允许执行解压到 nativeLibraryDir 的二进制，
                    // cloudflared 以 jniLibs/<abi>/libcloudflared.so 的形式随包发布。
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    // cloudflared 读不到 /etc/resolv.conf，DNS 只能从系统 API 取。
                    "dnsServers" -> result.success(currentDnsServers())
                    "startKeepAlive" -> {
                        val intent = Intent(this, TunnelForegroundService::class.java)
                            .setAction(TunnelForegroundService.ACTION_START)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopKeepAlive" -> {
                        startService(
                            Intent(this, TunnelForegroundService::class.java)
                                .setAction(TunnelForegroundService.ACTION_STOP)
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun currentDnsServers(): List<String> {
        return try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = manager.activeNetwork ?: return emptyList()
            val properties = manager.getLinkProperties(network) ?: return emptyList()
            properties.dnsServers.mapNotNull { it.hostAddress }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
