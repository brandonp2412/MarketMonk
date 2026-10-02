package com.codesail.market_monk

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Currency
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "market_monk/device_region",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getLocalCurrencyCode") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val currencyCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val region = android.icu.util.TimeZone.getRegion(TimeZone.getDefault().id)
                    val locale = Locale.Builder().setRegion(region).build()
                    Currency.getInstance(locale).currencyCode
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }

            result.success(currencyCode)
        }
    }
}
