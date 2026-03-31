/// User model for authentication
class User {
  final int id;
  final String username;
  final String email;
  final String? gender;
  final String token;
  final String? phoneNumber;
  final String? fullName;
  final String? avatar;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.gender,
    required this.token,
    this.phoneNumber,
    this.fullName,
    this.avatar,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json, String token) {
    return User(
      id: json['user_id'] ?? json['id'],
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      gender: json['gender'],
      token: token,
      phoneNumber: json['phone_number'],
      fullName: json['full_name'],
      avatar: json['avatar'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'gender': gender,
      'token': token,
      'phone_number': phoneNumber,
      'full_name': fullName,
      'avatar': avatar,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
