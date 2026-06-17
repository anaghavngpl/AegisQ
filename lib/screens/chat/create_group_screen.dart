import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupName = TextEditingController();
  final List<String> _selectedMembers = [];
  bool _isLoading = false;

  Future<void> _createGroup() async {
    if (_groupName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a group name")));
      return;
    }
    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select at least one member")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final members = [uid, ..._selectedMembers];
      // Capture before any async gap so the controller isn't disposed mid-flight
      final groupName = _groupName.text.trim();

      final groupRef = await FirebaseFirestore.instance.collection('chats').add({
        'isGroup': true,
        'groupName': groupName,
        'participants': members,
        'createdBy': uid,
        'lastMessage': 'Group created',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).maybePop();
        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
          chatId: groupRef.id,
          otherUserId: 'group', // non-empty placeholder — ChatScreen handles isGroup=true separately
          otherUserName: groupName,
          isGroup: true,
        )));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to create group: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)] : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors)),
        child: SafeArea(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFE9D5FF),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Color(0xFF581C87))),
                const Text("New Group", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF581C87))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _groupName,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: "Group Name",
                  hintStyle: TextStyle(color: textColor.withOpacity(0.5)),
                  filled: true,
                  fillColor: isDark ? Colors.white12 : Colors.white60,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: Text("Select Members", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final Map<String, QueryDocumentSnapshot> seen = {};
                  for (final doc in snap.data!.docs) {
                    if (doc.id == uid) continue;
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? data['displayName'])?.toString().trim() ?? '';
                    if (name.isEmpty) continue;
                    final lowerName = name.toLowerCase();
                    if (!seen.containsKey(lowerName)) {
                      seen[lowerName] = doc;
                    }
                  }
                  final users = seen.values.toList();
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: users.length,
                    itemBuilder: (context, i) {
                      final user = users[i].data() as Map<String, dynamic>;
                      final name = user['name'] ?? "User";
                      final userId = users[i].id;
                      final isSelected = _selectedMembers.contains(userId);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) _selectedMembers.add(userId);
                            else _selectedMembers.remove(userId);
                          });
                        },
                        title: Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                        secondary: CircleAvatar(
                          backgroundColor: const Color(0xFFF0ABFC),
                          backgroundImage: (user['photoUrl'] as String? ?? '').isNotEmpty 
                              ? MemoryImage(base64Decode(user['photoUrl'])) 
                              : null,
                          child: (user['photoUrl'] as String? ?? '').isEmpty 
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)) 
                              : null,
                        ),
                        activeColor: const Color(0xFFD946EF),
                        checkColor: Colors.white,
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _createGroup,
        backgroundColor: const Color(0xFFD946EF),
        label: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Create Group", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.check, color: Colors.white),
      ),
    );
  }
}
