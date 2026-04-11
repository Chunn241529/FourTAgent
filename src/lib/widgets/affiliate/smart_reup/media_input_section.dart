import 'dart:io';
import 'package:flutter/material.dart';
import '../../../screens/affiliate/theme/affiliate_theme.dart';

class MediaInputSection extends StatelessWidget {
  final String? url;
  final File? videoFile;
  final TextEditingController urlController;
  final VoidCallback onPickVideo;
  final VoidCallback onPaste;
  final ValueChanged<String> onUrlChanged;

  const MediaInputSection({
    super.key,
    required this.url,
    required this.videoFile,
    required this.urlController,
    required this.onPickVideo,
    required this.onPaste,
    required this.onUrlChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AffiliateTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, color: AffiliateTheme.primary),
              const SizedBox(width: 8),
              Text('Video Input', style: AffiliateTheme.titleStyle(context)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: urlController,
            onChanged: onUrlChanged,
            decoration: InputDecoration(
              hintText: 'Paste Douyin/TikTok URL here...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: onPaste,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('OR', style: AffiliateTheme.subtitleStyle(context)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: onPickVideo,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AffiliateTheme.primary.withOpacity(0.3),
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(16),
                color: AffiliateTheme.primary.withOpacity(0.02),
              ),
              child: Column(
                children: [
                  Icon(
                    videoFile != null ? Icons.check_circle : Icons.cloud_upload_outlined,
                    size: 48,
                    color: videoFile != null ? Colors.green : AffiliateTheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    videoFile != null ? videoFile!.path.split('/').last : 'Upload local video',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: videoFile != null ? Colors.green : AffiliateTheme.primary,
                    ),
                  ),
                  Text(
                    'MP4, MOV supported',
                    style: AffiliateTheme.subtitleStyle(context).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
