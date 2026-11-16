import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/stk500_flasher.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// Wireless firmware flashing. Gated behind a real confirmation dialog
/// because a dropped connection mid-flash leaves the board needing a USB
/// reflash to recover -- see the warning block in uno_radar.ino.
class OtaScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const OtaScreen({super.key, required this.bluetooth});

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

enum _OtaState { idle, waitingForReset, flashing, done, error }

class _OtaScreenState extends State<OtaScreen> {
  String? _hexContents;
  String? _fileName;
  _OtaState _state = _OtaState.idle;
  double _progress = 0;
  String _statusMessage = '';

  Future<void> _pickHexFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['hex'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    setState(() {
      _hexContents = String.fromCharCodes(result.files.single.bytes!);
      _fileName = result.files.single.name;
    });
  }

  Future<bool> _confirmRisk() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Before you flash wirelessly'),
            content: Text(
              'If the Bluetooth connection drops while this is writing to the '
              'Arduino, the board will be left without working firmware until '
              'you reflash it over USB. It is not permanently damaged -- just '
              'stuck until you plug it in.\n\n'
              'Make sure:\n'
              '• You already tested this exact .hex over USB and it works\n'
              '• You have a USB cable within reach, just in case\n'
              '• You\'re staying close to the Arduino during the update\n\n'
              'Continue?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('I understand, continue', style: TextStyle(color: ClayColors.danger)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _startFlash() async {
    if (_hexContents == null) return;
    if (widget.bluetooth.isDemo || widget.bluetooth.isWifi) {
      setState(() {
        _state = _OtaState.error;
        _statusMessage = widget.bluetooth.isDemo
            ? 'Demo mode: firmware updates need the real Arduino. Connect to your HC-05 to use this.'
            : 'Firmware updates only work over Bluetooth. Disconnect and connect to your HC-05 to use this.';
      });
      return;
    }
    if (!await _confirmRisk()) return;

    setState(() {
      _state = _OtaState.waitingForReset;
      _statusMessage = 'Telling the Arduino to reset into its bootloader...';
      _progress = 0;
    });

    widget.bluetooth.sendLine('ENTERUPDATE');
    // Give the chip a moment to actually reset before we start syncing --
    // the bootloader only listens for ~1s after reset, so don't wait long.
    await Future.delayed(Duration(milliseconds: 300));

    setState(() => _state = _OtaState.flashing);
    final flasher = Stk500Flasher(widget.bluetooth);
    flasher.flash(_hexContents!).listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress.fraction;
          _statusMessage = progress.message;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _state = _OtaState.error;
          _statusMessage = e.toString();
        });
      },
      onDone: () {
        if (!mounted) return;
        if (_state != _OtaState.error) {
          setState(() => _state = _OtaState.done);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          ClayContainer(
            color: ClayColors.danger.withOpacity(0.08),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: ClayColors.danger),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Experimental. Only flash a .hex you\'ve already verified over USB.',
                    style: TextStyle(color: ClayColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          ClayContainer(
            onTap: _pickHexFile,
            child: Row(
              children: [
                ClayBadge(icon: Icons.insert_drive_file_outlined, size: 44),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _fileName ?? 'Choose a .hex file...',
                    style: TextStyle(color: ClayColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          if (_state == _OtaState.flashing || _state == _OtaState.waitingForReset) ...[
            ClayContainer(
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: ClayColors.shadowDark.withOpacity(0.3),
                    color: ClayColors.primary,
                  ),
                  SizedBox(height: 12),
                  Text(_statusMessage, style: TextStyle(color: ClayColors.textSecondary), textAlign: TextAlign.center),
                ],
              ),
            ),
          ] else ...[
            ClayContainer(
              onTap: _hexContents == null ? null : _startFlash,
              color: _hexContents == null ? ClayColors.background : null,
              child: Center(
                child: Text(
                  'Flash over Bluetooth',
                  style: TextStyle(
                    color: _hexContents == null ? ClayColors.textSecondary : ClayColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          if (_state == _OtaState.done || _state == _OtaState.error)
            Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                _statusMessage,
                style: TextStyle(color: _state == _OtaState.error ? ClayColors.danger : ClayColors.success),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
