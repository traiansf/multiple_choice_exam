/// The on-screen framing guide drawn over the camera preview: the area
/// outside the A4 page frame is dimmed, the frame has a light border, and
/// four bracket squares show where the printed corner registration marks
/// must sit. Geometry comes from framing.dart so it always matches what the
/// OMR crop expects.
library;

import 'package:flutter/material.dart';

import 'framing.dart';

class SheetGuideOverlay extends StatelessWidget {
  const SheetGuideOverlay({super.key, this.hint});

  /// Optional hint line shown under the guide (e.g. the last framing error).
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: SheetGuidePainter()),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              hint ??
                  'Hold the phone flat above the sheet. Fill the frame and'
                      ' put each black corner square in its bracket.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SheetGuidePainter extends CustomPainter {
  const SheetGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final guide = pageGuideRect(size);

    // Dim everything outside the page frame.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(guide)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Page frame.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(guide, border);

    // Corner-mark brackets.
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.greenAccent;
    for (final target in cornerMarkTargets(guide)) {
      canvas.drawRect(target, bracket);
    }
  }

  // The painter has no fields: everything derives from the paint() size,
  // and Flutter repaints on size changes regardless. The hint text lives in
  // a sibling widget, not in this painter.
  @override
  bool shouldRepaint(covariant SheetGuidePainter oldDelegate) => false;
}
