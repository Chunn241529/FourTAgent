import 'package:flutter/material.dart';

/// Modern message input - input on top, icons on bottom
class MessageInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isLoading;
  final VoidCallback? onStop;

  const MessageInput({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onStop,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewPadding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8),
        borderRadius: BorderRadius.circular(16),
        // No border, no shadow
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text input
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              minLines: 3,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Nhắn tin cho FourT AI...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              ),
              enabled: !widget.isLoading,
            ),
            // Icons row
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 6),
              child: Row(
                children: [
                  _IconBtn(
                    icon: Icons.add_circle_outline,
                    onTap: () {},
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  _IconBtn(
                    icon: Icons.image_outlined,
                    onTap: () {},
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  _IconBtn(
                    icon: Icons.mic_none_outlined,
                    onTap: () {},
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const Spacer(),
                  widget.isLoading
                      ? _buildStopButton(theme)
                      : _buildSendButton(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme) {
    final canSend = _hasText && !widget.isLoading;
    
    return Material(
      color: canSend ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: canSend ? _send : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            Icons.arrow_upward_rounded,
            color: canSend ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.3),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildStopButton(ThemeData theme) {
    return Material(
      color: theme.colorScheme.error,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: widget.onStop,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: const Icon(
            Icons.stop_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 22),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}
