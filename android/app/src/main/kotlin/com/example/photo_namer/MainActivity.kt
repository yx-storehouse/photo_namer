package com.example.photo_namer

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "photo_namer/native_watermark_camera"
        private const val APP_UPDATE_CHANNEL = "photo_namer/app_update"
        private const val NATIVE_PREVIEW_VIEW_TYPE = "photo_namer/native_camera_preview"
    }

    private lateinit var nativeWatermarkChannel: MethodChannel
    private lateinit var appUpdateChannel: MethodChannel
    private val batchComposeExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    @Volatile
    private var batchComposeInFlight = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            NATIVE_PREVIEW_VIEW_TYPE,
            NativeWatermarkCameraPlatformViewFactory(
                activity = this,
                lifecycleOwner = this as LifecycleOwner,
                messenger = flutterEngine.dartExecutor.binaryMessenger,
            ),
        )
        nativeWatermarkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        nativeWatermarkChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "composeWatermark118Batch" -> composeWatermark118Batch(call, result)
                else -> result.notImplemented()
            }
        }
        appUpdateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_UPDATE_CHANNEL)
        appUpdateChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> result.success(canRequestPackageInstallsCompat())
                "openManageUnknownAppSources" -> {
                    openManageUnknownAppSources()
                    result.success(null)
                }

                "installApk" -> installApk(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        batchComposeExecutor.shutdown()
        super.onDestroy()
    }

    private fun composeWatermark118Batch(call: MethodCall, result: MethodChannel.Result) {
        if (batchComposeInFlight) {
            result.error("batch_busy", "Native watermark batch compose is already active.", null)
            return
        }

        val rawEntries = call.argument<List<*>>("entries")
        if (rawEntries == null) {
            result.error("invalid_args", "batch compose entries are missing.", null)
            return
        }

        val entries = rawEntries.mapNotNull { rawItem ->
            NativeWatermarkBatchComposer.BatchComposeEntry.fromMap(rawItem as? Map<*, *> ?: return@mapNotNull null)
        }
        if (entries.isEmpty()) {
            result.success(
                hashMapOf(
                    "successCount" to 0,
                    "missingCount" to 0,
                    "failedCount" to 0,
                    "results" to emptyList<Map<String, Any?>>(),
                ),
            )
            return
        }

        batchComposeInFlight = true
        batchComposeExecutor.execute {
            try {
                val summary = NativeWatermarkBatchComposer(this).composeBatch(entries)
                runOnUiThread {
                    result.success(summary.toMap())
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "batch_compose_failed",
                        error.message ?: "Native watermark batch compose failed.",
                        null,
                    )
                }
            } finally {
                batchComposeInFlight = false
            }
        }
    }

    private fun canRequestPackageInstallsCompat(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openManageUnknownAppSources() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath").orEmpty()
        if (filePath.isBlank()) {
            result.error("invalid_args", "apk file path is missing.", null)
            return
        }

        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            result.error("file_missing", "apk file does not exist.", null)
            return
        }

        try {
            val contentUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Throwable) {
            result.error(
                "install_failed",
                error.message ?: "failed to launch apk installer.",
                null,
            )
        }
    }

}
