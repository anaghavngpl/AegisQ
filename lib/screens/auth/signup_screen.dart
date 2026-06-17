import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../home/home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name     = TextEditingController();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _confirm  = TextEditingController();
  bool _isLoading = false, _obscure = true, _obscureConfirm = true, _agreed = false;
  String? _error;

  static const _grad1   = Color(0xFFCBA6F7);
  static const _grad2   = Color(0xFF7C3AED);
  static const _primary = Color(0xFF7C3AED);

  Future<void> _signup() async {
    if (!_agreed)                   { setState(() => _error = "Please agree to the terms"); return; }
    if (_name.text.trim().isEmpty)  { setState(() => _error = "Please enter your name"); return; }
    if (_email.text.trim().isEmpty) { setState(() => _error = "Please enter your email"); return; }
    if (_password.text.length < 6)  { setState(() => _error = "Password must be at least 6 characters"); return; }
    if (_password.text != _confirm.text) { setState(() => _error = "Passwords do not match"); return; }
    setState(() { _isLoading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(), password: _password.text);
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'name': _name.text.trim(), 'email': _email.text.trim(),
        'photoUrl': '', 'isOnline': true, 'createdAt': FieldValue.serverTimestamp(),
      });
      await cred.user?.updateDisplayName(_name.text.trim());
      if (mounted) Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } on FirebaseAuthException catch (e) {
      String msg = "Signup failed. Try again.";
      if (e.code == 'weak-password')        msg = "Password is too weak";
      if (e.code == 'email-already-in-use') msg = "Email already in use";
      if (e.code == 'invalid-email')        msg = "Invalid email format";
      setState(() { _error = msg; _isLoading = false; });
    } catch (_) {
      setState(() { _error = "Signup failed"; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final headerH = size.height * 0.36;
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
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [_grad1, Color(0xFFAB77F0), _grad2],
                  ),
                ),
              ),
              Positioned(top: -50, right: -50,
                  child: _blob3D(220, const Color(0xFF9B5FE0), const Color(0xFFE2C4FF))),
              Positioned(top: 20, left: -60,
                  child: _blob3D(170, const Color(0xFF5B1FA0), const Color(0xFFBB99EE))),
              Positioned(bottom: -25, right: 50,
                  child: _blob3D(130, const Color(0xFF7B3FBF), const Color(0xFFD4A8FF))),
              Positioned(top: 40, right: 65, child: _glowOrb(65)),
              Positioned(bottom: 40, left: 55, child: _glowOrb(38)),
              // App-themed text centred in header
              Positioned(top: 0, bottom: 0, left: 24, right: 24,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Your Privacy,\nFortified.",
                      style: GoogleFonts.poppins(
                        fontSize: 32, fontWeight: FontWeight.bold,
                        color: Colors.white, height: 1.2,
                        shadows: [Shadow(color: Colors.black.withOpacity(0.15), blurRadius: 12)],
                      )),
                    const SizedBox(height: 10),
                    Text("Join the future of\nquantum-proof messaging.",
                      style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.white.withOpacity(0.88),
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
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text("Get Started",
                      style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.bold, 
                        color: isDark ? const Color(0xFFE879F9) : _primary)),
                  ),
                  const SizedBox(height: 20),
                  _label("Full Name", isDark),
                  _field(_name, "Enter Full Name", false, Icons.person_outline, isDark),
                  const SizedBox(height: 14),
                  _label("Email", isDark),
                  _field(_email, "Enter Email", false, Icons.email_outlined, isDark),
                  const SizedBox(height: 14),
                  _label("Password", isDark),
                  _field(_password, "Enter Password", _obscure, Icons.lock_outline, isDark,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.grey[400], size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label("Confirm Password", isDark),
                  _field(_confirm, "Re-enter Password", _obscureConfirm, Icons.lock_outline, isDark,
                    suffix: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.grey[400], size: 20),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    SizedBox(width: 20, height: 20,
                      child: Checkbox(
                        value: _agreed, activeColor: _primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (v) => setState(() => _agreed = v ?? false))),
                    const SizedBox(width: 8),
                    Expanded(child: RichText(text: TextSpan(
                      text: "I agree to the processing of ",
                      style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12),
                      children: [TextSpan(text: "Personal data",
                        style: GoogleFonts.poppins(
                            color: _primary, fontWeight: FontWeight.w600, fontSize: 12))],
                    ))),
                  ]),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                  const SizedBox(height: 14),
                  _gradientButton("Sign up", _isLoading ? null : _signup, _isLoading),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: RichText(text: TextSpan(
                        text: "Already have an account? ",
                        style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14),
                        children: [TextSpan(text: "Sign in",
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
      boxShadow: [BoxShadow(color: base.withOpacity(0.3), blurRadius: 28, spreadRadius: 4)],
    ),
  );

  Widget _glowOrb(double s) => Container(
    width: s, height: s,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [Colors.white.withOpacity(0.9), const Color(0xFFE9D5FF).withOpacity(0.5)]),
      boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.6), blurRadius: 18, spreadRadius: 3)],
    ),
  );

  Widget _label(String t, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: GoogleFonts.poppins(
        fontSize: 12, fontWeight: FontWeight.w600, 
        color: isDark ? Colors.white54 : Colors.grey[500])),
  );

  Widget _field(TextEditingController c, String hint, bool obscure,
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
