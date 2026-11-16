import 'package:flutter/material.dart';
import '../theme/clay_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/clay_container.dart';

class _GuideStep {
  final IconData icon;
  final String title;
  final String intro;
  final List<String> points;
  final String? warning;
  const _GuideStep(this.icon, this.title, this.intro, this.points, {this.warning});
}

const _steps = <_GuideStep>[
  _GuideStep(
    Icons.inventory_2_outlined,
    'Check your parts',
    'Lay everything out before wiring. You need:',
    [
      'Arduino Uno + USB cable',
      'HC-SR04 ultrasonic sensor',
      'Servo motor (SG90 or similar)',
      'HC-05 Bluetooth module (bare board)',
      'ESP-01 WiFi module (flashed with the EchoSweep ESP sketch first)',
      'Buzzer, relay module, single-digit 7-segment display',
      '3.3V regulator (AMS1117-3.3), 0.1µF capacitor',
      'Resistors: 7 × 220Ω, 2 × 1kΩ, 2 × 2kΩ',
      'Li-ion cell, a 3.7V→5V boost converter (and ideally a TP4056 charger)',
      'Breadboard and jumper wires',
    ],
  ),
  _GuideStep(
    Icons.bolt_outlined,
    'Power rails',
    'Build the power first, with nothing else plugged in.',
    [
      'Li-ion cell → boost converter → 5V rail. Uno 5V pin and GND to the rails.',
      'Feed the 3.3V regulator from the 5V rail: this 3.3V rail is ONLY for the HC-05 and ESP-01.',
      'Connect every GND together (Uno, both rails, all modules).',
    ],
    warning: 'Never put 5V on the HC-05 or ESP-01. They are 3.3V parts and will burn out.',
  ),
  _GuideStep(
    Icons.settings_input_component_outlined,
    'Servo + ultrasonic sensor',
    'Glue or tape the HC-SR04 onto the servo horn so it turns with it.',
    [
      'Servo: brown/black → GND, red → 5V, orange/yellow signal → D9',
      'HC-SR04: VCC → 5V, GND → GND',
      'HC-SR04: TRIG → D7, ECHO → D6',
    ],
  ),
  _GuideStep(
    Icons.notifications_active_outlined,
    'Buzzer + relay',
    'These fire when something comes too close.',
    [
      'Buzzer: + → D8, − → GND',
      'Relay module: IN → D5, VCC → 5V, GND → GND',
      'Anything you switch through the relay goes on its COM/NO terminals',
    ],
  ),
  _GuideStep(
    Icons.bluetooth,
    'HC-05 Bluetooth',
    'This is the link to this app and to wireless firmware updates.',
    [
      'VCC → 3.3V rail, GND → GND',
      'HC-05 TX → Uno D0 (RX)',
      'Uno D1 (TX) → 1kΩ → HC-05 RX, and HC-05 RX → 2kΩ → GND (divider: 5V → 3.3V)',
      'KEY pin: leave unconnected (only tie it to 3.3V at power-on to enter AT setup mode)',
      'Auto-reset for wireless updates: Uno D4 → 0.1µF capacitor → Uno RESET',
    ],
    warning: 'Unplug the HC-05 wire from D0 while uploading over USB, or the upload fails.',
  ),
  _GuideStep(
    Icons.wifi,
    'ESP-01 WiFi',
    'Flash the ESP sketch onto it with a USB-serial adapter before wiring it in.',
    [
      'VCC and CH_PD (EN) → 3.3V rail, GND → GND',
      'ESP-01 TX → Uno D10',
      'Uno D11 → 1kΩ → ESP-01 RX, and ESP-01 RX → 2kΩ → GND',
      'Later, use the WiFi tab in this app to give it your network name and password',
    ],
  ),
  _GuideStep(
    Icons.looks_one_outlined,
    '7-segment display',
    'Shows how close the nearest object is (0 = alert, 9 = far).',
    [
      'Each segment through its own 220Ω resistor:',
      'a → D2, b → D3, c → D12, d → D13',
      'e → A0, f → A1, g → A2',
      'Common pin → GND (common-cathode digit)',
      'Common-anode digit? Common pin → 5V and set COMMON_CATHODE = false in the sketch',
    ],
  ),
  _GuideStep(
    Icons.battery_charging_full,
    'Battery sensing',
    'Lets the app show the battery level in the top bar.',
    [
      'Li-ion + (before the boost converter) → A3',
      'The cell is at most 4.2V, so it is safe to read directly',
    ],
  ),
  _GuideStep(
    Icons.rocket_launch_outlined,
    'Upload, pair, go',
    'Last steps before your first scan:',
    [
      'Upload uno_radar.ino over USB (HC-05 wire off D0 while uploading, then reconnect it)',
      'Power on: the servo starts sweeping and the display lights up',
      'On your phone: Settings → Bluetooth → pair "HC-05" (PIN 1234 or 0000)',
      'Open EchoSweep, tap the HC-05 in the list, and watch the live radar',
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
      _pager.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
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
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Text('${_page + 1} / $_total', style: const TextStyle(color: ClayColors.textSecondary)),
                  const Spacer(),
                  TextButton(onPressed: widget.onDone, child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => i == 0 ? const _WelcomePage() : _StepPage(step: _steps[i - 1], number: i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_total, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: ClayContainer(
                onTap: _next,
                child: Center(
                  child: Text(
                    _page == 0 ? "Let's build it" : (isLast ? 'Done, connect my radar' : 'Next step'),
                    style: const TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700, fontSize: 16),
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
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        Row(
          children: [
            ClayBadge(icon: step.icon, iconColor: ClayColors.primary, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STEP $number', style: const TextStyle(color: ClayColors.textSecondary, fontSize: 12, letterSpacing: 1.2)),
                  Text(step.title, style: const TextStyle(color: ClayColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(step.intro, style: const TextStyle(color: ClayColors.textSecondary, height: 1.4)),
        const SizedBox(height: 16),
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in step.points)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 10),
                        child: Icon(Icons.circle, size: 7, color: ClayColors.primary),
                      ),
                      Expanded(child: Text(p, style: const TextStyle(color: ClayColors.textPrimary, height: 1.4))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (step.warning != null) ...[
          const SizedBox(height: 16),
          ClayContainer(
            color: const Color(0xFFFFE8E8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: ClayColors.danger),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(step.warning!, style: const TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w600, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
