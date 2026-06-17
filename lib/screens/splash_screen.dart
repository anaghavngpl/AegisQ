import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth/login_screen.dart';
import 'home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const _AuthWrapper()));
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF7C3AED),
      body: Container(
        width: size.width,
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFCBA6F7), Color(0xFFAB77F0), Color(0xFF7C3AED)],
          ),
        ),
        child: Stack(children: [
          // ── Same blobs as login screen ──────────────────────────────
          Positioned(top: -60, right: -60,
              child: _blob3D(260, const Color(0xFF9B5FE0), const Color(0xFFE2C4FF))),
          Positioned(top: size.height * 0.18, left: -50,
              child: _blob3D(180, const Color(0xFF7B3FBF), const Color(0xFFD4A8FF))),
          Positioned(bottom: 120, left: -30,
              child: _blob3D(220, const Color(0xFF5B1FA0), const Color(0xFF9B6FD0))),
          Positioned(bottom: 260, right: 30,
              child: _blob3D(130, const Color(0xFF7B3FBF), const Color(0xFFD4A8FF))),
          Positioned(top: 80, left: 40,  child: _glowOrb(70)),
          Positioned(bottom: 200, right: 40, child: _glowOrb(50)),
          // ── Centred content on top of blobs ────────────────────────
          FadeTransition(
            opacity: _fade,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/AQ_logonew (1) (2).png',
                    width: 370, height: 370,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 36),
                  Text("AegisQ",
                    style: GoogleFonts.orbitron(
                      fontSize: 36, fontWeight: FontWeight.bold,
                      color: Colors.white, letterSpacing: 2,
                    )),
                  const SizedBox(height: 8),
                  Text("Quantum-safe Messaging",
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.85),
                    )),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _blob3D(double s, Color base, Color highlight) => Container(
    width: s, height: s,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.35, -0.35), radius: 0.85,
        colors: [highlight.withOpacity(0.9), base.withOpacity(0.75)],
      ),
      boxShadow: [BoxShadow(color: base.withOpacity(0.35), blurRadius: 32, spreadRadius: 4)],
    ),
  );

  Widget _glowOrb(double s) => Container(
    width: s, height: s,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [Colors.white.withOpacity(0.9), const Color(0xFFE9D5FF).withOpacity(0.5)]),
      boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.6), blurRadius: 20, spreadRadius: 4)],
    ),
  );
}

class _AuthWrapper extends StatelessWidget {
  const _AuthWrapper({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF7C3AED),
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        return snap.hasData ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
