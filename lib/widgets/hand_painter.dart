import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/hand.dart';

/// The skeleton over the camera frame.
///
/// The Python script drew the angles onto the image with `cv2.putText`. Here
/// they have a row of tiles of their own under the preview, so painting them
/// again on top of the frame only collided with the status chips.
class HandPainter extends CustomPainter {
  HandPainter({
    required this.hand,
    required this.mirror,
    required this.accent,
  }) : super(repaint: hand);

  final ValueListenable<Hand?> hand;
  final bool mirror;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final h = hand.value;
    if (h != null) {
      Offset at(int i) => Offset(
            (mirror ? 1 - h.x(i) : h.x(i)) * size.width,
            h.y(i) * size.height,
          );

      final bone = Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final [a, b] in handConnections) {
        canvas.drawLine(at(a), at(b), bone);
      }
      final joint = Paint()..color = Colors.white;
      for (var i = 0; i < 21; i++) {
        canvas.drawCircle(at(i), 3.5, joint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HandPainter old) =>
      old.mirror != mirror || old.accent != accent;
}
