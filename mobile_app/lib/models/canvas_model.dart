class CanvasModel {
  final int id;
  final int userId;
  final String title;
  final String content;
  final String type; // 'markdown' or 'code'
  final DateTime createdAt;
  final DateTime updatedAt;

  CanvasModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CanvasModel.fromJson(Map<String, dynamic> json) {
    return CanvasModel(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'] ?? 'Untitled',
      content: json['content'] ?? '',
      type: json['type'] ?? 'markdown',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'content': content,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
