import 'dart:async';

import 'package:flutter/material.dart';

import 'package:photo_namer/app_route_observer.dart';

class FabMenuAction {
  final String label;
  final IconData icon;
  final FutureOr<void> Function() onTap;
  final bool danger;

  const FabMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });
}

class ExpandableFab extends StatefulWidget {
  final List<FabMenuAction> actions;
  final String? heroTag;
  final FabMenuAction? primaryOverrideAction;

  const ExpandableFab({
    super.key,
    required this.actions,
    this.heroTag,
    this.primaryOverrideAction,
  });

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin, RouteAware {
  late final AnimationController _controller;
  late final Animation<double> _expand;
  ModalRoute<dynamic>? _route;

  @override
  void didUpdateWidget(covariant ExpandableFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.primaryOverrideAction != null && _controller.value > 0) {
      _controller.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expand = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    if (_controller.value > 0) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _controller.dispose();
    super.dispose();
  }

  bool get _open => _controller.value > 0.5;

  Future<void> _toggle() async {
    if (widget.primaryOverrideAction != null) {
      await widget.primaryOverrideAction!.onTap();
      return;
    }
    if (_controller.status == AnimationStatus.forward ||
        _controller.status == AnimationStatus.reverse)
      return;
    if (_open) {
      await _controller.reverse();
    } else {
      await _controller.forward();
    }
  }

  Future<void> _onActionTap(FabMenuAction action) async {
    if (_open) {
      await _controller.reverse();
    }
    await action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final h = 86.0 + widget.actions.length * 64.0;
    final colorScheme = Theme.of(context).colorScheme;

    return TapRegion(
      onTapOutside: (_) {
        if (_controller.value > 0) {
          _controller.reverse();
        }
      },
      child: SizedBox(
        width: 238,
        height: h,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.bottomRight,
              children: [
                ...List.generate(widget.actions.length, (i) {
                  final action = widget.actions[i];
                  final offsetY = (i + 1) * 64.0;
                  final btnBg = action.danger
                      ? const Color(0xFFD92D20)
                      : colorScheme.primary;
                  final btnFg = action.danger
                      ? Colors.white
                      : colorScheme.onPrimary;

                  return Positioned(
                    right: 0,
                    bottom: 12 + offsetY * _expand.value,
                    child: IgnorePointer(
                      ignoring: _expand.value < 0.95,
                      child: Opacity(
                        opacity: _expand.value,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: action.danger
                                      ? const Color(0xFFFDA29B)
                                      : Colors.black12,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Text(
                                action.label,
                                style: TextStyle(
                                  color: action.danger
                                      ? const Color(0xFFB42318)
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: FloatingActionButton(
                                heroTag: null,
                                mini: true,
                                backgroundColor: btnBg,
                                foregroundColor: btnFg,
                                elevation: 6,
                                highlightElevation: 10,
                                onPressed: () => _onActionTap(action),
                                child: Icon(action.icon, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                SizedBox(
                  width: 58,
                  height: 58,
                  child: FloatingActionButton(
                    heroTag: widget.heroTag,
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 8,
                    highlightElevation: 12,
                    onPressed: _toggle,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: widget.primaryOverrideAction != null
                          ? Icon(
                              widget.primaryOverrideAction!.icon,
                              key: const ValueKey('primary_override'),
                              size: 26,
                            )
                          : Transform.rotate(
                              key: const ValueKey('primary_plus'),
                              angle: _expand.value * 0.785398,
                              child: const Icon(Icons.add, size: 28),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

