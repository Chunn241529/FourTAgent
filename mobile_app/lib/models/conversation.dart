/// Conversation model
class Conversation {
  final int id;
  final int userId;
  final DateTime createdAt;
  String? title; // Derived from first message

  Conversation({
    required this.id,
    required this.userId,
    required this.createdAt,
    this.title,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      userId: json['user_id'],
      createdAt: DateTime.parse(json['created_at']),
      title: json['title'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'title': title,
    };
  }
}
