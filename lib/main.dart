import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const DesktopHostApp());
}

class DesktopHostApp extends StatelessWidget {
  const DesktopHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pixel 9 Desktop Host',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HostControlScreen(),
    );
  }
}

class HostControlScreen extends StatefulWidget {
  const HostControlScreen({super.key});

  @override
  State<HostControlScreen> createState() => _HostControlScreenState();
}

class _HostControlScreenState extends State<HostControlScreen> {
  static const platform = MethodChannel('com.jeremy.desktop/screen_stream');
  final TextEditingController _ipController = TextEditingController();

  bool _isStreaming = false;
  io.RawDatagramSocket? _udpSocket;
  Timer? _streamTimer;
  int _frameCounter = 0;

  final GlobalKey _repaintBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initUdpSender();
  }

  Future<void> _initUdpSender() async {
    _udpSocket = await io.RawDatagramSocket.bind(io.InternetAddress.anyIPv4, 0);
  }

  Future<void> _requestPermissionAndStart() async {
    final targetIp = _ipController.text.trim();
    if (targetIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the Chromecast Receiver IP address first')),
      );
      return;
    }

    try {
      await platform.invokeMethod('requestScreenCapture');
      _startStreamingLoop(targetIp);
    } catch (e) {
      debugPrint('MediaProjection authorization error: $e');
    }
  }

  void _startStreamingLoop(String targetIp) {
    setState(() {
      _isStreaming = true;
    });

    // 30 FPS Capture & Transmission Loop
    _streamTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) async {
      try {
        RenderRepaintBoundary? boundary =
            _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) return;

        ui.Image image = await boundary.toImage(pixelRatio: 0.5);
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;

        Uint8List pngBytes = byteData.buffer.asUint8List();
        _sendFrameInChunks(pngBytes, targetIp);
      } catch (e) {
        debugPrint('Frame streaming error: $e');
      }
    });
  }

  /// Packet Protocol matching Receiver:
  /// [4 bytes Frame ID][2 bytes Chunk Metadata][Payload Bytes...]
  void _sendFrameInChunks(Uint8List frameBytes, String targetIp) {
    if (_udpSocket == null) return;

    const int chunkSize = 1200;
    int totalChunks = (frameBytes.length / chunkSize).ceil();
    int frameId = _frameCounter++;

    for (int i = 0; i < totalChunks; i++) {
      int start = i * chunkSize;
      int end = (start + chunkSize < frameBytes.length) ? start + chunkSize : frameBytes.length;
      Uint8List chunkPayload = frameBytes.sublist(start, end);

      BytesBuilder builder = BytesBuilder();
      
      // Header 1: Frame ID (4 bytes)
      builder.add(_intTo32Bytes(frameId));

      // Header 2: Chunk info packed into 2 bytes
      var chunkInfoData = ByteData(2);
      chunkInfoData.setUint16(0, ((i & 0xFF) << 8) | (totalChunks & 0xFF), Endian.big);
      builder.add(chunkInfoData.buffer.asUint8List());

      // Payload
      builder.add(chunkPayload);

      _udpSocket?.send(
        builder.toBytes(),
        io.InternetAddress(targetIp),
        9876,
      );
    }
  }

  Uint8List _intTo32Bytes(int value) {
    var bdata = ByteData(4);
    bdata.setUint32(0, value, Endian.big);
    return bdata.buffer.asUint8List();
  }

  Future<void> _stopStreaming() async {
    _streamTimer?.cancel();
    try {
      await platform.invokeMethod('stopScreenCapture');
    } catch (e) {
      debugPrint('Error stopping capture service: $e');
    }

    setState(() {
      _isStreaming = false;
    });
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _udpSocket?.close();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixel 9 Desktop Host'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Icon(
              _isStreaming ? Icons.cast_connected : Icons.cast,
              color: _isStreaming ? Colors.greenAccent : Colors.grey,
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chromecast Receiver IP',
                hintText: 'e.g. 192.168.1.50',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tv),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isStreaming ? _stopStreaming : _requestPermissionAndStart,
                icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
                label: Text(_isStreaming ? 'Stop Streaming' : 'Start Stream to TV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isStreaming ? Colors.redAccent : Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Desktop Mode Surface Canvas (Streamed live over UDP):',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: RepaintBoundary(
                key: _repaintBoundaryKey,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isStreaming ? Colors.cyanAccent : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.desktop_windows,
                          size: 64,
                          color: _isStreaming ? Colors.cyanAccent : Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isStreaming
                              ? 'LIVE STREAMING TO RECEIVER'
                              : 'Desktop Workspace Ready',
                          style: TextStyle(
                            color: _isStreaming ? Colors.cyanAccent : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Anything rendered within this sandbox surface\nis encoded and broadcast on port 9876.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
