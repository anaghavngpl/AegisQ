import 'dart:math';
import 'package:flutter/material.dart';

class SecurityLabScreen extends StatefulWidget {
  const SecurityLabScreen({super.key});

  @override
  State<SecurityLabScreen> createState() => _SecurityLabScreenState();
}

class _SecurityLabScreenState extends State<SecurityLabScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _flowController;
  late AnimationController _stageController;

  int _tabIndex = 0; // 0 = Learn, 1 = Demo
  int _currentStage = 0;
  bool _running = false;

  // Expandable state per card
  final List<bool> _expanded = [false, false, false];

  final List<_AlgoCard> _cards = [
    _AlgoCard(
      title: 'ML-KEM (Kyber)',
      subtitle: 'How it protects your chat',
      icon: Icons.vpn_key,
      color: const Color(0xFF7C3AED),
      description:
          "ML-KEM uses mathematical lattices that even quantum computers can't solve efficiently. When you start a chat, both devices generate special puzzle pieces that only combine correctly with each other.",
      bullets: [
        ('🔑', 'Creates quantum-safe session keys'),
        ('🧩', 'Based on Learning With Errors (LWE)'),
        ('🚀', 'NIST approved post-quantum standard'),
      ],
    ),
    _AlgoCard(
      title: 'Double Ratchet',
      subtitle: 'How keys rotate for every message',
      icon: Icons.refresh,
      color: const Color(0xFF7C3AED),
      description:
          'Every message uses a unique key derived from the previous one. Even if one key is compromised, past and future messages remain safe.',
      bullets: [
        ('🔄', 'New key for every single message'),
        ('⏮', 'Forward secrecy - past is safe'),
        ('⏩', 'Future secrecy - future is safe'),
      ],
    ),
    _AlgoCard(
      title: 'Dilithium',
      subtitle: 'How identity is verified',
      icon: Icons.verified_user,
      color: const Color(0xFF7C3AED),
      description:
          'Dilithium creates unforgeable digital signatures. Each message carries proof that it came from the real sender, not an impersonator.',
      bullets: [
        ('✍️', 'Quantum-resistant signatures'),
        ('👤', 'Proves sender authenticity'),
        ('🛡', 'Prevents message tampering'),
      ],
    ),
  ];

  final List<_Stage> _stages = [
    _Stage(title: 'ML-KEM Key Generation', subtitle: 'Alice & Bob agree on a shared secret',
        icon: Icons.key_outlined, color: const Color(0xFF10B981),
        detail: 'ML-KEM (Kyber) uses lattice math to produce a shared key. Immune to quantum computers.',
        particles: ['pk', 'sk', 'ct', 'K']),
    _Stage(title: 'Double Ratchet Init', subtitle: 'Fresh key chain per session',
        icon: Icons.refresh_outlined, color: const Color(0xFF6366F1),
        detail: 'Every message advances the ratchet — forward secrecy guaranteed even if one key leaks.',
        particles: ['RK', 'CKs', 'CKr', 'Mk']),
    _Stage(title: 'Message Encryption', subtitle: 'AES-256-GCM per-message key',
        icon: Icons.lock_outline, color: const Color(0xFF8B5CF6),
        detail: 'Plaintext is encrypted. The key is derived from the ratchet then discarded immediately.',
        particles: ['PT', 'IV', 'CT', 'TAG']),
    _Stage(title: 'Dilithium Signing', subtitle: 'Identity cryptographically proven',
        icon: Icons.verified_outlined, color: const Color(0xFFD946EF),
        detail: 'Your Dilithium private key signs the ciphertext. Recipient can verify it came from you.',
        particles: ['msg', 'sk', 'σ', '✓']),
    _Stage(title: 'Secure Delivery', subtitle: 'Signed & encrypted packet sent',
        icon: Icons.send_outlined, color: const Color(0xFFF59E0B),
        detail: 'The signed ciphertext travels over TLS. On arrival, signature checked then decrypted.',
        particles: ['🔒', '→', '🛡', '✅']),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _flowController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _stageController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flowController.dispose();
    _stageController.dispose();
    super.dispose();
  }

  void _runDemo() async {
    if (_running) return;
    setState(() { _running = true; _currentStage = 0; });
    for (int i = 0; i < _stages.length; i++) {
      setState(() => _currentStage = i);
      _stageController.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 3500));
    }
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() => _running = false);
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
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: bgColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
              child: Row(children: [
                IconButton(icon: Icon(Icons.arrow_back, color: textColor), onPressed: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 4),
                Icon(Icons.science_outlined, color: const Color(0xFF7C3AED), size: 26),
                const SizedBox(width: 8),
                Text('Security Lab', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
              ]),
            ),

            const SizedBox(height: 16),

            // Tab toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.white.withValues(alpha: 0.6)),
                ),
                child: Row(children: [
                  _tabBtn('Learn', 0, isDark),
                  _tabBtn('Demo', 1, isDark),
                ]),
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: _tabIndex == 0
                  ? _buildLearnTab(isDark, textColor)
                  : _buildDemoTab(isDark, textColor),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tabBtn(String label, int idx, bool isDark) {
    final active = _tabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: active ? const LinearGradient(colors: [Color(0xFFD946EF), Color(0xFF7C3AED)]) : null,
            borderRadius: BorderRadius.circular(30),
            boxShadow: active ? [BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.35), blurRadius: 10)] : [],
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : (isDark ? Colors.white54 : const Color(0xFF7C3AED)))),
        ),
      ),
    );
  }

  // ── LEARN TAB ─────────────────────────────────────────────────────────────
  Widget _buildLearnTab(bool isDark, Color textColor) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        for (int i = 0; i < _cards.length; i++) ...[
          _learnCard(i, isDark, textColor),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        _allSystemsActive(isDark, textColor),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _learnCard(int idx, bool isDark, Color textColor) {
    final card = _cards[idx];
    final open = _expanded[idx];
    return GestureDetector(
      onTap: () => setState(() => _expanded[idx] = !open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: open ? Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.5), width: 1.5) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: card.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(card.icon, color: card.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(card.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                Text(card.subtitle, style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.55))),
              ])),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: card.color),
            ]),
          ),
          if (open) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(card.description,
                    style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.8), height: 1.5)),
                const SizedBox(height: 14),
                for (final b in card.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Text(b.$1, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Text(b.$2, style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.75), fontWeight: FontWeight.w500)),
                    ]),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  // ── DEMO TAB ──────────────────────────────────────────────────────────────
  Widget _buildDemoTab(bool isDark, Color textColor) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.6)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(children: [
            // Stage progress bar
            Row(
              children: List.generate(_stages.length, (i) {
                final active = i == _currentStage && _running;
                final done = _running ? i < _currentStage : i <= _currentStage;
                return Expanded(child: Container(
                  margin: EdgeInsets.only(right: i < _stages.length - 1 ? 4 : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: active ? 8 : 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: done || active ? _stages[i].color : (isDark ? Colors.white12 : Colors.grey.shade200),
                      boxShadow: active ? [BoxShadow(color: _stages[i].color.withValues(alpha: 0.6), blurRadius: 8)] : [],
                    ),
                  ),
                ));
              }),
            ),

            const SizedBox(height: 22),

            AnimatedBuilder(
              animation: _stageController,
              builder: (context, _) {
                final stage = _stages[_currentStage];
                final fadeIn = _stageController.status == AnimationStatus.forward ? _stageController.value : 1.0;
                return Opacity(
                  opacity: fadeIn,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - fadeIn)),
                    child: Column(children: [
                      // Stage header row
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: stage.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                          child: Icon(stage.icon, color: stage.color, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(stage.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                          Text(stage.subtitle, style: TextStyle(fontSize: 11, color: stage.color, fontWeight: FontWeight.w600)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: stage.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text('${_currentStage + 1}/${_stages.length}',
                              style: TextStyle(fontSize: 11, color: stage.color, fontWeight: FontWeight.bold)),
                        ),
                      ]),

                      const SizedBox(height: 16),

                      // Per-stage visualizer
                      SizedBox(
                        height: 130,
                        child: _buildStageVisualizer(_currentStage, stage, isDark),
                      ),

                      const SizedBox(height: 12),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: stage.color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
                        child: Text(stage.detail,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.75), height: 1.5)),
                      ),

                      const SizedBox(height: 12),
                    ]),
                  ),
                );
              },
            ),

            const SizedBox(height: 22),

            GestureDetector(
              onTap: _running ? null : _runDemo,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: _running ? null : const LinearGradient(colors: [Color(0xFFD946EF), Color(0xFF7C3AED)]),
                  color: _running ? Colors.grey.withValues(alpha: 0.15) : null,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: _running ? [] : [BoxShadow(color: const Color(0xFFD946EF).withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_running)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else
                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(_running ? 'Simulating...' : 'Run Simulation',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 24),
        _allSystemsActive(isDark, textColor),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _allSystemsActive(bool isDark, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [Colors.green.withValues(alpha: 0.1), Colors.green.withValues(alpha: 0.04)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        ScaleTransition(
          scale: Tween(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.18),
                boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 4)]),
            child: const Icon(Icons.security, color: Colors.green, size: 44),
          ),
        ),
        const SizedBox(height: 16),
        const Text('All Systems Active',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 6),
        Text('Your messages are protected with quantum-safe encryption.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white60 : const Color(0xFF581C87).withValues(alpha: 0.65), fontSize: 13, height: 1.4)),
      ]),
    );
  }

  Widget _buildStageVisualizer(int stage, _Stage s, bool isDark) {
    switch (stage) {
      case 0: return _KemViz(color: s.color, controller: _flowController, isDark: isDark);
      case 1: return _RatchetViz(color: s.color, controller: _flowController, isDark: isDark);
      case 2: return _EncryptViz(color: s.color, controller: _flowController, isDark: isDark);
      case 3: return _SignViz(color: s.color, controller: _flowController, isDark: isDark);
      case 4: return _DeliveryViz(color: s.color, controller: _flowController, isDark: isDark);
      default: return const SizedBox.shrink();
    }
  }
}

