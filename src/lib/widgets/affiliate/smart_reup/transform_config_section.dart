import 'package:flutter/material.dart';
import '../../../screens/affiliate/theme/affiliate_theme.dart';

class TransformConfigSection extends StatelessWidget {
  final Map<String, bool> configs;
  final Function(String, bool) onChanged;
  final String audioMode;
  final ValueChanged<String?> onAudioModeChanged;
  final String logoRemoval;
  final ValueChanged<String?> onLogoRemovalChanged;

  const TransformConfigSection({
    super.key,
    required this.configs,
    required this.onChanged,
    required this.audioMode,
    required this.onAudioModeChanged,
    required this.logoRemoval,
    required this.onLogoRemovalChanged,
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
              Icon(Icons.tune, color: AffiliateTheme.primary),
              const SizedBox(width: 8),
              Text('Smart Transformation', style: AffiliateTheme.titleStyle(context)),
            ],
          ),
          const SizedBox(height: 20),
          _buildTransformGrid(context),
          const Divider(height: 40),
          _buildDropdownSection(
            context,
            'Audio Mode',
            Icons.audiotrack,
            audioMode,
            {
              'strip': 'Strip Original',
              'shift': 'Pitch Shift',
            },
            onAudioModeChanged,
          ),
          const SizedBox(height: 16),
          _buildDropdownSection(
            context,
            'Logo Removal',
            Icons.blur_circular,
            logoRemoval,
            {
              'none': 'None',
              'manual': 'Manual Crop',
              'ai': 'AI Inpaint (Experimental)',
            },
            onLogoRemovalChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTransformGrid(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: configs.entries.map((e) {
        return _TransformChip(
          label: e.key.replaceAll('_', ' ').substring(0, 1).toUpperCase() + e.key.replaceAll('_', ' ').substring(1),
          value: e.value,
          onChanged: (val) => onChanged(e.key, val),
        );
      }).toList(),
    );
  }

  Widget _buildDropdownSection(
    BuildContext context,
    String label,
    IconData icon,
    String value,
    Map<String, String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AffiliateTheme.primary.withOpacity(0.7)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: options.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _TransformChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TransformChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = value;

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AffiliateTheme.primary : theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: active ? AffiliateTheme.primary : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: active ? Colors.white : theme.iconTheme.color?.withOpacity(0.5),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? Colors.white : theme.textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
