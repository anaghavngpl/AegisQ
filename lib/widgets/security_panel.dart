import 'package:flutter/material.dart';

class SecurityPanel extends StatelessWidget {
  final bool isSecure;
  final bool isRatchetActive;
  final bool isSigned;

  const SecurityPanel({
    Key? key,
    required this.isSecure,
    required this.isRatchetActive,
    required this.isSigned,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
           BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 10, spreadRadius: 1)
        ]
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            const Text("Quantum-Safe Session Status", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            _buildStatusRow(
                "ML-KEM-1024", 
                "Key Ecapsulation Mechanism", 
                isSecure ? "Verified" : "Handshaking...", 
                isSecure ? Colors.greenAccent : Colors.orangeAccent
            ),
            const Divider(color: Colors.white12),
            _buildStatusRow(
                "Double Ratchet", 
                "Forward Secrecy", 
                isRatchetActive ? "Active" : "Initializing...", 
                isRatchetActive ? Colors.greenAccent : Colors.orangeAccent
            ),
            const Divider(color: Colors.white12),
             _buildStatusRow(
                "Dilithium3", 
                "Post-Quantum Signatures", 
                isSigned ? "Valid" : "Pending", 
                isSigned ? Colors.greenAccent : Colors.orangeAccent
            ),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple), 
                child: const Text("Close Security Lab")
            )
        ],
      ),
    );
  }

  Widget _buildStatusRow(String title, String subtitle, String status, Color color) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                  ),
                  Row(
                      children: [
                          Icon(Icons.shield, color: color, size: 16),
                          const SizedBox(width: 6),
                          Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                      ],
                  )
              ],
          ),
      );
  }
}
