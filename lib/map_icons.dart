import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Круглый значок (для остановок).
Future<Uint8List> makeDotIcon({
  required Color fill,
  int size = 72,
  double ring = 10,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final c = Offset(size / 2, size / 2);
  canvas.drawCircle(c, size / 2 - 2, Paint()..color = const Color(0x55000000));
  canvas.drawCircle(c, size / 2 - 4, Paint()..color = Colors.white);
  canvas.drawCircle(c, size / 2 - 4 - ring, Paint()..color = fill);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Пузырь с адресом и точкой. Остриё находится ровно в центре картинки
/// (нижняя половина прозрачная), поэтому он встаёт точно на координаты.
Future<Uint8List> makeLabelIcon({
  required String text,
  required Color color,
}) async {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xFF1B1B1F),
        fontSize: 30,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: 520);

  const padH = 22.0, padV = 14.0, stem = 22.0, margin = 10.0;
  final bubbleW = (tp.width + padH * 2).clamp(96.0, 600.0).toDouble();
  final bubbleH = tp.height + padV * 2;
  final w = bubbleW + margin * 2;
  final tipY = margin + bubbleH + stem; // от верха до острия
  final h = tipY * 2;
  final cx = w / 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final bubble = RRect.fromRectAndRadius(
    Rect.fromLTWH(margin, margin, bubbleW, bubbleH),
    const Radius.circular(22),
  );
  final stemPath = Path()
    ..moveTo(cx - 14, margin + bubbleH - 1)
    ..lineTo(cx + 14, margin + bubbleH - 1)
    ..lineTo(cx, tipY)
    ..close();

  // тень
  final shadow = Paint()
    ..color = const Color(0x44000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  canvas.drawRRect(bubble.shift(const Offset(0, 4)), shadow);

  // пузырь и «хвостик»
  final fill = Paint()..color = Colors.white;
  canvas.drawRRect(bubble, fill);
  canvas.drawPath(stemPath, fill);
  final border = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;
  canvas.drawRRect(bubble, border);

  // точка на острие
  canvas.drawCircle(Offset(cx, tipY), 14, Paint()..color = Colors.white);
  canvas.drawCircle(Offset(cx, tipY), 9, Paint()..color = color);

  tp.paint(canvas, Offset(margin + (bubbleW - tp.width) / 2, margin + padV));

  final image = await recorder.endRecording().toImage(w.ceil(), h.ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
