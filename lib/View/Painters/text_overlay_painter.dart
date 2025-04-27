import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Αυτή η κλάση αναλαμβάνει να ζωγραφίσει το πλαίσιο πάνω στην προεπισκόπηση της κάμερας
class TextOverlayPainter extends CustomPainter {
  final Rect? targetBoundingBox;
  final Size imageSize;
  final Size previewSize;
  final double scale;
  final bool isTargetFound; // Σωστός στόχος βρέθηκε
  final bool isWrongTargetFound; // Λάθος στόχος βρέθηκε
  final ui.Image? correctIcon; // Το εικονίδιο για σωστό στόχο
  final ui.Image? wrongIcon; // Το εικονίδιο για λάθος στόχο

  // Σταθερές για το μέγεθος του εικονιδίου και το offset
  static const double iconSize = 80.0; // Μέγεθος εικονιδίου σε logical pixels
  static const double iconOffsetY =
      -10.0; // Πόσο πάνω από το πλαίσιο θα είναι το εικονίδιο

  TextOverlayPainter({
    required this.targetBoundingBox,
    required this.imageSize,
    required this.previewSize,
    required this.scale,
    required this.isTargetFound,
    required this.isWrongTargetFound,
    required this.correctIcon,
    required this.wrongIcon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Αν δεν έχω όλες τις πληροφορίες ή δεν υπάρχει πλαίσιο για ζωγραφική, δεν κάνω τίποτα
    if (imageSize.isEmpty ||
        previewSize.isEmpty ||
        size.isEmpty ||
        targetBoundingBox == null) {
      return;
    }

    final double scaleX = scale;
    final double scaleY = scale;

    // Υπολογίζω το οριζόντιο και κάθετο offset για να κεντράρω το πλαίσιο, αν χρειάζεται
    // Στην τρέχουσα υλοποίηση, το Stack κεντράρει, οπότε είναι 0.
    final double offsetX = (size.width - previewSize.width * scaleX) / 2;
    final double offsetY = (size.height - previewSize.height * scaleY) / 2;

    // Καθορίζω το χρώμα του πλαισίου
    final Color boxColor =
        isTargetFound
            ? Colors
                .greenAccent // Πράσινο για σωστό στόχο
            : isWrongTargetFound
            ? Colors
                .redAccent // Κόκκινο για λάθος στόχο
            : Colors
                .transparent; // Διάφανο αν δεν βλέπω τίποτα (αν και το targetBoundingBox δεν θα 'ναι null εδώ)

    // Δεν ζωγραφίζω πλαίσιο αν δεν βλέπω ούτε σωστό ούτε λάθος στόχο
    if (boxColor != Colors.transparent) {
      final Paint boxPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                4.0 // Λίγο πιο παχύ
            ..color = boxColor;

      final Rect scaledRect = Rect.fromLTRB(
        targetBoundingBox!.left * scaleX + offsetX,
        targetBoundingBox!.top * scaleY + offsetY,
        targetBoundingBox!.right * scaleX + offsetX,
        targetBoundingBox!.bottom * scaleY + offsetY,
      );
      canvas.drawRect(scaledRect, boxPaint);

      final Paint circlePaint =
          Paint()
            ..color = Colors.blue
            ..style = PaintingStyle.fill; // ή .stroke για περίγραμμα
      final Offset center = scaledRect.center; // Πάρε το κέντρο του ορθογωνίου
      final double radius = scaledRect.shortestSide / 2; // Υπολόγισε μια ακτίνα
      canvas.drawCircle(center, radius, circlePaint);

      // --- Ζωγραφική Εικονιδίου ---
      ui.Image? iconToDraw;
      if (isTargetFound && correctIcon != null) {
        iconToDraw = correctIcon;
      } else if (isWrongTargetFound && wrongIcon != null) {
        iconToDraw = wrongIcon;
      }

      if (iconToDraw != null) {
        // Υπολογίζω το κέντρο του εικονιδίου πάνω από το πλαίσιο
        final double iconCenterX = scaledRect.center.dx;
        final double iconCenterY =
            scaledRect.top + iconOffsetY - (iconSize / 2); // Κεντράρω κάθετα

        // Δημιουργώ το ορθογώνιο προορισμού για το εικονίδιο στην οθόνη
        final Rect iconDestRect = Rect.fromCenter(
          center: Offset(iconCenterX, iconCenterY),
          width: iconSize,
          height: iconSize,
        );

        // Δημιουργώ το ορθογώνιο πηγής (ολόκληρη η εικόνα του εικονιδίου)
        final Rect iconSourceRect = Rect.fromLTWH(
          0,
          0,
          iconToDraw.width.toDouble(),
          iconToDraw.height.toDouble(),
        );

        // Ζωγραφίζω το εικονίδιο
        canvas.drawImageRect(iconToDraw, iconSourceRect, iconDestRect, Paint());
      }
      // ---------------------------
    }
  }

  @override
  bool shouldRepaint(covariant TextOverlayPainter oldDelegate) {
    // Προσθέτω έλεγχο και για τις νέες παραμέτρους
    return oldDelegate.targetBoundingBox != targetBoundingBox ||
        oldDelegate.isTargetFound != isTargetFound ||
        oldDelegate.isWrongTargetFound != isWrongTargetFound ||
        oldDelegate.correctIcon != correctIcon ||
        oldDelegate.wrongIcon != wrongIcon ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.previewSize != previewSize ||
        oldDelegate.scale != scale;
  }
}