// ─── Stage 0: ML-KEM ─────────────────────────────────────────────────────────
class _KemViz extends StatelessWidget {
  final Color color; final AnimationController controller; final bool isDark;
  const _KemViz({required this.color, required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return CustomPaint(
          painter: _KemPainter(t: t, color: color, isDark: isDark),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
            _party('ALICE', color),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15 + 0.1 * sin(t * 2 * pi).abs()),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 14)]),
              child: Icon(Icons.key, color: color, size: 22),
            ),
            const Spacer(),
            _party('BOB', color),
          ]),
        );
      },
    );
  }

  Widget _party(String name, Color c) => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.12)),
        child: Icon(Icons.person_outline, color: c, size: 24)),
    const SizedBox(height: 4),
    Text(name, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c)),
  ]);
}

class _KemPainter extends CustomPainter {
  final double t; final Color color; final bool isDark;
  _KemPainter({required this.t, required this.color, required this.isDark});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1.5;
    // Lattice
    paint.color = color.withValues(alpha: 0.08); paint.style = PaintingStyle.stroke; paint.strokeWidth = 0.8;
    for (int i = 0; i < 6; i++) { final x = 50.0 + i * (size.width - 100) / 5; canvas.drawLine(Offset(x, 10), Offset(x, size.height - 10), paint); }
    for (int i = 0; i < 4; i++) { final y = 20.0 + i * (size.height - 40) / 3; canvas.drawLine(Offset(50, y), Offset(size.width - 50, y), paint); }
    // Animated packets
    for (int dir = 0; dir < 2; dir++) {
      final phase = (t + dir * 0.5) % 1.0;
      final x0 = dir == 0 ? 44.0 : size.width - 44;
      final x1 = size.width / 2;
      final px = x0 + (x1 - x0) * phase;
      final py = size.height / 2 + (dir == 0 ? -12.0 : 12.0);
      paint.color = color.withValues(alpha: 0.8 * (1 - (phase - 0.5).abs() * 2.0).clamp(0.0, 1.0));
      paint.style = PaintingStyle.fill; paint.strokeWidth = 1.5;
      canvas.drawCircle(Offset(px, py), 5, paint);
      paint.style = PaintingStyle.stroke; paint.color = color.withValues(alpha: 0.12);
      canvas.drawLine(Offset(x0, py), Offset(px, py), paint);
    }
  }
  @override bool shouldRepaint(_KemPainter old) => old.t != t;
}

