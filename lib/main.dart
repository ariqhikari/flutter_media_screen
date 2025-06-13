import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minimize_flutter_app/minimize_flutter_app.dart';
import 'screen_capture.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:http/io_client.dart';


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

  // Resolusi frame asli (sesuaikan dengan device)
  final int frameWidth = 1080;
  final int frameHeight = 2340;

  DateTime _lastProcessed = DateTime.now().subtract(Duration(seconds: 2));

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
    // Batas waktu 2 detik
    final now = DateTime.now();
    if (now.difference(_lastProcessed) < Duration(seconds: 2)) {
      return;
    }
    _lastProcessed = now;

    if (rawData is! Map) {
      print("Format data tidak valid (bukan Map)!");
      return;
    }

    try {
      final rawMap = Map<String, dynamic>.from(rawData);
      final bytes = rawMap['bytes'] as Uint8List;
      final metadata = Map<String, dynamic>.from(rawMap['metadata'] as Map);
      final frameW = metadata['width'] as int;
      final frameH = metadata['height'] as int;

      print("[DEBUG] Metadata: $metadata");

      final image = img.Image.fromBytes(
        width: frameW,
        height: frameH,
        bytes: bytes.buffer,
        order: img.ChannelOrder.rgba,
      );

      final preview = img.copyResize(image, width: 360);
      final jpeg = Uint8List.fromList(img.encodeJpg(preview));

      // === 1. Jalankan model / deteksi yang menghasilkan list bounding‐box ===
      // Contoh dummy: deteksi 2 kotak berbahaya
      final random = Random();
      final detectedBoxes = List.generate(1, (_) {
        final w = 100 + random.nextInt(frameW ~/ 2);
        final h = 100 + random.nextInt(frameH ~/ 2);
        final x = random.nextInt(frameW - w);
        final y = random.nextInt(frameH - h);
        return {'x': x, 'y': y, 'w': w, 'h': h};
      });

      print("[DEBUG] Detected boxes: $detectedBoxes");
      print("[DEBUG] BLOCK SCREEN");
      _blockScreen(detectedBoxes);

      if (mounted) {
        setState(() {
          _lastJpeg = jpeg;
        });
      }
      await uploadCapturedImage(jpeg);
    } catch (e) {
      print("Error memproses frame: $e");
    }
  }

  Future<void> _blockScreen(List<Map<String, int>> detectedBoxes) async {
    try {
      await _overlayChannel.invokeMethod(
          'showMultipleRegionOverlay', detectedBoxes);
    } catch (e) {
      print("Error panggil showMultipleRegionOverlay: $e");
    }
  }

  Future<void> _unblockScreen() async {
    try {
      await _overlayChannel.invokeMethod('removeAllRegionOverlay');
    } catch (e) {
      print("Gagal memanggil removeOverlay: $e");
    }
  }

  Future<void> uploadCapturedImage(Uint8List imageBytes) async {
    final uri = Uri.parse('https://balancebites.auroraweb.id/analyze');

    try {
      final httpClient = HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true; // abaikan SSL error

      final ioClient = IOClient(httpClient);

      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'capture.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));

      final streamedResponse = await ioClient.send(request);

      if (streamedResponse.statusCode == 200) {
        final responseBody = await streamedResponse.stream.bytesToString();
        print('[UPLOAD] Berhasil: $responseBody');
      } else {
        print('[UPLOAD] Gagal: ${streamedResponse.statusCode}');
      }
    } catch (e) {
      print('[UPLOAD] Error: $e');
    }
  }


  @override
  Widget build(BuildContext c) => WillPopScope(
    onWillPop:() async {
      await MinimizeFlutterApp.minimizeApp();
      return false;
    },
    child: Scaffold(
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
                    : Text(
                        'Monitoring ${_isMonitoring ? "aktif" : "nonaktif"}...'),
                SizedBox(height: 20),
                _isMonitoring
                    ? ElevatedButton.icon(
                        onPressed: _stopCapture,
                        icon: Icon(Icons.stop),
                        label: Text('Stop Monitoring'),
                        style:
                            ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      )
                    : ElevatedButton.icon(
                        onPressed: _initCapture,
                        icon: Icon(Icons.play_arrow),
                        label: Text('Start Monitoring'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                      ),
              ],
            ),
          ),
        ),
  );
}
