package com.example.photo_namer

import android.app.Activity
import android.graphics.Rect as AndroidRect
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.util.Size
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.View
import android.os.Build
import android.widget.ImageView
import android.widget.TextView
import androidx.exifinterface.media.ExifInterface
import com.example.photo_namer.ui.FixedAspectFrameLayout
import com.example.photo_namer.ui.GradientStrokeTextView
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt
import kotlin.random.Random

internal class NativeWatermarkBatchComposer(private val activity: Activity) {

    companion object {
        private const val PREFS_NAME = "watermark_118_debug_prefs"
        private const val TUNING_DEFAULTS_VERSION_KEY = "tuning_defaults_version"
        private const val TUNING_DEFAULTS_VERSION = 3
    }

    private val prefs: SharedPreferences by lazy {
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    private val targetCaptureSize = Size(1920, 2560)
    private val initLatch = CountDownLatch(1)
    private var initError: Throwable? = null

    private lateinit var rootView: View
    private lateinit var previewFrame: FixedAspectFrameLayout
    private lateinit var watermarkAnchor: View
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

    private var watermarkAdjustments = WatermarkAdjustments()

    init {
        activity.runOnUiThread {
            try {
                rootView = LayoutInflater.from(activity).inflate(
                    R.layout.view_native_watermark_camera_preview,
                    null,
                    false,
                )
                bindViews()
                previewFrame.aspectWidth = targetCaptureSize.width
                previewFrame.aspectHeight = targetCaptureSize.height
                loadPersistedAdjustments()
                layoutRenderer()
                applyWatermarkAdjustments()
                layoutRenderer()
                applyWatermarkAdjustments()
                layoutRenderer()
            } catch (throwable: Throwable) {
                initError = throwable
            } finally {
                initLatch.countDown()
            }
        }
    }

    fun composeBatch(entries: List<BatchComposeEntry>): BatchComposeSummary {
        ensureRendererReady()

        val results = ArrayList<BatchComposeEntryResult>(entries.size)
        var successCount = 0
        var missingCount = 0
        var failedCount = 0

        entries.forEach { entry ->
            val sourceFile = File(entry.rawPhotoPath)
            if (!sourceFile.exists()) {
                missingCount++
                results += BatchComposeEntryResult(
                    materialId = entry.materialId,
                    inspectionItemId = entry.inspectionItemId,
                    status = "missing",
                    outputPath = null,
                )
                return@forEach
            }

            try {
                val antiFakeCode = entry.antiFakeCode ?: generateAntiFakeCode()
                val overlayBitmap = renderOverlayBitmap(entry, antiFakeCode)
                composeWatermarkedPhoto(
                    sourceFile = sourceFile,
                    overlayBitmap = overlayBitmap,
                    outputFile = File(entry.outputPath),
                )
                successCount++
                results += BatchComposeEntryResult(
                    materialId = entry.materialId,
                    inspectionItemId = entry.inspectionItemId,
                    status = "success",
                    outputPath = entry.outputPath,
                )
            } catch (_: Throwable) {
                failedCount++
                results += BatchComposeEntryResult(
                    materialId = entry.materialId,
                    inspectionItemId = entry.inspectionItemId,
                    status = "failed",
                    outputPath = null,
                )
            }
        }

        return BatchComposeSummary(
            successCount = successCount,
            missingCount = missingCount,
            failedCount = failedCount,
            results = results,
        )
    }

    private fun ensureRendererReady() {
        if (!initLatch.await(3, TimeUnit.SECONDS)) {
            error("watermark renderer init timeout")
        }
        initError?.let { throw RuntimeException(it) }
    }

    private fun bindViews() {
        previewFrame = rootView.findViewById(R.id.previewFrame)
        watermarkAnchor = rootView.findViewById(R.id.watermarkAnchor)
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

    private fun renderOverlayBitmap(entry: BatchComposeEntry, antiFakeCode: String): Bitmap {
        val latch = CountDownLatch(1)
        var bitmap: Bitmap? = null
        var error: Throwable? = null

        activity.runOnUiThread {
            try {
                bindOverlay(entry, antiFakeCode)
                layoutRenderer()
                applyWatermarkAdjustments()
                layoutRenderer()
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
        return bitmap ?: error("overlay render failed")
    }

    private fun bindOverlay(entry: BatchComposeEntry, antiFakeCode: String) {
        val captureDate = Date(entry.captureTimeMillis)
        timeView.text = entry.displayTimeText ?: SimpleDateFormat("HH:mm", Locale.CHINA).format(captureDate)
        dateView.text =
            entry.displayDateText ?: SimpleDateFormat("yyyy.MM.dd EEEE", Locale.CHINA).format(captureDate)
        locationView.text = formatLocationText(
            rawValue = entry.location,
            maxWidthPx = watermarkAdjustments.locationColumnWidthDp.dpF,
        )
        weatherView.text = entry.weatherText
        roomCodeView.text = entry.roomCode
        antiFakeCodeView.text = antiFakeCode
        bindImprintText(entry.imprintText)
    }

    private fun layoutRenderer() {
        val rendererHostSize = resolveRendererHostSize()
        val widthSpec = View.MeasureSpec.makeMeasureSpec(
            rendererHostSize.width,
            View.MeasureSpec.EXACTLY,
        )
        val heightSpec = View.MeasureSpec.makeMeasureSpec(
            rendererHostSize.height,
            View.MeasureSpec.EXACTLY,
        )
        rootView.measure(widthSpec, heightSpec)
        rootView.layout(0, 0, rootView.measuredWidth, rootView.measuredHeight)
    }

    private fun resolveRendererHostSize(): Size {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds: AndroidRect = activity.windowManager.currentWindowMetrics.bounds
            if (bounds.width() > 0 && bounds.height() > 0) {
                return Size(bounds.width(), bounds.height())
            }
        }

        val metrics = activity.resources.displayMetrics
        val width = metrics.widthPixels.coerceAtLeast(targetCaptureSize.width / 2)
        val height = metrics.heightPixels.coerceAtLeast(targetCaptureSize.height / 2)
        return Size(width, height)
    }

    private fun applyWatermarkAdjustments() {
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
        }
        watermarkAnchor.requestLayout()
        watermarkAnchor.invalidate()
    }

    private fun loadPersistedAdjustments() {
        val storedDefaultsVersion = prefs.getInt(TUNING_DEFAULTS_VERSION_KEY, 0)
        if (storedDefaultsVersion < TUNING_DEFAULTS_VERSION) {
            watermarkAdjustments = WatermarkAdjustments()
            return
        }

        val defaults = WatermarkAdjustments()
        watermarkAdjustments = WatermarkAdjustments(
            anchorStartDp = loadFloatPref("anchor_start_dp", defaults.anchorStartDp),
            anchorEndDp = loadFloatPref("anchor_end_dp", defaults.anchorEndDp),
            anchorBottomDp = loadFloatPref("anchor_bottom_dp", defaults.anchorBottomDp),
            locationColumnWidthDp = loadFloatPref(
                "location_column_width_dp",
                defaults.locationColumnWidthDp,
            ),
            leftScale = loadFloatPref("left_scale", defaults.leftScale),
            leftXdp = loadFloatPref("left_x_dp", defaults.leftXdp),
            leftYdp = loadFloatPref("left_y_dp", defaults.leftYdp),
            timeTextSizeDp = loadFloatPref("time_text_size_dp", defaults.timeTextSizeDp),
            timeGlowRadiusDp = loadFloatPref("time_glow_radius_dp", defaults.timeGlowRadiusDp),
            timeXdp = loadFloatPref("time_x_dp", defaults.timeXdp),
            timeYdp = loadFloatPref("time_y_dp", defaults.timeYdp),
            rightScale = loadFloatPref("right_scale", defaults.rightScale),
            rightXdp = loadFloatPref("right_x_dp", defaults.rightXdp),
            rightYdp = loadFloatPref("right_y_dp", defaults.rightYdp),
            secureXdp = loadFloatPref("secure_x_dp", defaults.secureXdp),
            secureYdp = loadFloatPref("secure_y_dp", defaults.secureYdp),
            secureCodeTextSizeDp = loadFloatPref(
                "secure_code_text_size_dp",
                defaults.secureCodeTextSizeDp,
            ),
            secureTitleScale = loadFloatPref("secure_title_scale", defaults.secureTitleScale),
            secureShadowScaleX = loadFloatPref(
                "secure_shadow_scale_x",
                defaults.secureShadowScaleX,
            ),
            secureShadowScaleY = loadFloatPref(
                "secure_shadow_scale_y",
                defaults.secureShadowScaleY,
            ),
            secureShadowXdp = loadFloatPref("secure_shadow_x_dp", defaults.secureShadowXdp),
            secureShadowYdp = loadFloatPref("secure_shadow_y_dp", defaults.secureShadowYdp),
            secureCodeSpacingValue = loadFloatPref(
                "secure_code_spacing_value",
                defaults.secureCodeSpacingValue,
            ),
            demoXdp = loadFloatPref("demo_x_dp", defaults.demoXdp),
            demoYdp = loadFloatPref("demo_y_dp", defaults.demoYdp),
            roomCodeVerticalPaddingDp = loadFloatPref(
                "room_code_vertical_padding_dp",
                defaults.roomCodeVerticalPaddingDp,
            ),
            roomCodeTextSizeSp = loadFloatPref(
                "room_code_text_size_sp",
                defaults.roomCodeTextSizeSp,
            ),
            imprintIconWidthSp = loadFloatPref(
                "imprint_icon_width_sp",
                defaults.imprintIconWidthSp,
            ),
            imprintIconHeightSp = loadFloatPref(
                "imprint_icon_height_sp",
                defaults.imprintIconHeightSp,
            ),
            imprintTextSizeSp = loadFloatPref(
                "imprint_text_size_sp",
                defaults.imprintTextSizeSp,
            ),
        )
    }

    private fun bindImprintText(rawValue: String) {
        val parts = parseImprintParts(rawValue)
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

    private fun composeWatermarkedPhoto(sourceFile: File, overlayBitmap: Bitmap, outputFile: File) {
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

        outputFile.parentFile?.mkdirs()
        FileOutputStream(outputFile).use { stream ->
            mergedBitmap.compress(Bitmap.CompressFormat.JPEG, 95, stream)
            stream.flush()
        }

        overlayBitmap.recycle()
        sourceBitmap.recycle()
        mergedBitmap.recycle()
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

    private fun generateAntiFakeCode(length: Int = 14): String {
        val alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return buildString(length) {
            repeat(length) {
                append(alphabet[Random.nextInt(alphabet.length)])
            }
        }
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

    data class BatchComposeEntry(
        val materialId: Int?,
        val inspectionItemId: Int,
        val rawPhotoPath: String,
        val outputPath: String,
        val captureTimeMillis: Long,
        val location: String,
        val roomCode: String,
        val weatherText: String,
        val imprintText: String,
        val displayTimeText: String?,
        val displayDateText: String?,
        val antiFakeCode: String?,
    ) {
        companion object {
            fun fromMap(raw: Map<*, *>): BatchComposeEntry? {
                val rawPath = raw["rawPhotoPath"]?.toString()?.trim().orEmpty()
                val outputPath = raw["outputPath"]?.toString()?.trim().orEmpty()
                if (rawPath.isEmpty() || outputPath.isEmpty()) {
                    return null
                }
                return BatchComposeEntry(
                    materialId = (raw["materialId"] as? Number)?.toInt(),
                    inspectionItemId = (raw["inspectionItemId"] as? Number)?.toInt() ?: 0,
                    rawPhotoPath = rawPath,
                    outputPath = outputPath,
                    captureTimeMillis = (raw["captureTimeMillis"] as? Number)?.toLong()
                        ?: System.currentTimeMillis(),
                    location = raw["location"]?.toString().orEmpty(),
                    roomCode = raw["roomCode"]?.toString().orEmpty(),
                    weatherText = raw["weatherText"]?.toString().orEmpty(),
                    imprintText = raw["imprintText"]?.toString().orEmpty(),
                    displayTimeText = raw["displayTimeText"]?.toString()?.trim()?.ifEmpty { null },
                    displayDateText = raw["displayDateText"]?.toString()?.trim()?.ifEmpty { null },
                    antiFakeCode = raw["antiFakeCode"]?.toString()?.trim()?.ifEmpty { null },
                )
            }
        }
    }

    data class BatchComposeSummary(
        val successCount: Int,
        val missingCount: Int,
        val failedCount: Int,
        val results: List<BatchComposeEntryResult>,
    ) {
        fun toMap(): HashMap<String, Any?> {
            return hashMapOf(
                "successCount" to successCount,
                "missingCount" to missingCount,
                "failedCount" to failedCount,
                "results" to ArrayList(results.map { it.toMap() }),
            )
        }
    }

    data class BatchComposeEntryResult(
        val materialId: Int?,
        val inspectionItemId: Int,
        val status: String,
        val outputPath: String?,
    ) {
        fun toMap(): HashMap<String, Any?> {
            return hashMapOf(
                "materialId" to materialId,
                "inspectionItemId" to inspectionItemId,
                "status" to status,
                "outputPath" to outputPath,
            )
        }
    }

    private data class WatermarkAdjustments(
        val anchorStartDp: Float = 18f,
        val anchorEndDp: Float = 18f,
        val anchorBottomDp: Float = 9f,
        val locationColumnWidthDp: Float = 265f,
        val leftScale: Float = 1f,
        val leftXdp: Float = -12.9f,
        val leftYdp: Float = 3.3f,
        val timeTextSizeDp: Float = 25f,
        val timeGlowRadiusDp: Float = 0.5f,
        val timeXdp: Float = 3.4f,
        val timeYdp: Float = -0.7f,
        val rightScale: Float = 1f,
        val rightXdp: Float = 13.8f,
        val rightYdp: Float = 6.8f,
        val secureXdp: Float = 3.0f,
        val secureYdp: Float = -1.6f,
        val secureCodeTextSizeDp: Float = 5f,
        val secureTitleScale: Float = 1f,
        val secureShadowScaleX: Float = 0.7f,
        val secureShadowScaleY: Float = 1f,
        val secureShadowXdp: Float = -7.2f,
        val secureShadowYdp: Float = 0f,
        val secureCodeSpacingValue: Float = 0f,
        val demoXdp: Float = 2f,
        val demoYdp: Float = -2f,
        val roomCodeVerticalPaddingDp: Float = 7f,
        val roomCodeTextSizeSp: Float = 14f,
        val imprintIconWidthSp: Float = 12f,
        val imprintIconHeightSp: Float = 14f,
        val imprintTextSizeSp: Float = 12f,
    )

    private data class ImprintParts(
        val prefix: String,
        val divider: String?,
        val suffix: String?,
    )
}
