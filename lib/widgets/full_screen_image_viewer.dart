import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen profile photo viewer — immersive, like WhatsApp / Telegram.
/// Features: pinch-to-zoom, drag-down-to-dismiss, tap to toggle UI chrome,
/// smooth Hero animation, high-quality rendering.
class FullScreenImageViewer extends StatefulWidget {
  final String? imageBase64;
  final Uint8List? imageBytes;
  final String heroTag;
  final String userName;
  final String? statusText; // optional subtitle (e.g. "Online")

  const FullScreenImageViewer({
    Key? key,
    this.imageBase64,
    this.imageBytes,
    required this.heroTag,
    required this.userName,
    this.statusText,
  }) : super(key: key);

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer>
    with SingleTickerProviderStateMixin {
  bool _showChrome = true; // top/bottom UI bars
  double _dragOffset = 0;
  double _dragOpacity = 1.0;
  Uint8List? _imageBytes;

  late AnimationController _chromeController;
  late Animation<double> _chromeAnimation;

  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    if (widget.imageBytes != null) {
      _imageBytes = widget.imageBytes;
    } else if (widget.imageBase64 != null) {
      _imageBytes = base64Decode(widget.imageBase64!);
    }
    // Go full immersive
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _chromeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _chromeAnimation = CurvedAnimation(parent: _chromeController, curve: Curves.easeInOut);

    // Decode bytes once
    if (widget.imageBase64 != null && widget.imageBase64!.isNotEmpty) {
      try {
        _imageBytes = base64Decode(widget.imageBase64!);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _chromeController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) {
      _chromeController.forward();
    } else {
      _chromeController.reverse();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    // Only drag when not zoomed in
    if (_transformController.value != Matrix4.identity()) return;
    setState(() {
      _dragOffset += d.delta.dy;
      // Dim background as we drag down
      _dragOpacity = (1.0 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_dragOffset.abs() > 100 || d.primaryVelocity!.abs() > 600) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _dragOffset = 0;
        _dragOpacity = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageBytes != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background ──
          AnimatedOpacity(
            opacity: _dragOpacity,
            duration: Duration.zero,
            child: Container(color: Colors.black),
          ),

          // ── Main photo with drag-to-dismiss ──
          GestureDetector(
            onTap: _toggleChrome,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Center(
                child: Hero(
                  tag: widget.heroTag,
                  createRectTween: (begin, end) =>
                      MaterialRectCenterArcTween(begin: begin, end: end),
                  child: hasImage
                      ? InteractiveViewer(
                          transformationController: _transformController,
                          panEnabled: true,
                          minScale: 1.0,
                          maxScale: 6.0,
                          boundaryMargin: const EdgeInsets.all(20),
                          onInteractionEnd: (_) => setState(() {}),
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.height,
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => _avatarFallback(),
                            ),
                          ),
                        )
                      : _avatarFallback(),
                ),
              ),
            ),
          ),

          // ── Top bar (back button + name) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _chromeAnimation,
              child: IgnorePointer(
                ignoring: !_showChrome,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.userName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.statusText != null)
                                  Text(
                                    widget.statusText!,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom hint (swipe down) ──
          if (_showChrome && _dragOffset == 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _chromeAnimation,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0x99000000), Colors.transparent],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: const Column(
                    children: [
                      Icon(Icons.keyboard_arrow_down, color: Colors.white60, size: 22),
                      SizedBox(height: 4),
                      Text(
                        'Swipe down to close',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      width: 240,
      height: 240,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF7C3AED),
      ),
      child: Center(
        child: Text(
          widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 96,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
