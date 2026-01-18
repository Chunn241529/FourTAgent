/// Chat message model
class Message {
  final int? id;
  final int userId;
  final int conversationId;
  final String content;
  final String role; // 'user' or 'assistant'
  final DateTime timestamp;
  bool isStreaming;
  String? feedback; // "like", "dislike", or null
  String? thinking; // AI thinking/reasoning content
  String? imageBase64; // Base64 encoded image for display
  List<String> activeSearches; // Active search queries being executed
  List<String> completedSearches; // Completed searches to keep visible

  Message({
    this.id,
    required this.userId,
    required this.conversationId,
    required this.content,
    required this.role,
    required this.timestamp,
    this.isStreaming = false,
    this.feedback,
    this.thinking,
    this.imageBase64,
    List<String>? activeSearches,
    List<String>? completedSearches,
  }) : activeSearches = activeSearches ?? [],
       completedSearches = completedSearches ?? [];

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      userId: json['user_id'],
      conversationId: json['conversation_id'],
      content: json['content'],
      role: json['role'],
      timestamp: DateTime.parse(json['timestamp']),
      feedback: json['feedback'],
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
      'feedback': feedback,
    };
  }

  Message copyWith({
    int? id,
    String? content,
    bool? isStreaming,
    String? feedback,
    String? thinking,
    String? imageBase64,
    List<String>? activeSearches,
    List<String>? completedSearches,
  }) {
    return Message(
      id: id ?? this.id,
      userId: userId,
      conversationId: conversationId,
      content: content ?? this.content,
      role: role,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      feedback: feedback ?? this.feedback,
      thinking: thinking ?? this.thinking,
      imageBase64: imageBase64 ?? this.imageBase64,
      activeSearches: activeSearches ?? this.activeSearches,
      completedSearches: completedSearches ?? this.completedSearches,
    );
  }
}


