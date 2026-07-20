package com.example.photo_namer

import android.Manifest
import android.app.Activity
import android.content.SharedPreferences
import android.content.res.Configuration
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.media.MediaActionSound
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Size
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.Surface
import android.view.HapticFeedbackConstants
import android.view.View
import android.text.TextWatcher
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.core.widget.doAfterTextChanged
import androidx.exifinterface.media.ExifInterface
import com.example.photo_namer.ui.FixedAspectFrameLayout
import com.example.photo_namer.ui.GradientStrokeTextView
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt
import kotlin.random.Random
import org.json.JSONArray
import org.json.JSONObject

class NativeWatermarkCameraActivity : AppCompatActivity() {

    companion object {
        private const val PREFS_NAME = "watermark_118_debug_prefs"
        private const val TUNING_DEFAULTS_VERSION_KEY = "tuning_defaults_version"
        private const val TUNING_DEFAULTS_VERSION = 3
        private const val LOCATION_BUTTON_IDLE_TEXT = "定位天气"
        private const val LOCATION_BUTTON_LOADING_TEXT = "定位中"
        const val EXTRA_TITLE = "title"
        const val EXTRA_CAPTURE_COUNT = "capture_count"
        const val EXTRA_ROOM_CODE = "room_code"
        const val EXTRA_LOCATION = "location"
        const val EXTRA_WEATHER_TEXT = "weather_text"
        const val EXTRA_IMPRINT_TEXT = "imprint_text"
        const val EXTRA_RESULT_JSON = "result_json"

        fun createIntent(
            context: Context,
            title: String,
            captureCount: Int,
            roomCode: String,
            location: String,
            weatherText: String,
            imprintText: String,
        ): Intent {
            return Intent(context, NativeWatermarkCameraActivity::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_CAPTURE_COUNT, captureCount)
                .putExtra(EXTRA_ROOM_CODE, roomCode)
                .putExtra(EXTRA_LOCATION, location)
                .putExtra(EXTRA_WEATHER_TEXT, weatherText)
                .putExtra(EXTRA_IMPRINT_TEXT, imprintText)
        }
    }

    private val prefs: SharedPreferences by lazy {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grantResult ->
        val granted = grantResult[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            grantResult[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (granted) {
            setLocationWeatherRefreshing(false)
            refreshLocationWeather()
        } else {
            setLocationWeatherRefreshing(false)
            showLocationPermissionHelp()
        }
    }

    private val captureExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val locationWeatherExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val captureItems = mutableListOf<CapturedPhoto>()
    private val clockTicker = object : Runnable {
        override fun run() {
            bindOverlay(Date())
            watermarkAnchor.postDelayed(this, 1000L)
        }
    }

    private lateinit var previewView: PreviewView
    private lateinit var previewFrame: FixedAspectFrameLayout
    private lateinit var watermarkAnchor: View
    private lateinit var topBar: View
    private lateinit var bottomControls: View
    private lateinit var titleView: TextView
    private lateinit var captureHintView: TextView
    private lateinit var captureButton: ImageButton
    private lateinit var captureButtonShell: View
    private lateinit var captureFlashOverlay: View
    private lateinit var editWatermarkButton: TextView
    private lateinit var tuneWatermarkButton: TextView
    private lateinit var refreshLocationWeatherButton: TextView
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

    private var captureCount = 1
    private var captureInFlight = false
    private var imageCapture: ImageCapture? = null
    private lateinit var roomCode: String
    private lateinit var location: String
    private lateinit var weatherText: String
    private var autoLocationValue: String = ""
    private var autoWeatherText: String = ""
    private var manualLocationOverride: String? = null
    private var manualWeatherOverride: String? = null
    private lateinit var imprintText: String
    private lateinit var defaultRoomCode: String
    private lateinit var defaultLocation: String
    private lateinit var defaultWeatherText: String
    private lateinit var defaultImprintText: String
    private var previewAntiFakeCode: String = generateAntiFakeCode()
    private var timeOverrideText: String? = null
    private var dateOverrideText: String? = null
    private var antiFakeCodeLocked = false
    private var isRefreshingLocationWeather = false
    private var watermarkAdjustments = WatermarkAdjustments()
    private var needsTuningDefaultsMigration = false
    private val shutterSound: MediaActionSound by lazy {
        MediaActionSound().apply {
            load(MediaActionSound.SHUTTER_CLICK)
        }
    }
    // 统一画布尺寸。
    // 想整体提清晰度或改预览/导出比例，优先从这里下手。
    // 当前是 3:4；如果改这里，也要同步关注 FixedAspectFrameLayout 的表现。
    private val targetCaptureSize = Size(1920, 2560)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_native_watermark_camera)

        parseIntent()
        loadPersistedState()
        ensurePreviewAntiFakeCode(generateFreshWhenAuto = true)
        bindViews()
        bindInsets()
        bindStaticUi()
        if (needsTuningDefaultsMigration) {
            savePersistedState()
            needsTuningDefaultsMigration = false
        }
        startCamera()
    }

    override fun onStart() {
        super.onStart()
        watermarkAnchor.removeCallbacks(clockTicker)
        watermarkAnchor.post(clockTicker)
    }

    override fun onStop() {
        watermarkAnchor.removeCallbacks(clockTicker)
        super.onStop()
    }

    override fun onDestroy() {
        captureExecutor.shutdown()
        locationWeatherExecutor.shutdown()
        shutterSound.release()
        super.onDestroy()
    }

    private fun parseIntent() {
        captureCount = intent.getIntExtra(EXTRA_CAPTURE_COUNT, 1).coerceAtLeast(1)
        roomCode = intent.getStringExtra(EXTRA_ROOM_CODE).orEmpty()
        val initialLocation = intent.getStringExtra(EXTRA_LOCATION).orEmpty()
        val initialWeatherText = intent.getStringExtra(EXTRA_WEATHER_TEXT).orEmpty()
        autoLocationValue = ""
        autoWeatherText = ""
        manualLocationOverride = initialLocation
        manualWeatherOverride = initialWeatherText
        location = initialLocation
        weatherText = initialWeatherText
        imprintText = intent.getStringExtra(EXTRA_IMPRINT_TEXT).orEmpty()
        if (roomCode.isBlank()) {
            roomCode = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        }
        defaultRoomCode = roomCode
        defaultLocation = initialLocation
        defaultWeatherText = initialWeatherText
        defaultImprintText = imprintText
    }

