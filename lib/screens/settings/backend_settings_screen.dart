import 'package:flutter/material.dart';
import '../../services/websocket_crypto_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackendSettingsScreen extends StatefulWidget {
  const BackendSettingsScreen({Key? key}) : super(key: key);

  @override
  State<BackendSettingsScreen> createState() => _BackendSettingsScreenState();
}

class _BackendSettingsScreenState extends State<BackendSettingsScreen> {
  final _urlController = TextEditingController();
  bool _testing = false;
  String? _status;
  bool? _connected;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('backend_url') ?? 'ws://10.0.2.2:8000';
    _urlController.text = savedUrl;
  }

  Future<void> _saveUrl() async {
    await WebSocketCryptoService().setBackendUrl(_urlController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backend URL saved!'), backgroundColor: Colors.green),
    );
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _status = 'Connecting...'; _connected = null; });
    
    try {
      await WebSocketCryptoService().setBackendUrl(_urlController.text);
      final connected = await WebSocketCryptoService().connect('test_connection');
      
      if (connected) {
        setState(() { _status = 'Connected successfully!'; _connected = true; });
        WebSocketCryptoService().disconnect('test_connection');
      } else {
        setState(() { _status = 'Connection failed'; _connected = false; });
      }
    } catch (e) {
      setState(() { _status = 'Error: $e'; _connected = false; });
    }
    
    setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark 
      ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)] 
      : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);
    final subColor = isDark ? Colors.white70 : const Color(0xFF9333EA);
    final cardColor = isDark ? Colors.white12 : Colors.white60;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors)),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: textColor),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
                Text("Backend Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
              ]),
            ),
            
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD946EF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD946EF).withOpacity(0.3)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, color: Color(0xFFD946EF)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      "Configure the Python backend URL for real quantum-safe encryption. The backend handles ML-KEM key exchange, Double Ratchet, and Dilithium signatures.",
                      style: TextStyle(color: textColor, fontSize: 13),
                    )),
                  ]),
                ),
                
                const SizedBox(height: 24),
                
                // URL Input
                Text("BACKEND URL", style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
                  child: TextField(
                    controller: _urlController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: "ws://192.168.1.X:8000",
                      hintStyle: TextStyle(color: subColor.withOpacity(0.5)),
                      prefixIcon: Icon(Icons.link, color: subColor),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "• For Emulator: ws://10.0.2.2:8000\n• For Real Phone: Find your computer's IP (e.g. 192.168.1.5) and use ws://192.168.1.5:8000\n• Ensure both devices are on the SAME Wi-Fi network.",
                  style: TextStyle(color: subColor, fontSize: 12, height: 1.5),
                ),
                
                const SizedBox(height: 24),
                
                // Test Connection Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.wifi_tethering, color: Colors.white),
                    label: Text(_testing ? "CONNECTING..." : "TEST CONNECTION", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9333EA),
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                    ),
                  ),
                ),
                
                // Status
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _connected == true ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _connected == true ? Colors.green : Colors.red),
                    ),
                    child: Row(children: [
                      Icon(
                        _connected == true ? Icons.check_circle : Icons.error,
                        color: _connected == true ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_status!, style: TextStyle(color: textColor))),
                    ]),
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveUrl,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD946EF),
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                    ),
                    child: const Text("APPLY & SAVE URL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Backend Start Instructions
                Text("HOW TO START BACKEND", style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("1. Open terminal in backend folder", style: TextStyle(color: textColor)),
                    const SizedBox(height: 4),
                    Text("2. Install dependencies:", style: TextStyle(color: textColor)),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.black12, borderRadius: BorderRadius.circular(8)),
                      child: Text("pip install -r requirements.txt", style: TextStyle(fontFamily: 'monospace', color: subColor, fontSize: 12)),
                    ),
                    Text("3. Run server:", style: TextStyle(color: textColor)),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.black12, borderRadius: BorderRadius.circular(8)),
                      child: Text("uvicorn main:app --host 0.0.0.0 --port 8000", style: TextStyle(fontFamily: 'monospace', color: subColor, fontSize: 12)),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
