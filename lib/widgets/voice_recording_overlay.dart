import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

class VoiceRecordingOverlay extends StatefulWidget {
  final String userName;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final Stream<double> amplitudeStream;

  const VoiceRecordingOverlay({
    super.key,
    required this.userName,
    required this.onStop,
    required this.onCancel,
    required this.onRetry,
    required this.amplitudeStream,
  });

  @override
  State<VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<VoiceRecordingOverlay> with SingleTickerProviderStateMixin {
  final List<double> _amplitudes = List.filled(40, 0.05);
  int _seconds = 0;
  Timer? _timer;
  StreamSubscription? _ampSub;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _listenToAmplitude();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _listenToAmplitude() {
    _ampSub = widget.amplitudeStream.listen((amp) {
      if (mounted) {
        setState(() {
          _amplitudes.removeAt(0);
          // Normalized range for the bars (0.05 to 1.0)
          double normalized = (amp + 60) / 60;
          _amplitudes.add(normalized.clamp(0.05, 1.0));
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFE5E7FD); // Very light lavender/blue
    const primaryPurple = Color(0xFF581C87); // Deep purple for text/icons
    const secondaryPurple = Color(0xFF7C3AED);

    return Stack(
      children: [
        // Backdrop Blur for the upper part
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),
        ),
        // Bottom Card (Half Screen)
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.55,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(48)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 30,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  children: [
                    Text(
                      "Recording",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: primaryPurple,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      "to ${widget.userName}",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: primaryPurple,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(flex: 2),
                    // Symmetrical Waveform
                    SizedBox(
                      height: 80,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _amplitudes.map((amp) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            width: 3,
                            height: 80 * amp,
                            decoration: BoxDecoration(
                              color: secondaryPurple.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Spacer(flex: 3),
                    Text(
                      _formatDuration(_seconds),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: primaryPurple.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _controlButton(Icons.refresh, widget.onRetry, primaryPurple.withOpacity(0.3)),
                        _sendButton(secondaryPurple),
                        _controlButton(Icons.delete_outline, widget.onCancel, primaryPurple.withOpacity(0.3)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onTap, Color color) {
    return IconButton(
      icon: Icon(icon, color: color, size: 28),
      onPressed: onTap,
    );
  }

  Widget _sendButton(Color iconColor) {
    return GestureDetector(
      onTap: widget.onStop,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: iconColor.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(Icons.send_rounded, color: iconColor, size: 32),
      ),
    );
  }
}
