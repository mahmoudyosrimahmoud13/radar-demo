import 'dart:async';
import 'dart:typed_data';
import 'bluetooth_service.dart';
import 'intel_hex.dart';

/// Flashes a new .hex onto the Uno over the Bluetooth link, speaking the
/// same STK500v1 protocol avrdude uses for a USB upload -- because after
/// ENTERUPDATE resets the chip into the Optiboot bootloader, the Bluetooth
/// link IS the programming link (HC-05 is wired to the hardware serial
/// pins the bootloader listens on).
///
/// READ THE WARNING IN uno_radar.ino before using this. In short: this is
/// more fragile than USB upload. Only flash firmware you've already
/// tested over USB. Keep a USB cable within reach. A failed flash leaves
/// the board needing a USB reflash to recover -- it does not destroy the
/// chip, but it will not run your program until you do that.
///
/// Protocol constants and command bytes are the standard STK500v1 set
/// (as used by Optiboot / avrdude's "arduino" programmer).
class Stk500FlashException implements Exception {
  final String message;
  Stk500FlashException(this.message);
  @override
  String toString() => 'Stk500FlashException: $message';
}

class Stk500Progress {
  final int pagesWritten;
  final int totalPages;
  final String message;
  Stk500Progress(this.pagesWritten, this.totalPages, this.message);
  double get fraction => totalPages == 0 ? 0 : pagesWritten / totalPages;
}

class Stk500Flasher {
  static const int _stkOk = 0x10;
  static const int _stkInsync = 0x14;
  static const int _crcEop = 0x20;
  static const int _cmdGetSync = 0x30;
  static const int _cmdEnterProgmode = 0x50;
  static const int _cmdLeaveProgmode = 0x51;
  static const int _cmdLoadAddress = 0x55;
  static const int _cmdProgPage = 0x64;
  static const int _memtypeFlash = 0x46; // 'F'

  static const int pageSizeBytes = 128; // ATmega328P flash page size

  final RadarBluetoothService bt;
  Stk500Flasher(this.bt);

  final _inbox = <int>[];
  StreamSubscription<Uint8List>? _sub;

  void _startListening() {
    _inbox.clear();
    _sub = bt.rawBytes.listen((chunk) => _inbox.addAll(chunk));
  }

  Future<void> _stopListening() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<List<int>> _waitForBytes(int count, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_inbox.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        throw Stk500FlashException(
            'Timed out waiting for a response from the bootloader. '
            'The board may not be in bootloader mode, or the Bluetooth '
            'link is too slow/unstable right now.');
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final result = _inbox.sublist(0, count);
    _inbox.removeRange(0, count);
    return result;
  }

  Future<void> _sendAndExpectOk(List<int> command, {Duration timeout = const Duration(seconds: 2)}) async {
    bt.sendRaw([...command, _crcEop]);
    final resp = await _waitForBytes(2, timeout);
    if (resp[0] != _stkInsync || resp[1] != _stkOk) {
      throw Stk500FlashException(
          'Bootloader did not acknowledge command 0x${command.isNotEmpty ? command[0].toRadixString(16) : "?"} '
          '(got ${resp.map((b) => "0x${b.toRadixString(16)}").join(",")})');
    }
  }

  /// Flashes [hexContents] (the raw text of an Arduino-exported .hex file)
  /// onto the board. Call this only right after sending ENTERUPDATE and
  /// seeing the Uno disconnect/reconnect -- the bootloader only listens
  /// for ~1 second after reset before giving up and running the old
  /// program, so start syncing promptly.
  Stream<Stk500Progress> flash(String hexContents) {
    final controller = StreamController<Stk500Progress>();
    _run(hexContents, controller);
    return controller.stream;
  }

  Future<void> _run(String hexContents, StreamController<Stk500Progress> out) async {
    _startListening();
    try {
      out.add(Stk500Progress(0, 0, 'Parsing .hex file...'));
      final parsed = IntelHex.parse(hexContents);
      final pages = IntelHex.flattenToPages(parsed, pageSizeBytes);

      out.add(Stk500Progress(0, pages.length, 'Syncing with bootloader...'));
      await _sync();

      out.add(Stk500Progress(0, pages.length, 'Entering programming mode...'));
      await _sendAndExpectOk([_cmdEnterProgmode]);

      for (int i = 0; i < pages.length; i++) {
        final wordAddress = (i * pageSizeBytes) ~/ 2;
        await _loadAddress(wordAddress);
        await _writePage(pages[i]);
        out.add(Stk500Progress(i + 1, pages.length, 'Writing page ${i + 1} of ${pages.length}...'));
      }

      out.add(Stk500Progress(pages.length, pages.length, 'Finishing up...'));
      await _sendAndExpectOk([_cmdLeaveProgmode]);

      out.add(Stk500Progress(pages.length, pages.length, 'Done. The board is now running the new firmware.'));
      await out.close();
    } catch (e) {
      out.addError(e);
      await out.close();
    } finally {
      await _stopListening();
    }
  }

  Future<void> _sync({int maxAttempts = 15}) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      _inbox.clear();
      bt.sendRaw([_cmdGetSync, _crcEop]);
      try {
        final resp = await _waitForBytes(2, const Duration(milliseconds: 400));
        if (resp[0] == _stkInsync && resp[1] == _stkOk) return;
      } catch (_) {
        // timeout on this attempt, try again
      }
    }
    throw Stk500FlashException(
        'Could not sync with the bootloader. Make sure you sent ENTERUPDATE '
        'and are trying again within a second or two of the reset, and that '
        'the HC-05 is wired to pins 0/1 at 115200 baud.');
  }

  Future<void> _loadAddress(int wordAddress) async {
    final lo = wordAddress & 0xFF;
    final hi = (wordAddress >> 8) & 0xFF;
    await _sendAndExpectOk([_cmdLoadAddress, lo, hi]);
  }

  Future<void> _writePage(List<int> pageBytes) async {
    final lenHi = (pageBytes.length >> 8) & 0xFF;
    final lenLo = pageBytes.length & 0xFF;
    await _sendAndExpectOk(
      [_cmdProgPage, lenHi, lenLo, _memtypeFlash, ...pageBytes],
      timeout: const Duration(seconds: 3),
    );
  }
}
