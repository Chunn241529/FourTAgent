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
    // Server returns UTC time without 'Z' suffix, add it to parse as UTC then convert to local
    final utcString = json['created_at'].endsWith('Z') ? json['created_at'] : '${json['created_at']}Z';
    final utcTime = DateTime.parse(utcString);
    final localTime = utcTime.toLocal();
    
    return Conversation(
      id: json['id'],
      userId: json['user_id'],
      createdAt: localTime,
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