// ─── Stage 1: Double Ratchet ──────────────────────────────────────────────────
class _RatchetViz extends StatelessWidget {
  final Color color; final AnimationController controller; final bool isDark;
  const _RatchetViz({required this.color, required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        const keys = ['K₀', 'K₁', 'K₂', 'K₃', 'K₄'];
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(keys.length, (i) {
              final phase = (t * keys.length - i).clamp(0.0, 1.0);
              final done = phase >= 1; final active = phase > 0 && phase < 1;
              return Row(children: [
                AnimatedContainer(duration: const Duration(milliseconds: 200),
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: done ? color : (active ? color.withValues(alpha: 0.55) : color.withValues(alpha: 0.1)),
                    boxShadow: done || active ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10)] : []),
                  child: Center(child: Text(keys[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                      color: done || active ? Colors.white : color.withValues(alpha: 0.5))))),
                if (i < keys.length - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(Icons.arrow_forward_ios, size: 9, color: done ? color.withValues(alpha: 0.7) : (isDark ? Colors.white24 : Colors.grey.shade300))),
              ]);
            }),
          ),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              RotationTransition(turns: controller, child: Icon(Icons.settings, size: 14, color: color)),
              const SizedBox(width: 6),
              Text('Ratchet advancing...', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ])),
        ]);
      },
    );
  }
}

