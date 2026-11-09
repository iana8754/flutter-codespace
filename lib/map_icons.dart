import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Рисует круглый значок (без внешних файлов-картинок).
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
