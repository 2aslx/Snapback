import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../models/photo_item.dart';
import '../theme/app_theme.dart';

Uint8List? decodeDataUrl(String? dataUrl) {
  if (dataUrl == null || !dataUrl.contains(',')) return null;
  try {
    return base64Decode(dataUrl.split(',').last);
  } catch (_) {
    return null;
  }
}

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.item,
    this.onTap,
    this.width,
    this.height,
    this.showDate = true,
  });

  final PhotoItem item;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeDataUrl(item.thumbDataUrl);
    final grad = kTileGradients[item.id % kTileGradients.length];
    final label =
        item.date.length >= 2 ? item.date.substring(2) : item.date;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: bytes == null ? grad : null,
          image: bytes != null
              ? DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          children: [
            if (bytes == null)
              Center(
                child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
              ),
            if (showDate && label.isNotEmpty)
              Positioned(
                bottom: 4,
                left: 6,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SnapbackTopBar extends StatelessWidget {
  const SnapbackTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Row(
      children: [
        if (onBack != null)
          GestureDetector(
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '‹',
                style: TextStyle(fontSize: 24, color: c.ink, height: 1),
              ),
            ),
          ),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class SnapButton extends StatelessWidget {
  const SnapButton({
    super.key,
    required this.label,
    required this.onTap,
    this.ghost = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
          color: ghost ? c.soft : c.pri,
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: ghost ? c.pri : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class SnapOptionCard extends StatelessWidget {
  const SnapOptionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? c.soft : c.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? c.pri : c.line,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, color: c.ink),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: c.mute),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class SnapChip extends StatelessWidget {
  const SnapChip({
    super.key,
    required this.label,
    this.selected = false,
    this.dashed = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool dashed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: dashed ? Colors.transparent : (selected ? c.pri : c.soft),
          borderRadius: BorderRadius.circular(99),
          border: dashed ? Border.all(color: c.mute) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: dashed ? c.mute : (selected ? Colors.white : c.pri),
          ),
        ),
      ),
    );
  }
}

class SnapRowCard extends StatelessWidget {
  const SnapRowCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, color: c.ink)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 11.5, color: c.mute),
                    ),
                ],
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: TextStyle(
                  color: c.pri,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget buildIconBox(BuildContext context, String emoji, {int? gradIndex}) {
  final c = context.sc;
  return Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: gradIndex == null ? c.soft : null,
      gradient: gradIndex != null
          ? kTileGradients[gradIndex % kTileGradients.length]
          : null,
      borderRadius: BorderRadius.circular(11),
    ),
    alignment: Alignment.center,
    child: Text(emoji, style: const TextStyle(fontSize: 18)),
  );
}
