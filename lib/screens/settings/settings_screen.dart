import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/login_screen.dart';
import '../../services/theme_service.dart';
import '../../services/biometric_service.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'security_lab_screen.dart';
import 'app_lock_screen.dart';
import 'backend_settings_screen.dart';

import 'blocked_users_screen.dart';
import 'data_hygiene_screen.dart';
import 'session_activity_screen.dart';
import 'package:provider/provider.dart';
import '../../services/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bioController = TextEditingController();
  int _currentTipIndex = 0;
  final List<String> _securityTips = [
    "Your keys refresh with every message.",
    "Screenshot blocking hides your messages from prying eyes.",
    "Quantum-proof algorithms protect you against future threats.",
    "AegisQ doesn't store your plaintext messages on any server.",
    "Stealth mode masks your identity in the chat list.",
    "Enable Biometric Lock for maximum local security.",
    "One-time photos disappear forever after being viewed.",
    "Verification ticks confirm the integrity of every message."
  ];

  @override
  void initState() {
    super.initState();
    _initBio();
  }

  void _initBio() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _bioController.text = settings.bio ?? 'Hey there! I am using AegisQ';
  }

  Future<void> _applyScreenshotBlock(bool block) async {
    if (Platform.isAndroid) {
      if (block) {
        await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
      } else {
        await FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
      }
    }
  }


  Future<void> _saveBio(String newBio) async {
    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      await settings.updateProfile(null, newBio, null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bio updated!"), backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update bio"), backgroundColor: Colors.red));
    }
  }

  void _showPhotoOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D1B3D) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text("Profile Photo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF581C87))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Color(0xFFD946EF)),
            title: Text("Choose from Gallery", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
            onTap: () {
              Navigator.of(context).maybePop();
              _pickProfilePhoto();
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Color(0xFFA855F7)),
            title: Text("Take a Photo", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
            onTap: () {
              Navigator.of(context).maybePop();
              _takeProfilePhoto();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text("Remove Photo", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
            onTap: () {
              Navigator.of(context).maybePop();
              _removeProfilePhoto();
            },
          ),
          ListTile(
            leading: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.grey),
            title: Text("Cancel", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (img != null) {
      final bytes = await File(img.path).readAsBytes();
      final base64 = base64Encode(bytes);
      await settings.updateProfile(null, null, base64);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile photo updated!"), backgroundColor: Colors.green));
    }
  }

  Future<void> _takeProfilePhoto() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (img != null) {
      final bytes = await File(img.path).readAsBytes();
      final base64 = base64Encode(bytes);
      await settings.updateProfile(null, null, base64);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile photo updated!"), backgroundColor: Colors.green));
    }
  }

  Future<void> _removeProfilePhoto() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.updateProfile(null, null, '');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile photo removed"), backgroundColor: Colors.green));
  }



  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);
    final subColor = isDark ? Colors.white70 : const Color(0xFF9333EA);
    final accentColor = const Color(0xFFD946EF);
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.5);
    final glassBorder = Border.all(
      color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.4),
      width: 1.5);

    return Scaffold(
      backgroundColor: isDark ? Theme.of(context).scaffoldBackgroundColor : bgColors[0],
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)] : bgColors,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
        // ── Gradient blob header strip ─────────────────────────
        Stack(clipBehavior: Clip.hardEdge, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A0A2E), Color(0xFF2D1B3D), Color(0xFF1A1025)])
                  : const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFFCBA6F7), Color(0xFFAB77F0), Color(0xFF7C3AED)]),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withOpacity(isDark ? 0.0 : 0.2), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(children: [
              GestureDetector(
                onTap: _showPhotoOptions,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2.5)),
                      child: CircleAvatar(
                        radius: 55,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        backgroundImage: (settings.photoUrl != null && settings.photoUrl!.isNotEmpty)
                            ? MemoryImage(base64Decode(settings.photoUrl!)) : null,
                        child: (settings.photoUrl == null || settings.photoUrl!.isEmpty)
                            ? Text((settings.name != null && settings.name!.isNotEmpty) ? settings.name![0].toUpperCase() : "U",
                                style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold))
                            : null,
                      ),
                    ),
                    Positioned(
                      right: 2, bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4)]),
                        child: Icon(Icons.camera_alt, color: accentColor, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => _showRenameDialog(settings.name ?? "User"),
                child: Text(settings.name ?? "User",
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white,
                    shadows: [Shadow(color: Color(0x33000000), blurRadius: 8)])),
              ),
              const SizedBox(height: 4),
              Text(user?.email ?? "",
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              // Bio pill
              GestureDetector(
                onTap: () => _showBioDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Flexible(child: Text(settings.bio ?? 'Hey there! I am using AegisQ',
                        style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.white))),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit, size: 12, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          // Light-mode blobs
          if (!isDark) ...[ 
            Positioned(top: -28, right: -28, child: _blobS(110, const Color(0xFF9B5FE0), const Color(0xFFE2C4FF))),
            Positioned(top: 8, left: -38, child: _blobS(75, const Color(0xFF5B1FA0), const Color(0xFFBB99EE))),
            Positioned(bottom: 10, right: 60, child: _glowOrbS(48)),
          ],
          // Dark-mode: subtle night-sky stars (non-interactive, low opacity)
          if (isDark) ...[ 
            Positioned(top: 14, left: 30,  child: _starDot(2.5, 0.55)),
            Positioned(top: 22, left: 110, child: _starDot(1.8, 0.40)),
            Positioned(top: 10, left: 200, child: _starDot(2.2, 0.50)),
            Positioned(top: 30, right: 40, child: _starDot(1.6, 0.35)),
            Positioned(top: 50, left: 60,  child: _starDot(1.4, 0.30)),
            Positioned(top: 18, right: 90, child: _starDot(2.0, 0.45)),
            Positioned(top: 42, left: 170, child: _starDot(1.5, 0.30)),
            Positioned(top: 8,  right: 150, child: _starDot(2.8, 0.50)),
          ],
        ]),
        // Wrapped settings items with padding
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 32),
               // PROTECTION ENGINE
              _panelHeader("PROTECTION ENGINE"),
               _sectionCard([
                  // PostQuantum Cipher Engine tile
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityLabScreen())),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.hub_outlined, color: Color(0xFF10B981), size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('PostQuantum Cipher Engine',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : const Color(0xFF4C1D95))),
                                const SizedBox(height: 2),
                                Text('ML-KEM + Dilithium  Always On',
                                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : const Color(0xFF6B7280))),
                              ],
                            )),
                            const Icon(Icons.chevron_right, color: Color(0xFF10B981), size: 20),
                          ]),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ),
                 _newTile(
                   icon: Icons.fingerprint, 
                   iconColor: const Color(0xFFF472B6), 
                   title: "Biometric Lock", 
                   subtitle: "Manage device access",
                   isDark: isDark,
                   onTap: () async {
                     await Navigator.push(context, MaterialPageRoute(builder: (_) => const AppLockScreen()));
                   },
                 ),
                 _newSwitchTile(
                    icon: Icons.screenshot,
                    iconColor: const Color(0xFF6366F1),
                    title: "Screenshot Protection",
                    subtitle: "Block screenshots globally",
                    value: settings.screenshotProtection,
                    isDark: isDark,
                    onChanged: (v) {
                      settings.toggleScreenshotProtection(v);
                      _applyScreenshotBlock(v);
                    },
                 ),
               ], isDark),

              const SizedBox(height: 24),

              // PRIVACY & VISIBILITY
              _panelHeader("PRIVACY & VISIBILITY"),
              Row(
                children: [
                   Expanded(child: _gridCard(
                     icon: Icons.access_time_filled, 
                     title: "Last Seen", 
                     status: settings.lastSeenHidden ? "HIDDEN" : "VISIBLE",
                     isActive: !settings.lastSeenHidden,
                     isDark: isDark,
                     onTap: () {
                        settings.toggleLastSeenHidden(!settings.lastSeenHidden);
                     }
                   )),
                  const SizedBox(width: 16),
                  Expanded(child: _gridCard(
                    icon: Icons.sensors, 
                    title: "Online", 
                    status: settings.onlineHidden ? "HIDDEN" : "VISIBLE",
                    isActive: !settings.onlineHidden,
                    isDark: isDark,
                    onTap: () {
                       settings.toggleOnlineHidden(!settings.onlineHidden);
                    }
                  )),
                ],
              ),
              const SizedBox(height: 16),

              _sectionCard([
                 _newSwitchTile(
                   icon: Icons.done_all, 
                   iconColor: const Color(0xFFD946EF), 
                   title: "Read Receipts", 
                   subtitle: "Show seen status", 
                   value: settings.readReceipts, 
                   isDark: isDark,
                   onChanged: (v) {
                     settings.toggleReadReceipts(v);
                   }
                 ),
                 _newTile(
                   icon: Icons.block, 
                   iconColor: const Color(0xFFF87171), 
                   title: "Blocked Access", 
                   subtitle: "Manage restricted entities",
                   isDark: isDark,
                   onTap: () {
                     Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedUsersScreen()));
                   },
                 ),
               ], isDark),

              const SizedBox(height: 24),

              // SYSTEM
              _panelHeader("CONTROL CENTER"),
              _sectionCard([
                _newSwitchTile(
                  icon: Icons.auto_awesome, 
                  iconColor: const Color(0xFFC084FC), 
                  title: "Stealth Mode", 
                  subtitle: "Enable to mask identity", 
                  value: settings.stealthMode, 
                  isDark: isDark,
                  onChanged: (v) {
                    settings.toggleStealthMode(v);
                  }
                ),
                _newTile(
                   icon: Icons.account_tree_outlined, 
                   iconColor: const Color(0xFF60A5FA), 
                   title: "Session Activity", 
                   subtitle: "Track device sessions",
                   isDark: isDark,
                   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionActivityScreen())),
                ),
                _newTile(
                   icon: Icons.cleaning_services_outlined, 
                   iconColor: const Color(0xFFFBBF24), 
                   title: "Data Hygiene", 
                   subtitle: "Clear temporary cache",
                   isDark: isDark,
                   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataHygieneScreen())),
                ),

              ], isDark),

              const SizedBox(height: 24),

              // PREFERENCES
              _panelHeader("PREFERENCES"),
              _sectionCard([
                _newSwitchTile(
                  icon: Icons.brightness_6, 
                  iconColor: const Color(0xFFF472B6), 
                  title: "Night Vision", 
                  subtitle: "Toggle dark theme", 
                  value: isDark, 
                  isDark: isDark,
                  onChanged: (v) {
                    ThemeService().toggleTheme(v);
                  }
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentTipIndex = (_currentTipIndex + 1) % _securityTips.length;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: glassBorder),
                    child: Row(
                      children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.vpn_key_outlined, color: Color(0xFFD946EF), size: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [Text("💡 Security Tip", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor)), const Spacer(), Icon(Icons.chevron_right, size: 16, color: accentColor.withValues(alpha: 0.5))]),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                transitionBuilder: (Widget child, Animation<double> animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0.0, 0.2),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: Text(
                                  _securityTips[_currentTipIndex],
                                  key: ValueKey<int>(_currentTipIndex),
                                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : const Color(0xFF7C3AED))
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ], isDark),

              const SizedBox(height: 40),

              // VERSION & TERMINATE
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _showTransparencyReport,
                      child: Text("AegisQ Secure", style: TextStyle(color: isDark ? Colors.white60 : const Color(0xFF581C87).withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
                    ),
                    Text("v1.2.4 • Quantum-Proof Engine", style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF581C87).withValues(alpha: 0.4), fontSize: 12)),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _terminateSession,
                        icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                        label: const Text("Logout", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor: isDark ? Colors.red.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.red.withValues(alpha: 0.2))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
          ]),  // closes Column
        ), // closes Padding
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: const Color(0xFFC084FC))),
  );

  Widget _sectionCard(List<Widget> children, bool isDark) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF2D1B3D).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.4), width: 1.5),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Column(children: children),
  );

  Widget _gridCard({required IconData icon, required String title, required String status, bool isActive = false, required VoidCallback onTap, required bool isDark}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF9333EA).withValues(alpha: 0.2) : (isDark ? const Color(0xFF2D1B3D).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isActive ? const Color(0xFF9333EA).withValues(alpha: 0.5) : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.4)), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Icon(icon, color: isActive ? const Color(0xFFC084FC) : (isDark ? Colors.white70 : const Color(0xFF9333EA).withValues(alpha: 0.5)), size: 30),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isActive ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF4C1D95).withValues(alpha: 0.6)))),
          const SizedBox(height: 4),
          Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFFD946EF) : Colors.grey, letterSpacing: 1)),
        ],
      ),
    ),
  );

  Widget _newTile({required IconData icon, required Color iconColor, required String title, required String subtitle, Widget? trailing, VoidCallback? onTap, required bool isDark}) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    leading: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: iconColor, size: 24),
    ),
    title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF4C1D95))),
    subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : const Color(0xFF6B7280))),
    trailing: trailing ?? Icon(Icons.chevron_right, color: isDark ? Colors.white38 : const Color(0xFF9333EA).withValues(alpha: 0.4), size: 20),
  );

  Widget _newSwitchTile({required IconData icon, required Color iconColor, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged, required bool isDark}) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    leading: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: iconColor, size: 24),
    ),
    title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF4C1D95))),
    subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : const Color(0xFF6B7280))),
    trailing: Transform.scale(
      scale: 0.9,
      child: Switch(
        value: value, 
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: const Color(0xFF9333EA),
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: isDark ? Colors.white12 : Colors.grey[300],
      ),
    ),
  );

  void _showBioDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: _bioController.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2D1B3D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Update Bio", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
        content: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 3,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: "Tell us about yourself...",
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white60 : Colors.grey))),
          TextButton(
            onPressed: () async {
              final newBio = controller.text;
              await _saveBio(newBio);
              if (mounted) Navigator.of(context).maybePop();
            },
            child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD946EF))),
          ),
        ],
      ),
    );
  }

  Future<void> _terminateSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout?"),
        content: const Text("You will be logged out of this device."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Stay")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Logout", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
      }
    }
  }

  void _showRenameDialog(String currentName) {
    final nameController = TextEditingController(text: currentName);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D1B3D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Edit Name"),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: "Enter your name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                await settings.updateProfile(newName, null, null);
                if (mounted) Navigator.of(context).maybePop();
              }
            },
            child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD946EF))),
          ),
        ],
      ),
    );
  }

  void _showTransparencyReport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D1B3D) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text("Transparency Report", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          Text("AegisQ is open-source and audited by security experts.", style: TextStyle(fontSize: 14)),
          SizedBox(height: 8),
          Text("Total Data Requests: 0", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text("Encryption Protocol: X-Kyber- Dilithium Hybrid", style: TextStyle(fontSize: 12)),
          SizedBox(height: 16),
        ]),
      ),
    );
  }



  void _showDisappearingMessagesDialog(SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) {
        int tempDuration = settings.disappearDuration;
        bool tempEnabled = settings.disappearingMessages;
        final presets = [
          {'label': '30s', 'value': 30},
          {'label': '1m', 'value': 60},
          {'label': '5m', 'value': 300},
          {'label': '1h', 'value': 3600},
          {'label': '24h', 'value': 86400},
          {'label': '7d', 'value': 604800},
        ];

        return StatefulBuilder(builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1124) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Row(children: [
              const Icon(Icons.auto_delete_outlined, color: Color(0xFFD946EF)),
              const SizedBox(width: 12),
              const Text("Global Privacy", style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("New messages sent in all chats will automatically vanish after the selected duration.", 
                style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text("Global Vanish", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF581C87))),
                subtitle: const Text("Applied to all new chats", style: TextStyle(fontSize: 12)),
                value: tempEnabled,
                onChanged: (v) => setDialogState(() => tempEnabled = v),
                activeColor: const Color(0xFFD946EF),
              ),
              if (tempEnabled) ...[
                const SizedBox(height: 20),
                const Text("Select Duration:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets.map((p) {
                    final isSelected = tempDuration == p['value'];
                    return GestureDetector(
                      onTap: () => setDialogState(() => tempDuration = p['value'] as int),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFD946EF) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100]),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? const Color(0xFFD946EF) : Colors.transparent),
                        ),
                        child: Text(
                          p['label'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () {
                  settings.toggleDisappearingMessages(tempEnabled, tempDuration);
                  Navigator.of(context).maybePop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Global settings updated"), backgroundColor: Colors.green));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD946EF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Widget _blobS(double s, Color base, Color highlight) => Container(
    width: s, height: s,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.35, -0.35), radius: 0.85,
        colors: [highlight.withValues(alpha: 0.75), base.withValues(alpha: 0.55)],
      ),
    ),
  );

  Widget _glowOrbS(double s) => Container(
    width: s, height: s,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.75), const Color(0xFFE9D5FF).withValues(alpha: 0.3)]),
    ),
  );

  /// Tiny glowing star dot for the night-sky header in dark mode.
  Widget _starDot(double radius, double opacity) => Container(
    width: radius * 2,
    height: radius * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withOpacity(opacity),
      boxShadow: [
        BoxShadow(
          color: Colors.white.withOpacity(opacity * 0.6),
          blurRadius: radius * 2,
          spreadRadius: radius * 0.5,
        ),
      ],
    ),
  );
}
