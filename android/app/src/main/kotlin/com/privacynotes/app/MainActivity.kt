package com.privacynotes.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.privacynotes.app/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureWindow" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                    result.success(true)
                }
                "disableSecureWindow" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "pbkdf2" -> {
                    val secret = call.argument<String>("secret") ?: ""
                    val salt = call.argument<ByteArray>("salt") ?: ByteArray(0)
                    val iterations = call.argument<Int>("iterations") ?: 100000
                    val keyLengthBits = call.argument<Int>("keyLengthBits") ?: 256

                    kotlin.concurrent.thread(start = true) {
                        val chars = secret.toCharArray()
                        val spec = javax.crypto.spec.PBEKeySpec(chars, salt, iterations, keyLengthBits)
                        try {
                            val skf = javax.crypto.SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                            val key = skf.generateSecret(spec).encoded
                            runOnUiThread {
                                result.success(key)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("KDF_ERROR", e.message, null)
                            }
                        } finally {
                            spec.clearPassword()
                            chars.fill('\u0000')
                        }
                    }
                }
                "getElapsedRealtime" -> {
                    val elapsed = android.os.SystemClock.elapsedRealtime()
                    result.success(elapsed)
                }
                else -> result.notImplemented()
            }
        }
    }
}
