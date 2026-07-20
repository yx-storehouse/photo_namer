# 118 水印手动微调文档

这份文档对应当前项目里的安卓原生预览/导出链路，目标是方便你后面做像素级微调。

## 1. 当前主链路

- 原生拍照页: `android/app/src/main/kotlin/com/example/photo_namer/NativeWatermarkCameraActivity.kt`
- 预览外层布局: `android/app/src/main/res/layout/activity_native_watermark_camera.xml`
- 左下 118 主模板: `android/app/src/main/res/layout/view_watermark_118_left.xml`
- 右下角标模板 17: `android/app/src/main/res/layout/view_watermark_lr17.xml`
- 时间描边渐变字: `android/app/src/main/kotlin/com/example/photo_namer/ui/GradientStrokeTextView.kt`
- 预览固定比例容器: `android/app/src/main/kotlin/com/example/photo_namer/ui/FixedAspectFrameLayout.kt`

## 2. 当前统一画布

- 预览和导出统一使用 `1920 x 2560`
- 比例为 `3:4`
- 预览容器比例由 `FixedAspectFrameLayout` 控制
- 导出时如果原图不是 `3:4`，会先在 `NativeWatermarkCameraActivity.normalizeCapturedBitmap()` 里裁成 `3:4`，再缩放到 `1920 x 2560`

## 3. 你最常会改的参数

### 3.0 当前推荐默认值

这组值已经同步到 `NativeWatermarkCameraActivity.WatermarkAdjustments()`，点拍照页里的 `恢复默认` 就会回到这套基线。

- 左边距: `18.0dp`
- 右边距: `18.0dp`
- 底边距: `9.0dp`
- 左侧整体缩放: `1.0`
- 左侧整体 X: `-12.9dp`
- 左侧整体 Y: `3.5dp`
- 时间字大小: `23.0dp`
- 时间字发光: `2.2dp`
- 时间字 X: `3.4dp`
- 时间字 Y: `-0.7dp`
- 右侧整体缩放: `1.0`
- 右侧整体 X: `13.8dp`
- 右侧整体 Y: `6.6dp`
- 防伪块 X: `-3.4dp`
- 防伪块 Y: `0.0dp`
- 备注块高度: `6.0dp`
- 备注字体大小: `12.0sp`
- 盾牌宽度: `12.0sp`
- 盾牌高度: `14.0sp`
- 验证文字大小: `12.0sp`

### 3.1 整体左右边距

文件: `android/app/src/main/res/layout/activity_native_watermark_camera.xml`

- `watermarkAnchor.paddingStart`
- `watermarkAnchor.paddingEnd`
- `watermarkAnchor.paddingBottom`

这三个值控制整块水印贴边距离。

- `paddingStart` 调大: 整块水印往右
- `paddingStart` 调小: 整块水印往左
- `paddingEnd` 调大: 整块水印往左
- `paddingEnd` 调小: 整块水印往右
- `paddingBottom` 调大: 整块水印往上
- `paddingBottom` 调小: 整块水印往下
- 建议步进: `1dp`

### 3.2 左侧时间条

文件: `android/app/src/main/res/layout/view_watermark_118_left.xml`

- `watermark118TimeStrip.layout_width`
- `watermark118TimeStrip.layout_height`
- 左侧黄块:
  - `36dp x 24dp`
  - `layout_marginStart=4dp`
- 时间字:
  - `tvWatermarkTime.layout_marginEnd`
  - `tvWatermarkTime.minWidth`
  - `tvWatermarkTime.textSize`
- `tvWatermarkTime.letterSpacing`

时间字真正的描边/渐变/居中逻辑在:

- `android/app/src/main/kotlin/com/example/photo_namer/ui/GradientStrokeTextView.kt`

你如果觉得时间还要上下左右微调，优先改这个类里的:

- `extraInsetPx`
- `baseline`
- `centerX`
- `strokeWidthPx`

效果说明:

