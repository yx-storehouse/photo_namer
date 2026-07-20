package com.example.photo_namer.ui

import android.content.Context
import android.util.AttributeSet
import android.widget.FrameLayout

class FixedAspectFrameLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    var aspectWidth: Int = 3
    var aspectHeight: Int = 4

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val availableWidth = MeasureSpec.getSize(widthMeasureSpec)
        val availableHeight = MeasureSpec.getSize(heightMeasureSpec)

        if (availableWidth == 0 || availableHeight == 0 || aspectWidth <= 0 || aspectHeight <= 0) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            return
        }

        val targetHeightFromWidth = availableWidth * aspectHeight / aspectWidth
        val targetWidthFromHeight = availableHeight * aspectWidth / aspectHeight

        val measuredWidth: Int
        val measuredHeight: Int
        if (targetHeightFromWidth <= availableHeight) {
            measuredWidth = availableWidth
            measuredHeight = targetHeightFromWidth
        } else {
            measuredWidth = targetWidthFromHeight
            measuredHeight = availableHeight
        }

        val exactWidth = MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY)
        val exactHeight = MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.EXACTLY)
        super.onMeasure(exactWidth, exactHeight)
    }
}
