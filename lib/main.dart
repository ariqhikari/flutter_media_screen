import 'dart:async';
import 'dart:math';
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

  // 1) Simpan dua frame terakhir untuk deteksi scroll:
  img.Image? _prevFrame; // frame sebelumnya
  img.Image? _currentFrame; // frame sekarang (hasil decode)

  // 2) Bounding‐box terakhir dari model (List of maps dengan {'x','y','w','h'}):
  List<Map<String, int>> _lastBoxes = [];

  // 3) Timer untuk deteksi idle (scroll berhenti):
  Timer? _idleTimer;
  bool _isIdle = false;

  // 4) Resolusi frame penuh (device‐specific, sesuaikan):
  final int screenW = 1080;
  final int screenH = 2400;

  final DateTime _lastProcessed = DateTime.now().subtract(Duration(seconds: 2));

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
    // // Batas waktu 2 detik
    // final now = DateTime.now();
    // if (now.difference(_lastProcessed) < Duration(seconds: 2)) {
    //   return;
    // }
    // _lastProcessed = now;

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

      // 1) Decode current frame
      final image = img.Image.fromBytes(
        width: frameW,
        height: frameH,
        bytes: bytes.buffer,
        order: img.ChannelOrder.rgba,
      );

      _currentFrame = image;

      if (_prevFrame == null) {
        // Pertama kali: belum ada prevFrame, langsung anggap idle dan panggil model:
        await _runModelAndOverlay(_currentFrame!);
        _prevFrame = _currentFrame;
        return;
      }

      // 2) Hitung scrollOffset (dy) antara prev dan curr
      // Hitung dy (scroll offset)
      var dy = estimateScrollOffset(_prevFrame!, _currentFrame!);
      // Jika scroll ke bawah, di kebanyakan kasus dy>0; scroll ke atas dy<0.
      // Namun jika dirasa terbalik, Anda bisa membalik tandanya:
      dy = -dy;
      print("[DEBUG] Scroll offset (dy): $dy");

      if (dy.abs() <= 1) {
        // Kemungkinan idle; debounce 300ms
        _idleTimer?.cancel();
        _idleTimer = Timer(Duration(milliseconds: 300), () async {
          if (!_isIdle) {
            _isIdle = true;
            await _runModelAndOverlay(_currentFrame!);
          }
        });
      } else {
        // User sedang scroll → batalkan debounce dan shift bounding‐box
        _idleTimer?.cancel();
        _isIdle = false;

        if (_lastBoxes.isNotEmpty) {
          final shiftedBoxes = _lastBoxes.map((box) {
            int oldX = box['x']!;
            int oldY = box['y']!;
            int w = box['w']!;
            int h = box['h']!;

            // Hitung newY = oldY + dy, kemudian clamp agar tetap di [0..screenH - h]
            int newY = oldY + dy;
            if (newY < 0) newY = 0;
            if (newY > screenH - h) newY = screenH - h;

            return {
              'x': oldX,
              'y': newY,
              'w': w,
              'h': h,
            };
          }).toList();

          await _blockScreen(shiftedBoxes);
          _lastBoxes = shiftedBoxes;
        }
      }

      _prevFrame = _currentFrame;

      // Tampilkan preview di UI (opsional)
      final preview = img.copyResize(_currentFrame!, width: 360);
      final jpeg = Uint8List.fromList(img.encodeJpg(preview));
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) setState(() => _lastJpeg = jpeg);
      });

      // final preview = img.copyResize(image, width: 360);
      // final jpeg = Uint8List.fromList(img.encodeJpg(preview));

      // // === 1. Jalankan model / deteksi yang menghasilkan list bounding‐box ===
      // // Contoh dummy: deteksi 2 kotak berbahaya
      // final random = Random();
      // final detectedBoxes = List.generate(1, (_) {
      //   final w = 100 + random.nextInt(frameW ~/ 2);
      //   final h = 100 + random.nextInt(frameH ~/ 2);
      //   final x = random.nextInt(frameW - w);
      //   final y = random.nextInt(frameH - h);
      //   return {'x': x, 'y': y, 'w': w, 'h': h};
      // });

      // print("[DEBUG] Detected boxes: $detectedBoxes");
      // print("[DEBUG] BLOCK SCREEN");
      // _blockScreen(detectedBoxes);

      // if (mounted) {
      //   setState(() {
      //     _lastJpeg = jpeg;
      //   });
      // }
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

  Future<void> _runModelAndOverlay(img.Image frame) async {
    final int w = frame.width;
    final int h = frame.height;
    final centerX = w ~/ 2 - 100;
    final centerY = h ~/ 2 - 100;
    final modelBoxes = [
      {'x': centerX, 'y': centerY, 'w': 1080, 'h': 200},
    ];

    _lastBoxes = modelBoxes; // simpan hasil model

    // Kirim overlay pertama
    _blockScreen(modelBoxes);
  }

  /// Estimasi dy (pergeseran vertikal) antara `prev` dan `curr`.
  /// - Pertama, ambil 3 strip horizontal masing‐masing stripHeight px tinggi.
  /// - Hitung SAD (sum of absolute differences) pada setiap strip di setiap dy di [-maxShift..maxShift].
  /// - Terapkan THRESHOLD: jika rata‐rata per‐pixel SAD terlalu tinggi, anggap "no movement" (dy=0).
  int estimateScrollOffset(img.Image prev, img.Image curr,
      {int maxShift = 20}) {
    final w = prev.width;
    final h = prev.height;

    // 3 strip horizontal: di h/4, h/2, 3h/4
    final List<int> stripYs = [h ~/ 4, h ~/ 2, 3 * h ~/ 4];
    const int stripHeight = 8; // Tinggikan sedikit biar lebih representatif
    const int stripWidth = 80; // Lebarkan biar makin stabil
    const int stripSpacing = 8; // Sampling tiap 8 px agar tidak over‐sample
    const double sadThresholdPerPixel = 15.0;
    // Jika rata‐rata per pixel SAD > 15, artinya terlalu banyak perbedaan (bayangan/pencahayaan), skip.

    int totalDy = 0;
    int validStrips = 0;

    for (final y in stripYs) {
      int bestDy = 0;
      double bestSAD = double.infinity;
      int bestValidPixels = 0;

      for (int dy = -maxShift; dy <= maxShift; dy++) {
        double sad = 0.0;
        int validPixels = 0;

        // Untuk setiap y0 di strip [y..y+stripHeight)
        for (int y0 = y; y0 < y + stripHeight; y0++) {
          for (int x = w ~/ 2 - stripWidth ~/ 2;
              x < w ~/ 2 + stripWidth ~/ 2;
              x += stripSpacing) {
            final y2 = y0 + dy;
            if (y2 < 0 || y2 >= h) continue;

            final p1 = prev.getPixel(x, y0);
            final p2 = curr.getPixel(x, y2);

            final l1 = img.getLuminance(p1);
            final l2 = img.getLuminance(p2);
            sad += (l1 - l2).abs();
            validPixels++;
          }
        }

        if (validPixels == 0) continue;
        // Hitung rata‐rata per pixel
        final avgSad = sad / validPixels;
        // Jika rata‐rata SAD lebih besar dari threshold, artinya terlalu banyak perbedaan kasatmata
        // (misal pantulan layar atau konten berubah drastis), skip pergeseran ini.
        if (avgSad > sadThresholdPerPixel) continue;

        if (sad < bestSAD) {
          bestSAD = sad;
          bestDy = dy;
          bestValidPixels = validPixels;
        }
      }

      // Jika kita menemukan candidato SAD valid (bestValidPixels > 0)
      if (bestValidPixels > 0 && bestSAD < double.infinity) {
        totalDy += bestDy;
        validStrips++;
      }
    }

    // Jika tidak ada strip yang “valid” (misal rata‐rata SAD selalu > threshold), kembali 0
    if (validStrips == 0) return 0;
    // Rata‐rata dy di antara strip yang valid
    return totalDy ~/ validStrips;
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
      );
}
