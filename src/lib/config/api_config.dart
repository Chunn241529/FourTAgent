/// API Configuration for FourT Chat App
class ApiConfig {
  // Change this to your backend URL
  // For local development: http://localhost:8000
  // For production: https://fourt.io.vn
  static String baseUrl = 'https://fourt.io.vn'; // Default to tunnel, but mutable
  
  static const String tunnelUrl = 'https://fourt.io.vn';
  static const String localUrl = 'http://localhost:8000';
  
  // Auth endpoints (prefix: /auth)
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verify = '/auth/verify';
  static const String forgetPassword = '/auth/forgetpw';
  static const String resetPassword = '/auth/reset-password';
  static const String validateToken = '/auth/validate-token';
  static const String devices = '/auth/devices';
  static const String changePassword = '/auth/change-password';
  static const String profile = '/auth/profile';
  static const String uploadAvatar = '/auth/upload-avatar';
  static const String resendCode = '/auth/resend-code';
  static const String deleteAccount = '/auth/delete-account';
  
  // Conversations endpoints
  static const String conversations = '/conversations';
  
  // Messages endpoints
  static const String messages = '/messages';
  
  // Chat endpoint
  static const String chat = '/send';
  static const String chatToolResult = '/send/tool_result';
  
  // Feedback endpoint
  static const String feedback = '/feedback';
  
  // Audio/Voice endpoints
  static const String transcribeAudio = '/voice/transcribe';
  
  // Cloud files endpoints
  static const String cloudFiles = '/cloud/files';
  static const String cloudFilesContent = '/cloud/files/content';
  static const String cloudFilesDownload = '/cloud/files/download';
  static const String cloudFilesUpload = '/cloud/files/upload';
  static const String cloudFilesStream = '/cloud/files/stream';
  static const String cloudFolders = '/cloud/folders';
  
  // Generation endpoints (Text/Image)
  static const String generateStream = '/generate/stream';
  static const String generateImageStudio = '/generate/image/studio';
  static const String editImageStudio = '/generate/image/edit/studio';
  static const String generatedImage = '/generate/image/view';

  // Translate endpoints
  static const String translate = '/generate/translate/stream';
  
  // TTS endpoints
  static const String ttsTurboVoices = '/tts/turbo/voices';
  static const String ttsHqVoices = '/tts/hq/voices';
  static const String ttsTurboSynthesize = '/tts/turbo/synthesize';
  static const String ttsHqSynthesize = '/tts/hq/synthesize';
  
  // Affiliate / Automation endpoints
  static const String affiliateStatus = '/affiliate/status';
  static const String affiliateScrape = '/affiliate/scrape';
  static const String affiliateProducts = '/affiliate/products';
  static const String affiliateGenerateScript = '/affiliate/generate-script';
  static const String affiliateRenderVideo = '/affiliate/render-video';
  static const String affiliateJobs = '/affiliate/jobs';
  static const String affiliateGenerateAiVideo = '/affiliate/generate-ai-video';
  static const String affiliateAiVideoJobs = '/affiliate/ai-video-jobs';
  static const String affiliateSmartReupTransforms = '/affiliate/smart-reup/transforms';
  static const String affiliateSmartReup = '/affiliate/smart-reup';
  static const String affiliateSmartReupDouyin = '/affiliate/smart-reup-douyin';
  static const String affiliateSmartReupExtractFrame = '/affiliate/smart-reup/extract-frame';
  static const String affiliateUploadSubtitle = '/affiliate/upload-subtitle';
  static const String affiliateUploadModelImage = '/affiliate/upload-model-image';
  static const String affiliateLlmProviders = '/affiliate/llm-providers';
}
