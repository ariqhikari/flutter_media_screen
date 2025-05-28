import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  final _sc = ScreenCapture();
  // Interpreter? _interpreter;
  Uint8List? _lastJpeg;

  @override
  void initState() {
    super.initState();
    // _loadModel();
    _initCapture();
  }

  // Future<void> _loadModel() async {
  //   _interpreter = await Interpreter.fromAsset('model.tflite');
  // }

  Future<void> _initCapture() async {
    bool ok = await _sc.requestPermission();
    if (!ok) return;
    _sc.frameStream.listen(_processFrame);
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

      print("[DEBUG] Metadata: $metadata");
      print("[DEBUG] Bytes length: ${bytes.length}");

      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        order: img.ChannelOrder.rgba,
      );

      final preview = img.copyResize(image, width: 360);
      final jpeg = Uint8List.fromList(img.encodeJpg(preview));

      Future.delayed(Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _lastJpeg = jpeg;
          });
        }
      });
    } catch (e) {
      print("Error memproses frame: $e");
    }
  }

  void _blockScreen() {
    // Panggil overlay native atau tampilkan widget full-screen
    showDialog(
        context: context,
        builder: (_) => Center(
            child: Container(
                color: Colors.black54,
                child: Text('Konten Diblokir',
                    style: TextStyle(color: Colors.white, fontSize: 24)))));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text('Parental Control')),
        body: Center(
          child: _lastJpeg == null
              ? Text('Monitoring aktif...')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Latest frame:'),
                    SizedBox(height: 10),
                    Image.memory(
                      _lastJpeg!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      height: 300,
                    ),
                  ],
                ),
        ),
      );
}
