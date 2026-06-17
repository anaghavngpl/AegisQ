import 'package:flutter/material.dart';
import '../settings/settings_screen.dart';
import 'chats_screen.dart';
import '../../services/biometric_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final screens = const [ChatsScreen(), SettingsScreen()];
  bool _isLocked = false;  // Start unlocked; only lock if biometric is enabled
  bool _checkingAuth = true; // Show loading until we know auth state

  @override
  void initState() {
    super.initState();
    _checkAppLock();
  }

  Future<void> _checkAppLock() async {
    final enabled = await BiometricService().isBiometricEnabled();
    if (!enabled) {
      if (mounted) setState(() { _isLocked = false; _checkingAuth = false; });
      return;
    }

    // Biometric IS enabled — show lock screen and authenticate
    if (mounted) setState(() { _isLocked = true; _checkingAuth = false; });

    setState(() => _checkingAuth = true);

    try {
      final success = await BiometricService().authenticateForAppUnlock();
      if (mounted) {
        setState(() {
          _isLocked = !success;
          _checkingAuth = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _checkingAuth = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // While checking if biometric is enabled, show a simple loading screen (no fingerprint icon)
    if (_checkingAuth) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF1A1025) : const Color(0xFFFAE8FF),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFD946EF)),
        ),
      );
    }

    // Show lock screen only if biometric IS enabled and app is locked
    if (_isLocked) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D), const Color(0xFF4C1D95)] 
                : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated-like Lock Icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                  ),
                  child: Icon(
                    Icons.lock_person_outlined,
                    size: 100,
                    color: isDark ? const Color(0xFFE879F9) : const Color(0xFF9333EA),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  "AegisQ",
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: isDark ? Colors.white : const Color(0xFF581C87),
                  ),
                ),
                Text(
                  "SECURED BY QUANTUM PROOF",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: isDark ? const Color(0xFFD946EF) : const Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(height: 60),
                
                // Glassmorphism Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _checkAppLock,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fingerprint, color: isDark ? Colors.white : const Color(0xFF581C87), size: 28),
                          const SizedBox(width: 16),
                          Text(
                            "TAP TO UNLOCK",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: isDark ? Colors.white : const Color(0xFF581C87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }


    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D1B3D) : Colors.white,
          boxShadow: [BoxShadow(color: const Color(0xFFD946EF).withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFD946EF),
          unselectedItemColor: isDark ? Colors.white54 : const Color(0xFF9333EA),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble), label: "Chats"),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: "Profile"),
          ],
        ),
      ),
    );
  }
}
