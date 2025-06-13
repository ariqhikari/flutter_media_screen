import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screen_capture.dart';
import 'package:image/image.dart' as img;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext c) => MaterialApp(home: HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  // Channels
  static const _captureControlChannel = MethodChannel('screen_capture');
  static const _overlayControlChannel = MethodChannel('overlay_control');

  final _sc = ScreenCapture();
  StreamSubscription? _subscription;
  bool _isMonitoring = false;
  Uint8List? _lastJpeg;

  @override
  void initState() {
    super.initState();

    // Handle enable/disable calls from AccessibilityService
    _captureControlChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'enableCapture':
          print("[DEBUG] enableCapture dipanggil");
          await _startStreaming();
          break;
        case 'disableCapture':
          print("[DEBUG] disableCapture dipanggil");
          _stopStreaming();
          break;
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _initCapture() async {
    bool ok = await _sc.requestPermission();
    if (!ok) return;

    print("[DEBUG] Permission granted. Waiting for enableCapture...");
    setState(() => _isMonitoring = true);
  }

  void _stopCapture() {
    // 1) Stop listening
    _subscription?.cancel();
    _subscription = null;

    // 2) Reset UI state
    setState(() {
      _isMonitoring = false;
      _lastJpeg = null;
    });

    // 3) Clear any overlay
    _overlayControlChannel.invokeMethod('removeOverlay');
  }

  Future<void> _processFrame(dynamic rawData) async {
    if (rawData is! Map) return;
    try {
      // Extract frame + metadata
      final rawMap = Map<String, dynamic>.from(rawData);
      final bytes = rawMap['bytes'] as Uint8List;
      final m = Map<String, dynamic>.from(rawMap['metadata'] as Map);
      final w = m['width'] as int, h = m['height'] as int;

      // Decode & preview
      final frame = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: bytes.buffer,
        order: img.ChannelOrder.rgba,
      );
      final preview = img.copyResize(frame, width: 360);
      final jpeg = Uint8List.fromList(img.encodeJpg(preview));

      // **Demo logic**: block ALWAYS. Replace with your model.
      await _overlayControlChannel.invokeMethod('showOverlay');

      // Update UI
      if (mounted) setState(() => _lastJpeg = jpeg);
    } catch (e) {
      print("Error processing frame: $e");
    }
  }

  Future<void> _startStreaming() async {
    if (_subscription != null) return;
    _subscription = _sc.frameStream.listen(_processFrame);
  }

  void _stopStreaming() {
    _subscription?.cancel();
    _subscription = null;
    _overlayControlChannel.invokeMethod('removeOverlay');
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text('Parental Control')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_lastJpeg != null) ...[
                Text('Latest frame:'),
                SizedBox(height: 10),
                Image.memory(
                  _lastJpeg!,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  height: 300,
                ),
                SizedBox(height: 20),
              ] else ...[
                Text('Monitoring ${_isMonitoring ? "aktif" : "nonaktif"}...'),
                SizedBox(height: 20),
              ],
              ElevatedButton.icon(
                onPressed: _isMonitoring
                    ? null
                    : _initCapture, // disable setelah granted
                icon: Icon(Icons.security),
                label: Text('Grant Permission'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
              )
            ],
          ),
        ),
      );
}
