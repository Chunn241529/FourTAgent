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
  int? deepSearchStartIndex; // Index in 'thinking' string where Deep Search starts
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
  List<Map<String, String>> codeExecutions; // Code execution history
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
    List<Map<String, String>>? codeExecutions,
    this.deepSearchStartIndex,
  }) : activeSearches = activeSearches ?? [],
       completedSearches = completedSearches ?? [],
       completedFileActions = completedFileActions ?? [],
       deepSearchUpdates = deepSearchUpdates ?? [],
       generatedImages = generatedImages ?? [],
       codeExecutions = codeExecutions ?? [];

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

    Message msg = Message(
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
      codeExecutions: json['code_executions'] != null
          ? (json['code_executions'] as List).map((e) => Map<String, String>.from(e)).toList()
          : null,
      deepSearchStartIndex: json['deep_search_start_index'],
    );
    
    // Auto-fix for history loading:
    // If we have deep search updates but no start index, try to derive it.
    // Also extract PLAN from thinking if it was saved there.
    if (msg.deepSearchUpdates.isNotEmpty && msg.deepSearchStartIndex == null) {
       // Heuristic: If we have updates, assume deep search happened. 
       // If thinking contains "PLAN:", extract it.
       if (msg.thinking != null && msg.thinking!.contains('PLAN:\n')) {
          final parts = msg.thinking!.split('PLAN:\n');
          if (parts.length > 1) {
             final planPart = parts[1];
             // Check if there is a following section (e.g. Thinking)
             // The backend logic was: "PLAN:\n{plan}\n\n{thinking}" OR "PLAN:\n{plan}"
             
             // Try to find where "real" thinking starts (if any) or just use plan
             // It's tricky to separate perfectly without a clear delimiter for "THINKING:" 
             // if the original thinking didn't have a header.
             // But usually we just want to extract the plan.
             
             // Let's look for double newline as separator
             final endOfPlanIndex = planPart.indexOf('\n\n');
             if (endOfPlanIndex != -1) {
                final extractedPlan = planPart.substring(0, endOfPlanIndex);
                final remainingThinking = planPart.substring(endOfPlanIndex).trim();
                
                // Construct new message
                msg = msg.copyWith(
                   plan: extractedPlan,
                   thinking: remainingThinking,
                   deepSearchStartIndex: 0, // Plan is at start usually in this reconstruction
                );
             } else {
                // Whole thing is plan?
                msg = msg.copyWith(
                   plan: planPart.trim(),
                   thinking: '', // No thinking left?
                   deepSearchStartIndex: 0,
                );
             }
          }
       } else {
          // No PLAN marker, but has updates. 
          // Set index to 0 so "Thinking" (if any) is treated as Post-Search or Pre-Search?
          // If we have updates, usually the text content is the Final Report.
          // Thinking field contains the reasoning.
          // If we want to show Thinking -> UI -> Plan -> Thinking...
          // We need to know where to split.
          // If no index is saved, default to showing Deep Search UI at the TOP (index 0) 
          // or BOTTOM (index length)?
          // Let's default to top (0) so it's visible.
          msg = msg.copyWith(deepSearchStartIndex: 0);
       }
    }
    
    return msg;
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
      'deep_search_start_index': deepSearchStartIndex,
      'thinking': thinking,
      'generated_images': generatedImages,
      'code_executions': codeExecutions,
      'deep_search_updates': deepSearchUpdates,
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
    List<Map<String, String>>? codeExecutions,
    int? deepSearchStartIndex,
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
      codeExecutions: codeExecutions ?? this.codeExecutions,
      deepSearchStartIndex: deepSearchStartIndex ?? this.deepSearchStartIndex,
    );
  }
}


