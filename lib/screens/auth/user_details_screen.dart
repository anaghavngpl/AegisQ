import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../home/home_screen.dart';

class UserDetailsScreen extends StatefulWidget {
  final String userId;
  const UserDetailsScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController(); 
  String? _base64Image;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 400);

    if (pickedFile != null) {
      final bytes = await File(pickedFile.path).readAsBytes();
      setState(() {
        _base64Image = base64Encode(bytes);
      });
    }
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser!;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set({
      'name': _name.text.trim(),
      'age': int.tryParse(_age.text) ?? 0,
      'email': user.email,
      'profileCompleted': true,
      'photoUrl': _base64Image ?? '',
      'isOnline': true,
      'blockedUsers': [],
      // 'publicKey': ... (will be handled by backend/crypto service)
    }, SetOptions(merge: true));

    // await EncryptionService.generateAndStoreKeys(widget.userId); // Pending refactor

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark 
      ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)] 
      : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDark ? 0.1 : 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.6)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Complete Profile", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF7C3AED))),
                    const SizedBox(height: 24),
                    GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                            CircleAvatar(
                                radius: 50,
                                backgroundColor: const Color(0xFFF0ABFC),
                                backgroundImage: _base64Image != null 
                                    ? MemoryImage(base64Decode(_base64Image!)) 
                                    : null,
                                child: _base64Image == null 
                                    ? const Icon(Icons.person, size: 50, color: Colors.white) 
                                    : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Color(0xFFD946EF), shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                              ),
                            ),
                          ],
                        ),
                    ),
                    const SizedBox(height: 8),
                    Text("Tap to upload photo", style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 12)),
                    const SizedBox(height: 24),
                    _buildField(_name, "Display Name", Icons.person, textColor, isDark),
                    const SizedBox(height: 16),
                    _buildField(_age, "Age", Icons.cake, textColor, isDark, keyboardType: TextInputType.number),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _save, 
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD946EF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text("Continue", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController c, String label, IconData icon, Color textColor, bool isDark, {TextInputType? keyboardType}) => TextField(
    controller: c, 
    style: TextStyle(color: textColor), 
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label, 
      labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF9333EA)), 
      prefixIcon: Icon(icon, color: const Color(0xFFD946EF)), 
      filled: true, 
      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.7), 
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFD946EF), width: 1.5)),
    )
  );
}