// ─── Stage 2: Encryption ──────────────────────────────────────────────────────
class _EncryptViz extends StatelessWidget {
  final Color color; final AnimationController controller; final bool isDark;
  const _EncryptViz({required this.color, required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final lockAnim = ((t - 0.4) / 0.3).clamp(0.0, 1.0);
        return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 22)),
            const SizedBox(height: 4),
            const Text('Plaintext', style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
          ]),
          Icon(Icons.arrow_forward, color: color.withValues(alpha: 0.5), size: 18),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.08 + 0.08 * lockAnim), shape: BoxShape.circle,
                boxShadow: lockAnim > 0.3 ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12)] : []),
            child: Icon(lockAnim < 0.5 ? Icons.lock_open_outlined : Icons.lock_outline, color: color, size: 28)),
          Icon(Icons.arrow_forward, color: color.withValues(alpha: 0.5), size: 18),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.enhanced_encryption, color: color, size: 22)),
            const SizedBox(height: 4),
            Text('Ciphertext', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
          ]),
        ]);
      },
    );
  }
}

// ─── Stage 3: Dilithium Signing ───────────────────────────────────────────────
class _SignViz extends StatelessWidget {
  final Color color; final AnimationController controller; final bool isDark;
  const _SignViz({required this.color, required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 100, height: 70,
            decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.3))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ...List.generate(3, (i) => Container(margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
                  height: 3, decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 6),
              Container(width: 76, height: 2, child: CustomPaint(painter: _SigLinePainter(progress: t, color: color))),
            ]),
          ),
          const SizedBox(width: 14),
          AnimatedOpacity(duration: Duration.zero, opacity: t > 0.6 ? ((t - 0.6) / 0.4).clamp(0.0, 1.0) : 0.0,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified, color: color, size: 16),
                const SizedBox(width: 5),
                Text('σ Valid', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              ]))),
        ]));
      },
    );
  }
}

