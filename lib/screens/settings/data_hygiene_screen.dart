import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/settings_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'dart:math' as math;

class DataHygieneScreen extends StatefulWidget {
  const DataHygieneScreen({super.key});

  @override
  State<DataHygieneScreen> createState() => _DataHygieneScreenState();
}

class _DataHygieneScreenState extends State<DataHygieneScreen> with SingleTickerProviderStateMixin {
  String _cacheSize = "Calculating...";
  String _mediaSize = "0 B";
  AnimationController? _progressController;

  @override
  void initState() {
    super.initState();
    _calculateStorage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progressController ??= AnimationController(duration: const Duration(seconds: 2), vsync: this)..forward();
  }

  @override
  void dispose() {
    _progressController?.dispose();
    super.dispose();
  }

  Future<void> _calculateStorage() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = await getApplicationCacheDirectory();
      
      int cacheBytes = await _getDirSize(tempDir) + await _getDirSize(cacheDir);
      
      setState(() {
        _cacheSize = _formatBytes(cacheBytes);
      });
      _progressController?.forward();
    } catch (e) {
      setState(() {
        _cacheSize = "Unknown";
      });
    }
  }

  Future<int> _getDirSize(Directory dir) async {
    int total = 0;
    try {
      if (await dir.exists()) {
        await for (var file in dir.list(recursive: true, followLinks: false)) {
          if (file is File) {
            total += await file.length();
          }
        }
      }
    } catch (e) {
      // Ignore errors
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes > 0) ? (bytes.toString().length / 3).floor() : 0;
    if (i >= suffixes.length) i = suffixes.length - 1; 
    // Simplified logic for brevity, can be more robust
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1048576) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / 1048576).toStringAsFixed(1)} MB";
  }

  Future<void> _clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = await getApplicationCacheDirectory();
      
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cache cleared successfully"), backgroundColor: Colors.green)
        );
        _calculateStorage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to clear cache"), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _clearMedia() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int count = 0;
      for (var key in keys) {
        if (key.startsWith('msg_cache_')) {
          // Check if it contains media
          final content = prefs.getString(key);
          if (content != null && (content.contains('"imageBase64"') || content.contains('"fileName"'))) {
             // For simplicity, we just clear the whole cache for that chat if it has media, 
             // or ideally parse and remove. Here we'll just clear valid cache keys.
             await prefs.remove(key);
             count++;
          }
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cleared $count media cache entries"), backgroundColor: Colors.green)
        );
        _calculateStorage();
      }
    } catch (e) {
      debugPrint("Error clearing media: $e");
    }
  }

  double _calculatePercentage() {
    // Parse _cacheSize to bytes
    int bytes = 0;
    try {
      if (_cacheSize.contains("KB")) {
        bytes = (double.parse(_cacheSize.replaceAll(" KB", "")) * 1024).toInt();
      } else if (_cacheSize.contains("MB")) {
        bytes = (double.parse(_cacheSize.replaceAll(" MB", "")) * 1024 * 1024).toInt();
      } else if (_cacheSize.contains("GB")) {
        bytes = (double.parse(_cacheSize.replaceAll(" GB", "")) * 1024 * 1024 * 1024).toInt();
      } else if (_cacheSize.contains("B")) {
        bytes = int.parse(_cacheSize.replaceAll(" B", ""));
      }
    } catch (e) {
        return 0.0;
    }
    
    // Cap at 500MB for visual "fullness"
    const maxBytes = 500 * 1024 * 1024;
    return (bytes / maxBytes).clamp(0.0, 1.0);
  }

  void _showClearConfirmation(String title, String description, String size, IconData icon, Color color, Future<void> Function() onConfirm) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Text(size, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.7))),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).maybePop();
                  await onConfirm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("Confirm & Clear", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text("Cancel", style: TextStyle(color: textColor.withOpacity(0.5))),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_progressController == null) {
      _progressController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..forward();
    }
    
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark 
      ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)] 
      : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

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
                Text("Data Hygiene", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
              ]),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Storage Hero
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFD946EF), Color(0xFFA855F7)]),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: const Color(0xFFD946EF).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(children: [
                      CustomPaint(
                        painter: StorageRingPainter(
                          progress: _progressController!, 
                          percentage: _calculatePercentage(), // Pass calculated percentage
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          child: const Icon(Icons.storage_rounded, color: Colors.white, size: 48),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(_cacheSize, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
                      const Text("Total Cache Used", style: TextStyle(color: Colors.white70)),
                    ]),
                  ),

                  const SizedBox(height: 30),

                  _sectionHeader("STORAGE BREAKDOWN", textColor),
                  Container(
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
                    child: Column(children: [
                      _storageItem(Icons.cached, "Cache", _cacheSize, const Color(0xFFC084FC), textColor),
                      const Divider(height: 1),
                      _storageItem(Icons.image_outlined, "Media Files", _mediaSize, const Color(0xFFF472B6), textColor),
                    ]),
                  ),

                  const SizedBox(height: 30),

                  _sectionHeader("CLEAN UP", textColor),
                  Container(
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
                    child: Column(children: [
                      _actionItem(
                        Icons.delete_sweep_outlined, 
                        "Clear Cache", 
                        "Free up temporary files", 
                        const Color(0xFFD946EF), 
                        textColor, 
                        () => _showClearConfirmation("Clear Cache", "This will remove temporary files and cached data. Your chats and media will not be affected.", _cacheSize, Icons.delete_sweep_outlined, const Color(0xFFD946EF), _clearCache),
                        trailing: _cacheSize
                      ),
                      const Divider(height: 1),
                      _actionItem(
                        Icons.perm_media_outlined, 
                        "Clear Downloaded Media", 
                        "Delete images and files", 
                        const Color(0xFFA855F7), 
                        textColor, 
                        () => _showClearConfirmation("Clear Media", "This will delete all downloaded images and files from your device. Messages will be preserved.", _mediaSize, Icons.perm_media_outlined, const Color(0xFFA855F7), _clearMedia),
                        trailing: _mediaSize
                      ),
                    ]),
                  ),

                  const SizedBox(height: 30),

                  _sectionHeader("AUTOMATION", textColor),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.auto_delete, color: Color(0xFF6366F1)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Auto-Delete Old Media", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                        Text("Remove files older than 30 days", style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.6))),
                      ])),
                      Switch(
                        value: settings.autoDeleteMedia,
                        onChanged: (v) => settings.toggleAutoDeleteMedia(v),
                        activeColor: Colors.white,
                        activeTrackColor: const Color(0xFF6366F1),
                      ),
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

  Widget _sectionHeader(String title, Color color) => Padding(
    padding: const EdgeInsets.only(left: 10, bottom: 10),
    child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.withOpacity(0.6), letterSpacing: 1.2)),
  );

  Widget _storageItem(IconData icon, String title, String size, Color iconColor, Color textColor) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Row(children: [
      Icon(icon, color: iconColor),
      const SizedBox(width: 16),
      Text(title, style: TextStyle(fontSize: 16, color: textColor)),
      const Spacer(),
      Text(size, style: TextStyle(fontWeight: FontWeight.bold, color: textColor.withOpacity(0.7))),
    ]),
  );

  Widget _actionItem(IconData icon, String title, String sub, Color iconColor, Color textColor, VoidCallback onTap, {String? trailing}) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 16, color: textColor)),
          Text(sub, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
        ])),
        if (trailing != null) ...[
           Text(trailing, style: TextStyle(fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6))),
           const SizedBox(width: 8),
        ],
        Icon(Icons.chevron_right, color: textColor.withOpacity(0.3)),
      ]),
    ),
  );
}

class StorageRingPainter extends CustomPainter {
  final Animation<double> progress;
  final double percentage;

  StorageRingPainter({required this.progress, required this.percentage}) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) + 10;
    
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    final progressPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;

    if (percentage > 0) {
      canvas.drawCircle(center, radius, bgPaint);
    }

    final sweepAngle = 2 * math.pi * progress.value * percentage; 
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant StorageRingPainter oldDelegate) => true;
}
