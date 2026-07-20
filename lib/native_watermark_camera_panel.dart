import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_watermark_camera_preview.dart';

typedef NativeWatermarkStateUpdater =
    Future<NativeWatermarkPreviewState?> Function(Map<String, dynamic> changes);
typedef NativeWatermarkStateRefresher =
    Future<NativeWatermarkPreviewState?> Function();

class NativeWatermarkControlPanel extends StatefulWidget {
  const NativeWatermarkControlPanel({
    super.key,
    required this.state,
    required this.isRefreshingAddress,
    required this.isRefreshingWeather,
    required this.onUpdateState,
    required this.onRefreshAddress,
    required this.onRefreshWeather,
  });

  final NativeWatermarkPreviewState? state;
  final bool isRefreshingAddress;
  final bool isRefreshingWeather;
  final NativeWatermarkStateUpdater onUpdateState;
  final NativeWatermarkStateRefresher onRefreshAddress;
  final NativeWatermarkStateRefresher onRefreshWeather;

  @override
  State<NativeWatermarkControlPanel> createState() =>
      _NativeWatermarkControlPanelState();
}

class _NativeWatermarkControlPanelState
    extends State<NativeWatermarkControlPanel> {
  Future<void> _openPanel() async {
    final state = widget.state;
    if (state == null) {
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭水印面板',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final media = MediaQuery.of(dialogContext);
        final width = math.min(388.0, media.size.width - 16);
        final topOffset = media.padding.top + kToolbarHeight + 8;
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: topOffset,
                    right: 8,
                    bottom: math.max(media.viewInsets.bottom, 12),
                  ),
                  child: SizedBox(
                    width: width,
                    child: _NativeWatermarkPanelDialog(
                      initialState: state,
                      isRefreshingAddress: widget.isRefreshingAddress,
                      isRefreshingWeather: widget.isRefreshingWeather,
                      onUpdateState: widget.onUpdateState,
                      onRefreshAddress: widget.onRefreshAddress,
                      onRefreshWeather: widget.onRefreshWeather,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, -0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stateReady = widget.state != null;
    final primary = Theme.of(context).colorScheme.primary;

    return IgnorePointer(
      ignoring: !stateReady,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: stateReady ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _openPanel,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white.withValues(alpha: 0.14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '118',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF4E617D),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2233),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Color(0xFF5D6B85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD5DDEF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 16, color: const Color(0xFF2C57D8)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldBlock extends StatelessWidget {
  const _FieldBlock({
    required this.title,
    required this.hint,
    required this.child,
  });

  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE4F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2233),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(fontSize: 11, color: Color(0xFF66758E)),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _AdjustmentSectionCard extends StatelessWidget {
  const _AdjustmentSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE4F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Color(0xFF66758E)),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _AdjustmentTile extends StatefulWidget {
  const _AdjustmentTile({
    required this.spec,
    required this.value,
    required this.expanded,
    required this.inputDecorationBuilder,
    required this.onToggle,
    required this.onPreviewChanged,
    required this.onCommitted,
  });

  final _AdjustmentSpec spec;
  final double value;
  final bool expanded;
  final InputDecoration Function(String hint) inputDecorationBuilder;
  final VoidCallback onToggle;
  final ValueChanged<double> onPreviewChanged;
  final ValueChanged<double> onCommitted;

  @override
  State<_AdjustmentTile> createState() => _AdjustmentTileState();
}

class _AdjustmentTileState extends State<_AdjustmentTile> {
  late double _value;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _value = widget.spec.snap(widget.value);
    _controller = TextEditingController(text: _formatValue(_value));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _AdjustmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextValue = widget.spec.snap(widget.value);
    if ((nextValue - _value).abs() > 0.0001) {
      _value = nextValue;
      if (!_focusNode.hasFocus) {
        _controller.text = _formatValue(nextValue);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: widget.expanded ? Colors.white : const Color(0xFFF4F7FD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.expanded
              ? const Color(0xFF4C7DFF).withValues(alpha: 0.35)
              : const Color(0xFFDCE4F5),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A2233),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_formatValue(_value)} ${spec.unit}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2C57D8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF597089),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            child: !widget.expanded
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(spec.key),
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spec.helper,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF66758E),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                          ),
                          child: Slider(
                            value: _value,
                            min: spec.min,
                            max: spec.max,
                            onChanged: (next) {
                              final snapped = spec.snap(next);
                              if ((snapped - _value).abs() < 0.0001) {
                                return;
                              }
                              setState(() {
                                _value = snapped;
                                if (!_focusNode.hasFocus) {
                                  _controller.text = _formatValue(snapped);
                                }
                              });
                              widget.onPreviewChanged(snapped);
                            },
                            onChangeEnd: (next) {
                              final snapped = spec.snap(next);
                              setState(() {
                                _value = snapped;
                                if (!_focusNode.hasFocus) {
                                  _controller.text = _formatValue(snapped);
                                }
                              });
                              widget.onCommitted(snapped);
                            },
                          ),
                        ),
                        Row(
                          children: [
                            _StepButton(
                              icon: Icons.remove_rounded,
                              onTap: () =>
                                  _commit(spec.snap(_value - spec.step)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                textAlign: TextAlign.center,
                                decoration: widget.inputDecorationBuilder(
                                  spec.unit,
                                ),
                                onTap: () {
                                  _controller.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: _controller.text.length,
                                  );
                                },
                                onSubmitted: (raw) {
                                  final parsed = double.tryParse(raw);
                                  if (parsed == null) {
                                    _controller.text = _formatValue(_value);
                                    return;
                                  }
                                  _commit(spec.snap(parsed));
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StepButton(
                              icon: Icons.add_rounded,
                              onTap: () =>
                                  _commit(spec.snap(_value + spec.step)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _commit(double nextValue) {
    setState(() {
      _value = nextValue;
      _controller.text = _formatValue(nextValue);
    });
    widget.onCommitted(nextValue);
  }

  String _formatValue(double value) => value.toStringAsFixed(1);
}

class _AdjustmentSection {
  const _AdjustmentSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<_AdjustmentSpec> items;
}

class _AdjustmentSpec {
  const _AdjustmentSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.helper,
    required this.min,
    required this.max,
    required this.step,
  });

  final String key;
  final String label;
  final String unit;
  final String helper;
  final double min;
  final double max;
  final double step;

  double clamp(double value) => value.clamp(min, max).toDouble();

  double snap(double value) {
    final clamped = clamp(value);
    final ticks = ((clamped - min) / step).round();
    return clamp(min + ticks * step);
  }
}

const List<_AdjustmentSection> _adjustmentSections = <_AdjustmentSection>[
  _AdjustmentSection(
    title: '整体贴边',
    subtitle: '控制整块水印距离左右和底部的锚点。',
    items: <_AdjustmentSpec>[
      _AdjustmentSpec(
        key: 'anchorStartDp',
        label: '左边距',
        unit: 'dp',
        helper: '控制整个水印锚点距离左边的偏移。',
        min: 0,
        max: 48,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'anchorEndDp',
        label: '右边距',
        unit: 'dp',
        helper: '控制整个水印锚点距离右边的偏移。',
        min: 0,
        max: 48,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'anchorBottomDp',
        label: '底边距',
        unit: 'dp',
        helper: '控制整块水印距离底边的高度。',
        min: 0,
        max: 36,
        step: 0.1,
      ),
    ],
  ),
  _AdjustmentSection(
    title: '左侧主块',
    subtitle: '控制时间、地址、日期、天气这一组。',
    items: <_AdjustmentSpec>[
      _AdjustmentSpec(
        key: 'locationColumnWidthDp',
        label: '地址行宽',
        unit: 'dp',
        helper: '影响地址换行宽度和一行能放多少字。',
        min: 180,
        max: 360,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'leftScale',
        label: '左侧整体缩放',
        unit: 'x',
        helper: '缩放左侧整组，不改相对布局。',
        min: 0.7,
        max: 1.3,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'leftXdp',
        label: '左侧整体 X',
        unit: 'dp',
        helper: '横向微调左侧主块。',
        min: -40,
        max: 40,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'leftYdp',
        label: '左侧整体 Y',
        unit: 'dp',
        helper: '纵向微调左侧主块。',
        min: -40,
        max: 40,
        step: 0.1,
      ),
    ],
  ),
  _AdjustmentSection(
    title: '时间字微调',
    subtitle: '控制时间数字的大小、描边发光和位置。',
    items: <_AdjustmentSpec>[
      _AdjustmentSpec(
        key: 'timeTextSizeDp',
        label: '时间字大小',
        unit: 'dp',
        helper: '控制时间数字本体大小。',
        min: 12,
        max: 40,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'timeGlowRadiusDp',
        label: '时间发光',
        unit: 'dp',
        helper: '控制时间字白光描边强度。',
        min: 0,
        max: 4,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'timeXdp',
        label: '时间字 X',
        unit: 'dp',
        helper: '横向微调时间字位置。',
        min: -20,
        max: 20,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'timeYdp',
        label: '时间字 Y',
        unit: 'dp',
        helper: '纵向微调时间字位置。',
        min: -20,
        max: 20,
        step: 0.1,
      ),
    ],
  ),
  _AdjustmentSection(
    title: '右侧主块',
    subtitle: '控制右下角防伪块的整体位置和缩放。',
    items: <_AdjustmentSpec>[
      _AdjustmentSpec(
        key: 'rightScale',
        label: '右侧整体缩放',
        unit: 'x',
        helper: '缩放右侧整组，不改内部相对关系。',
        min: 0.7,
        max: 1.3,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'rightXdp',
        label: '右侧整体 X',
        unit: 'dp',
        helper: '横向微调右侧整组。',
        min: -40,
        max: 40,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'rightYdp',
        label: '右侧整体 Y',
        unit: 'dp',
        helper: '纵向微调右侧整组。',
        min: -40,
        max: 40,
        step: 0.1,
      ),
    ],
  ),
  _AdjustmentSection(
    title: '防伪块',
    subtitle: '控制“防伪”图片、灰底和防伪码之间的关系。',
    items: <_AdjustmentSpec>[
      _AdjustmentSpec(
        key: 'secureXdp',
        label: '防伪块 X',
        unit: 'dp',
        helper: '横向微调防伪块。',
        min: -20,
        max: 20,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureYdp',
        label: '防伪块 Y',
        unit: 'dp',
        helper: '纵向微调防伪块。',
        min: -20,
        max: 20,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureCodeTextSizeDp',
        label: '防伪码大小',
        unit: 'dp',
        helper: '控制防伪码文本大小。',
        min: 2,
        max: 12,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureTitleScale',
        label: '防伪图缩放',
        unit: 'x',
        helper: '控制“防伪”图本体大小。',
        min: 0.4,
        max: 1.6,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureShadowScaleX',
        label: '灰底宽缩放',
        unit: 'x',
        helper: '控制灰底横向缩放。',
        min: 0.2,
        max: 2,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureShadowScaleY',
        label: '灰底高缩放',
        unit: 'x',
        helper: '控制灰底纵向缩放。',
        min: 0.2,
        max: 2,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureShadowXdp',
        label: '灰底 X',
        unit: 'dp',
        helper: '横向微调灰底相对防伪码的位置。',
        min: -20,
        max: 20,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureShadowYdp',
        label: '灰底 Y',
        unit: 'dp',
        helper: '纵向微调灰底相对防伪码的位置。',
        min: -20,
        max: 20,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'secureCodeSpacingValue',
        label: '防伪码间距',
        unit: '值',
        helper: '控制防伪码字符间距，0 最贴近原版。',
        min: -0.2,
        max: 1.2,
        step: 0.1,
      ),
    ],
  ),
  _AdjustmentSection(
    title: '左下验证行',
    subtitle: '控制备注块高度、盾牌图标和验证文字大小。',
    items: <_AdjustmentSpec>[
      _AdjustmentSpec(
        key: 'roomCodeVerticalPaddingDp',
        label: '备注块高度',
        unit: 'dp',
        helper: '控制左下备注区域上下留白。',
        min: 0,
        max: 24,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'roomCodeTextSizeSp',
        label: '备注字体大小',
        unit: 'sp',
        helper: '控制左下备注文本大小。',
        min: 8,
        max: 24,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'imprintIconWidthSp',
        label: '盾牌宽度',
        unit: 'sp',
        helper: '控制盾牌图标宽度。',
        min: 6,
        max: 24,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'imprintIconHeightSp',
        label: '盾牌高度',
        unit: 'sp',
        helper: '控制盾牌图标高度。',
        min: 6,
        max: 24,
        step: 0.1,
      ),
      _AdjustmentSpec(
        key: 'imprintTextSizeSp',
        label: '验证文字大小',
        unit: 'sp',
        helper: '控制盾牌后面文案的字体大小。',
        min: 8,
        max: 24,
        step: 0.1,
      ),
    ],
  ),
];

class _NativeWatermarkPanelDialog extends StatefulWidget {
  const _NativeWatermarkPanelDialog({
    required this.initialState,
    required this.isRefreshingAddress,
    required this.isRefreshingWeather,
    required this.onUpdateState,
    required this.onRefreshAddress,
    required this.onRefreshWeather,
  });

  final NativeWatermarkPreviewState initialState;
  final bool isRefreshingAddress;
  final bool isRefreshingWeather;
  final NativeWatermarkStateUpdater onUpdateState;
  final NativeWatermarkStateRefresher onRefreshAddress;
  final NativeWatermarkStateRefresher onRefreshWeather;

  @override
  State<_NativeWatermarkPanelDialog> createState() =>
      _NativeWatermarkPanelDialogState();
}

class _NativeWatermarkPanelDialogState
    extends State<_NativeWatermarkPanelDialog> {
  late Map<String, double> _adjustments;

  late final TextEditingController _locationController;
  late final TextEditingController _weatherController;
  late final TextEditingController _roomCodeController;
  late final TextEditingController _imprintController;
  late final TextEditingController _timeController;
  late final TextEditingController _dateController;
  late final TextEditingController _antiFakeController;

  Timer? _adjustmentTimer;
  bool _isSavingParams = false;
  bool _isResettingParams = false;
  bool _isResettingAdjustments = false;
  bool _isRefreshingAddress = false;
  bool _isRefreshingWeather = false;
  bool _isSyncingAdjustments = false;
  bool _pendingAdjustmentSync = false;
  bool _pendingAdjustmentPersist = false;
  bool _antiFakeCodeLocked = false;
  int _tabIndex = 0;
  String? _expandedAdjustmentKey;

  @override
  void initState() {
    super.initState();
    _locationController = TextEditingController();
    _weatherController = TextEditingController();
    _roomCodeController = TextEditingController();
    _imprintController = TextEditingController();
    _timeController = TextEditingController();
    _dateController = TextEditingController();
    _antiFakeController = TextEditingController();
    _isRefreshingAddress = widget.isRefreshingAddress;
    _isRefreshingWeather = widget.isRefreshingWeather;
    _applyState(widget.initialState);
  }

  @override
  void dispose() {
    _adjustmentTimer?.cancel();
    _locationController.dispose();
    _weatherController.dispose();
    _roomCodeController.dispose();
    _imprintController.dispose();
    _timeController.dispose();
    _dateController.dispose();
    _antiFakeController.dispose();
    super.dispose();
  }

  void _applyState(NativeWatermarkPreviewState state) {
    _adjustments = Map<String, double>.from(state.adjustments);
    _antiFakeCodeLocked = state.antiFakeCodeLocked;
    _locationController.text = state.location;
    _weatherController.text = state.weatherText;
    _roomCodeController.text = state.roomCode;
    _imprintController.text = state.imprintText;
    _timeController.text = state.timeOverrideText ?? '';
    _dateController.text = state.dateOverrideText ?? '';
    _antiFakeController.text = state.antiFakeCode;
  }

  Future<void> _runStateAction(
    Future<NativeWatermarkPreviewState?> Function() action,
  ) async {
    final nextState = await action();
    if (!mounted || nextState == null) {
      return;
    }
    setState(() {
      _applyState(nextState);
    });
  }

  Map<String, dynamic> _collectParamChanges() {
    return <String, dynamic>{
      'location': _locationController.text.trim(),
      'weatherText': _weatherController.text.trim(),
      'roomCode': _roomCodeController.text.trim(),
      'imprintText': _imprintController.text.trim(),
      'timeOverrideText': _timeController.text.trim(),
      'dateOverrideText': _dateController.text.trim(),
      'antiFakeCode': _antiFakeController.text.trim().toUpperCase(),
      'antiFakeCodeLocked': _antiFakeCodeLocked,
    };
  }

  Future<void> _applyParams() async {
    if (_isSavingParams) {
      return;
    }
    setState(() {
      _isSavingParams = true;
    });
    try {
      await _runStateAction(() => widget.onUpdateState(_collectParamChanges()));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingParams = false;
        });
      }
    }
  }

  Future<void> _resetParams() async {
    if (_isResettingParams) {
      return;
    }
    setState(() {
      _isResettingParams = true;
    });
    try {
      await _runStateAction(
        () => widget.onUpdateState(<String, dynamic>{
          'resetParamsToDefaults': true,
        }),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResettingParams = false;
        });
      }
    }
  }

  Future<void> _resetAdjustments() async {
    if (_isResettingAdjustments) {
      return;
    }
    _adjustmentTimer?.cancel();
    _adjustmentTimer = null;
    _pendingAdjustmentSync = false;
    _pendingAdjustmentPersist = false;
    setState(() {
      _isResettingAdjustments = true;
    });
    try {
      await _runStateAction(
        () => widget.onUpdateState(<String, dynamic>{
          'resetAdjustmentsToDefaults': true,
        }),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResettingAdjustments = false;
        });
      }
    }
  }

  Future<void> _refreshAddress() async {
    if (_isRefreshingAddress) {
      return;
    }
    setState(() {
      _isRefreshingAddress = true;
    });
    try {
      await _runStateAction(widget.onRefreshAddress);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingAddress = false;
        });
      }
    }
  }

  Future<void> _refreshWeather() async {
    if (_isRefreshingWeather) {
      return;
    }
    setState(() {
      _isRefreshingWeather = true;
    });
    try {
      await _runStateAction(widget.onRefreshWeather);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingWeather = false;
        });
      }
    }
  }

  void _scheduleAdjustmentSync({bool persist = false}) {
    _pendingAdjustmentPersist = _pendingAdjustmentPersist || persist;
    _adjustmentTimer?.cancel();
    _adjustmentTimer = Timer(const Duration(milliseconds: 120), () {
      _adjustmentTimer = null;
      unawaited(_flushAdjustmentSync());
    });
  }

  Future<void> _flushAdjustmentSync() async {
    if (_isSyncingAdjustments) {
      _pendingAdjustmentSync = true;
      return;
    }
    _isSyncingAdjustments = true;
    try {
      do {
        final shouldPersist = _pendingAdjustmentPersist;
        _pendingAdjustmentPersist = false;
        _pendingAdjustmentSync = false;
        final snapshot = Map<String, double>.from(_adjustments);
        await widget.onUpdateState(<String, dynamic>{
          'adjustments': snapshot,
          'persistWatermarkState': shouldPersist,
        });
        if (!mounted) {
          return;
        }
      } while (_pendingAdjustmentSync);
    } finally {
      _isSyncingAdjustments = false;
    }
  }

  void _previewAdjustment(_AdjustmentSpec spec, double value) {
    _adjustments[spec.key] = spec.snap(value);
    _scheduleAdjustmentSync();
  }

  void _commitAdjustment(_AdjustmentSpec spec, double value) {
    _adjustments[spec.key] = spec.snap(value);
    _pendingAdjustmentPersist = true;
    _adjustmentTimer?.cancel();
    _adjustmentTimer = null;
    unawaited(_flushAdjustmentSync());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = math.min(
      MediaQuery.of(context).size.height * 0.82,
      760.0,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          color: const Color(0xFFF7FAFF),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(scheme),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _tabIndex == 0
                        ? _buildParamsPage(scheme)
                        : _buildAdjustmentsPage(scheme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary.withValues(alpha: 0.12), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_filter_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '118 水印控制台',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '参数和微调都会直接同步到原生预览',
                      style: TextStyle(fontSize: 11, color: Color(0xFF5D6B85)),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                tooltip: '关闭',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: '参数',
                    selected: _tabIndex == 0,
                    onTap: () => setState(() => _tabIndex = 0),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _TabButton(
                    label: '微调',
                    selected: _tabIndex == 1,
                    onTap: () => setState(() => _tabIndex = 1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamsPage(ColorScheme scheme) {
    return SingleChildScrollView(
      key: const ValueKey('params-page'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            color: scheme.primary,
            icon: Icons.gps_fixed_rounded,
            title: '地址和天气已拆成两个独立入口',
            message: '点哪个就只刷新哪个，手动填的文本不会被另一个按钮顺手覆盖。',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionChipButton(
                icon: Icons.place_rounded,
                label: _isRefreshingAddress ? '获取中...' : '获取地址',
                loading: _isRefreshingAddress,
                onTap: _isRefreshingAddress ? null : _refreshAddress,
              ),
              _ActionChipButton(
                icon: Icons.cloud_sync_rounded,
                label: _isRefreshingWeather ? '获取中...' : '获取天气',
                loading: _isRefreshingWeather,
                onTap: _isRefreshingWeather ? null : _refreshWeather,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FieldBlock(
            title: '地址',
            hint: '为空时可手动不显示',
            child: TextField(
              controller: _locationController,
              minLines: 1,
              maxLines: 3,
              decoration: _inputDecoration('手动输入地址'),
            ),
          ),
          const SizedBox(height: 12),
          _FieldBlock(
            title: '天气',
            hint: '例如 多云 26°C',
            child: TextField(
              controller: _weatherController,
              decoration: _inputDecoration('手动输入天气'),
            ),
          ),
          const SizedBox(height: 12),
          _FieldBlock(
            title: '备注文本',
            hint: '左下角房间完整名',
            child: TextField(
              controller: _roomCodeController,
              minLines: 1,
              maxLines: 2,
              decoration: _inputDecoration('例如 1号楼-A座-101-空调机房'),
            ),
          ),
          const SizedBox(height: 12),
          _FieldBlock(
            title: '验证文案',
            hint: '盾牌右侧的文案',
            child: TextField(
              controller: _imprintController,
              minLines: 1,
              maxLines: 2,
              decoration: _inputDecoration('例如 时间地点真实'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FieldBlock(
                  title: '时间覆盖',
                  hint: '留空则自动时间',
                  child: TextField(
                    controller: _timeController,
                    decoration: _inputDecoration('例如 08:33'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FieldBlock(
                  title: '日期覆盖',
                  hint: '留空则自动日期',
                  child: TextField(
                    controller: _dateController,
                    decoration: _inputDecoration('例如 2026.03.14'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FieldBlock(
            title: '防伪码',
            hint: '为空时会生成随机测试码',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _antiFakeController,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(14),
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9]'),
                          ),
                        ],
                        textCapitalization: TextCapitalization.characters,
                        decoration: _inputDecoration('例如 9D34A1C7F6B2'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _antiFakeCodeLocked,
                      onChanged: (value) {
                        setState(() {
                          _antiFakeCodeLocked = value;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: Color(0xFF5D6B85),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _antiFakeCodeLocked ? '防伪码固定' : '防伪码可自动生成',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5D6B85),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        _antiFakeController.clear();
                        setState(() {
                          _antiFakeCodeLocked = false;
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('清空重生成'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isResettingParams ? null : _resetParams,
                  icon: _isResettingParams
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restart_alt_rounded),
                  label: const Text('恢复默认文案'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSavingParams ? null : _applyParams,
                  icon: _isSavingParams
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('应用到预览'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentsPage(ColorScheme scheme) {
    return SingleChildScrollView(
      key: const ValueKey('adjustments-page'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            color: scheme.primary,
            icon: Icons.tune_rounded,
            title: '只展开当前这一项，方便你盯着效果看',
            message: '拖动滑块会即时同步，数值框支持直接输入一位小数。',
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isResettingAdjustments ? null : _resetAdjustments,
              icon: _isResettingAdjustments
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded),
              label: const Text('恢复微调默认'),
            ),
          ),
          const SizedBox(height: 12),
          for (final section in _adjustmentSections) ...[
            _AdjustmentSectionCard(
              title: section.title,
              subtitle: section.subtitle,
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < section.items.length;
                    index++
                  ) ...[
                    _buildAdjustmentTile(section.items[index]),
                    if (index != section.items.length - 1)
                      const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildAdjustmentTile(_AdjustmentSpec spec) {
    final value = _adjustments[spec.key] ?? 0;
    final expanded = _expandedAdjustmentKey == spec.key;
    return RepaintBoundary(
      child: _AdjustmentTile(
        spec: spec,
        value: value,
        expanded: expanded,
        inputDecorationBuilder: _inputDecoration,
        onToggle: () {
          setState(() {
            _expandedAdjustmentKey = expanded ? null : spec.key;
          });
        },
        onPreviewChanged: (next) => _previewAdjustment(spec, next),
        onCommitted: (next) => _commitAdjustment(spec, next),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6DFF0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6DFF0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF4C7DFF), width: 1.4),
      ),
    );
  }
}