- `watermark118TimeStrip.layout_width` 调大: 整条底纹更长
- `watermark118TimeStrip.layout_height` 调大: 整条底纹更高
- `tvWatermarkTime.layout_marginEnd` 调大: 时间整体往左
- `tvWatermarkTime.layout_marginEnd` 调小: 时间整体往右
- `tvWatermarkTime.minWidth` 调大: 时间的可用排版区更宽
- `tvWatermarkTime.textSize` 调大: 数字更大
- `tvWatermarkTime.letterSpacing` 调大: 数字更分开
- 建议步进:
  - 位置类 `0.5dp ~ 1dp`
  - 字号类 `0.5sp ~ 1sp`
  - 字距类 `0.005 ~ 0.01`

### 3.3 左侧正文区

文件: `android/app/src/main/res/layout/view_watermark_118_left.xml`

- 地址/日期/天气整体与黄竖条间距:
  - 第二层 `LinearLayout.layout_marginStart=8dp`
- 三行字体大小:
  - 地址 `15.6sp`
  - 日期 `13.4sp`
  - 天气 `13.4sp`
- 三行上下间距:
  - 日期 `layout_marginTop=4dp`
  - 天气 `layout_marginTop=4dp`

重点:

- 地址控件 `tvWatermarkLocation.maxLines=2`，现在允许长地址自动换两行
- `tvWatermarkLocation.lineSpacingExtra` 调大: 地址两行更松
- `tvWatermarkLocation.textSize` 调大: 地址更大
- `tvWatermarkDate.layout_marginTop` 调大: 日期往下
- `tvWatermarkWeather.layout_marginTop` 调大: 天气往下
- 建议步进:
  - 间距 `1dp`
  - 字号 `0.5sp ~ 1sp`

### 3.4 备注块

文件: `android/app/src/main/res/layout/view_watermark_118_left.xml`

- `tvWatermarkRoomCode.layout_marginTop=6dp`
- `paddingStart=6dp`
- `paddingTop=6dp`
- `paddingEnd=10dp`
- `paddingBottom=6dp`

背景渐变在:

- `android/app/src/main/res/drawable/bg_custom_text.xml`

效果说明:

- `layout_marginTop` 调大: 备注块往下
- `paddingStart/End` 调大: 背景更宽
- `paddingTop/Bottom` 调大: 背景更高
- 建议步进: `1dp`

### 3.5 左下盾牌备注

文件: `android/app/src/main/res/layout/view_watermark_118_left.xml`

- 外层上边距:
  - `imprintRow.layout_marginTop=5dp`
- 图标尺寸:
  - `ivWatermarkImprint.width=12sp`
  - `ivWatermarkImprint.height=14sp`
- 图标透明度:
  - `alpha=0.7`
- 文字拆分:
  - `tvWatermarkImprintPrefix`
  - `tvWatermarkImprintDivider`
  - `tvWatermarkImprintSuffix`
- 分隔符透明度:
  - `tvWatermarkImprintDivider.textColor=#80FFFFFF`
- 盾牌和文字间距:
  - `imprintTextGroup.layout_marginStart=4dp`

真实运行逻辑现在也在代码里做了拆分:

- `NativeWatermarkCameraActivity.bindImprintText()`
- `NativeWatermarkCameraActivity.parseImprintParts()`

说明:

- 如果你在参数面板里输入 `今日水印相机已验证|时间地点真实`
  - 运行时会拆成前半句 + 半透明 `I` + 后半句
- 如果你输入普通文案，不带分隔符
  - 会退回成单段文本显示

效果说明:

- `imprintRow.layout_marginTop` 调大: 整行往下
- `ivWatermarkImprint.width/height` 调大: 盾牌更大
- `tvWatermarkImprintPrefix.textSize` / `tvWatermarkImprintSuffix.textSize` 调大: 验证文案更大
- `tvWatermarkImprintDivider.textColor` 透明度调低: 中间 `I` 更淡
- `imprintTextGroup.layout_marginStart` 调大: 盾牌和文案更开
- 建议步进:
  - 位置/尺寸 `1dp`
  - 字号 `0.5sp`

### 3.6 右下角 `water17`

文件: `android/app/src/main/res/layout/view_watermark_lr17.xml`

