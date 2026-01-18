/// User model for authentication
class User {
  final int id;
  final String username;
  final String email;
  final String? gender;
  final String token;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.gender,
    required this.token,
  });

  factory User.fromJson(Map<String, dynamic> json, String token) {
    return User(
      id: json['user_id'] ?? json['id'],
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      gender: json['gender'],
      token: token,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'gender': gender,
      'token': token,
    };
  }
}
