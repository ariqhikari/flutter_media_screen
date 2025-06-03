import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:tflite_flutter/tflite_flutter.dart';
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
  static const _overlayChannel = MethodChannel('overlay_control');
  final _sc = ScreenCapture();
  // Interpreter? _interpreter;
  Uint8List? _lastJpeg;
  bool _isMonitoring = false;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    // _loadModel();
  }

  Future<void> _initCapture() async {
    bool ok = await _sc.requestPermission();
    if (!ok) return;

    _subscription = _sc.frameStream.listen(_processFrame);
    setState(() {
      _isMonitoring = true;
    });
  }

  void _stopCapture() {
    _subscription?.cancel();
    setState(() {
      _isMonitoring = false;
      _lastJpeg = null;
    });
    _unblockScreen(); // optional: hilangkan overlay saat stop
  }

  Future<void> _processFrame(dynamic rawData) async {
    if (rawData is! Map) {
      print("Format data tidak valid (bukan Map)!");
      return;
    }

    try {
      final rawMap = Map<String, dynamic>.from(rawData);
      final bytes = rawMap['bytes'] as Uint8List;
      final metadata = Map<String, dynamic>.from(rawMap['metadata'] as Map);
      final width = metadata['width'] as int;
      final height = metadata['height'] as int;

      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        order: img.ChannelOrder.rgba,
      );

      final preview = img.copyResize(image, width: 360);
      final jpeg = Uint8List.fromList(img.encodeJpg(preview));

      Future.delayed(Duration(seconds: 2), () {
        print("[DEBUG] BLOCK SCREEN");
        // _blockScreen();
        // aku ubah sementara soalnya keblokir, jadi harus restart hp
        _unblockScreen();
      });

      if (mounted) {
        setState(() {
          _lastJpeg = jpeg;
        });
      }
    } catch (e) {
      print("Error memproses frame: $e");
    }
  }

  Future<void> _blockScreen() async {
    try {
      await _overlayChannel.invokeMethod('showOverlay');
    } catch (e) {
      print("Gagal memanggil showOverlay: $e");
    }
  }

  Future<void> _unblockScreen() async {
    try {
      await _overlayChannel.invokeMethod('removeOverlay');
    } catch (e) {
      print("Gagal memanggil removeOverlay: $e");
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text('Parental Control')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _lastJpeg != null
              ? Column(
            children: [
              Text('Latest frame:'),
              SizedBox(height: 10),
              Image.memory(
                _lastJpeg!,
                gaplessPlayback: true,
                fit: BoxFit.contain,
                height: 300,
              ),
              SizedBox(height: 20),
            ],
          )
              : Text('Monitoring ${_isMonitoring ? "aktif" : "nonaktif"}...'),

          SizedBox(height: 20),

          _isMonitoring
              ? ElevatedButton.icon(
            onPressed: _stopCapture,
            icon: Icon(Icons.stop),
            label: Text('Stop Monitoring'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          )
              : ElevatedButton.icon(
            onPressed: _initCapture,
            icon: Icon(Icons.play_arrow),
            label: Text('Start Monitoring'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    ),
  );
}

