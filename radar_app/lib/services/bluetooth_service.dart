import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Thin wrapper around classic Bluetooth SPP (flutter_bluetooth_serial) for
/// talking to the HC-05. Android only -- iOS can't do classic SPP, which is
/// why this project is Android-only by choice.
///
/// Exposes:
///  - a broadcast stream of raw lines received from the Uno
///  - sendLine() to push a command ("CFG,...", "WIFI,...", "ENTERUPDATE")
///  - connect()/disconnect() and connection-state notifications
class RadarBluetoothService {
  BluetoothConnection? _connection;
  final _lineController = StreamController<String>.broadcast();
  final _stateController = StreamController<bool>.broadcast();
  final _rawController = StreamController<Uint8List>.broadcast();
  String _recvBuffer = '';

  Stream<String> get lines => _lineController.stream;
  Stream<bool> get connectionState => _stateController.stream;

  /// Every raw chunk received, unparsed. The OTA flasher reads STK500's
  /// binary responses from this instead of [lines], since bootloader
  /// replies aren't newline-delimited text and would corrupt the line
  /// buffer (and vice versa -- don't run normal radar traffic and OTA
  /// flashing at the same time).
  Stream<Uint8List> get rawBytes => _rawController.stream;

  bool get isConnected => _connection?.isConnected ?? false;

  Future<List<BluetoothDevice>> getBondedDevices() async {
    return await FlutterBluetoothSerial.instance.getBondedDevices();
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    _connection = await BluetoothConnection.toAddress(device.address);
    _stateController.add(true);

    _connection!.input!.listen(
      (Uint8List data) {
        _rawController.add(data);
        _recvBuffer += utf8.decode(data, allowMalformed: true);
        while (_recvBuffer.contains('\n')) {
          final idx = _recvBuffer.indexOf('\n');
          final line = _recvBuffer.substring(0, idx).trim();
          _recvBuffer = _recvBuffer.substring(idx + 1);
          if (line.isNotEmpty) _lineController.add(line);
        }
      },
      onDone: () => _stateController.add(false),
      onError: (_) => _stateController.add(false),
    );
  }

  Future<void> disconnect() async {
    await _connection?.finish();
    _connection = null;
    _stateController.add(false);
  }

  void sendLine(String command) {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    conn.output.add(utf8.encode('$command\n'));
  }

  /// Hands raw bytes directly to the output sink, for the OTA flasher
  /// which needs to send raw STK500 binary frames, not text lines.
  void sendRaw(List<int> bytes) {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    conn.output.add(bytes);
  }

  void dispose() {
    _lineController.close();
    _stateController.close();
    _rawController.close();
  }
}
