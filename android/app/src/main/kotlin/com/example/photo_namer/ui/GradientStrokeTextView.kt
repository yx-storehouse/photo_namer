package com.example.photo_namer.ui

import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.util.AttributeSet
import androidx.appcompat.widget.AppCompatTextView
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

class GradientStrokeTextView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : AppCompatTextView(context, attrs, defStyleAttr) {

    companion object {
        private const val STROKE_COLOR = 0xFFF7FBFF.toInt()
        private const val INNER_GLOW_COLOR = 0xF2FFFFFF.toInt()
        private const val OUTER_GLOW_COLOR = 0xB3FFFFFF.toInt()
    }

    private val density = resources.displayMetrics.density
    private val strokeWidthPx = 2f * density
    private var fillShader: Shader? = null
    private var glowRadiusDp = 2.2f

    init {
        includeFontPadding = false
        paint.isDither = true
        paint.isSubpixelText = true
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        applyGlow()
    }

    fun setGlowRadiusDp(value: Float) {
        val normalized = value.coerceAtLeast(0f)
        if (glowRadiusDp == normalized) {
            return
        }
        glowRadiusDp = normalized
        applyGlow()
        requestLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val value = text?.toString().orEmpty()
        val metrics = paint.fontMetrics
        val extraInsetPx = calculateExtraInsetPx()
        val desiredWidth = ceil(
            paint.measureText(value) +
                (extraInsetPx * 2) +
                (strokeWidthPx * 2f) +
                paddingLeft +
                paddingRight,
        ).toInt()
        val desiredHeight = ceil(
            (metrics.bottom - metrics.top) +
                (extraInsetPx * 2) +
                (strokeWidthPx * 2f) +
                paddingTop +
                paddingBottom,
        ).toInt()

        setMeasuredDimension(
            resolveSize(
                desiredWidth.coerceAtLeast(suggestedMinimumWidth),
                widthMeasureSpec,
            ),
            resolveSize(
                desiredHeight.coerceAtLeast(suggestedMinimumHeight),
                heightMeasureSpec,
            ),
        )
    }

    override fun onDraw(canvas: Canvas) {
        val value = text?.toString().orEmpty()
        if (value.isEmpty()) {
            return
        }

        val textPaint = paint
        val oldShader = textPaint.shader
        val oldStyle = textPaint.style
        val oldStrokeWidth = textPaint.strokeWidth
        val oldColor = currentTextColor
        val oldAlign = textPaint.textAlign
        val oldStrokeJoin = textPaint.strokeJoin
        val oldMaskFilter = textPaint.maskFilter
        val metrics = textPaint.fontMetrics
        val extraInsetPx = calculateExtraInsetPx()
        val contentLeft = paddingLeft.toFloat() + extraInsetPx
        val contentRight = width.toFloat() - paddingRight - extraInsetPx
        val contentTop = paddingTop.toFloat() + extraInsetPx
        val contentBottom = height.toFloat() - paddingBottom - extraInsetPx
        // 时间字像素级微调优先看这里：
        // centerX 控左右居中，baseline 控上下居中，strokeWidthPx 控描边粗细。
        val centerX = (contentLeft + contentRight) / 2f
        val baseline = (contentTop + contentBottom) / 2f - (metrics.ascent + metrics.descent) / 2f

        textPaint.textAlign = Paint.Align.CENTER

        textPaint.shader = null
        textPaint.style = Paint.Style.STROKE
        textPaint.strokeJoin = Paint.Join.ROUND
        val glowRadiusPx = glowRadiusDp * density
        if (glowRadiusPx > 0.05f) {
            textPaint.maskFilter = BlurMaskFilter(
                glowRadiusPx * 1.35f,
                BlurMaskFilter.Blur.NORMAL,
            )
            textPaint.strokeWidth = strokeWidthPx + (glowRadiusPx * 0.95f)
            textPaint.color = OUTER_GLOW_COLOR
            canvas.drawText(value, centerX, baseline, textPaint)

            textPaint.maskFilter = BlurMaskFilter(
                glowRadiusPx * 0.72f,
                BlurMaskFilter.Blur.NORMAL,
            )
            textPaint.strokeWidth = strokeWidthPx + (glowRadiusPx * 0.42f)
            textPaint.color = INNER_GLOW_COLOR
            canvas.drawText(value, centerX, baseline, textPaint)
        }
        textPaint.maskFilter = null
        textPaint.strokeWidth = strokeWidthPx
        textPaint.color = STROKE_COLOR
        canvas.drawText(value, centerX, baseline, textPaint)

        textPaint.style = Paint.Style.FILL
        textPaint.strokeWidth = oldStrokeWidth
        textPaint.shader = fillShader
        textPaint.color = oldColor
        textPaint.maskFilter = null
        canvas.drawText(value, centerX, baseline, textPaint)

        textPaint.maskFilter = oldMaskFilter
        textPaint.shader = oldShader
        textPaint.style = oldStyle
        textPaint.strokeWidth = oldStrokeWidth
        textPaint.color = oldColor
        textPaint.textAlign = oldAlign
        textPaint.strokeJoin = oldStrokeJoin
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateShader()
    }

    override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) {
        super.onTextChanged(text, start, before, count)
        updateShader()
    }

    private fun updateShader() {
        val textHeight = if (height > 0) height.toFloat() else paint.textSize
        fillShader = LinearGradient(
            0f,
            0f,
            0f,
            textHeight,
            0xFF0075FF.toInt(),
            0xFF000000.toInt(),
            Shader.TileMode.CLAMP,
        )
        invalidate()
    }

    private fun applyGlow() {
        invalidate()
    }

    private fun calculateExtraInsetPx(): Int {
        val glowInsetPx = glowRadiusDp * density * 2.2f
        return max(strokeWidthPx * 1.7f, glowInsetPx).roundToInt().coerceAtLeast(4)
    }
}
