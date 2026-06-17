class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final String bio;
  final bool isOnline;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.bio = 'Hey there! I am using AegisQ',
    this.isOnline = false,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? 'User',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      bio: data['bio'] ?? 'Hey there! I am using AegisQ',
      isOnline: data['isOnline'] ?? false,
    );
  }
}