- 右下主图当前按素材原始比例 `wrap_content`
- 如果想整体右移/左移，优先改:
  - `watermarkAnchor.paddingEnd`
- 如果只想改右下角自己:
  - `watermarkRightRoot`
  - `secureRow.translationX`

效果说明:

- `secureRow.translationX` 调大: 防伪块往右
- `secureRow.translationX` 调小: 防伪块往左
- 建议步进: `0.5dp ~ 1dp`

### 3.7 防伪块

文件: `android/app/src/main/res/layout/view_watermark_lr17.xml`

- 防伪标题图:
  - `10dp x 7dp`
- 代码外壳:
  - `paddingLeft=1dp`
  - `paddingTop=0.25dp`
- 代码字体:
  - `6dp`
- 代码最小宽度:
  - `minWidth=52dp`

效果说明:

- `minWidth` 调大: 灰底更长
- `textSize` 调大: 防伪码更大
- `letterSpacing` 调大: 防伪码更分开
- 建议步进:
  - 宽度 `1dp`
  - 字号 `0.5dp`
  - 字距 `0.005`

## 4. 当前可直接手动调的内容

现在拍照预览页顶部有一个 `参数` 按钮，可以直接改这些文案:

- 地址
- 时间
- 日期
- 天气
- 备注块
- 底部备注
- 防伪码

说明:

- 时间和日期留空时，会自动跟随当前系统时间
- 防伪码留空时，会重新随机生成 14 位
- 点 `恢复默认` 会恢复为进入相机时的默认参数
- 顶部 `定位天气` 按钮会申请定位权限，并刷新真实地址与实时天气

相关文件:

- `android/app/src/main/res/layout/dialog_watermark_params.xml`
- `android/app/src/main/kotlin/com/example/photo_namer/NativeWatermarkCameraActivity.kt`

## 4.1 当前可直接拖动的调节面板

现在拍照预览页顶部还有一个 `调节` 按钮，会打开实时滑杆面板。

真实参数定义位置:

- `android/app/src/main/kotlin/com/example/photo_namer/NativeWatermarkCameraActivity.kt`
- 关键结构体: `WatermarkAdjustments`
- 真正生效位置: `applyWatermarkAdjustments()`

当前滑杆包括:

- 左边距
- 右边距
- 底边距
- 左侧整体缩放
- 左侧整体 X
- 左侧整体 Y
- 时间字大小
- 时间字 X
- 时间字 Y
- 右侧整体缩放
- 右侧整体 X
- 右侧整体 Y
- 防伪块 X
- 防伪块 Y
- 盾牌宽度
- 盾牌高度
- 验证文字大小

说明:

- 拖动时会立即作用到当前预览
- 右上角数字框可直接手输，支持 `0.1` 精度
- 关闭后保留当前调节
- `恢复默认` 会回到当前代码里的默认值
- 这些调节是直接作用在原生真实视图上的，所以拍出来也会沿用

单位说明:

- `dp`: 位置和位移
- `sp`: 字号和盾牌尺寸
- `x`: 整体缩放倍率

## 5. 如果你要做像素级抠位置

推荐顺序:

1. 先只调 `watermarkAnchor` 的 `paddingStart/paddingEnd/paddingBottom`
2. 再调左侧时间条的 `marginEnd / minWidth / textSize`
3. 再调右下角 `secureRow.translationX`
4. 最后才去碰 `GradientStrokeTextView.kt`

原因:

- 前三步只会改布局，不容易把文字本身效果改坏
- `GradientStrokeTextView.kt` 改的是绘制逻辑，影响更大

## 6. 如果你要继续追绝对 1:1

当前已经统一到了同一比例和同一导出分辨率，但还不是“严格读取原版运行时矩阵”的完全复刻。

如果后面你要继续往下抠，优先看:

- `NativeWatermarkCameraActivity.composeWatermarkedPhoto()`
- `NativeWatermarkCameraActivity.normalizeCapturedBitmap()`
- `PreviewView` 实际裁切区域和最终导出裁切区域是否完全同构
