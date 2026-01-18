/// Chat message model
class Message {
  final int? id;
  final int userId;
  final int conversationId;
  final String content;
  final String role; // 'user' or 'assistant'
  final DateTime timestamp;
  bool isStreaming;

  Message({
    this.id,
    required this.userId,
    required this.conversationId,
    required this.content,
    required this.role,
    required this.timestamp,
    this.isStreaming = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      userId: json['user_id'],
      conversationId: json['conversation_id'],
      content: json['content'],
      role: json['role'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'conversation_id': conversationId,
      'content': content,
      'role': role,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  Message copyWith({String? content, bool? isStreaming}) {
    return Message(
      id: id,
      userId: userId,
      conversationId: conversationId,
      content: content ?? this.content,
      role: role,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
