import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class ScreenCapture {
  static const MethodChannel _method = MethodChannel('screen_capture');
  static const EventChannel _events = EventChannel('screen_stream');

  /// Minta izin capture layar
  Future<bool> requestPermission() async {
    return await _method.invokeMethod<bool>('requestPermission') ?? false;
  }

  /// Stream frame bytes
  Stream<Map<String, dynamic>> get frameStream => _events
      .receiveBroadcastStream()
      .map((data) => Map<String, dynamic>.from(data as Map));
}
