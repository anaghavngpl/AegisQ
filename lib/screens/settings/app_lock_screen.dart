import 'package:flutter/material.dart';
import '../../services/biometric_service.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({Key? key}) : super(key: key);
  
  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _isAvailable = false;
  bool _isEnabled = false;
  bool _loading = true;
  List<String> _availableMethods = [];

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final service = BiometricService();
    final available = await service.isAuthAvailable();
    final enabled = await service.isBiometricEnabled();
    final methods = await service.getAvailableMethods();
    
    if (mounted) {
      setState(() {
        _isAvailable = available;
        _isEnabled = enabled;
        _availableMethods = methods;
        _loading = false;
      });
    }
  }

  Future<void> _toggleLock() async {
    final service = BiometricService();
    if (_isEnabled) {
      // Disable - authenticate first using the system-level method (PIN/Biometric)
      final success = await service.authenticate(reason: 'Authenticate to disable app lock');
      if (success) {
        await service.setBiometricEnabled(false);
        setState(() => _isEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("App lock disabled"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Authentication failed"), backgroundColor: Colors.red),
        );
      }
    } else {
      // Enable - try to authenticate first
      final success = await service.authenticate(reason: 'Authenticate to enable app lock');
      if (success) {
        await service.setBiometricEnabled(true);
        setState(() => _isEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("App lock enabled!"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Authentication failed or cancelled"), backgroundColor: Colors.orange),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark 
      ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)] 
      : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);
    final subColor = isDark ? Colors.white70 : const Color(0xFF9333EA);
    final cardColor = isDark ? Colors.white12 : Colors.white60;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: textColor),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
                Text("App Lock", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
              ]),
            ),
            
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD946EF)))
                : ListView(padding: const EdgeInsets.all(16), children: [
                    // Lock Icon
                    Container(
                      padding: const EdgeInsets.all(32),
                      child: Icon(
                        _isEnabled ? Icons.lock : Icons.lock_open,
                        size: 80,
                        color: _isEnabled ? const Color(0xFFD946EF) : subColor,
                      ),
                    ),
                    
                    // Status Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
                      child: Column(children: [
                        Text(
                          _isEnabled ? "App Lock is ON" : "App Lock is OFF",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isEnabled 
                            ? "AegisQ is protected. You'll need Fingerprint, Face ID, or Device PIN to open."
                            : "Enable App Lock to secure your messages with biometrics or system PIN.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subColor),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _toggleLock,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isEnabled ? Colors.red : const Color(0xFFD946EF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(_isEnabled ? "Disable App Lock" : "Enable App Lock"),
                        ),
                      ]),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Requirements
                    Text("REQUIREMENTS", style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
                      child: _requirementItem(
                        Icons.fingerprint,
                        "Fingerprint Security",
                        _availableMethods.isNotEmpty 
                          ? "Available: ${_availableMethods.join(', ')}"
                          : "System biometric security verified",
                        _availableMethods.isNotEmpty || _isAvailable,
                        textColor,
                        subColor,
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD946EF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.3)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline, color: Color(0xFFD946EF)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(
                          "App Lock protects the entire app. To lock individual chats, go to the contact's profile within a chat.",
                          style: TextStyle(color: textColor, fontSize: 13),
                        )),
                      ]),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _requirementItem(IconData icon, String title, String subtitle, bool met, Color textColor, Color subColor) {
    return ListTile(
      leading: Icon(icon, color: met ? Colors.green : Colors.orange),
      title: Text(title, style: TextStyle(color: textColor)),
      subtitle: Text(subtitle, style: TextStyle(color: subColor, fontSize: 12)),
      trailing: Icon(
        met ? Icons.check_circle : Icons.warning_rounded,
        color: met ? Colors.green : Colors.orange,
      ),
    );
  }
}
