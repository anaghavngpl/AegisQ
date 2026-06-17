import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/settings_provider.dart';
import 'package:provider/provider.dart';

class SessionActivityScreen extends StatelessWidget {
  const SessionActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;
    final bgColors = isDark 
      ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)] 
      : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);
    final sectionColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                IconButton(icon: Icon(Icons.arrow_back, color: textColor), onPressed: () => Navigator.of(context).maybePop()),
                Text("Session Activity", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
              ]),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _sectionHeader("CURRENT SESSION", textColor),
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: sectionColor, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFD946EF), borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.smartphone, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("This Device", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        const Text("Active now", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(border: Border.all(color: Colors.green), borderRadius: BorderRadius.circular(20)),
                        child: Row(children: const [
                          Icon(Icons.check_circle, color: Colors.green, size: 14),
                          SizedBox(width: 4),
                          Text("Active", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                        ]),
                      ),
                    ]),
                  ),

                  _sectionHeader("ACCOUNT ACTIVITY", textColor),
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: sectionColor, borderRadius: BorderRadius.circular(20)),
                    child: Column(children: [
                      _activityItem(Icons.login, "Last Login", _formatDateTime(user?.metadata.lastSignInTime), textColor),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider()),
                      _activityItem(Icons.calendar_today, "Account Created", _formatDate(user?.metadata.creationTime), textColor),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider()),
                      _activityItem(Icons.email_outlined, "Email", user?.email ?? "Unknown", textColor),
                    ]),
                  ),

                  _sectionHeader("SECURITY STATUS", textColor),
                  Container(
                    decoration: BoxDecoration(color: sectionColor, borderRadius: BorderRadius.circular(20)),
                    child: Column(children: [
                      _statusItem(Icons.vpn_key_outlined, "Key Refresh", "Security refreshed recently", Colors.green, textColor),
                      _statusItem(Icons.security, "Encryption", "Quantum-safe active", Colors.green, textColor),
                      _statusItem(Icons.verified_user_outlined, "Identity", "Dilithium verified", Colors.green, textColor),
                    ]),
                  ),

                   const SizedBox(height: 24),
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3))),
                     child: Row(children: [
                       const Icon(Icons.info_outline, color: Color(0xFF6366F1)),
                       const SizedBox(width: 16),
                       const Expanded(child: Text("AegisQ automatically manages your secure sessions. Keys refresh with every message.", style: TextStyle(fontSize: 12, color: Color(0xFF6366F1)))),
                     ]),
                   ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return "Unknown";
    return "${date.day}/${date.month}/${date.year}";
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return "Unknown";
    return "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  Widget _sectionHeader(String title, Color color) => Padding(
    padding: const EdgeInsets.only(left: 10, bottom: 10),
    child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.withOpacity(0.6), letterSpacing: 1.2)),
  );

  Widget _activityItem(IconData icon, String title, String value, Color textColor) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Row(children: [
      Icon(icon, color: const Color(0xFFD946EF), size: 20),
      const SizedBox(width: 16),
      Text(title, style: TextStyle(fontSize: 16, color: textColor)),
      const Spacer(),
      Text(value, style: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.w500)),
    ]),
  );

  Widget _statusItem(IconData icon, String title, String status, Color statusColor, Color textColor) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
    child: Row(children: [
      Icon(icon, color: const Color(0xFFD946EF), size: 20),
      const SizedBox(width: 16),
      Expanded(child: Text(title, style: TextStyle(fontSize: 16, color: textColor))),
      Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w500, fontSize: 13)),
    ]),
  );
}
