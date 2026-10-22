import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// iOS motion, in one place. Since iOS 17 the system animates with springs described by a perceptual
/// duration and a bounce (SwiftUI `Spring(duration:bounce:)`); with mass 1 that is
///   stiffness = (2π / duration)²,  damping = 4π · (1 − bounce) / duration.
///
///  - [smooth]  `.smooth`  0.5 s, bounce 0     — page/tab changes, sheets, things settling into place
///  - [snappy]  `.snappy`  0.5 s, bounce 0.15  — taps, toggles, selection capsules, swipe rows
///  - [bouncy]  `.bouncy`  0.5 s, bounce 0.3   — small playful feedback (undo toast)
///
/// Gesture-driven motion (sheet drag, swipe-to-delete) runs the spring as a physics simulation and hands
/// it the finger's release velocity, like UIKit. Implicit widgets (AnimatedContainer …) take the same
/// springs as a [SpringCurve] plus its [SpringCurve.duration].
class IOSMotion {
  IOSMotion._();

  static SpringDescription spring(double duration, double bounce) => SpringDescription(
        mass: 1,
        stiffness: (2 * 3.141592653589793 / duration) * (2 * 3.141592653589793 / duration),
        damping: 4 * 3.141592653589793 * (1 - bounce) / duration,
      );

  static final SpringDescription smooth = spring(0.5, 0);
  static final SpringDescription snappy = spring(0.5, 0.15);
  static final SpringDescription bouncy = spring(0.5, 0.3);

  static final SpringCurve smoothCurve = SpringCurve(smooth);
  static final SpringCurve snappyCurve = SpringCurve(snappy);
  static final SpringCurve bouncyCurve = SpringCurve(bouncy);

  /// Runs [controller] to [target] on [spring], starting from the current value with [velocity]
  /// (units per second, e.g. pixels/s from a drag end).
  static TickerFuture animate(AnimationController controller, double target,
      {SpringDescription? spring, double velocity = 0}) {
    // Tolerance scales with the distance travelled, so it suits pixels (sheets, rows) as well as
    // 0…1 progress and item indexes.
    final span = (target - controller.value).abs();
    final eps = span == 0 ? 0.001 : span * 0.002;
    final sim = SpringSimulation(spring ?? smooth, controller.value, target, velocity,
        tolerance: Tolerance(distance: eps, velocity: eps * 10));
    return controller.animateWith(sim);
  }
}

/// A spring from 0 to 1 at rest, packaged as a [Curve] for implicit animations. [duration] is how long
/// the spring takes to settle (within 0.5 % of the target), so use the pair together:
///   AnimatedContainer(duration: IOSMotion.snappyCurve.duration, curve: IOSMotion.snappyCurve, …)
class SpringCurve extends Curve {
  SpringCurve(this.spring)
      : duration = _settle(spring),
        _sim = SpringSimulation(spring, 0, 1, 0);

  final SpringDescription spring;
  final Duration duration;
  final SpringSimulation _sim;

  double get _seconds => duration.inMicroseconds / Duration.microsecondsPerSecond;

  static Duration _settle(SpringDescription spring) {
    final sim = SpringSimulation(spring, 0, 1, 0);
    var last = 0.0;
    for (var t = 0.0; t < 3; t += 0.004) {
      if ((sim.x(t) - 1).abs() > 0.005) last = t;
    }
    return Duration(microseconds: ((last + 0.004) * 1e6).round());
  }

  @override
  double transformInternal(double t) => _sim.x(t * _seconds);
}
