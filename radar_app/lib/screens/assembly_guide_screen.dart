import 'package:flutter/material.dart';
import '../theme/clay_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/clay_container.dart';
import '../widgets/wiring_diagram.dart';

class _GuideStep {
  final IconData icon;
  final String title;
  final String intro;
  final List<String> points;
  final String? warning;
  final Set<String> diagram; // parts to highlight on the wiring diagram
  const _GuideStep(this.icon, this.title, this.intro, this.points, {this.warning, this.diagram = const {}});
}

const _steps = <_GuideStep>[
  _GuideStep(
    Icons.inventory_2_outlined,
    'Check your parts',
    'Lay everything out before wiring. The basic build needs:',
    [
      'Arduino Uno + USB cable, and a USB power bank to run it',
      'HC-SR04 ultrasonic sensor and a servo (SG90 or similar)',
      'HC-05 Bluetooth module (bare board)',
      'Relay module (and a buzzer, optional)',
      '3 resistors of the same value, anything from 1kΩ to 10kΩ (for the HC-05)',
      'Breadboard and jumper wires',
      'Later, for WiFi and the digit display: ESP-01 + 3.3V regulator, a single-digit 7-segment display + 7 × 220Ω',
    ],
    diagram: {},
  ),
  _GuideStep(
    Icons.computer,
    'Set up your Linux computer',
    'One-time setup so the Arduino IDE can see your Uno.',
    [
      'Install the Arduino IDE: open a terminal and run  flatpak install flathub cc.arduino.IDE2  (or download the AppImage from arduino.cc)',
      'Let your user talk to USB boards:  sudo usermod -aG dialout \$USER  then log out and back in',
      'On Zorin/Ubuntu, remove brltty, which grabs USB-serial adapters:  sudo apt remove brltty',
      'Plug the Uno in and run  ls /dev/ttyACM*  : you should see /dev/ttyACM0. A USB-serial adapter shows as /dev/ttyUSB0',
      'In the IDE pick that port under Tools > Port',
    ],
    warning: 'Upload fails with "Permission denied" on /dev/ttyACM0? You skipped the dialout step, or did not log out afterwards.',
  ),
  _GuideStep(
    Icons.bolt_outlined,
    'Power',
    'The power bank powers everything through the Uno.',
    [
      'Power bank → USB cable → the Uno\'s USB port',
      'The Uno\'s 5V pin feeds the servo, HC-SR04 and relay',
      'The Uno\'s 3.3V pin feeds the HC-05 only',
      'Connect every GND to the Uno\'s GND',
      'Keep it unplugged while you wire. Plug in only to test',
    ],
    warning: 'Never put 5V on the HC-05 or ESP-01. They are 3.3V parts and will burn out.',
    diagram: {'power'},
  ),
  _GuideStep(
    Icons.settings_input_component_outlined,
    'Servo + ultrasonic sensor',
    'Glue or tape the HC-SR04 onto the servo horn so it turns with it, eyes facing forward.',
    [
      'Servo: brown/black → GND, red → 5V, orange/yellow signal → D9',
      'HC-SR04: VCC → 5V, GND → GND',
      'HC-SR04: TRIG → D7, ECHO → D6',
      'Leave slack in the sensor wires so they don\'t pull when the servo turns',
    ],
    diagram: {'servo', 'sonar'},
  ),
  _GuideStep(
    Icons.notifications_active_outlined,
    'Relay + buzzer',
    'These react when something comes too close.',
    [
      'Relay module: IN → D5, VCC → 5V, GND → GND',
      'Buzzer (optional): + → D8, − → GND. Skip it if you don\'t have one',
      'Whatever the relay switches goes on its COM and NO terminals',
    ],
    warning: 'Never switch mains (220V) on a breadboard build.',
    diagram: {'relay', 'buzzer'},
  ),
  _GuideStep(
    Icons.bluetooth,
    'HC-05 Bluetooth',
    'This is the link to this app.',
    [
      'VCC → the Uno\'s 3.3V pin, GND → GND',
      'HC-05 TXD → Uno D0 (direct wire, safe)',
      'Uno D1 → one resistor → HC-05 RXD. From HC-05 RXD, the other two resistors in a row → GND. This turns 5V into a safe 3.3V',
      'KEY pin: leave unconnected',
      'Optional, for wireless firmware updates: Uno D4 → 0.1µF capacitor → Uno RESET',
    ],
    warning: 'Unplug the wire on D0 while uploading over USB, or the upload fails.',
    diagram: {'hc05', 'resetcap'},
  ),
  _GuideStep(
    Icons.wifi,
    'ESP-01 WiFi (later)',
    'Optional: needs a separate 3.3V regulator, because the Uno\'s 3.3V pin can\'t power WiFi.',
    [
      'Flash esp01_radar_server.ino onto it first with a 3.3V USB-serial adapter',
      'VCC and EN → regulator 3.3V, GND → GND',
      'ESP-01 TX → Uno D10',
      'Uno D11 → resistor divider → ESP-01 RX (same trick as the HC-05)',
      'Then use the WiFi tab in this app to send it your network name and password',
    ],
    diagram: {'esp'},
  ),
  _GuideStep(
    Icons.looks_one_outlined,
    '7-segment display (later)',
    'Optional: shows how close the nearest object is (0 = alert, 9 = far).',
    [
      'Each segment through its own 220Ω resistor:',
      'a → D2, b → D3, c → D12, d → D13',
      'e → A0, f → A1, g → A2',
      'Common pin → GND (common-cathode digit)',
    ],
    diagram: {'display'},
  ),
  _GuideStep(
    Icons.rocket_launch_outlined,
    'Upload, pair, go',
    'Last steps before your first scan:',
    [
      'In the Arduino IDE: open uno_radar.ino, Tools > Board > Arduino Uno, Port > /dev/ttyACM0, Upload (D0 wire off while uploading)',
      'Reconnect the D0 wire and plug in the power bank: the servo starts sweeping',
      'On your phone: Settings → Bluetooth → pair "HC-05" (PIN 1234 or 0000)',
      'Open EchoSweep, tap the HC-05 in the list, and watch the live radar',
      'No hardware yet? Tap "Try demo mode" on the connect screen',
    ],
  ),
];