    private fun bindViews() {
        previewView = findViewById(R.id.previewView)
        previewFrame = findViewById(R.id.previewFrame)
        watermarkAnchor = findViewById(R.id.watermarkAnchor)
        topBar = findViewById(R.id.topBar)
        bottomControls = findViewById(R.id.bottomControls)
        titleView = findViewById(R.id.tvCameraTitle)
        captureHintView = findViewById(R.id.tvCaptureHint)
        captureButton = findViewById(R.id.btnCapture)
        captureButtonShell = findViewById(R.id.captureButtonShell)
        captureFlashOverlay = findViewById(R.id.captureFlashOverlay)
        editWatermarkButton = findViewById(R.id.btnEditWatermark)
        tuneWatermarkButton = findViewById(R.id.btnTuneWatermark)
        refreshLocationWeatherButton = findViewById(R.id.btnRefreshLocationWeather)
        leftRoot = findViewById(R.id.watermark118LeftRoot)
        timeView = findViewById(R.id.tvWatermarkTime)
        locationView = findViewById(R.id.tvWatermarkLocation)
        locationColumnView = findViewById(R.id.watermark118CopyColumn)
        dateView = findViewById(R.id.tvWatermarkDate)
        weatherView = findViewById(R.id.tvWatermarkWeather)
        roomCodeView = findViewById(R.id.tvWatermarkRoomCode)
        imprintIconView = findViewById(R.id.ivWatermarkImprint)
        imprintTextGroup = findViewById(R.id.imprintTextGroup)
        imprintPrefixView = findViewById(R.id.tvWatermarkImprintPrefix)
        imprintDividerView = findViewById(R.id.tvWatermarkImprintDivider)
        imprintSuffixView = findViewById(R.id.tvWatermarkImprintSuffix)
        antiFakeTitleView = findViewById(R.id.ivAntiFakeTitle)
        antiFakeCodeShadowView = findViewById(R.id.ivAntiFakeCodeShadow)
        antiFakeCodeView = findViewById(R.id.tvAntiFakeCode)
        rightRoot = findViewById(R.id.watermarkRightRoot)
        secureRow = findViewById(R.id.secureRow)
        demoRibbonView = findViewById(R.id.tvWatermarkDemoRibbon)
    }

