import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../base/step_clock.dart';

/// A codicon turning as `codicon-modifier-spin` turns one: once in 1.5s, in
/// 30 steps; still where motion is turned down.
class IdeSpinning extends StatefulWidget {
  const IdeSpinning(this.child, {super.key});

  final Widget child;

  /// The steps of a turn.
  static const steps = 30;

  /// One step: drawn only then, not at every vsync.
  static const step = Duration(milliseconds: 1500 ~/ steps);

  @override
  State<IdeSpinning> createState() => _IdeSpinningState();
}

class _IdeSpinningState extends State<IdeSpinning> {
  final StepClock _clock = StepClock(IdeSpinning.step);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = _clock.keepTo(context);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _clock,
    builder: (context, child) => Transform.rotate(
      angle: _still
          ? 0
          : _clock.ticks % IdeSpinning.steps / IdeSpinning.steps * 2 * math.pi,
      child: child,
    ),
    child: widget.child,
  );
}
