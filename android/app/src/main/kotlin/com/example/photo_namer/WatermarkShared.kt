package com.example.photo_namer

import android.content.SharedPreferences
import kotlin.math.roundToInt
import kotlin.random.Random

/**
 * 118 水印微调参数,预览(PlatformView)与离屏批量合成(BatchComposer)共用,
 * 保证两条链路读到同一套持久化调节值。
 */
internal data class WatermarkAdjustments(
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
) {
    fun writeTo(editor: SharedPreferences.Editor): SharedPreferences.Editor {
        return editor
            .putFloat("anchor_start_dp", anchorStartDp)
            .putFloat("anchor_end_dp", anchorEndDp)
            .putFloat("anchor_bottom_dp", anchorBottomDp)
            .putFloat("location_column_width_dp", locationColumnWidthDp)
            .putFloat("left_scale", leftScale)
            .putFloat("left_x_dp", leftXdp)
            .putFloat("left_y_dp", leftYdp)
            .putFloat("time_text_size_dp", timeTextSizeDp)
            .putFloat("time_glow_radius_dp", timeGlowRadiusDp)
            .putFloat("time_x_dp", timeXdp)
            .putFloat("time_y_dp", timeYdp)
            .putFloat("right_scale", rightScale)
            .putFloat("right_x_dp", rightXdp)
            .putFloat("right_y_dp", rightYdp)
            .putFloat("secure_x_dp", secureXdp)
            .putFloat("secure_y_dp", secureYdp)
            .putFloat("secure_code_text_size_dp", secureCodeTextSizeDp)
            .putFloat("secure_title_scale", secureTitleScale)
            .putFloat("secure_shadow_scale_x", secureShadowScaleX)
            .putFloat("secure_shadow_scale_y", secureShadowScaleY)
            .putFloat("secure_shadow_x_dp", secureShadowXdp)
            .putFloat("secure_shadow_y_dp", secureShadowYdp)
            .putFloat("secure_code_spacing_value", secureCodeSpacingValue)
            .putFloat("demo_x_dp", demoXdp)
            .putFloat("demo_y_dp", demoYdp)
            .putFloat("room_code_vertical_padding_dp", roomCodeVerticalPaddingDp)
            .putFloat("room_code_text_size_sp", roomCodeTextSizeSp)
            .putFloat("imprint_icon_width_sp", imprintIconWidthSp)
            .putFloat("imprint_icon_height_sp", imprintIconHeightSp)
            .putFloat("imprint_text_size_sp", imprintTextSizeSp)
            .putInt(TUNING_DEFAULTS_VERSION_KEY, TUNING_DEFAULTS_VERSION)
    }

    companion object {
        const val PREFS_NAME = "watermark_118_debug_prefs"
        const val TUNING_DEFAULTS_VERSION_KEY = "tuning_defaults_version"
        const val TUNING_DEFAULTS_VERSION = 3

        fun loadFromPrefs(prefs: SharedPreferences): WatermarkAdjustments {
            val storedDefaultsVersion = prefs.getInt(TUNING_DEFAULTS_VERSION_KEY, 0)
            if (storedDefaultsVersion < TUNING_DEFAULTS_VERSION) {
                return WatermarkAdjustments()
            }

            val defaults = WatermarkAdjustments()
            return WatermarkAdjustments(
                anchorStartDp = loadFloatPref(prefs, "anchor_start_dp", defaults.anchorStartDp),
                anchorEndDp = loadFloatPref(prefs, "anchor_end_dp", defaults.anchorEndDp),
                anchorBottomDp = loadFloatPref(prefs, "anchor_bottom_dp", defaults.anchorBottomDp),
                locationColumnWidthDp = loadFloatPref(
                    prefs,
                    "location_column_width_dp",
                    defaults.locationColumnWidthDp,
                ),
                leftScale = loadFloatPref(prefs, "left_scale", defaults.leftScale),
                leftXdp = loadFloatPref(prefs, "left_x_dp", defaults.leftXdp),
                leftYdp = loadFloatPref(prefs, "left_y_dp", defaults.leftYdp),
                timeTextSizeDp = loadFloatPref(prefs, "time_text_size_dp", defaults.timeTextSizeDp),
                timeGlowRadiusDp = loadFloatPref(
                    prefs,
                    "time_glow_radius_dp",
                    defaults.timeGlowRadiusDp,
                ),
                timeXdp = loadFloatPref(prefs, "time_x_dp", defaults.timeXdp),
                timeYdp = loadFloatPref(prefs, "time_y_dp", defaults.timeYdp),
                rightScale = loadFloatPref(prefs, "right_scale", defaults.rightScale),
                rightXdp = loadFloatPref(prefs, "right_x_dp", defaults.rightXdp),
                rightYdp = loadFloatPref(prefs, "right_y_dp", defaults.rightYdp),
                secureXdp = loadFloatPref(prefs, "secure_x_dp", defaults.secureXdp),
                secureYdp = loadFloatPref(prefs, "secure_y_dp", defaults.secureYdp),
                secureCodeTextSizeDp = loadFloatPref(
                    prefs,
                    "secure_code_text_size_dp",
                    defaults.secureCodeTextSizeDp,
                ),
                secureTitleScale = loadFloatPref(
                    prefs,
                    "secure_title_scale",
                    defaults.secureTitleScale,
                ),
                secureShadowScaleX = loadFloatPref(
                    prefs,
                    "secure_shadow_scale_x",
                    defaults.secureShadowScaleX,
                ),
                secureShadowScaleY = loadFloatPref(
                    prefs,
                    "secure_shadow_scale_y",
                    defaults.secureShadowScaleY,
                ),
                secureShadowXdp = loadFloatPref(
                    prefs,
                    "secure_shadow_x_dp",
                    defaults.secureShadowXdp,
                ),
                secureShadowYdp = loadFloatPref(
                    prefs,
                    "secure_shadow_y_dp",
                    defaults.secureShadowYdp,
                ),
                secureCodeSpacingValue = loadFloatPref(
                    prefs,
                    "secure_code_spacing_value",
                    defaults.secureCodeSpacingValue,
                ),
                demoXdp = loadFloatPref(prefs, "demo_x_dp", defaults.demoXdp),
                demoYdp = loadFloatPref(prefs, "demo_y_dp", defaults.demoYdp),
                roomCodeVerticalPaddingDp = loadFloatPref(
                    prefs,
                    "room_code_vertical_padding_dp",
                    defaults.roomCodeVerticalPaddingDp,
                ),
                roomCodeTextSizeSp = loadFloatPref(
                    prefs,
                    "room_code_text_size_sp",
                    defaults.roomCodeTextSizeSp,
                ),
                imprintIconWidthSp = loadFloatPref(
                    prefs,
                    "imprint_icon_width_sp",
                    defaults.imprintIconWidthSp,
                ),
                imprintIconHeightSp = loadFloatPref(
                    prefs,
                    "imprint_icon_height_sp",
                    defaults.imprintIconHeightSp,
                ),
                imprintTextSizeSp = loadFloatPref(
                    prefs,
                    "imprint_text_size_sp",
                    defaults.imprintTextSizeSp,
                ),
            )
        }

        private fun loadFloatPref(
            prefs: SharedPreferences,
            key: String,
            defaultValue: Float,
        ): Float {
            return try {
                prefs.getFloat(key, defaultValue)
            } catch (_: ClassCastException) {
                prefs.getInt(key, defaultValue.roundToInt()).toFloat()
            }
        }
    }
}

/** 验证文案的三段拆分结果(前半句 / 分隔符 / 后半句)。 */
internal data class ImprintParts(
    val prefix: String,
    val divider: String?,
    val suffix: String?,
)

/** 把"前半句|后半句"式验证文案拆成两段,与原版展示规则一致。 */
internal fun parseImprintParts(rawValue: String): ImprintParts {
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

/** 生成 14 位大写字母数字防伪码。 */
internal fun generateAntiFakeCode(length: Int = 14): String {
    val alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return buildString(length) {
        repeat(length) {
            append(alphabet[Random.nextInt(alphabet.length)])
        }
    }
}