class _SigLinePainter extends CustomPainter {
  final double progress; final Color color;
  _SigLinePainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height / 2);
    for (double x = 0; x <= size.width * progress; x++) {
      path.lineTo(x, size.height / 2 + sin(x / size.width * pi * 4) * size.height * 0.4);
    }
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(_SigLinePainter old) => old.progress != progress;
}

// ─── Stage 4: Secure Delivery ─────────────────────────────────────────────────
class _DeliveryViz extends StatelessWidget {
  final Color color; final AnimationController controller; final bool isDark;
  const _DeliveryViz({required this.color, required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final arrived = t > 0.8;
        final w = MediaQuery.of(context).size.width - 80;
        return Stack(children: [
          CustomPaint(painter: _TunnelPainter(color: color, t: t, isDark: isDark)),
          Positioned(left: 12, top: 38, child: _node(Icons.smartphone, 'Sender', color.withValues(alpha: 0.5))),
          Positioned(right: 12, top: 38, child: _node(Icons.smartphone, 'Receiver', arrived ? color : color.withValues(alpha: 0.3))),
          if (arrived)
            Positioned(right: 10, top: 5,
              child: Opacity(opacity: ((t - 0.8) / 0.2).clamp(0.0, 1.0),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withValues(alpha: 0.45))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.verified_user, size: 12, color: color),
                    const SizedBox(width: 3),
                    Text('Verified', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
                  ])))),
          Positioned(
            left: 52 + w * Curves.easeInOut.transform(t),
            top: 42,
            child: Opacity(opacity: t > 0.88 ? ((1 - t) / 0.12).clamp(0.0, 1.0) : 1.0,
              child: Container(width: 32, height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10)],
                    border: Border.all(color: color.withValues(alpha: 0.65))),
                child: Icon(Icons.lock, size: 13, color: color))),
          ),
        ]);
      },
    );
  }

  Widget _node(IconData icon, String label, Color c) => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: c, size: 20)),
    const SizedBox(height: 4),
    Text(label, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.bold)),
  ]);
}

class _TunnelPainter extends CustomPainter {
  final Color color; final double t; final bool isDark;
  _TunnelPainter({required this.color, required this.t, required this.isDark});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(44, size.height / 2 - 8, size.width - 88, 16), const Radius.circular(8)),
        Paint()..color = color.withValues(alpha: 0.1)..style = PaintingStyle.fill);
    final dp = Paint()..color = color.withValues(alpha: 0.3)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    for (int i = 0; i < 8; i++) {
      final x = 50.0 + ((i / 8 + t) % 1.0) * (size.width - 100);
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 10, size.height / 2), dp);
    }
  }
  @override bool shouldRepaint(_TunnelPainter old) => old.t != t;
}

// ─── Shared models ────────────────────────────────────────────────────────────
class _Stage {
  final String title, subtitle, detail;
  final IconData icon; final Color color; final List<String> particles;
  const _Stage({required this.title, required this.subtitle, required this.icon,
      required this.color, required this.detail, required this.particles});
}

class _AlgoCard {
  final String title, subtitle, description;
  final IconData icon; final Color color;
  final List<(String, String)> bullets;
  const _AlgoCard({required this.title, required this.subtitle, required this.icon,
      required this.color, required this.description, required this.bullets});
}

class _ParticleRow extends StatelessWidget {
  final List<String> labels; final Color color; final AnimationController controller;
  const _ParticleRow({required this.labels, required this.color, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(labels.length, (i) {
            final phase = (t - i * 0.25) % 1.0;
            final opacity = sin(phase * pi).clamp(0.25, 1.0).toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.translate(
                offset: Offset(0, -4 * sin(phase * pi)),
                child: Opacity(opacity: opacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.3 + 0.25 * opacity))),
                    child: Text(labels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color))))));
          }),
        );
      },
    );
  }
}
