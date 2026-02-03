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
  List<String> completedFileActions; // Completed file actions (READ:path, CREATE:path)
  List<String> deepSearchUpdates; // Deep Search status logs
  String? plan; // Research plan for Deep Search
  final String? toolName;
  final String? toolCallId;
  final dynamic toolCalls;
  List<String> generatedImages; // Generated images from ComfyUI
  bool isGeneratingImage;
  String? generationError;

  Message({
    this.id,
    required this.userId,
    required this.conversationId,
    required this.content,
    required this.role,
    required this.timestamp,
    this.isStreaming = false,
    this.isGeneratingImage = false,
    this.generationError,
    this.feedback,
    this.thinking,
    this.imageBase64,
    List<String>? activeSearches,
    List<String>? completedSearches,
    List<String>? completedFileActions,
    List<String>? deepSearchUpdates,
    this.plan,
    this.toolName,
    this.toolCallId,
    this.toolCalls,
    List<String>? generatedImages,
  }) : activeSearches = activeSearches ?? [],
       completedSearches = completedSearches ?? [],
       completedFileActions = completedFileActions ?? [],
       deepSearchUpdates = deepSearchUpdates ?? [],
       generatedImages = generatedImages ?? [];

  factory Message.fromJson(Map<String, dynamic> json) {
    // Reconstruct completed searches from tool calls
    List<String> reconstructedSearches = [];
    if (json['tool_calls'] != null) {
      final calls = json['tool_calls'];
      if (calls is List) {
        for (var call in calls) {
          if (call is Map && 
              call['function'] != null && 
              call['function']['name'] == 'web_search') {
             try {
                final args = call['function']['arguments'];
                if (args is Map && args['query'] is String) {
                   reconstructedSearches.add(args['query']);
                } else if (args is String) {
                   // Try to extract query from string if possible, or ignore complexity for now
                   // In backend we ensure args is usually parsed or we can try limited parsing
                }
             } catch (_) {}
          }
        }
      }
    }

    return Message(
      id: json['id'],
      userId: json['user_id'],
      conversationId: json['conversation_id'],
      content: json['content'],
      role: json['role'],
      timestamp: DateTime.parse(json['timestamp']),
      feedback: json['feedback'],
      toolName: json['tool_name'],
      toolCallId: json['tool_call_id'],
      toolCalls: json['tool_calls'],
      thinking: json['thinking'],
      generatedImages: json['generated_images'] != null 
          ? List<String>.from(json['generated_images']) 
          : null,
      completedSearches: reconstructedSearches,
      deepSearchUpdates: json['deep_search_updates'] != null
          ? List<String>.from(json['deep_search_updates'])
          : null,
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
      'tool_name': toolName,
      'tool_call_id': toolCallId,
      'tool_calls': toolCalls,
    };
  }

  Message copyWith({
    int? id,
    String? content,
    bool? isStreaming,
    bool? isGeneratingImage,
    String? generationError,
    String? feedback,
    String? thinking,
    String? imageBase64,
    List<String>? activeSearches,
    List<String>? completedSearches,
    List<String>? completedFileActions,
    List<String>? deepSearchUpdates,
    String? plan,
    String? toolName,
    String? toolCallId,
    dynamic toolCalls,
    List<String>? generatedImages,
  }) {
    return Message(
      id: id ?? this.id,
      userId: userId,
      conversationId: conversationId,
      content: content ?? this.content,
      role: role,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
      generationError: generationError ?? this.generationError,
      feedback: feedback ?? this.feedback,
      thinking: thinking ?? this.thinking,
      imageBase64: imageBase64 ?? this.imageBase64,
      activeSearches: activeSearches ?? this.activeSearches,
      completedSearches: completedSearches ?? this.completedSearches,
      completedFileActions: completedFileActions ?? this.completedFileActions,
      deepSearchUpdates: deepSearchUpdates ?? this.deepSearchUpdates,
      plan: plan ?? this.plan,
      toolName: toolName ?? this.toolName,
      toolCallId: toolCallId ?? this.toolCallId,
      toolCalls: toolCalls ?? this.toolCalls,
      generatedImages: generatedImages ?? this.generatedImages,
    );
  }
}


