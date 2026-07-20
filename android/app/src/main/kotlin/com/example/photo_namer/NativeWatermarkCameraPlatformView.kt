package com.example.photo_namer

import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaActionSound
import android.util.Size
import android.util.TypedValue
import android.view.HapticFeedbackConstants
import android.view.LayoutInflater
import android.view.Surface
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import androidx.lifecycle.LifecycleOwner
import com.example.photo_namer.ui.FixedAspectFrameLayout
import com.example.photo_namer.ui.GradientStrokeTextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

class NativeWatermarkCameraPlatformViewFactory(
    private val activity: android.app.Activity,
    private val lifecycleOwner: LifecycleOwner,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = (args as? Map<*, *>)
            ?.entries
            ?.associate { it.key.toString() to it.value }
            .orEmpty()
        return NativeWatermarkCameraPlatformView(
            activity = activity,
            lifecycleOwner = lifecycleOwner,
            messenger = messenger,
            viewId = viewId,
            creationParams = creationParams,
        )
    }
}

private class NativeWatermarkCameraPlatformView(
    private val activity: android.app.Activity,
    private val lifecycleOwner: LifecycleOwner,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<String, Any?>,
) : PlatformView {

    private val methodChannel = MethodChannel(
        messenger,
        "photo_namer/native_camera_preview_$viewId",
    )
    private val prefs: SharedPreferences by lazy {
        activity.getSharedPreferences(WatermarkAdjustments.PREFS_NAME, Context.MODE_PRIVATE)
    }
    private val captureExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val rootView = LayoutInflater.from(activity).inflate(
        R.layout.view_native_watermark_camera_preview,
        null,
        false,
    )
    private val shutterSound: MediaActionSound by lazy {
        MediaActionSound().apply {
            load(MediaActionSound.SHUTTER_CLICK)
        }
    }
    private val targetCaptureSize = Size(1920, 2560)
    private val clockTicker = object : Runnable {
        override fun run() {
            if (disposed) {
                return
            }
            bindOverlay(Date())
            watermarkAnchor.postDelayed(this, 1000L)
        }
    }

    private lateinit var previewView: PreviewView
    private lateinit var previewFrame: FixedAspectFrameLayout
    private lateinit var watermarkAnchor: View
    private lateinit var captureFlashOverlay: View
    private lateinit var leftRoot: View
    private lateinit var timeView: GradientStrokeTextView
    private lateinit var locationView: TextView
    private lateinit var locationColumnView: View
    private lateinit var dateView: TextView
    private lateinit var weatherView: TextView
    private lateinit var roomCodeView: TextView
    private lateinit var imprintIconView: ImageView
    private lateinit var imprintTextGroup: View
    private lateinit var imprintPrefixView: TextView
    private lateinit var imprintDividerView: TextView
    private lateinit var imprintSuffixView: TextView
    private lateinit var antiFakeTitleView: ImageView
    private lateinit var antiFakeCodeShadowView: ImageView
    private lateinit var antiFakeCodeView: TextView
    private lateinit var rightRoot: View
    private lateinit var secureRow: View
    private lateinit var demoRibbonView: TextView

    private var previewUseCase: Preview? = null
    private var imageCapture: ImageCapture? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var disposed = false
    private var cameraReady = false
    private var captureInFlight = false

    private var roomCode = ""
    private var location = ""
    private var weatherText = ""
    private var autoLocationValue = ""
    private var autoWeatherText = ""
    private var manualLocationOverride: String? = null
    private var manualWeatherOverride: String? = null
    private var imprintText = ""
    private var defaultRoomCode = ""
    private var defaultLocation = ""
    private var defaultWeatherText = ""
    private var defaultImprintText = ""
    private var previewAntiFakeCode = generateAntiFakeCode()
    private var timeOverrideText: String? = null
    private var dateOverrideText: String? = null
    private var antiFakeCodeLocked = false
    private var watermarkEnabled = true
    private var watermarkAdjustments = WatermarkAdjustments()

    init {
        parseCreationParams(creationParams)
        bindViews()
        loadPersistedState()
        ensurePreviewAntiFakeCode(generateFreshWhenAuto = true)
        bindStaticUi()
        methodChannel.setMethodCallHandler(::handleMethodCall)
        rootView.post {
            if (!disposed) {
                startCamera()
                watermarkAnchor.removeCallbacks(clockTicker)
                watermarkAnchor.post(clockTicker)
            }
        }
    }

    override fun getView(): View = rootView

    override fun dispose() {
        if (disposed) {
            return
        }
        disposed = true
        watermarkAnchor.removeCallbacks(clockTicker)
        stopCamera()
        captureExecutor.shutdown()
        methodChannel.setMethodCallHandler(null)
        try {
            shutterSound.release()
        } catch (_: Exception) {
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> capturePhoto(result)
            "getWatermarkState" -> result.success(exportWatermarkState())
            "updateWatermarkState" -> updateWatermarkState(call, result)
            "shutdownCamera" -> shutdownCamera(result)
            else -> result.notImplemented()
        }
    }

    private fun shutdownCamera(result: MethodChannel.Result) {
        if (disposed) {
            result.success(null)
            return
        }
        activity.runOnUiThread {
            stopCamera()
            result.success(null)
        }
    }

    private fun stopCamera() {
        cameraReady = false
        captureInFlight = false
        try {
            cameraProvider?.unbindAll()
        } catch (_: Exception) {
        }
        cameraProvider = null
        imageCapture = null
        previewUseCase = null
    }

    private fun updateWatermarkState(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("invalid_args", "watermark state update args missing", null)
            return
        }
        val persistWatermarkState = arguments["persistWatermarkState"] as? Boolean ?: true
        val watermarkWasEnabled = watermarkEnabled

        if ((arguments["resetParamsToDefaults"] as? Boolean) == true) {
            manualLocationOverride = defaultLocation
            manualWeatherOverride = defaultWeatherText
            roomCode = defaultRoomCode
            imprintText = defaultImprintText
            timeOverrideText = null
            dateOverrideText = null
            antiFakeCodeLocked = false
            previewAntiFakeCode = generateAntiFakeCode()
        }

        if ((arguments["resetAdjustmentsToDefaults"] as? Boolean) == true) {
            watermarkAdjustments = WatermarkAdjustments()
        }

        if (arguments.containsKey("watermarkEnabled")) {
            watermarkEnabled = arguments["watermarkEnabled"] as? Boolean ?: watermarkEnabled
        }
        if (arguments.containsKey("location")) {
            manualLocationOverride = (arguments["location"] as? String)?.trim().orEmpty()
        }
        if (arguments.containsKey("weatherText")) {
            manualWeatherOverride = (arguments["weatherText"] as? String)?.trim().orEmpty()
        }
        if (arguments.containsKey("roomCode")) {
            roomCode = (arguments["roomCode"] as? String)
                ?.trim()
                .orEmpty()
                .ifBlank { defaultRoomCode }
        }
        if (arguments.containsKey("imprintText")) {
            imprintText = (arguments["imprintText"] as? String)?.trim().orEmpty()
        }
        if (arguments.containsKey("timeOverrideText")) {
            timeOverrideText = (arguments["timeOverrideText"] as? String)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        }
        if (arguments.containsKey("dateOverrideText")) {
            dateOverrideText = (arguments["dateOverrideText"] as? String)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        }
        if (arguments.containsKey("antiFakeCodeLocked")) {
            antiFakeCodeLocked = arguments["antiFakeCodeLocked"] as? Boolean ?: antiFakeCodeLocked
        }
        if (arguments.containsKey("antiFakeCode")) {
            val antiFakeValue = (arguments["antiFakeCode"] as? String)
                ?.trim()
                ?.uppercase(Locale.ROOT)
                ?.take(14)
                .orEmpty()
            previewAntiFakeCode = if (antiFakeValue.isEmpty()) {
                generateAntiFakeCode()
            } else {
                antiFakeValue
            }
        }
        ensurePreviewAntiFakeCode(
            generateFreshWhenAuto = !watermarkWasEnabled &&
                watermarkEnabled &&
                !antiFakeCodeLocked &&
                !arguments.containsKey("antiFakeCode"),
        )

        val rawAdjustments = arguments["adjustments"] as? Map<*, *>
        if (rawAdjustments != null) {
            watermarkAdjustments = watermarkAdjustments.copy(
                anchorStartDp = readFloatArg(
                    rawAdjustments,
                    "anchorStartDp",
                    watermarkAdjustments.anchorStartDp,
                ),
                anchorEndDp = readFloatArg(
                    rawAdjustments,
                    "anchorEndDp",
                    watermarkAdjustments.anchorEndDp,
                ),
                anchorBottomDp = readFloatArg(
                    rawAdjustments,
                    "anchorBottomDp",
                    watermarkAdjustments.anchorBottomDp,
                ),
                locationColumnWidthDp = readFloatArg(
                    rawAdjustments,
                    "locationColumnWidthDp",
                    watermarkAdjustments.locationColumnWidthDp,
                ),
                leftScale = readFloatArg(rawAdjustments, "leftScale", watermarkAdjustments.leftScale),
                leftXdp = readFloatArg(rawAdjustments, "leftXdp", watermarkAdjustments.leftXdp),
                leftYdp = readFloatArg(rawAdjustments, "leftYdp", watermarkAdjustments.leftYdp),
                timeTextSizeDp = readFloatArg(
                    rawAdjustments,
                    "timeTextSizeDp",
                    watermarkAdjustments.timeTextSizeDp,
                ),
                timeGlowRadiusDp = readFloatArg(
                    rawAdjustments,
                    "timeGlowRadiusDp",
                    watermarkAdjustments.timeGlowRadiusDp,
                ),
                timeXdp = readFloatArg(rawAdjustments, "timeXdp", watermarkAdjustments.timeXdp),
                timeYdp = readFloatArg(rawAdjustments, "timeYdp", watermarkAdjustments.timeYdp),
                rightScale = readFloatArg(rawAdjustments, "rightScale", watermarkAdjustments.rightScale),
                rightXdp = readFloatArg(rawAdjustments, "rightXdp", watermarkAdjustments.rightXdp),
                rightYdp = readFloatArg(rawAdjustments, "rightYdp", watermarkAdjustments.rightYdp),
                secureXdp = readFloatArg(rawAdjustments, "secureXdp", watermarkAdjustments.secureXdp),
                secureYdp = readFloatArg(rawAdjustments, "secureYdp", watermarkAdjustments.secureYdp),
                secureCodeTextSizeDp = readFloatArg(
                    rawAdjustments,
                    "secureCodeTextSizeDp",
                    watermarkAdjustments.secureCodeTextSizeDp,
                ),
                secureTitleScale = readFloatArg(
                    rawAdjustments,
                    "secureTitleScale",
                    watermarkAdjustments.secureTitleScale,
                ),
                secureShadowScaleX = readFloatArg(
                    rawAdjustments,
                    "secureShadowScaleX",
                    watermarkAdjustments.secureShadowScaleX,
                ),
                secureShadowScaleY = readFloatArg(
                    rawAdjustments,
                    "secureShadowScaleY",
                    watermarkAdjustments.secureShadowScaleY,
                ),
                secureShadowXdp = readFloatArg(
                    rawAdjustments,
                    "secureShadowXdp",
                    watermarkAdjustments.secureShadowXdp,
                ),
                secureShadowYdp = readFloatArg(
                    rawAdjustments,
                    "secureShadowYdp",
                    watermarkAdjustments.secureShadowYdp,
                ),
                secureCodeSpacingValue = readFloatArg(
                    rawAdjustments,
                    "secureCodeSpacingValue",
                    watermarkAdjustments.secureCodeSpacingValue,
                ),
                roomCodeVerticalPaddingDp = readFloatArg(
                    rawAdjustments,
                    "roomCodeVerticalPaddingDp",
                    watermarkAdjustments.roomCodeVerticalPaddingDp,
                ),
                roomCodeTextSizeSp = readFloatArg(
                    rawAdjustments,
                    "roomCodeTextSizeSp",
                    watermarkAdjustments.roomCodeTextSizeSp,
                ),
                imprintIconWidthSp = readFloatArg(
                    rawAdjustments,
                    "imprintIconWidthSp",
                    watermarkAdjustments.imprintIconWidthSp,
                ),
                imprintIconHeightSp = readFloatArg(
                    rawAdjustments,
                    "imprintIconHeightSp",
                    watermarkAdjustments.imprintIconHeightSp,
                ),
                imprintTextSizeSp = readFloatArg(
                    rawAdjustments,
                    "imprintTextSizeSp",
                    watermarkAdjustments.imprintTextSizeSp,
                ),
            )
        }

        syncEffectiveLocationWeather()
        applyWatermarkVisibility()
        applyWatermarkAdjustments()
        bindOverlay(Date())
        if (persistWatermarkState) {
            savePersistedState()
        }
        result.success(exportWatermarkState())
    }

    private fun parseCreationParams(params: Map<String, Any?>) {
        watermarkEnabled = params["watermarkEnabled"] as? Boolean ?: true
        roomCode = (params["roomCode"] as? String).orEmpty()
        val initialLocation = (params["location"] as? String).orEmpty()
        val initialWeatherText = (params["weatherText"] as? String).orEmpty()
        autoLocationValue = ""
        autoWeatherText = ""
        manualLocationOverride = initialLocation
        manualWeatherOverride = initialWeatherText
        location = initialLocation
        weatherText = initialWeatherText
        imprintText = (params["imprintText"] as? String).orEmpty()
        if (roomCode.isBlank()) {
            roomCode = (params["title"] as? String).orEmpty()
        }
        defaultRoomCode = roomCode
        defaultLocation = initialLocation
        defaultWeatherText = initialWeatherText
        defaultImprintText = imprintText
    }

    private fun bindViews() {
        previewView = rootView.findViewById(R.id.previewView)
        previewFrame = rootView.findViewById(R.id.previewFrame)
        watermarkAnchor = rootView.findViewById(R.id.watermarkAnchor)
        captureFlashOverlay = rootView.findViewById(R.id.captureFlashOverlay)
        leftRoot = rootView.findViewById(R.id.watermark118LeftRoot)
        timeView = rootView.findViewById(R.id.tvWatermarkTime)
        locationView = rootView.findViewById(R.id.tvWatermarkLocation)
        locationColumnView = rootView.findViewById(R.id.watermark118CopyColumn)
        dateView = rootView.findViewById(R.id.tvWatermarkDate)
        weatherView = rootView.findViewById(R.id.tvWatermarkWeather)
        roomCodeView = rootView.findViewById(R.id.tvWatermarkRoomCode)
        imprintIconView = rootView.findViewById(R.id.ivWatermarkImprint)
        imprintTextGroup = rootView.findViewById(R.id.imprintTextGroup)
        imprintPrefixView = rootView.findViewById(R.id.tvWatermarkImprintPrefix)
        imprintDividerView = rootView.findViewById(R.id.tvWatermarkImprintDivider)
        imprintSuffixView = rootView.findViewById(R.id.tvWatermarkImprintSuffix)
        antiFakeTitleView = rootView.findViewById(R.id.ivAntiFakeTitle)
        antiFakeCodeShadowView = rootView.findViewById(R.id.ivAntiFakeCodeShadow)
        antiFakeCodeView = rootView.findViewById(R.id.tvAntiFakeCode)
        rightRoot = rootView.findViewById(R.id.watermarkRightRoot)
        secureRow = rootView.findViewById(R.id.secureRow)
        demoRibbonView = rootView.findViewById(R.id.tvWatermarkDemoRibbon)
    }

    private fun bindStaticUi() {
        previewFrame.aspectWidth = targetCaptureSize.width
        previewFrame.aspectHeight = targetCaptureSize.height
        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        bindImprintText()
        applyWatermarkVisibility()
        applyWatermarkAdjustments()
        bindOverlay(Date())
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(activity)
        providerFuture.addListener(
            {
                if (disposed) {
                    return@addListener
                }
                try {
                    val provider = providerFuture.get()
                    val rotation = currentDisplayRotation()
                    val preview = Preview.Builder()
                        .setTargetResolution(targetCaptureSize)
                        .build()
                        .also {
                            it.targetRotation = rotation
                            it.surfaceProvider = previewView.surfaceProvider
                        }
                    val capture = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .setJpegQuality(95)
                        .setTargetResolution(targetCaptureSize)
                        .build()
                        .also {
                            it.targetRotation = rotation
                        }

                    provider.unbindAll()
                    provider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        capture,
                    )
                    cameraProvider = provider
                    previewUseCase = preview
                    imageCapture = capture
                    cameraReady = true
                    notifyFlutter("cameraReady", null)
                } catch (error: Exception) {
                    cameraReady = false
                    notifyFlutter(
                        "cameraError",
                        mapOf("message" to (error.message ?: "camera init failed")),
                    )
                }
            },
            ContextCompat.getMainExecutor(activity),
        )
    }

    private fun capturePhoto(result: MethodChannel.Result) {
        val capture = imageCapture
        if (disposed) {
            result.error("disposed", "camera preview already disposed", null)
            return
        }
        if (capture == null || !cameraReady) {
            result.error("not_ready", "camera preview not ready", null)
            return
        }
        if (captureInFlight) {
            result.error("busy", "camera capture already running", null)
            return
        }

        captureInFlight = true
        playCaptureFeedback()

        val now = Date()
        bindOverlay(now)
        val antiFakeCode = previewAntiFakeCode
        val captureLocation = location
        val captureWeatherText = weatherText
        val captureRoomCode = roomCode
        val captureImprintText = imprintText
        val displayTimeText = currentDisplayTimeText(now)
        val displayDateText = currentDisplayDateText(now)
        capture.targetRotation = currentDisplayRotation()

        val sourceFile = File.createTempFile(
            "wm118_${System.currentTimeMillis()}_",
            ".jpg",
            activity.externalCacheDir ?: activity.cacheDir,
        )
        val outputOptions = ImageCapture.OutputFileOptions.Builder(sourceFile).build()

        capture.takePicture(
            outputOptions,
            captureExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    try {
                        val finalFile = sourceFile

                        activity.runOnUiThread {
                            if (disposed) {
                                result.error("disposed", "camera preview already disposed", null)
                                return@runOnUiThread
                            }
                            if (!antiFakeCodeLocked) {
                                previewAntiFakeCode = generateAntiFakeCode()
                            }
                            persistAntiFakeState()
                            captureInFlight = false
                            bindOverlay(Date())
                            result.success(
                                hashMapOf<String, Any?>(
                                    "photoPath" to finalFile.absolutePath,
                                    "captureTimeMillis" to now.time,
                                    "watermarkEnabled" to watermarkEnabled,
                                    "skipCompose" to !watermarkEnabled,
                                    "preferNativeCompose" to watermarkEnabled,
                                    "antiFakeCode" to antiFakeCode,
                                    "location" to captureLocation,
                                    "roomCode" to captureRoomCode,
                                    "weatherText" to captureWeatherText,
                                    "imprintText" to captureImprintText,
                                    "displayTimeText" to displayTimeText,
                                    "displayDateText" to displayDateText,
                                    "adjustments" to hashMapOf(
                                        "anchorStartDp" to watermarkAdjustments.anchorStartDp,
                                        "anchorEndDp" to watermarkAdjustments.anchorEndDp,
                                        "anchorBottomDp" to watermarkAdjustments.anchorBottomDp,
                                        "locationColumnWidthDp" to watermarkAdjustments.locationColumnWidthDp,
                                        "leftScale" to watermarkAdjustments.leftScale,
                                        "leftXdp" to watermarkAdjustments.leftXdp,
                                        "leftYdp" to watermarkAdjustments.leftYdp,
                                        "timeTextSizeDp" to watermarkAdjustments.timeTextSizeDp,
                                        "timeGlowRadiusDp" to watermarkAdjustments.timeGlowRadiusDp,
                                        "timeXdp" to watermarkAdjustments.timeXdp,
                                        "timeYdp" to watermarkAdjustments.timeYdp,
                                        "rightScale" to watermarkAdjustments.rightScale,
                                        "rightXdp" to watermarkAdjustments.rightXdp,
                                        "rightYdp" to watermarkAdjustments.rightYdp,
                                        "secureXdp" to watermarkAdjustments.secureXdp,
                                        "secureYdp" to watermarkAdjustments.secureYdp,
                                        "secureCodeTextSizeDp" to watermarkAdjustments.secureCodeTextSizeDp,
                                        "secureTitleScale" to watermarkAdjustments.secureTitleScale,
                                        "secureShadowScaleX" to watermarkAdjustments.secureShadowScaleX,
                                        "secureShadowScaleY" to watermarkAdjustments.secureShadowScaleY,
                                        "secureShadowXdp" to watermarkAdjustments.secureShadowXdp,
                                        "secureShadowYdp" to watermarkAdjustments.secureShadowYdp,
                                        "secureCodeSpacingValue" to watermarkAdjustments.secureCodeSpacingValue,
                                        "demoXdp" to watermarkAdjustments.demoXdp,
                                        "demoYdp" to watermarkAdjustments.demoYdp,
                                        "roomCodeVerticalPaddingDp" to watermarkAdjustments.roomCodeVerticalPaddingDp,
                                        "roomCodeTextSizeSp" to watermarkAdjustments.roomCodeTextSizeSp,
                                        "imprintIconWidthSp" to watermarkAdjustments.imprintIconWidthSp,
                                        "imprintIconHeightSp" to watermarkAdjustments.imprintIconHeightSp,
                                        "imprintTextSizeSp" to watermarkAdjustments.imprintTextSizeSp,
                                    ),
                                ),
                            )
                        }
                    } catch (error: Exception) {
                        activity.runOnUiThread {
                            captureInFlight = false
                            result.error(
                                "capture_failed",
                                error.message ?: "capture failed",
                                null,
                            )
                        }
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    activity.runOnUiThread {
                        captureInFlight = false
                        result.error(
                            "capture_failed",
                            exception.message ?: "capture failed",
                            null,
                        )
                    }
                }
            },
        )
    }

    private fun playCaptureFeedback() {
        rootView.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
        try {
            shutterSound.play(MediaActionSound.SHUTTER_CLICK)
        } catch (_: Exception) {
        }

        captureFlashOverlay.animate().cancel()
        captureFlashOverlay.alpha = 0f
        captureFlashOverlay.visibility = View.VISIBLE
        captureFlashOverlay.animate()
            .alpha(0.2f)
            .setDuration(65L)
            .withEndAction {
                captureFlashOverlay.animate()
                    .alpha(0f)
                    .setDuration(180L)
                    .withEndAction {
                        captureFlashOverlay.visibility = View.GONE
                    }
                    .start()
            }
            .start()
    }

    private fun captureOverlayBitmap(): Bitmap {
        val latch = CountDownLatch(1)
        var bitmap: Bitmap? = null
        var error: Throwable? = null

        activity.runOnUiThread {
            try {
                if (watermarkAnchor.width <= 0 || watermarkAnchor.height <= 0) {
                    error = IllegalStateException("overlay not measured")
                } else {
                    bitmap = Bitmap.createBitmap(
                        watermarkAnchor.width,
                        watermarkAnchor.height,
                        Bitmap.Config.ARGB_8888,
                    )
                    val canvas = Canvas(bitmap!!)
                    watermarkAnchor.draw(canvas)
                }
            } catch (throwable: Throwable) {
                error = throwable
            } finally {
                latch.countDown()
            }
        }

        latch.await(2, TimeUnit.SECONDS)
        error?.let { throw RuntimeException(it) }
        return bitmap ?: error("overlay capture failed")
    }

    private fun composeWatermarkedPhoto(sourceFile: File, overlayBitmap: Bitmap): File {
        val sourceBitmap = normalizeCapturedBitmap(
            decodeBitmapRespectOrientation(sourceFile.absolutePath),
        )
        val mergedBitmap = sourceBitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(mergedBitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            isFilterBitmap = true
            isDither = true
        }
        canvas.drawBitmap(
            overlayBitmap,
            null,
            Rect(0, 0, mergedBitmap.width, mergedBitmap.height),
            paint,
        )

        val outputFile = File.createTempFile(
            "wm118_rendered_${System.currentTimeMillis()}_",
            ".jpg",
            activity.externalCacheDir ?: activity.cacheDir,
        )
        FileOutputStream(outputFile).use { stream ->
            mergedBitmap.compress(Bitmap.CompressFormat.JPEG, 95, stream)
            stream.flush()
        }

        overlayBitmap.recycle()
        sourceBitmap.recycle()
        mergedBitmap.recycle()
        sourceFile.delete()
        return outputFile
    }

    private fun decodeBitmapRespectOrientation(path: String): Bitmap {
        val bitmap = BitmapFactory.decodeFile(path)
            ?: error("source image decode failed")
        val orientation = ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
        }

        if (
            matrix.isIdentity &&
            activity.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT &&
            bitmap.width > bitmap.height
        ) {
            matrix.postRotate(90f)
        }

        if (matrix.isIdentity) {
            return bitmap
        }

        val rotated = Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true,
        )
        bitmap.recycle()
        return rotated
    }

    private fun normalizeCapturedBitmap(bitmap: Bitmap): Bitmap {
        val targetAspect = targetCaptureSize.width.toFloat() / targetCaptureSize.height.toFloat()
        val bitmapAspect = bitmap.width.toFloat() / bitmap.height.toFloat()

        val croppedBitmap = if (kotlin.math.abs(bitmapAspect - targetAspect) < 0.001f) {
            bitmap
        } else if (bitmapAspect > targetAspect) {
            val targetWidth = (bitmap.height * targetAspect).toInt()
            val offsetX = ((bitmap.width - targetWidth) / 2f).toInt().coerceAtLeast(0)
            Bitmap.createBitmap(
                bitmap,
                offsetX,
                0,
                targetWidth.coerceAtMost(bitmap.width),
                bitmap.height,
            )
        } else {
            val targetHeight = (bitmap.width / targetAspect).toInt()
            val offsetY = ((bitmap.height - targetHeight) / 2f).toInt().coerceAtLeast(0)
            Bitmap.createBitmap(
                bitmap,
                0,
                offsetY,
                bitmap.width,
                targetHeight.coerceAtMost(bitmap.height),
            )
        }

        val scaledBitmap = if (
            croppedBitmap.width == targetCaptureSize.width &&
            croppedBitmap.height == targetCaptureSize.height
        ) {
            croppedBitmap
        } else {
            Bitmap.createScaledBitmap(
                croppedBitmap,
                targetCaptureSize.width,
                targetCaptureSize.height,
                true,
            )
        }

        if (croppedBitmap !== bitmap) {
            bitmap.recycle()
        }
        if (scaledBitmap !== croppedBitmap) {
            croppedBitmap.recycle()
        }
        return scaledBitmap
    }

    private fun bindOverlay(now: Date) {
        syncEffectiveLocationWeather()
        applyWatermarkVisibility()
        timeView.text = currentDisplayTimeText(now)
        dateView.text = currentDisplayDateText(now)
        locationView.text = formatLocationText(
            rawValue = location,
            maxWidthPx = watermarkAdjustments.locationColumnWidthDp.dpF,
        )
        weatherView.text = weatherText
        roomCodeView.text = roomCode
        bindImprintText()
        antiFakeCodeView.text = previewAntiFakeCode
    }

    private fun ensurePreviewAntiFakeCode(generateFreshWhenAuto: Boolean = false) {
        val normalized = previewAntiFakeCode
            .trim()
            .uppercase(Locale.ROOT)
            .take(14)
        val shouldGenerate = normalized.isBlank() ||
            (generateFreshWhenAuto && watermarkEnabled && !antiFakeCodeLocked)
        previewAntiFakeCode = if (shouldGenerate) {
            generateAntiFakeCode()
        } else {
            normalized
        }
    }

    private fun applyWatermarkVisibility() {
        watermarkAnchor.visibility = if (watermarkEnabled) View.VISIBLE else View.INVISIBLE
    }

    private fun currentDisplayRotation(): Int {
        return previewView.display?.rotation ?: Surface.ROTATION_0
    }

    private fun currentDisplayTimeText(now: Date): String {
        return timeOverrideText ?: SimpleDateFormat("HH:mm", Locale.CHINA).format(now)
    }

    private fun currentDisplayDateText(now: Date): String {
        return dateOverrideText ?: SimpleDateFormat("yyyy.MM.dd EEEE", Locale.CHINA).format(now)
    }

    private fun applyWatermarkAdjustments(shouldPersist: Boolean = false) {
        watermarkAnchor.setPaddingRelative(
            watermarkAdjustments.anchorStartDp.dp,
            watermarkAnchor.paddingTop,
            watermarkAdjustments.anchorEndDp.dp,
            watermarkAdjustments.anchorBottomDp.dp,
        )
        val locationColumnLayoutParams = locationColumnView.layoutParams
        locationColumnLayoutParams.width = watermarkAdjustments.locationColumnWidthDp.dp
        locationColumnView.layoutParams = locationColumnLayoutParams
        leftRoot.translationX = watermarkAdjustments.leftXdp.dpF
        leftRoot.translationY = watermarkAdjustments.leftYdp.dpF
        timeView.setTextSize(TypedValue.COMPLEX_UNIT_DIP, watermarkAdjustments.timeTextSizeDp)
        timeView.setGlowRadiusDp(watermarkAdjustments.timeGlowRadiusDp)
        timeView.translationX = watermarkAdjustments.timeXdp.dpF
        timeView.translationY = watermarkAdjustments.timeYdp.dpF
        rightRoot.translationX = watermarkAdjustments.rightXdp.dpF
        rightRoot.translationY = watermarkAdjustments.rightYdp.dpF
        secureRow.translationX = watermarkAdjustments.secureXdp.dpF
        secureRow.translationY = watermarkAdjustments.secureYdp.dpF
        antiFakeCodeView.setTextSize(
            TypedValue.COMPLEX_UNIT_DIP,
            watermarkAdjustments.secureCodeTextSizeDp,
        )
        antiFakeTitleView.layoutParams = antiFakeTitleView.layoutParams.apply {
            width = (10f * watermarkAdjustments.secureTitleScale).dp
            height = (7f * watermarkAdjustments.secureTitleScale).dp
        }
        antiFakeCodeShadowView.pivotX = antiFakeCodeShadowView.width / 2f
        antiFakeCodeShadowView.pivotY = antiFakeCodeShadowView.height / 2f
        antiFakeCodeShadowView.scaleX = watermarkAdjustments.secureShadowScaleX
        antiFakeCodeShadowView.scaleY = watermarkAdjustments.secureShadowScaleY
        antiFakeCodeShadowView.translationX = watermarkAdjustments.secureShadowXdp.dpF
        antiFakeCodeShadowView.translationY = watermarkAdjustments.secureShadowYdp.dpF
        antiFakeCodeView.letterSpacing =
            watermarkAdjustments.secureCodeSpacingValue.coerceAtLeast(0f) / 100f
        demoRibbonView.translationX = watermarkAdjustments.demoXdp.dpF
        demoRibbonView.translationY = watermarkAdjustments.demoYdp.dpF
        locationView.maxLines = Int.MAX_VALUE
        locationView.setHorizontallyScrolling(false)
        roomCodeView.setPaddingRelative(
            roomCodeView.paddingStart,
            watermarkAdjustments.roomCodeVerticalPaddingDp.dp,
            roomCodeView.paddingEnd,
            watermarkAdjustments.roomCodeVerticalPaddingDp.dp,
        )
        roomCodeView.setTextSize(TypedValue.COMPLEX_UNIT_SP, watermarkAdjustments.roomCodeTextSizeSp)

        val iconLayoutParams = imprintIconView.layoutParams
        iconLayoutParams.width = watermarkAdjustments.imprintIconWidthSp.sp.roundToInt()
        iconLayoutParams.height = watermarkAdjustments.imprintIconHeightSp.sp.roundToInt()
        imprintIconView.layoutParams = iconLayoutParams
        imprintIconView.maxWidth = iconLayoutParams.width

        val imprintLineHeight = iconLayoutParams.height.coerceAtLeast(1)
        val imprintTextContainerHeight = maxOf(
            imprintLineHeight,
            (watermarkAdjustments.imprintTextSizeSp * 1.45f).sp.roundToInt(),
        )
        val imprintTextGroupLayoutParams = imprintTextGroup.layoutParams
        imprintTextGroupLayoutParams.height = imprintTextContainerHeight
        imprintTextGroup.layoutParams = imprintTextGroupLayoutParams
        imprintTextGroup.minimumHeight = imprintTextContainerHeight
        listOf(imprintPrefixView, imprintDividerView, imprintSuffixView).forEach { textView ->
            textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, watermarkAdjustments.imprintTextSizeSp)
            val textLayoutParams = textView.layoutParams
            textLayoutParams.height = imprintTextContainerHeight
            textView.layoutParams = textLayoutParams
            textView.minHeight = imprintTextContainerHeight
            textView.translationY = 0.35f.dpF
        }
        if (leftRoot.height > 0 && rightRoot.height > 0) {
            leftRoot.pivotX = 0f
            leftRoot.pivotY = leftRoot.height.toFloat()
            leftRoot.scaleX = watermarkAdjustments.leftScale
            leftRoot.scaleY = watermarkAdjustments.leftScale
            rightRoot.pivotX = rightRoot.width.toFloat()
            rightRoot.pivotY = rightRoot.height.toFloat()
            rightRoot.scaleX = watermarkAdjustments.rightScale
            rightRoot.scaleY = watermarkAdjustments.rightScale
        } else {
            watermarkAnchor.post {
                if (!disposed) {
                    applyWatermarkAdjustments()
                }
            }
        }
        watermarkAnchor.requestLayout()
        watermarkAnchor.invalidate()
        if (shouldPersist) {
            savePersistedState()
        }
    }

    private fun loadPersistedState() {
        manualLocationOverride = defaultLocation
        manualWeatherOverride = defaultWeatherText
        autoLocationValue = ""
        autoWeatherText = ""
        syncEffectiveLocationWeather()
        roomCode = defaultRoomCode
        imprintText = defaultImprintText
        timeOverrideText = null
        dateOverrideText = null
        antiFakeCodeLocked = prefs.getBoolean("anti_fake_locked", false)
        previewAntiFakeCode = prefs.getString(
            "anti_fake_value",
            generateAntiFakeCode(),
        ).orEmpty().ifBlank { generateAntiFakeCode() }
        val storedDefaultsVersion = prefs.getInt(
            WatermarkAdjustments.TUNING_DEFAULTS_VERSION_KEY,
            0,
        )
        if (storedDefaultsVersion < WatermarkAdjustments.TUNING_DEFAULTS_VERSION) {
            watermarkAdjustments = WatermarkAdjustments()
            savePersistedState()
        } else {
            watermarkAdjustments = WatermarkAdjustments.loadFromPrefs(prefs)
        }
    }

    private fun savePersistedState() {
        syncEffectiveLocationWeather()
        watermarkAdjustments.writeTo(
            prefs.edit()
                .remove("location_value")
                .remove("weather_value")
                .remove("location_manual_override")
                .remove("weather_manual_override")
                .remove("location_auto_value")
                .remove("weather_auto_value")
                .remove("room_code_value")
                .remove("imprint_value")
                .remove("time_override_value")
                .remove("date_override_value")
                .putBoolean("anti_fake_locked", antiFakeCodeLocked)
                .putString("anti_fake_value", previewAntiFakeCode),
        ).apply()
    }

    private fun persistAntiFakeState() {
        prefs.edit()
            .putBoolean("anti_fake_locked", antiFakeCodeLocked)
            .putString("anti_fake_value", previewAntiFakeCode)
            .apply()
    }

    private fun effectiveLocationText(): String {
        return manualLocationOverride ?: defaultLocation
    }

    private fun effectiveWeatherText(): String {
        return manualWeatherOverride ?: defaultWeatherText
    }

    private fun syncEffectiveLocationWeather() {
        location = effectiveLocationText()
        weatherText = effectiveWeatherText()
    }

    private fun bindImprintText() {
        val parts = parseImprintParts(imprintText)
        imprintPrefixView.text = parts.prefix
        val showTrailingPart = !parts.suffix.isNullOrBlank()
        imprintDividerView.visibility = if (showTrailingPart) View.VISIBLE else View.GONE
        imprintSuffixView.visibility = if (showTrailingPart) View.VISIBLE else View.GONE
        if (showTrailingPart) {
            imprintDividerView.text = parts.divider.orEmpty()
            imprintSuffixView.text = parts.suffix.orEmpty()
        } else {
            imprintDividerView.text = ""
            imprintSuffixView.text = ""
        }
    }

    private fun formatLocationText(rawValue: String, maxWidthPx: Float): String {
        val normalized = rawValue
            .replace("\r", "")
            .replace("\n", "")
            .trim()
        if (normalized.isEmpty()) {
            return normalized
        }
        if (maxWidthPx <= 0f) {
            return normalized
        }

        val wrappedLines = mutableListOf<String>()
        val lineBuilder = StringBuilder()
        var currentWidth = 0f

        normalized.forEach { character ->
            val charText = character.toString()
            val charWidth = locationView.paint.measureText(charText)
            val willOverflow = lineBuilder.isNotEmpty() && currentWidth + charWidth > maxWidthPx
            if (willOverflow) {
                wrappedLines += lineBuilder.toString()
                lineBuilder.clear()
                currentWidth = 0f
            }
            lineBuilder.append(character)
            currentWidth += charWidth
        }
        if (lineBuilder.isNotEmpty()) {
            wrappedLines += lineBuilder.toString()
        }

        return wrappedLines.joinToString("\n")
    }

    private fun exportWatermarkState(): HashMap<String, Any?> {
        return hashMapOf(
            "watermarkEnabled" to watermarkEnabled,
            "location" to location,
            "weatherText" to weatherText,
            "roomCode" to roomCode,
            "imprintText" to imprintText,
            "timeOverrideText" to timeOverrideText,
            "dateOverrideText" to dateOverrideText,
            "antiFakeCode" to previewAntiFakeCode,
            "antiFakeCodeLocked" to antiFakeCodeLocked,
            "defaults" to hashMapOf(
                "location" to defaultLocation,
                "weatherText" to defaultWeatherText,
                "roomCode" to defaultRoomCode,
                "imprintText" to defaultImprintText,
            ),
            "adjustments" to hashMapOf(
                "anchorStartDp" to watermarkAdjustments.anchorStartDp,
                "anchorEndDp" to watermarkAdjustments.anchorEndDp,
                "anchorBottomDp" to watermarkAdjustments.anchorBottomDp,
                "locationColumnWidthDp" to watermarkAdjustments.locationColumnWidthDp,
                "leftScale" to watermarkAdjustments.leftScale,
                "leftXdp" to watermarkAdjustments.leftXdp,
                "leftYdp" to watermarkAdjustments.leftYdp,
                "timeTextSizeDp" to watermarkAdjustments.timeTextSizeDp,
                "timeGlowRadiusDp" to watermarkAdjustments.timeGlowRadiusDp,
                "timeXdp" to watermarkAdjustments.timeXdp,
                "timeYdp" to watermarkAdjustments.timeYdp,
                "rightScale" to watermarkAdjustments.rightScale,
                "rightXdp" to watermarkAdjustments.rightXdp,
                "rightYdp" to watermarkAdjustments.rightYdp,
                "secureXdp" to watermarkAdjustments.secureXdp,
                "secureYdp" to watermarkAdjustments.secureYdp,
                "secureCodeTextSizeDp" to watermarkAdjustments.secureCodeTextSizeDp,
                "secureTitleScale" to watermarkAdjustments.secureTitleScale,
                "secureShadowScaleX" to watermarkAdjustments.secureShadowScaleX,
                "secureShadowScaleY" to watermarkAdjustments.secureShadowScaleY,
                "secureShadowXdp" to watermarkAdjustments.secureShadowXdp,
                "secureShadowYdp" to watermarkAdjustments.secureShadowYdp,
                "secureCodeSpacingValue" to watermarkAdjustments.secureCodeSpacingValue,
                "demoXdp" to watermarkAdjustments.demoXdp,
                "demoYdp" to watermarkAdjustments.demoYdp,
                "roomCodeVerticalPaddingDp" to watermarkAdjustments.roomCodeVerticalPaddingDp,
                "roomCodeTextSizeSp" to watermarkAdjustments.roomCodeTextSizeSp,
                "imprintIconWidthSp" to watermarkAdjustments.imprintIconWidthSp,
                "imprintIconHeightSp" to watermarkAdjustments.imprintIconHeightSp,
                "imprintTextSizeSp" to watermarkAdjustments.imprintTextSizeSp,
            ),
        )
    }

    private fun readFloatArg(
        values: Map<*, *>,
        key: String,
        fallback: Float,
    ): Float {
        return when (val value = values[key]) {
            is Number -> value.toFloat()
            is String -> value.toFloatOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun notifyFlutter(method: String, arguments: Any?) {
        if (disposed) {
            return
        }
        activity.runOnUiThread {
            if (!disposed) {
                methodChannel.invokeMethod(method, arguments)
            }
        }
    }

    private val Float.dp: Int
        get() = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            activity.resources.displayMetrics,
        ).roundToInt()

    private val Float.dpF: Float
        get() = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            activity.resources.displayMetrics,
        )

    private val Float.sp: Float
        get() = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            this,
            activity.resources.displayMetrics,
        )

}
