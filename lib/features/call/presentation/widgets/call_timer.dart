import 'package:flutter/material.dart';

class CallTimer extends StatelessWidget {
  final Duration elapsed;

  const CallTimer({super.key, required this.elapsed});

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(elapsed),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
