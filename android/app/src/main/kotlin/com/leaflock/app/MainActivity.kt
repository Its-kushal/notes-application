package com.leaflock.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.leaflock.app/security"
    private var methodChannel: MethodChannel? = null
    private var pendingFilePayload: Map<String, Any?>? = null
    private var isDartReady = false
    private var isColdStartExternal = false

    override fun getInitialRoute(): String {
        return "/"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val originalIntent = intent
        if (originalIntent?.action == Intent.ACTION_VIEW && originalIntent.data?.scheme == "content") {
            isColdStartExternal = true
        }
        handleIntent(originalIntent)
        if (originalIntent?.data?.scheme == "content") {
            val sanitized = Intent(originalIntent)
            sanitized.data = null
            setIntent(sanitized)
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        if (intent.action == Intent.ACTION_VIEW && intent.data?.scheme == "content") {
            isColdStartExternal = false
        }
        handleIntent(intent)
        val sanitized = Intent(intent)
        if (sanitized.data?.scheme == "content") {
            sanitized.data = null
        }
        super.onNewIntent(sanitized)
        setIntent(sanitized)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) {
            return
        }
        val uri = intent.data ?: return
        if (uri.scheme != "content") {
            return
        }

        kotlin.concurrent.thread(start = true) {
            val payload = readUriPayload(uri)
            runOnUiThread {
                if (isDartReady && methodChannel != null) {
                    methodChannel?.invokeMethod("onFileOpened", payload)
                } else {
                    pendingFilePayload = payload
                }
            }
        }
    }

    private fun readUriPayload(uri: Uri): Map<String, Any?> {
        var displayName: String? = null
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx != -1) {
                        displayName = cursor.getString(idx)
                    }
                }
            }
        } catch (_: Exception) {}

        if (displayName == null) {
            displayName = uri.lastPathSegment ?: "file"
        }

        val inputStream = try {
            contentResolver.openInputStream(uri)
        } catch (_: Exception) {
            null
        } ?: return mapOf(
            "name" to displayName,
            "bytes" to null,
            "error" to "UNREADABLE"
        )

        // Read at most 2 MB + 1 byte (2,097,153 bytes)
        val maxBytesToRead = 2 * 1024 * 1024 + 1
        val buffer = ByteArray(8192)
        val baos = ByteArrayOutputStream()
        var totalRead = 0

        try {
            inputStream.use { stream ->
                while (totalRead < maxBytesToRead) {
                    val toRead = Math.min(buffer.size, maxBytesToRead - totalRead)
                    val read = stream.read(buffer, 0, toRead)
                    if (read == -1) break
                    baos.write(buffer, 0, read)
                    totalRead += read
                }
            }
        } catch (_: Exception) {
            return mapOf(
                "name" to displayName,
                "bytes" to null,
                "error" to "UNREADABLE"
            )
        }

        return mapOf(
            "name" to displayName,
            "bytes" to baos.toByteArray(),
            "error" to null
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    isDartReady = true
                    val payload = pendingFilePayload
                    pendingFilePayload = null
                    result.success(payload)
                }
                "exitExternalViewer" -> {
                    if (isColdStartExternal) {
                        finish()
                    } else {
                        moveTaskToBack(true)
                    }
                    result.success(true)
                }
                "openDefaultAppsSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                            result.success(true)
                            return@setMethodCallHandler
                        }
                    } catch (_: Exception) {}

                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
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
