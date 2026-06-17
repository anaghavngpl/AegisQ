import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../home/home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _isLoading = false, _obscure = true;
  String? _error;

  static const _grad1   = Color(0xFFCBA6F7);
  static const _grad2   = Color(0xFF7C3AED);
  static const _primary = Color(0xFF7C3AED);

  Future<void> _login() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(), password: _password.text);
      if (mounted) Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (_) {
      setState(() { _error = "Invalid credentials"; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final headerH = size.height * 0.44;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1025) : Colors.white,
      body: Stack(children: [
        // ── Gradient blob header ─────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: SizedBox(
            height: headerH,
            child: Stack(clipBehavior: Clip.none, children: [
              // BG gradient
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [_grad1, Color(0xFFAB77F0), _grad2],
                  ),
                ),
              ),
              // Blobs
              Positioned(top: -50, right: -50,
                  child: _blob3D(240, const Color(0xFF9B5FE0), const Color(0xFFE2C4FF))),
              Positioned(top: 30, left: -60,
                  child: _blob3D(190, const Color(0xFF5B1FA0), const Color(0xFFBB99EE))),
              Positioned(bottom: -30, right: 60,
                  child: _blob3D(140, const Color(0xFF7B3FBF), const Color(0xFFD4A8FF))),
              Positioned(top: 50, right: 70, child: _glowOrb(70)),
              Positioned(bottom: 50, left: 60, child: _glowOrb(40)),
              // App-themed text centred in header
              Positioned(top: 0, bottom: 0, left: 24, right: 24,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Secure.\nPrivate.",
                      style: GoogleFonts.poppins(
                        fontSize: 36, fontWeight: FontWeight.bold,
                        color: Colors.white, height: 1.2,
                        shadows: [Shadow(color: Colors.black.withOpacity(0.15), blurRadius: 12)],
                      )),
                    const SizedBox(height: 10),
                    Text("Protected by quantum-safe\nend-to-end encryption.",
                      style: GoogleFonts.poppins(
                        fontSize: 14, color: Colors.white.withOpacity(0.88),
                        height: 1.55,
                      )),
                  ],
                ),
              ),
            ]),
          ),
        ),

        // ── White card form ──────────────────────────────────────────
        Positioned(
          top: headerH - 28, left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1025) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28), topRight: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text("Welcome back",
                      style: GoogleFonts.poppins(
                        fontSize: 24, fontWeight: FontWeight.bold, 
                        color: isDark ? const Color(0xFFE879F9) : _primary)),
                  ),
                  const SizedBox(height: 28),
                  _label("Email", isDark),
                  _inputField(_email, "Email ID", false, Icons.email_outlined, isDark),
                  const SizedBox(height: 16),
                  _inputField(_password, "Password", _obscure, Icons.lock_outline, isDark,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.grey[400], size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                  const SizedBox(height: 28),
                  _gradientButton("Sign in", _isLoading ? null : _login, _isLoading),
                  const SizedBox(height: 24),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SignupScreen())),
                      child: RichText(text: TextSpan(
                        text: "Don't have an account? ",
                        style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14),
                        children: [TextSpan(text: "Sign up",
                          style: GoogleFonts.poppins(color: _primary, fontWeight: FontWeight.bold))],
                      )),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
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

  Widget _label(String t, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: GoogleFonts.poppins(
        fontSize: 12, fontWeight: FontWeight.w600, 
        color: isDark ? Colors.white54 : Colors.grey[500])),
  );

  Widget _inputField(TextEditingController c, String hint, bool obscure,
      IconData icon, bool isDark, {Widget? suffix}) =>
    TextField(
      controller: c, obscureText: obscure,
      style: GoogleFonts.poppins(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1E1E2E)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: isDark ? Colors.white24 : Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(icon, color: isDark ? const Color(0xFFC084FC) : const Color(0xFFAB77F0), size: 20),
        suffixIcon: suffix,
        filled: true, 
        fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFFAF5FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE9D5FF))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE9D5FF))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? const Color(0xFFE879F9) : _primary, width: 2)),
      ),
    );

  Widget _gradientButton(String label, VoidCallback? onTap, bool loading) =>
    Container(
      width: double.infinity, height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [Color(0xFFAB77F0), Color(0xFF7C3AED)]),
        boxShadow: [BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.35),
            blurRadius: 18, offset: const Offset(0, 7))],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(label, style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
}