    private fun bindInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.nativeCameraRoot)) { _, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            topBar.updatePadding(top = 16.dp + systemBars.top)
            bottomControls.updatePadding(bottom = 14.dp + systemBars.bottom)
            insets
        }
    }

    private fun bindStaticUi() {
        titleView.text = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        roomCodeView.text = roomCode
        bindImprintText()
        previewFrame.aspectWidth = targetCaptureSize.width
        previewFrame.aspectHeight = targetCaptureSize.height
        applyWatermarkAdjustments()

        findViewById<TextView>(R.id.btnBack).setOnClickListener {
            finish()
        }
        editWatermarkButton.setOnClickListener {
            showWatermarkParamsDialog()
        }
        tuneWatermarkButton.setOnClickListener {
            showWatermarkTuningDialog()
        }
        refreshLocationWeatherButton.setOnClickListener {
            requestLocationWeatherAuthorization()
        }
        captureButton.setOnClickListener {
            takePhoto()
        }

        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE

        updateCaptureHint()
        bindOverlay(Date())
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener(
            {
                try {
                    val rotation = currentDisplayRotation()
                    val cameraProvider = providerFuture.get()
                    val preview = Preview.Builder()
                        .setTargetResolution(targetCaptureSize)
                        .build()
                        .also {
                            it.targetRotation = rotation
                            it.surfaceProvider = previewView.surfaceProvider
                        }
                    imageCapture = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .setJpegQuality(95)
                        .setTargetResolution(targetCaptureSize)
                        .build()
                        .also {
                            it.targetRotation = rotation
                        }

                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        this,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        imageCapture,
                    )
                } catch (error: Exception) {
                    Toast.makeText(this, "相机初始化失败: ${error.message}", Toast.LENGTH_SHORT).show()
                    finish()
                }
            },
            ContextCompat.getMainExecutor(this),
        )
    }

    private fun bindOverlay(now: Date) {
        syncEffectiveLocationWeather()
        timeView.text = timeOverrideText ?: SimpleDateFormat("HH:mm", Locale.CHINA).format(now)
        dateView.text = dateOverrideText ?: SimpleDateFormat("yyyy.MM.dd EEEE", Locale.CHINA).format(now)
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
            (generateFreshWhenAuto && !antiFakeCodeLocked)
        previewAntiFakeCode = if (shouldGenerate) {
            generateAntiFakeCode()
        } else {
            normalized
        }
    }

    private fun requestLocationWeatherAuthorization() {
        if (isRefreshingLocationWeather) {
            return
        }
        if (hasLocationPermission()) {
            refreshLocationWeather()
            return
        }
        setLocationWeatherRefreshing(true)
        locationPermissionLauncher.launch(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
        )
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun refreshLocationWeather(
        showSuccessToast: Boolean = true,
        showFailureUi: Boolean = true,
    ) {
        if (isRefreshingLocationWeather) {
            return
        }
        if (!hasLocationPermission()) {
            if (showFailureUi) {
                requestLocationWeatherAuthorization()
            }
            return
        }

        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (locationManager == null) {
            if (showFailureUi) {
                Toast.makeText(this, "定位服务不可用", Toast.LENGTH_SHORT).show()
            }
            return
        }

        val provider = pickLocationProvider(locationManager)
        if (provider == null) {
            if (showFailureUi) {
                showEnableLocationServicesHelp()
            }
            return
        }

        setLocationWeatherRefreshing(true)
        val fallbackLocation = findBestLastKnownLocation(locationManager)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                locationManager.getCurrentLocation(
                    provider,
                    null,
                    ContextCompat.getMainExecutor(this),
                ) { currentLocation ->
                    val resolvedLocation = currentLocation ?: fallbackLocation
                    if (resolvedLocation == null) {
                        setLocationWeatherRefreshing(false)
                        if (showFailureUi) {
                            Toast.makeText(this, "暂时拿不到定位结果", Toast.LENGTH_SHORT).show()
                        }
                        return@getCurrentLocation
                    }
                    resolveLocationWeatherOnBackground(
                        sourceLocation = resolvedLocation,
                        showSuccessToast = showSuccessToast,
                    )
                }
            } catch (_: SecurityException) {
                setLocationWeatherRefreshing(false)
                if (showFailureUi) {
                    showLocationPermissionHelp()
                }
            }
            return
        }

        if (fallbackLocation == null) {
            setLocationWeatherRefreshing(false)
            if (showFailureUi) {
                Toast.makeText(this, "暂时拿不到定位结果", Toast.LENGTH_SHORT).show()
            }
            return
        }
        resolveLocationWeatherOnBackground(
            sourceLocation = fallbackLocation,
            showSuccessToast = showSuccessToast,
        )
    }

    private fun resolveLocationWeatherOnBackground(
        sourceLocation: Location,
        showSuccessToast: Boolean,
    ) {
        locationWeatherExecutor.execute {
            val nextLocation = resolveAddressText(sourceLocation)
            val nextWeather = resolveWeatherText(sourceLocation)

            runOnUiThread {
                val appliedLocation = nextLocation.isNotBlank()
                val appliedWeather = nextWeather.isNotBlank()

                if (appliedLocation) {
                    autoLocationValue = nextLocation
                    manualLocationOverride = nextLocation
                    defaultLocation = nextLocation
                }
                if (appliedWeather) {
                    autoWeatherText = nextWeather
                    manualWeatherOverride = nextWeather
                    defaultWeatherText = nextWeather
                }
                syncEffectiveLocationWeather()
                bindOverlay(Date())
                savePersistedState()
                setLocationWeatherRefreshing(false)
                if (showSuccessToast) {
                    Toast.makeText(
                        this,
                        buildLocationWeatherRefreshToast(
                            appliedLocation = appliedLocation,
                            appliedWeather = appliedWeather,
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                }
            }
        }
    }

    private fun setLocationWeatherRefreshing(isRefreshing: Boolean) {
        isRefreshingLocationWeather = isRefreshing
        refreshLocationWeatherButton.isEnabled = !isRefreshing
        refreshLocationWeatherButton.alpha = if (isRefreshing) 0.72f else 1f
        refreshLocationWeatherButton.text =
            if (isRefreshing) LOCATION_BUTTON_LOADING_TEXT else LOCATION_BUTTON_IDLE_TEXT
    }

    private fun pickLocationProvider(locationManager: LocationManager): String? {
        return when {
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            else -> null
        }
    }

    private fun findBestLastKnownLocation(locationManager: LocationManager): Location? {
        val providers = listOf(
            LocationManager.NETWORK_PROVIDER,
            LocationManager.GPS_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        )
        return providers.mapNotNull { provider ->
            try {
                locationManager.getLastKnownLocation(provider)
            } catch (_: SecurityException) {
                null
            } catch (_: IllegalArgumentException) {
                null
            }
        }.maxByOrNull { candidate ->
            candidate.time
        }
    }

    private fun resolveAddressText(sourceLocation: Location): String {
        if (!Geocoder.isPresent()) {
            return ""
        }

        return try {
            val geocoder = Geocoder(this, Locale.CHINA)
            val addresses = geocoder.getFromLocation(
                sourceLocation.latitude,
                sourceLocation.longitude,
                1,
            ).orEmpty()
            val address = addresses.firstOrNull() ?: return ""
            buildDetailedAddressText(address)
        } catch (_: Exception) {
            ""
        }
    }

    private fun buildDetailedAddressText(address: Address): String {
        val district = address.subLocality?.trim().orEmpty()
            .ifBlank { address.subAdminArea?.trim().orEmpty() }
        val street = "${address.thoroughfare.orEmpty()}${address.subThoroughfare.orEmpty()}".trim()
        val feature = address.featureName?.trim().orEmpty()
        val parts = mutableListOf<String>()

        appendAddressPart(parts, district)
        appendAddressPart(parts, street)
        if (street.isBlank()) {
            appendAddressPart(parts, feature)
        } else if (
            feature.isNotBlank() &&
            feature != district &&
            !street.contains(feature) &&
            !feature.contains(street)
        ) {
            appendAddressPart(parts, feature)
        }

        val hasDistrict = district.isNotBlank()
        val hasStreet = street.isNotBlank()
        val hasFeature = feature.isMeaningfulAddressFeature(address)
        if (!hasDistrict || (!hasStreet && !hasFeature)) {
            return ""
        }
        return parts.joinToString(separator = "")
    }

    private fun appendAddressPart(parts: MutableList<String>, rawValue: String?) {
        val value = rawValue?.trim().orEmpty()
        if (value.isEmpty()) {
            return
        }
        if (parts.isEmpty()) {
            parts += value
            return
        }

        val lastValue = parts.last()
        if (lastValue == value || lastValue.contains(value)) {
            return
        }
        if (value.contains(lastValue)) {
            parts[parts.lastIndex] = value
            return
        }
        parts += value
    }

    private fun resolveWeatherText(sourceLocation: Location): String {
        var connection: HttpURLConnection? = null
        return try {
            val query = buildString {
                append("https://api.open-meteo.com/v1/forecast")
                append("?latitude=${"%.6f".format(Locale.US, sourceLocation.latitude)}")
                append("&longitude=${"%.6f".format(Locale.US, sourceLocation.longitude)}")
                append("&current=temperature_2m,weather_code")
                append("&timezone=auto")
                append("&forecast_days=1")
            }
            connection = (URL(query).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8000
                readTimeout = 8000
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                return ""
            }

            val responseText = connection.inputStream.bufferedReader().use { it.readText() }
            val currentObject = JSONObject(responseText).optJSONObject("current") ?: return ""
            val temperature = currentObject.optDouble("temperature_2m", Double.NaN)
            val weatherCode = currentObject.optInt("weather_code", Int.MIN_VALUE)
            if (!temperature.isFinite() || weatherCode == Int.MIN_VALUE) {
                return ""
            }

            "${mapWeatherCode(weatherCode)} ${temperature.roundToInt()}°C"
        } catch (_: Exception) {
            ""
        } finally {
            connection?.disconnect()
        }
    }

    private fun mapWeatherCode(code: Int): String {
        return when (code) {
            0, 1 -> "晴"
            2 -> "多云"
            3 -> "阴"
            45, 48 -> "有雾"
            51, 53, 55, 56, 57 -> "毛毛雨"
            61, 80 -> "小雨"
            63, 81 -> "中雨"
            65, 82 -> "大雨"
            66, 67 -> "冻雨"
            71, 77, 85 -> "小雪"
            73, 86 -> "中雪"
            75 -> "大雪"
            95 -> "雷雨"
            96, 99 -> "强雷雨"
            else -> "天气"
        }
    }

    private fun showLocationPermissionHelp() {
        AlertDialog.Builder(this)
            .setTitle("需要定位权限")
            .setMessage("授权后才能刷新真实地址和天气。你可以点“去设置”直接打开系统权限页。")
            .setNegativeButton("取消", null)
            .setPositiveButton("去设置") { _, _ ->
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", packageName, null)
                    },
                )
            }
            .show()
    }

    private fun showEnableLocationServicesHelp() {
        AlertDialog.Builder(this)
            .setTitle("请先开启定位服务")
            .setMessage("定位服务关闭时，无法获取真实地址和天气。")
            .setNegativeButton("取消", null)
            .setPositiveButton("去开启") { _, _ ->
                startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            }
            .show()
    }

    private fun takePhoto() {
        val capture = imageCapture ?: return
        if (captureInFlight) {
            return
        }

        captureInFlight = true
        captureButton.isEnabled = false
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
        val photoFile = File.createTempFile(
            "wm118_${System.currentTimeMillis()}_",
            ".jpg",
            externalCacheDir ?: cacheDir,
        )
        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()

        capture.takePicture(
            outputOptions,
            captureExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    try {
                        val overlayBitmap = captureOverlayBitmap()
                        val renderedFile = composeWatermarkedPhoto(
                            sourceFile = photoFile,
                            overlayBitmap = overlayBitmap,
                        )

                        runOnUiThread {
                            captureItems += CapturedPhoto(
                                photoPath = renderedFile.absolutePath,
                                captureTimeMillis = now.time,
                                antiFakeCode = antiFakeCode,
                                location = captureLocation,
                                roomCode = captureRoomCode,
                                weatherText = captureWeatherText,
                                imprintText = captureImprintText,
                                displayTimeText = displayTimeText,
                                displayDateText = displayDateText,
                            )

                            if (!antiFakeCodeLocked) {
                                previewAntiFakeCode = generateAntiFakeCode()
                            }
                            persistAntiFakeState()

                            if (captureItems.size >= captureCount) {
                                finishWithResult()
                                return@runOnUiThread
                            }

                            captureInFlight = false
                            captureButton.isEnabled = true
                            updateCaptureHint()
                            bindOverlay(Date())
                        }
                    } catch (error: Exception) {
                        runOnUiThread {
                            captureInFlight = false
                            captureButton.isEnabled = true
                            Toast.makeText(
                                this@NativeWatermarkCameraActivity,
                                "成片生成失败: ${error.message}",
                                Toast.LENGTH_SHORT,
                            ).show()
                        }
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    runOnUiThread {
                        captureInFlight = false
                        captureButton.isEnabled = true
                        Toast.makeText(
                            this@NativeWatermarkCameraActivity,
                            "拍照失败: ${exception.message}",
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            },
        )
    }

    private fun captureOverlayBitmap(): Bitmap {
        val latch = CountDownLatch(1)
        var bitmap: Bitmap? = null
        var error: Throwable? = null

        runOnUiThread {
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
            externalCacheDir ?: cacheDir,
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
            resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT &&
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

    // 成片导出前统一裁成 targetCaptureSize 对应的比例，再缩放到最终尺寸。
    // 如果后面你觉得“预览构图”和“成片构图”还有细微差异，优先从这里继续抠。
    private fun normalizeCapturedBitmap(bitmap: Bitmap): Bitmap {
        val targetAspect = targetCaptureSize.width.toFloat() / targetCaptureSize.height.toFloat()
        val bitmapAspect = bitmap.width.toFloat() / bitmap.height.toFloat()

        val croppedBitmap = if (kotlin.math.abs(bitmapAspect - targetAspect) < 0.001f) {
            bitmap
        } else if (bitmapAspect > targetAspect) {
            val targetWidth = (bitmap.height * targetAspect).toInt()
            val offsetX = ((bitmap.width - targetWidth) / 2f).toInt().coerceAtLeast(0)
            Bitmap.createBitmap(bitmap, offsetX, 0, targetWidth.coerceAtMost(bitmap.width), bitmap.height)
        } else {
            val targetHeight = (bitmap.width / targetAspect).toInt()
            val offsetY = ((bitmap.height - targetHeight) / 2f).toInt().coerceAtLeast(0)
            Bitmap.createBitmap(bitmap, 0, offsetY, bitmap.width, targetHeight.coerceAtMost(bitmap.height))
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

    private fun currentDisplayRotation(): Int {
        return previewView.display?.rotation ?: display?.rotation ?: Surface.ROTATION_0
    }

    private fun updateCaptureHint() {
        if (captureCount > 1) {
            captureHintView.visibility = View.VISIBLE
            captureHintView.text = "拍摄第 ${captureItems.size + 1} / $captureCount 张"
        } else {
            captureHintView.visibility = View.GONE
        }
    }

    private fun playCaptureFeedback() {
        captureButton.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
        try {
            shutterSound.play(MediaActionSound.SHUTTER_CLICK)
        } catch (_: Exception) {
        }

        captureButtonShell.animate().cancel()
        captureButton.animate().cancel()
        captureButtonShell.scaleX = 1f
        captureButtonShell.scaleY = 1f
        captureButton.scaleX = 1f
        captureButton.scaleY = 1f
        captureButtonShell.animate()
            .scaleX(0.94f)
            .scaleY(0.94f)
            .setDuration(70L)
            .withEndAction {
                captureButtonShell.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(150L)
                    .start()
            }
            .start()
        captureButton.animate()
            .scaleX(0.96f)
            .scaleY(0.96f)
            .setDuration(70L)
            .withEndAction {
                captureButton.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(150L)
                    .start()
            }
            .start()

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

    private fun finishWithResult() {
        val payload = JSONArray()
        captureItems.forEach { photo ->
            payload.put(
                JSONObject()
                    .put("photoPath", photo.photoPath)
                    .put("captureTimeMillis", photo.captureTimeMillis)
                    .put("antiFakeCode", photo.antiFakeCode)
                    .put("location", photo.location)
                    .put("roomCode", photo.roomCode)
                    .put("weatherText", photo.weatherText)
                    .put("imprintText", photo.imprintText)
                    .put("displayTimeText", photo.displayTimeText)
                    .put("displayDateText", photo.displayDateText),
            )
        }
        setResult(
            Activity.RESULT_OK,
            Intent().putExtra(EXTRA_RESULT_JSON, payload.toString()),
        )
        finish()
    }

    private fun generateAntiFakeCode(length: Int = 14): String {
        val alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return buildString(length) {
            repeat(length) {
                append(alphabet[Random.nextInt(alphabet.length)])
            }
        }
    }

    private fun currentDisplayTimeText(now: Date): String {
        return timeOverrideText ?: SimpleDateFormat("HH:mm", Locale.CHINA).format(now)
    }

    private fun currentDisplayDateText(now: Date): String {
        return dateOverrideText ?: SimpleDateFormat("yyyy.MM.dd EEEE", Locale.CHINA).format(now)
    }

    // 顶部“参数”按钮对应的手动调参面板。
    // 这里主要改文案内容；位置和尺寸统一走“调节”面板，支持 0.1 精度。
    private fun showWatermarkParamsDialog() {
        val contentView = LayoutInflater.from(this).inflate(
            R.layout.dialog_watermark_params,
            null,
            false,
        )
        val locationInput = contentView.findViewById<EditText>(R.id.etParamLocation)
        val timeInput = contentView.findViewById<EditText>(R.id.etParamTime)
        val dateInput = contentView.findViewById<EditText>(R.id.etParamDate)
        val weatherInput = contentView.findViewById<EditText>(R.id.etParamWeather)
        val roomCodeInput = contentView.findViewById<EditText>(R.id.etParamRoomCode)
        val imprintInput = contentView.findViewById<EditText>(R.id.etParamImprint)
        val antiFakeCodeInput = contentView.findViewById<EditText>(R.id.etParamAntiFakeCode)
        val randomAntiFakeButton = contentView.findViewById<TextView>(R.id.btnRandomAntiFakeCode)

        fun bindFormValues(
            locationValue: String,
            timeValue: String?,
            dateValue: String?,
            weatherValue: String,
            roomCodeValue: String,
            imprintValue: String,
            antiFakeValue: String,
        ) {
            locationInput.setText(locationValue)
            timeInput.setText(timeValue.orEmpty())
            dateInput.setText(dateValue.orEmpty())
            weatherInput.setText(weatherValue)
            roomCodeInput.setText(roomCodeValue)
            imprintInput.setText(imprintValue)
            antiFakeCodeInput.setText(antiFakeValue)
            antiFakeCodeInput.setSelection(antiFakeCodeInput.text?.length ?: 0)
            updateLocationWeatherInputHints(
                locationInput = locationInput,
                weatherInput = weatherInput,
            )
        }

        bindFormValues(
            locationValue = location,
            timeValue = timeOverrideText,
            dateValue = dateOverrideText,
            weatherValue = weatherText,
            roomCodeValue = roomCode,
            imprintValue = imprintText,
            antiFakeValue = previewAntiFakeCode,
        )

        randomAntiFakeButton.setOnClickListener {
            val randomCode = generateAntiFakeCode()
            antiFakeCodeInput.setText(randomCode)
            antiFakeCodeInput.setSelection(randomCode.length)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle("水印参数")
            .setView(contentView)
            .setNegativeButton("取消", null)
            .setNeutralButton("恢复默认", null)
            .setPositiveButton("应用", null)
            .create()

        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                bindFormValues(
                    locationValue = "",
                    timeValue = null,
                    dateValue = null,
                    weatherValue = "",
                    roomCodeValue = defaultRoomCode,
                    imprintValue = defaultImprintText,
                    antiFakeValue = generateAntiFakeCode(),
                )
            }

            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                manualLocationOverride = locationInput.text.toString().trim()
                manualWeatherOverride = weatherInput.text.toString().trim()
                roomCode = roomCodeInput.text.toString().trim().ifBlank { defaultRoomCode }
                imprintText = imprintInput.text.toString().trim()
                timeOverrideText = timeInput.text.toString().trim().takeIf { it.isNotEmpty() }
                dateOverrideText = dateInput.text.toString().trim().takeIf { it.isNotEmpty() }

                val antiFakeValue = antiFakeCodeInput.text.toString()
                    .trim()
                    .uppercase(Locale.ROOT)
                    .take(14)
                if (antiFakeValue.isEmpty()) {
                    antiFakeCodeLocked = false
                    previewAntiFakeCode = generateAntiFakeCode()
                } else {
                    antiFakeCodeLocked = true
                    previewAntiFakeCode = antiFakeValue
                }

                syncEffectiveLocationWeather()
                bindOverlay(Date())
                savePersistedState()
                dialog.dismiss()
            }
        }

        dialog.show()
    }

    // 这个面板负责常用位置 / 尺寸微调，拖动或手输时立即作用到预览和拍照导出的真实视图。
    private fun showWatermarkTuningDialog() {
        val contentView = LayoutInflater.from(this).inflate(
            R.layout.dialog_watermark_tuning,
            null,
            false,
        )
        val tuningItemIds = listOf(
            R.id.itemAnchorStart,
            R.id.itemAnchorEnd,
            R.id.itemAnchorBottom,
            R.id.itemLocationCharsPerLine,
            R.id.itemLeftScale,
            R.id.itemLeftX,
            R.id.itemLeftY,
            R.id.itemTimeSize,
            R.id.itemTimeGlow,
            R.id.itemTimeX,
            R.id.itemTimeY,
            R.id.itemRightScale,
            R.id.itemRightX,
            R.id.itemRightY,
            R.id.itemSecureX,
            R.id.itemSecureY,
            R.id.itemSecureCodeSize,
            R.id.itemSecureTitleScale,
            R.id.itemSecureShadowScaleX,
            R.id.itemSecureShadowScaleY,
            R.id.itemSecureShadowX,
            R.id.itemSecureShadowY,
            R.id.itemSecureCodeSpacing,
            R.id.itemRoomCodeHeight,
            R.id.itemRoomCodeTextSize,
            R.id.itemImprintIconWidth,
            R.id.itemImprintIconHeight,
            R.id.itemImprintTextSize,
        )
        val tuningHeaderIds = listOf(
            R.id.tvTuningHint,
            R.id.tvSectionAnchor,
            R.id.tvSectionLeft,
            R.id.tvSectionTime,
            R.id.tvSectionRight,
            R.id.tvSectionSecure,
            R.id.tvSectionImprint,
        )

        fun setTuningFocus(activeItemId: Int?) {
            tuningHeaderIds.forEach { headerId ->
                contentView.findViewById<View>(headerId).visibility =
                    if (activeItemId == null) View.VISIBLE else View.GONE
            }
            tuningItemIds.forEach { itemId ->
                contentView.findViewById<View>(itemId).visibility =
                    if (activeItemId == null || itemId == activeItemId) {
                        View.VISIBLE
                    } else {
                        View.GONE
                    }
            }
        }

        fun bindSlider(
            itemId: Int,
            label: String,
            unit: String,
            minValue: Float,
            maxValue: Float,
            currentValue: () -> Float,
            onValueChanged: (Float) -> Unit,
        ) {
            val itemView = contentView.findViewById<View>(itemId)
            val labelView = itemView.findViewById<TextView>(R.id.tvSliderLabel)
            val valueInput = itemView.findViewById<EditText>(R.id.etSliderValue)
            val unitView = itemView.findViewById<TextView>(R.id.tvSliderUnit)
            val seekBar = itemView.findViewById<SeekBar>(R.id.seekBarSlider)
            val minTenths = (minValue * 10f).roundToInt()
            val maxTenths = (maxValue * 10f).roundToInt()
            var suppressSeekCallback = false
            var suppressTextCallback = false

            fun clampValue(value: Float): Float {
                return value.normalizeTuningValue().coerceIn(minValue, maxValue)
            }

            fun progressFor(value: Float): Int {
                return (clampValue(value) * 10f).roundToInt() - minTenths
            }

            fun syncInputText(value: Float) {
                val formatted = value.formatTuningValue()
                if (valueInput.text?.toString() != formatted) {
                    suppressTextCallback = true
                    valueInput.setText(formatted)
                    valueInput.setSelection(formatted.length)
                    suppressTextCallback = false
                }
            }

            fun commitTextInput(reformatText: Boolean) {
                val typedValue = valueInput.text?.toString().parseTuningNumber() ?: currentValue()
                val clampedValue = clampValue(typedValue)
                onValueChanged(clampedValue)
                val progress = progressFor(clampedValue)
                if (seekBar.progress != progress) {
                    suppressSeekCallback = true
                    seekBar.progress = progress
                    suppressSeekCallback = false
                }
                if (reformatText) {
                    syncInputText(clampedValue)
                }
            }

            labelView.text = label
            unitView.text = unit
            seekBar.max = maxTenths - minTenths
            syncInputText(clampValue(currentValue()))
            suppressSeekCallback = true
            seekBar.progress = progressFor(currentValue())
            suppressSeekCallback = false
            seekBar.setOnSeekBarChangeListener(
                object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                        if (suppressSeekCallback) {
                            return
                        }
                        val value = clampValue((minTenths + progress) / 10f)
                        onValueChanged(value)
                        if (!valueInput.hasFocus()) {
                            syncInputText(value)
                        }
                    }

                    override fun onStartTrackingTouch(seekBar: SeekBar?) {
                        setTuningFocus(itemId)
                    }

                    override fun onStopTrackingTouch(seekBar: SeekBar?) {
                        setTuningFocus(null)
                    }
                },
            )

            val oldWatcher = valueInput.getTag(R.id.etSliderValue) as? TextWatcher
            if (oldWatcher != null) {
                valueInput.removeTextChangedListener(oldWatcher)
            }
            val watcher = valueInput.doAfterTextChanged { editable ->
                if (suppressTextCallback) {
                    return@doAfterTextChanged
                }
                val typedValue = editable?.toString().parseTuningNumber() ?: return@doAfterTextChanged
                val clampedValue = clampValue(typedValue)
                onValueChanged(clampedValue)
                val progress = progressFor(clampedValue)
                if (seekBar.progress != progress) {
                    suppressSeekCallback = true
                    seekBar.progress = progress
                    suppressSeekCallback = false
                }
            }
            valueInput.setTag(R.id.etSliderValue, watcher)
            valueInput.setOnFocusChangeListener { _, hasFocus ->
                if (hasFocus) {
                    setTuningFocus(itemId)
                } else {
                    commitTextInput(reformatText = true)
                    setTuningFocus(null)
                }
            }
            valueInput.setOnEditorActionListener { _, _, _ ->
                commitTextInput(reformatText = true)
                valueInput.clearFocus()
                false
            }
        }

        fun renderSliders() {
            bindSlider(
                R.id.itemLocationCharsPerLine,
                "地址行宽",
                "dp",
                180f,
                320f,
                { watermarkAdjustments.locationColumnWidthDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(locationColumnWidthDp = value)
                bindOverlay(Date())
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemAnchorStart,
                "左边距",
                "dp",
                0f,
                64f,
                { watermarkAdjustments.anchorStartDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(anchorStartDp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemAnchorEnd,
                "右边距",
                "dp",
                0f,
                64f,
                { watermarkAdjustments.anchorEndDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(anchorEndDp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemAnchorBottom,
                "底边距",
                "dp",
                0f,
                48f,
                { watermarkAdjustments.anchorBottomDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(anchorBottomDp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemLeftScale,
                "左侧整体缩放",
                "x",
                0.7f,
                1.5f,
                { watermarkAdjustments.leftScale },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(leftScale = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemLeftX,
                "左侧整体 X",
                "dp",
                -40f,
                40f,
                { watermarkAdjustments.leftXdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(leftXdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemLeftY,
                "左侧整体 Y",
                "dp",
                -60f,
                60f,
                { watermarkAdjustments.leftYdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(leftYdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemTimeSize,
                "时间字大小",
                "dp",
                20f,
                34f,
                { watermarkAdjustments.timeTextSizeDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(timeTextSizeDp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemTimeGlow,
                "时间发光",
                "dp",
                0f,
                8f,
                { watermarkAdjustments.timeGlowRadiusDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(timeGlowRadiusDp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemTimeX,
                "时间字 X",
                "dp",
                -20f,
                20f,
                { watermarkAdjustments.timeXdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(timeXdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemTimeY,
                "时间字 Y",
                "dp",
                -20f,
                20f,
                { watermarkAdjustments.timeYdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(timeYdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemRightScale,
                "右侧整体缩放",
                "x",
                0.7f,
                1.5f,
                { watermarkAdjustments.rightScale },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(rightScale = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemRightX,
                "右侧整体 X",
                "dp",
                -40f,
                40f,
                { watermarkAdjustments.rightXdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(rightXdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemRightY,
                "右侧整体 Y",
                "dp",
                -60f,
                60f,
                { watermarkAdjustments.rightYdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(rightYdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureX,
                "防伪块 X",
                "dp",
                -30f,
                30f,
                { watermarkAdjustments.secureXdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureXdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureY,
                "防伪块 Y",
                "dp",
                -20f,
                20f,
                { watermarkAdjustments.secureYdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureYdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureCodeSize,
                "防伪码大小",
                "dp",
                4f,
                12f,
                { watermarkAdjustments.secureCodeTextSizeDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureCodeTextSizeDp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureTitleScale,
                "防伪图缩放",
                "x",
                0.5f,
                2f,
                { watermarkAdjustments.secureTitleScale },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureTitleScale = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureShadowScaleX,
                "灰底宽缩放",
                "x",
                0.5f,
                2f,
                { watermarkAdjustments.secureShadowScaleX },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureShadowScaleX = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureShadowScaleY,
                "灰底高缩放",
                "x",
                0.5f,
                2f,
                { watermarkAdjustments.secureShadowScaleY },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureShadowScaleY = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureShadowX,
                "灰底 X",
                "dp",
                -20f,
                20f,
                { watermarkAdjustments.secureShadowXdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureShadowXdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureShadowY,
                "灰底 Y",
                "dp",
                -20f,
                20f,
                { watermarkAdjustments.secureShadowYdp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureShadowYdp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemSecureCodeSpacing,
                "防伪码间距",
                "值",
                0f,
                100f,
                { watermarkAdjustments.secureCodeSpacingValue },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(secureCodeSpacingValue = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemRoomCodeHeight,
                "备注块高度",
                "dp",
                2f,
                14f,
                { watermarkAdjustments.roomCodeVerticalPaddingDp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(roomCodeVerticalPaddingDp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemRoomCodeTextSize,
                "备注字体大小",
                "sp",
                10f,
                18f,
                { watermarkAdjustments.roomCodeTextSizeSp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(roomCodeTextSizeSp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemImprintIconWidth,
                "盾牌宽度",
                "sp",
                8f,
                18f,
                { watermarkAdjustments.imprintIconWidthSp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(imprintIconWidthSp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemImprintIconHeight,
                "盾牌高度",
                "sp",
                10f,
                20f,
                { watermarkAdjustments.imprintIconHeightSp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(imprintIconHeightSp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
            bindSlider(
                R.id.itemImprintTextSize,
                "验证文字大小",
                "sp",
                10f,
                16f,
                { watermarkAdjustments.imprintTextSizeSp },
            ) { value ->
                watermarkAdjustments = watermarkAdjustments.copy(imprintTextSizeSp = value)
                applyWatermarkAdjustments(shouldPersist = true)
            }
        }

        renderSliders()
        setTuningFocus(null)

        val dialog = AlertDialog.Builder(this)
            .setTitle("水印调节")
            .setView(contentView)
            .setNegativeButton("关闭", null)
            .setNeutralButton("恢复默认", null)
            .create()

        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                watermarkAdjustments = WatermarkAdjustments()
                applyWatermarkAdjustments(shouldPersist = true)
                renderSliders()
            }
        }

        dialog.show()
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
        // 对齐原版 `LRView.b(LRData)`：防伪码字距 = textW / 100f。
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
                applyWatermarkAdjustments()
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
        // 备注块需要始终跟当前房间完整名走，不再跨房间复用上一次手动值。
        // 每次打开相机都以 Flutter 传入的当前房间完整名为基线。
        roomCode = defaultRoomCode
        imprintText = defaultImprintText
        timeOverrideText = null
        dateOverrideText = null
        antiFakeCodeLocked = prefs.getBoolean("anti_fake_locked", false)
        previewAntiFakeCode = prefs.getString(
            "anti_fake_value",
            generateAntiFakeCode(),
        ).orEmpty().ifBlank { generateAntiFakeCode() }
        val storedDefaultsVersion = prefs.getInt(TUNING_DEFAULTS_VERSION_KEY, 0)
        if (storedDefaultsVersion < TUNING_DEFAULTS_VERSION) {
            watermarkAdjustments = WatermarkAdjustments()
            needsTuningDefaultsMigration = true
        } else {
            watermarkAdjustments = WatermarkAdjustments(
                anchorStartDp = loadFloatPref("anchor_start_dp", WatermarkAdjustments().anchorStartDp),
                anchorEndDp = loadFloatPref("anchor_end_dp", WatermarkAdjustments().anchorEndDp),
                anchorBottomDp = loadFloatPref("anchor_bottom_dp", WatermarkAdjustments().anchorBottomDp),
                locationColumnWidthDp = loadFloatPref(
                    "location_column_width_dp",
                    WatermarkAdjustments().locationColumnWidthDp,
                ),
                leftScale = loadFloatPref("left_scale", WatermarkAdjustments().leftScale),
                leftXdp = loadFloatPref("left_x_dp", WatermarkAdjustments().leftXdp),
                leftYdp = loadFloatPref("left_y_dp", WatermarkAdjustments().leftYdp),
                timeTextSizeDp = loadFloatPref("time_text_size_dp", WatermarkAdjustments().timeTextSizeDp),
                timeGlowRadiusDp = loadFloatPref(
                    "time_glow_radius_dp",
                    WatermarkAdjustments().timeGlowRadiusDp,
                ),
                timeXdp = loadFloatPref("time_x_dp", WatermarkAdjustments().timeXdp),
                timeYdp = loadFloatPref("time_y_dp", WatermarkAdjustments().timeYdp),
                rightScale = loadFloatPref("right_scale", WatermarkAdjustments().rightScale),
                rightXdp = loadFloatPref("right_x_dp", WatermarkAdjustments().rightXdp),
                rightYdp = loadFloatPref("right_y_dp", WatermarkAdjustments().rightYdp),
                secureXdp = loadFloatPref("secure_x_dp", WatermarkAdjustments().secureXdp),
                secureYdp = loadFloatPref("secure_y_dp", WatermarkAdjustments().secureYdp),
                secureCodeTextSizeDp = loadFloatPref(
                    "secure_code_text_size_dp",
                    WatermarkAdjustments().secureCodeTextSizeDp,
                ),
                secureTitleScale = loadFloatPref(
                    "secure_title_scale",
                    WatermarkAdjustments().secureTitleScale,
                ),
                secureShadowScaleX = loadFloatPref(
                    "secure_shadow_scale_x",
                    WatermarkAdjustments().secureShadowScaleX,
                ),
                secureShadowScaleY = loadFloatPref(
                    "secure_shadow_scale_y",
                    WatermarkAdjustments().secureShadowScaleY,
                ),
                secureShadowXdp = loadFloatPref(
                    "secure_shadow_x_dp",
                    WatermarkAdjustments().secureShadowXdp,
                ),
                secureShadowYdp = loadFloatPref(
                    "secure_shadow_y_dp",
                    WatermarkAdjustments().secureShadowYdp,
                ),
                secureCodeSpacingValue = loadFloatPref(
                    "secure_code_spacing_value",
                    WatermarkAdjustments().secureCodeSpacingValue,
                ),
                demoXdp = loadFloatPref("demo_x_dp", WatermarkAdjustments().demoXdp),
                demoYdp = loadFloatPref("demo_y_dp", WatermarkAdjustments().demoYdp),
                roomCodeVerticalPaddingDp = loadFloatPref(
                    "room_code_vertical_padding_dp",
                    WatermarkAdjustments().roomCodeVerticalPaddingDp,
                ),
                roomCodeTextSizeSp = loadFloatPref(
                    "room_code_text_size_sp",
                    WatermarkAdjustments().roomCodeTextSizeSp,
                ),
                imprintIconWidthSp = loadFloatPref(
                    "imprint_icon_width_sp",
                    WatermarkAdjustments().imprintIconWidthSp,
                ),
                imprintIconHeightSp = loadFloatPref(
                    "imprint_icon_height_sp",
                    WatermarkAdjustments().imprintIconHeightSp,
                ),
                imprintTextSizeSp = loadFloatPref(
                    "imprint_text_size_sp",
                    WatermarkAdjustments().imprintTextSizeSp,
                ),
            )
        }
    }

    private fun savePersistedState() {
        syncEffectiveLocationWeather()
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
            .putString("anti_fake_value", previewAntiFakeCode)
            .putFloat("anchor_start_dp", watermarkAdjustments.anchorStartDp)
            .putFloat("anchor_end_dp", watermarkAdjustments.anchorEndDp)
            .putFloat("anchor_bottom_dp", watermarkAdjustments.anchorBottomDp)
            .putFloat("location_column_width_dp", watermarkAdjustments.locationColumnWidthDp)
            .putFloat("left_scale", watermarkAdjustments.leftScale)
            .putFloat("left_x_dp", watermarkAdjustments.leftXdp)
            .putFloat("left_y_dp", watermarkAdjustments.leftYdp)
            .putFloat("time_text_size_dp", watermarkAdjustments.timeTextSizeDp)
            .putFloat("time_glow_radius_dp", watermarkAdjustments.timeGlowRadiusDp)
            .putFloat("time_x_dp", watermarkAdjustments.timeXdp)
            .putFloat("time_y_dp", watermarkAdjustments.timeYdp)
            .putFloat("right_scale", watermarkAdjustments.rightScale)
            .putFloat("right_x_dp", watermarkAdjustments.rightXdp)
            .putFloat("right_y_dp", watermarkAdjustments.rightYdp)
            .putFloat("secure_x_dp", watermarkAdjustments.secureXdp)
            .putFloat("secure_y_dp", watermarkAdjustments.secureYdp)
            .putFloat("secure_code_text_size_dp", watermarkAdjustments.secureCodeTextSizeDp)
            .putFloat("secure_title_scale", watermarkAdjustments.secureTitleScale)
            .putFloat("secure_shadow_scale_x", watermarkAdjustments.secureShadowScaleX)
            .putFloat("secure_shadow_scale_y", watermarkAdjustments.secureShadowScaleY)
            .putFloat("secure_shadow_x_dp", watermarkAdjustments.secureShadowXdp)
            .putFloat("secure_shadow_y_dp", watermarkAdjustments.secureShadowYdp)
            .putFloat("secure_code_spacing_value", watermarkAdjustments.secureCodeSpacingValue)
            .putFloat("demo_x_dp", watermarkAdjustments.demoXdp)
            .putFloat("demo_y_dp", watermarkAdjustments.demoYdp)
            .putFloat(
                "room_code_vertical_padding_dp",
                watermarkAdjustments.roomCodeVerticalPaddingDp,
            )
            .putFloat("room_code_text_size_sp", watermarkAdjustments.roomCodeTextSizeSp)
            .putFloat("imprint_icon_width_sp", watermarkAdjustments.imprintIconWidthSp)
            .putFloat("imprint_icon_height_sp", watermarkAdjustments.imprintIconHeightSp)
            .putFloat("imprint_text_size_sp", watermarkAdjustments.imprintTextSizeSp)
            .putInt(TUNING_DEFAULTS_VERSION_KEY, TUNING_DEFAULTS_VERSION)
            .apply()
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

    private fun updateLocationWeatherInputHints(
        locationInput: EditText,
        weatherInput: EditText,
    ) {
        val currentAutoLocation = autoLocationValue
        val currentAutoWeather = autoWeatherText
        locationInput.hint = if (currentAutoLocation.isBlank()) {
            "手动填写；点“定位天气”仅在地址足够精确时才回填"
        } else {
            "手动填写；点“定位天气”可回填，当前缓存：$currentAutoLocation"
        }
        weatherInput.hint = if (currentAutoWeather.isBlank()) {
            "手动填写；点“定位天气”可回填真实天气"
        } else {
            "手动填写；点“定位天气”可回填，当前缓存：$currentAutoWeather"
        }
    }

    private fun buildLocationWeatherRefreshToast(
        appliedLocation: Boolean,
        appliedWeather: Boolean,
    ): String {
        return when {
            appliedLocation && appliedWeather -> "真实地址和天气已填入"
            appliedWeather -> "天气已填入，地址精度不足未写入"
            appliedLocation -> "真实地址已填入，天气获取失败"
            else -> "定位成功，但地址精度不足且天气获取失败"
        }
    }

    private fun String.isMeaningfulAddressFeature(address: Address): Boolean {
        val feature = trim()
        if (feature.isEmpty()) {
            return false
        }
        val rejected = setOf(
            address.adminArea?.trim().orEmpty(),
            address.locality?.trim().orEmpty(),
            address.subAdminArea?.trim().orEmpty(),
            address.subLocality?.trim().orEmpty(),
            address.thoroughfare?.trim().orEmpty(),
        ).filter { it.isNotEmpty() }
        return feature !in rejected
    }

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).toInt()

    private val Float.dp: Int
        get() = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            resources.displayMetrics,
        ).roundToInt()

    private val Float.dpF: Float
        get() = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            resources.displayMetrics,
        )

    private val Float.sp: Float
        get() = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            this,
            resources.displayMetrics,
        )

    // 这里就是拍照页“恢复默认”会读回去的默认参数。
    // 命名规则：
    // 1. `Xdp` 正值 = 往右，负值 = 往左
    // 2. `Ydp` 正值 = 往下，负值 = 往上
    // 3. `Scale` = 整块缩放
    // 4. `Dp/Sp` 已经写在字段名里，直接改这里即可
    private data class WatermarkAdjustments(
        // 整块水印贴边距离：
        // start 调大 -> 整体往右；end 调大 -> 整体往左；bottom 调大 -> 整体往上。
        val anchorStartDp: Float = 18f,
        val anchorEndDp: Float = 18f,
        val anchorBottomDp: Float = 9f,

        // 左侧地址/日期/天气正文列宽。
        // 调大后地址更晚换行，调小后更容易换成两行/三行。
        val locationColumnWidthDp: Float = 265f,

        // 左侧整块：包含时间条、地址日期天气、备注块、左下验证行。
        val leftScale: Float = 1f,
        // 118 当前推荐默认参数，按你最新确认的这版基线固定。
        val leftXdp: Float = -12.9f,
        val leftYdp: Float = 3.3f,

        // 时间字本体：字号、白光强度、在时间底纹里的微调位置。
        val timeTextSizeDp: Float = 25f,
        val timeGlowRadiusDp: Float = 0.5f,
        val timeXdp: Float = 3.4f,
        val timeYdp: Float = -0.7f,

        // 右下整块：包含 water17 主图 + 防伪块。
        val rightScale: Float = 1f,
        val rightXdp: Float = 13.8f,
        val rightYdp: Float = 6.8f,

        // 右下防伪块：只调“防伪图 + 防伪码”这一行。
        val secureXdp: Float = 3.0f,
        val secureYdp: Float = -1.6f,
        // 防伪码字号。
        val secureCodeTextSizeDp: Float = 5f,
        // 左侧“防伪”图片缩放。
        val secureTitleScale: Float = 1f,
        // 灰底阴影图的宽高缩放。
        val secureShadowScaleX: Float = 0.7f,
        val secureShadowScaleY: Float = 1f,
        // 灰底阴影图独立位移，专门用来和防伪码重新对齐。
        val secureShadowXdp: Float = -7.2f,
        val secureShadowYdp: Float = 0f,
        // 原版语义就是 LRData.textW。
        // 实际渲染时会套用 `letterSpacing = textW / 100f`。
        val secureCodeSpacingValue: Float = 0f,

        // 旧版 DEMO 角标参数，当前角标已隐藏，保留只是兼容历史持久化值。
        val demoXdp: Float = 2f,
        val demoYdp: Float = -2f,

        // 左侧备注块：`roomCode` 那个半透明灰底条。
        // verticalPadding 主要控制块高度；textSize 控备注文字大小。
        val roomCodeVerticalPaddingDp: Float = 7f,
        val roomCodeTextSizeSp: Float = 14f,

        // 左下验证行：盾牌图标 + “今日水印相机已验证 I 时间地点真实”。
        // 宽高只影响盾牌；textSize 影响右边整段验证文案。
        val imprintIconWidthSp: Float = 12f,
        val imprintIconHeightSp: Float = 14f,
        val imprintTextSizeSp: Float = 12f,
    )

    private data class ImprintParts(
        val prefix: String,
        val divider: String?,
        val suffix: String?,
    )

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

    private fun parseImprintParts(rawValue: String): ImprintParts {
        val trimmedValue = rawValue.trim()
        if (trimmedValue.isEmpty()) {
            return ImprintParts("", null, null)
        }

        val pipeIndex = trimmedValue.indexOf('|')
        if (pipeIndex in 1 until trimmedValue.lastIndex) {
            return ImprintParts(
                prefix = trimmedValue.substring(0, pipeIndex).trim(),
                divider = "I",
                suffix = trimmedValue.substring(pipeIndex + 1).trim(),
            )
        }

        val spacedDividerMatch = Regex("^(.*?)(\\s+[I丨｜]\\s+)(.+)$").find(trimmedValue)
        if (spacedDividerMatch != null) {
            return ImprintParts(
                prefix = spacedDividerMatch.groupValues[1].trim(),
                divider = spacedDividerMatch.groupValues[2].trim().replace("|", "I"),
                suffix = spacedDividerMatch.groupValues[3].trim(),
            )
        }

        return ImprintParts(trimmedValue, null, null)
    }

    private fun loadFloatPref(key: String, defaultValue: Float): Float {
        return try {
            prefs.getFloat(key, defaultValue)
        } catch (_: ClassCastException) {
            prefs.getInt(key, defaultValue.roundToInt()).toFloat()
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

    private fun String?.parseTuningNumber(): Float? {
        val cleanedValue = this
            ?.trim()
            ?.replace('，', '.')
            ?.replace(',', '.')
            ?: return null
        if (cleanedValue.isEmpty() || cleanedValue == "-" || cleanedValue == "." || cleanedValue == "-.") {
            return null
        }
        return cleanedValue.toFloatOrNull()
    }

    private fun Float.normalizeTuningValue(): Float {
        return (this * 10f).roundToInt() / 10f
    }

    private fun Float.formatTuningValue(): String {
        return String.format(Locale.US, "%.1f", this.normalizeTuningValue())
    }

    private data class CapturedPhoto(
        val photoPath: String,
        val captureTimeMillis: Long,
        val antiFakeCode: String,
        val location: String,
        val roomCode: String,
        val weatherText: String,
        val imprintText: String,
        val displayTimeText: String,
        val displayDateText: String,
    )
}