/// Step-by-step assembly guide. Opens automatically the first time the
/// app runs, and anytime later from the "Assembly guide" button.
class AssemblyGuideScreen extends StatefulWidget {
  final VoidCallback onDone;
  const AssemblyGuideScreen({super.key, required this.onDone});

  @override
  State<AssemblyGuideScreen> createState() => _AssemblyGuideScreenState();
}

class _AssemblyGuideScreenState extends State<AssemblyGuideScreen> {
  final _pager = PageController();
  int _page = 0;

  int get _total => _steps.length + 1; // +1 for the welcome page

  void _next() {
    if (_page < _total - 1) {
      _pager.nextPage(duration: Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _total - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Text('${_page + 1} / $_total', style: TextStyle(color: ClayColors.textSecondary)),
                  Spacer(),
                  TextButton(onPressed: widget.onDone, child: Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => i == 0 ? _WelcomePage() : _StepPage(step: _steps[i - 1], number: i),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_total, (i) {
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 250),
                    margin: EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? ClayColors.primary : ClayColors.shadowDark.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: ClayContainer(
                onTap: _next,
                child: Center(
                  child: Text(
                    _page == 0 ? "Let's build it" : (isLast ? 'Done, connect my radar' : 'Next step'),
                    style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700, fontSize: 16),
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

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppLogo(size: 140),
          SizedBox(height: 32),
          Text('EchoSweep', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
          SizedBox(height: 8),
          Text('Your room, on radar.', style: TextStyle(fontSize: 16, color: ClayColors.primary, fontWeight: FontWeight.w600)),
          SizedBox(height: 24),
          Text(
            'This guide walks you through wiring the sweeping sensor, alarms, '
            'Bluetooth and WiFi, one part at a time. It takes about 30–45 minutes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ClayColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  final _GuideStep step;
  final int number;
  const _StepPage({required this.step, required this.number});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        Row(
          children: [
            ClayBadge(icon: step.icon, iconColor: ClayColors.primary, size: 56),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STEP $number', style: TextStyle(color: ClayColors.textSecondary, fontSize: 12, letterSpacing: 1.2)),
                  Text(step.title, style: TextStyle(color: ClayColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        Text(step.intro, style: TextStyle(color: ClayColors.textSecondary, height: 1.4)),
        SizedBox(height: 16),
        if (step.diagram.isNotEmpty) ...[
          WiringDiagramCard(highlight: step.diagram, caption: 'Highlighted: this step\'s wires. Tap to zoom'),
          SizedBox(height: 16),
        ],
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in step.points)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 6, right: 10),
                        child: Icon(Icons.circle, size: 7, color: ClayColors.primary),
                      ),
                      Expanded(child: Text(p, style: TextStyle(color: ClayColors.textPrimary, height: 1.4))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (step.warning != null) ...[
          SizedBox(height: 16),
          ClayContainer(
            color: ClayColors.danger.withOpacity(0.15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: ClayColors.danger),
                SizedBox(width: 10),
                Expanded(
                  child: Text(step.warning!, style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w600, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
