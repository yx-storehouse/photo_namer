import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

const Duration _rikkaTransitionDuration = Duration(milliseconds: 520);

final Curve _rikkaTransitionCurve = _ComposeSpringCurve(
  duration: _rikkaTransitionDuration,
  spring: SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 150,
    ratio: 1,
  ),
);
final Curve _rikkaReverseTransitionCurve = _rikkaTransitionCurve.flipped;

class RikkaRoute<T> extends PageRoute<T> {
  RikkaRoute({
    required this.builder,
    super.settings,
    super.fullscreenDialog,
    this.maintainState = true,
  });

  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  Duration get transitionDuration => _rikkaTransitionDuration;

  @override
  Duration get reverseTransitionDuration => _rikkaTransitionDuration;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _buildSecondaryTransition(
      secondaryAnimation,
      _buildPrimaryTransition(animation, child),
    );
  }
}

Widget _buildPrimaryTransition(
  Animation<double> animation,
  Widget child,
) {
  final curvedAnimation = CurvedAnimation(
    parent: animation,
    curve: _rikkaTransitionCurve,
    reverseCurve: _rikkaReverseTransitionCurve,
  );

  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(curvedAnimation),
    child: child,
  );
}

Widget _buildSecondaryTransition(
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (secondaryAnimation.isDismissed) {
    return child;
  }

  final curvedAnimation = CurvedAnimation(
    parent: secondaryAnimation,
    curve: _rikkaTransitionCurve,
    reverseCurve: _rikkaReverseTransitionCurve,
  );

  return SlideTransition(
    position: Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.5, 0),
    ).animate(curvedAnimation),
    child: ColoredBox(
      color: Colors.white,
      child: ScaleTransition(
      scale: Tween<double>(
        begin: 1,
        end: 0.7,
      ).animate(curvedAnimation),
      child: FadeTransition(
        opacity: Tween<double>(
          begin: 1,
          end: 0,
        ).animate(curvedAnimation),
          child: child,
        ),
      ),
    ),
  );
}

Route<T> buildAppRoute<T>({
  required Widget page,
  RouteSettings? settings,
  bool fullscreenDialog = false,
  bool maintainState = true,
}) {
  return RikkaRoute<T>(
    builder: (_) => page,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    maintainState: maintainState,
  );
}

class _ComposeSpringCurve extends Curve {
  _ComposeSpringCurve({
    required Duration duration,
    required SpringDescription spring,
  }) : _durationInSeconds =
           duration.inMicroseconds / Duration.microsecondsPerSecond,
       _simulation = SpringSimulation(
         spring,
         0,
         1,
         0,
         snapToEnd: true,
       );

  final double _durationInSeconds;
  final SpringSimulation _simulation;

  @override
  double transformInternal(double t) {
    final value = _simulation.x(t * _durationInSeconds);
    return value.clamp(0.0, 1.0);
  }
}
