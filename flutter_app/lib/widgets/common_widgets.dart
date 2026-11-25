import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../models/photo_item.dart';
import '../theme/app_theme.dart';
import 'photo_image.dart';
import 'icon_paths.g.dart';

// 이 파일의 위젯은 index.html(2aslx-patch-1) 의 CSS 클래스와 1:1 대응한다.
// 주석의 선택자(.row, .sbar …)가 원본 스타일 위치.

Uint8List? decodeDataUrl(String? dataUrl) {
  if (dataUrl == null || !dataUrl.startsWith('data:')) return null;
  final i = dataUrl.indexOf(',');
  if (i < 0) return null;
  try {
    return base64Decode(dataUrl.substring(i + 1));
  } catch (_) {
    return null;
  }
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// .i — 24×24 라인 아이콘 (stroke 1.8, round). [name] 은 `<symbol id="i-name">`.
class SnapIcon extends StatelessWidget {
  const SnapIcon(
    this.name, {
    super.key,
    this.size = 18,
    this.color,
    this.strokeWidth = 1.8,
  });

  final String name;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c =
        color ?? DefaultTextStyle.of(context).style.color ?? context.sc.ink;
    final body = kIconPaths[name] ?? kIconPaths['image']!;
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="${_hex(c)}" stroke-width="$strokeWidth" '
        'stroke-linecap="round" stroke-linejoin="round" color="${_hex(c)}">'
        '${body.replaceAll('currentColor', _hex(c))}</svg>';
    return Opacity(
      opacity: c.a,
      child: SvgPicture.string(svg, width: size, height: size),
    );
  }
}

/// 누르면 opacity .6 (.btn:active, .chip:active, .row:active …)
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedOpacity(
        opacity: _down ? 0.6 : 1,
        duration: const Duration(milliseconds: 150),
        child: widget.child,
      ),
    );
  }
}

/// 화면 좌우 패딩(16)을 넘어 가장자리까지 채우는 영역 (margin: 0 -16px).
class Bleed extends StatelessWidget {
  const Bleed({super.key, required this.child, this.inset = 16});
  final Widget child;
  final double inset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, k) => SizedBox(
      width: k.maxWidth,
      child: OverflowBox(
        fit: OverflowBoxFit.deferToChild,
        minWidth: k.maxWidth + inset * 2,
        maxWidth: k.maxWidth + inset * 2,
        child: child,
      ),
    ),
  );
}

/// 한글 줄바꿈을 단어 단위로: Flutter 는 한글을 글자마다 끊어 '친구 / 와'처럼 단어가 쪼개진다.
/// 단어 안의 글자 사이에 보이지 않는 연결 문자(U+2060)를 넣어 띄어쓰기에서만 줄이 바뀌게 한다.
/// (화면 표시용 글자에만 쓰고, 입력칸·저장 값에는 쓰지 않는다)
String keepWords(String text) {
  if (!RegExp(r'[가-힣]').hasMatch(text)) return text;
  return text
      .split(' ')
      .map((w) => w.length < 2 ? w : w.split('').join('\u2060'))
      .join(' ');
}

/// 화면 전환 방향: 상단 뒤로가기 버튼으로 바뀌는 화면이면 true (셸이 '오른쪽으로 밀리는' 효과를 씀)
class SnapNav {
  static bool backPending = false;

  static void markBack() {
    backPending = true;
    // 화면이 바뀌지 않았으면 이번 프레임이 끝날 때 원래대로
    WidgetsBinding.instance.addPostFrameCallback((_) => backPending = false);
  }
}

/// .top — 가운데 제목(17/600) + 왼쪽 뒤로가기(< 아이콘) + 오른쪽 보조 텍스트
class SnapbackTopBar extends StatelessWidget {
  const SnapbackTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.leadingIcon,
    this.titleWidget,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? leadingIcon;

  /// 제목 자리에 글자 대신 넣을 위젯 (예: 앨범 이름 바로 편집)
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    // margin:-8px 0 8px — 위로 8 당겨진 44 높이. 아래 여백 8은 다음 요소의
    // margin-top 과 겹치므로(CSS margin collapse) 여기서는 36만 차지한다.
    return SizedBox(
      height: 36,
      child: OverflowBox(
        alignment: Alignment.bottomCenter,
        minHeight: 44,
        maxHeight: 44,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leadingIcon != null) ...[
                      SnapIcon(leadingIcon!, size: 19.5, color: c.ink),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child:
                          titleWidget ??
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              color: c.ink,
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              // 뒤로가기: 아이콘 주변까지 넓게 눌리도록 72 × 막대 높이 전체를 터치 영역으로
              if (onBack != null)
                Positioned(
                  left: -8,
                  top: 0,
                  bottom: 0,
                  width: 72,
                  child: Pressable(
                    onTap: () {
                      SnapNav.markBack();
                      onBack!();
                    },
                    child: Align(
                      alignment: const Alignment(-1, 0.25),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: SnapIcon(
                          'back',
                          size: 26,
                          color: c.pk,
                          strokeWidth: 2.2,
                        ),
                      ),
                    ),
                  ),
                ),
              if (trailing != null)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.mute,
                      ),
                      child: trailing!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// .lt .large — 큰 제목(기본 30/700, Inter) + 왼쪽 캐릭터(선택) + 원형 버튼(.tbtn)들
class LargeTitle extends StatelessWidget {
  const LargeTitle({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.fontSize = 30,
    this.fontWeight = FontWeight.w700,
  });
  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                letterSpacing: fontSize > 24 ? -0.8 : -0.3,
                height: 1.1,
                color: c.ink,
              ),
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 10), a],
        ],
      ),
    );
  }
}

/// .tbtn — 34 원형, fill 배경, pk 아이콘
class TitleButton extends StatelessWidget {
  const TitleButton({super.key, required this.icon, this.onTap});
  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    // 디자인 B3 — 배경 없는 검은 선 아이콘 (누르는 영역은 40×40)
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(child: SnapIcon(icon, size: 26, color: c.ink)),
      ),
    );
  }
}

/// h2 — 30/800, -0.6
class SnapH2 extends StatelessWidget {
  const SnapH2(this.text, {super.key, this.fontSize = 30});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.2,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w800,
        color: context.sc.ink,
      ),
    ),
  );
}

/// h3 — 20/700, margin 24 0 10, 아이콘 gap 6
class SnapH3 extends StatelessWidget {
  const SnapH3(
    this.text, {
    super.key,
    this.icon,
    this.trailing,
    this.small = false,
  });
  final String text;
  final String? icon;
  final String? trailing; // "(3)" 같은 개수
  final bool small; // #set h3: 13/400 mute, margin 24 14 6

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    if (small) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 24, 14, 6),
        child: Text(text, style: TextStyle(fontSize: 13, color: c.mute)),
      );
    }
    final style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: c.ink,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            SnapIcon(icon!, size: 23, color: c.ink),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(text, style: style)),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Text(trailing!, style: style),
          ],
        ],
      ),
    );
  }
}

/// .sub — 15, mute, line-height 1.45
class SnapSub extends StatelessWidget {
  const SnapSub(this.text, {super.key, this.center = false});
  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
    keepWords(text),
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: TextStyle(fontSize: 15, height: 1.45, color: context.sc.mute),
  );
}

/// .note — 13, mute, 가운데, margin-top 9
class SnapNote extends StatelessWidget {
  const SnapNote(this.text, {super.key, this.icon, this.color, this.top = 9});
  final String text;
  final String? icon;
  final Color? color;
  final double top;

  @override
  Widget build(BuildContext context) {
    final col = color ?? context.sc.mute;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Text.rich(
        TextSpan(
          children: [
            if (icon != null) ...[
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SnapIcon(icon!, size: 15, color: col),
              ),
              const TextSpan(text: ' '),
            ],
            TextSpan(text: keepWords(text)),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: col),
      ),
    );
  }
}

/// .btn — min 50, r14, 17/600, margin-top 16. ghost = .btn.g (fill 배경, pk 글자)
class SnapButton extends StatelessWidget {
  const SnapButton({
    super.key,
    required this.label,
    required this.onTap,
    this.ghost = false,
    this.icon,
    this.top = 16,
  });

  final String label;
  final VoidCallback? onTap;
  final bool ghost;
  final String? icon;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final fg = ghost ? c.pk : Colors.white;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Pressable(
        onTap: onTap ?? () {},
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1, // 누를 수 없는 상태는 흐리게
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ghost ? c.fill : c.pri,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  SnapIcon(icon!, size: 19.5, color: fg),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// .ic — 30×30, r8, 흰 아이콘. 그라데이션 인덱스가 없으면 pri 배경.
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.gradIndex,
    this.size = 30,
    this.radius = 8,
    this.image,
  });
  final String icon;
  final int? gradIndex;
  final double size;
  final double radius;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: image != null
            ? c.card
            : (gradIndex == null ? c.pri : null),
        gradient: image == null && gradIndex != null
            ? kTileGradients[gradIndex! % 6]
            : null,
        borderRadius: BorderRadius.circular(radius),
        // 작은 썸네일은 칸에 꽉 차게
        image: image != null
            ? DecorationImage(image: image!, fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: image != null
          ? null
          : SnapIcon(icon, size: size * 0.65, color: Colors.white),
    );
  }
}

/// .row / .opt 를 묶는 iOS 그룹 (첫 행 위 r13 · 마지막 행 아래 r13 · 0.5px 구분선)
class SnapGroup extends StatelessWidget {
  const SnapGroup({
    super.key,
    required this.children,
    this.top = 12,
    this.separatorInset = 56,
  });
  final List<Widget> children;
  final double top;
  final double separatorInset;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ColoredBox(
          color: c.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: EdgeInsets.only(left: separatorInset),
                    child: Container(height: 0.5, color: c.line),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// .row / .opt 한 줄 — padding 11 14, font 16, gap 12, min 48
class SnapRow extends StatelessWidget {
  const SnapRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitle2,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.checked,
    this.titleWidget,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? subtitle2;
  final String? trailingText; // .r — pk 13/600
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? checked; // .opt[data-sel] — 선택 시 오른쪽 ✓
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    Widget? small(String? s) => s == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(s, style: TextStyle(fontSize: 13, color: c.mute)),
          );
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  titleWidget ??
                      Text(title, style: TextStyle(fontSize: 16, color: c.ink)),
                  ?small(subtitle),
                  ?small(subtitle2),
                ],
              ),
            ),
            if (trailingText != null) ...[
              const SizedBox(width: 12),
              Text(
                trailingText!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.pk,
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (checked != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 20,
                height: 20,
                child: checked!
                    ? SnapIcon('check', size: 20, color: c.pk, strokeWidth: 2.6)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// › (pk) — 행 오른쪽 이동 표시
class Chevron extends StatelessWidget {
  const Chevron({super.key});
  @override
  Widget build(BuildContext context) =>
      Text('›', style: TextStyle(fontSize: 16, color: context.sc.pk));
}

/// .chip — fill 배경 · ink 14/500 · pad 7 13. 선택 시 ink 배경 · bg 글자.
/// [card] = .sugg .chip (card 배경 + 0.5px 테두리), [dashed] = "기억 안 나요"
class SnapChip extends StatelessWidget {
  const SnapChip({
    super.key,
    required this.label,
    this.selected = false,
    this.dashed = false,
    this.card = false,
    this.icon,
    this.onTap,
    this.onLongPress,
    this.accent = false,
  });

  final String label;
  final bool selected;
  final bool dashed;
  final bool card;
  final String? icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 선택 시 테라코타(pri) 배경 + 흰 글씨 (앨범 카테고리 필터)
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final fg = dashed
        ? c.mute
        : selected
        ? (accent ? Colors.white : c.bg)
        : c.ink;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: dashed
              ? null
              : selected
              ? (accent ? c.pri : c.ink)
              : (card ? c.card : c.fill),
          borderRadius: BorderRadius.circular(99),
          border: dashed
              ? Border.all(color: c.mute)
              : card
              ? Border.all(color: c.line, width: 0.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              SnapIcon(icon!, size: 16, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// .sbar — fill 배경 r12. 입력형(.sbar.in)은 오른쪽에 32 원형 pri 버튼.
class SnapSearchBar extends StatelessWidget {
  const SnapSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = '',
    this.enabled = true,
    this.showIcon = true,
    this.buttonIcon = 'arrow',
    this.buttonText,
    this.busy = false,
    this.onSubmit,
    this.onChanged,
    this.keyboardType,
    this.showButton = false,
  });

  /// enabled 가 false(누르면 이동하는 표시용 바)여도 오른쪽 주황 화살표를 보여줌 (홈 검색창)
  final bool showButton;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final bool enabled; // false = 누르면 이동하는 표시용 바 (.sbar)
  final bool showIcon;
  final String buttonIcon;
  final String? buttonText;
  final bool busy;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      // 입력칸 밖(화면 다른 곳)을 누르면 키보드를 내린다
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      readOnly: !enabled,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSubmit?.call(),
      onChanged: onChanged,
      style: TextStyle(fontSize: 17, height: 1.2, color: c.ink),
      decoration: InputDecoration(
        isCollapsed: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 17, height: 1.2, color: c.mute),
        border: InputBorder.none,
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: enabled || showButton
          ? const EdgeInsets.fromLTRB(20, 6, 6, 6)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          if (showIcon) ...[
            SnapIcon('search', size: 19.5, color: c.mute),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: IgnorePointer(ignoring: !enabled, child: field),
          ),
          if (enabled || showButton) ...[
            const SizedBox(width: 7),
            Pressable(
              onTap: enabled ? onSubmit : null,
              child: Opacity(
                opacity: busy ? 0.5 : 1,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.pri,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: buttonText != null
                      ? Text(
                          buttonText!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                          ),
                        )
                      : SnapIcon(buttonIcon, size: 19.5, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// .ph — 사진 타일 (그라데이션 + 흰 아이콘, 또는 썸네일). small = 날짜 라벨.
class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.item,
    this.onTap,
    this.width,
    this.height,
    this.showDate = true,
    this.radius = 11,
    this.iconSize = 30,
    this.label,
    this.fit = BoxFit.cover,
  });

  /// 썸네일·그리드는 cover(칸에 꽉 차게), 크게 보는 사진은 contain(전체가 보이게)
  final BoxFit fit;
  final PhotoItem item;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final bool showDate;
  final double radius;
  final double iconSize;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text =
        label ?? (item.date.length >= 2 ? item.date.substring(2) : item.date);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, k) {
          // 칸 크기에 맞는 화질로 불러온다 (iOS 원본 / 웹 1080 미리보기 / 썸네일)
          final w = width ?? (k.hasBoundedWidth ? k.maxWidth : 120);
          final h = height ?? (k.hasBoundedHeight ? k.maxHeight : w);
          final provider = photoImageProvider(
            item,
            logicalSize: math.max(w, h),
            dpr: dpr,
          );
          return _tile(provider, text, context.sc.card);
        },
      ),
    );
  }

  Widget _tile(ImageProvider? provider, String text, Color letterbox) {
    final bytes = provider;
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        // 사진이 없으면 그라데이션. 전체 보기(contain)일 때 남는 곳은 옅은 바탕
        color: bytes != null ? letterbox : null,
        gradient: bytes == null ? kTileGradients[item.id % 6] : null,
        image: bytes != null
            ? DecorationImage(image: bytes, fit: fit, onError: (_, _) {})
            : null,
      ),
      child: Stack(
        children: [
          if (bytes == null)
            Center(
              child: Opacity(
                opacity: 0.92,
                child: SnapIcon(
                  item.icon,
                  size: iconSize,
                  color: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
            ),
          if (showDate)
            Positioned(
              left: 6,
              bottom: 4,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Color(0x77000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
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

/// .grid — 3열, gap 2, 가장자리까지 (모서리 없음, 날짜 숨김)
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.items, this.onTap, this.selected});
  final List<PhotoItem> items;
  final void Function(PhotoItem)? onTap;

  /// 선택 모드: null 이 아니면 각 타일에 선택 표시 (선택된 사진은 주황 테두리 + 체크)
  final Set<int>? selected;

  // 디자인 B3 — 둥근 모서리 타일 3열, 사이 간격 6
  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final tile = PhotoTile(
          item: items[i],
          radius: 16,
          showDate: false,
          onTap: onTap == null ? null : () => onTap!(items[i]),
        );
        final sel = selected;
        if (sel == null) return tile;
        final on = sel.contains(items[i].id);
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: on ? 0.6 : 1, child: tile),
            if (on)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.pri, width: 3),
                  ),
                ),
              ),
            Positioned(
              top: 7,
              right: 7,
              child: IgnorePointer(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on ? c.pri : const Color(0x99FFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: on
                      ? const SnapIcon(
                          'check',
                          size: 13,
                          color: Colors.white,
                          strokeWidth: 2.6,
                        )
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 확인 팝업 (예: 삭제). 확인을 누르면 true.
Future<bool> showSnapConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '삭제',
  bool destructive = true,
}) async {
  final c = context.sc;
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => Dialog(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: c.mute),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SnapButton(
                    label: '취소',
                    ghost: true,
                    top: 0,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Pressable(
                    onTap: () => Navigator.of(ctx).pop(true),
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: destructive ? const Color(0xFFD93A2B) : c.pri,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

/// .hs — 가로 스크롤 타일 (88, r10, gap 6)
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.items, this.onTap});
  final List<PhotoItem> items;
  final void Function(PhotoItem)? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 92,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) => PhotoTile(
        item: items[i],
        width: 88,
        height: 88,
        radius: 10,
        iconSize: 24,
        onTap: onTap == null ? null : () => onTap!(items[i]),
      ),
    ),
  );
}

/// .sw — iOS 스위치 51×31, 켜짐 #34c759
class SnapSwitch extends StatelessWidget {
  const SnapSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 51,
        height: 31,
        decoration: BoxDecoration(
          color: value ? const Color(0xFF34C759) : c.line,
          borderRadius: BorderRadius.circular(99),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 27,
            height: 27,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// .st — 통계 상자 (card, r13, 숫자 20 / 라벨 12 mute)
class StatBoxes extends StatelessWidget {
  const StatBoxes({super.key, required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[i].$1,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      items[i].$2,
                      style: TextStyle(fontSize: 12, color: c.mute),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// .bub — 말풍선 (bot: card, 왼쪽 아래 4 / me: pri, 오른쪽 아래 4)
class SnapBubble extends StatelessWidget {
  const SnapBubble({super.key, required this.child, this.isMe = false});
  final Widget child;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.88,
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 7),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: isMe ? c.pri : c.card,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(19),
                topRight: const Radius.circular(19),
                bottomLeft: Radius.circular(isMe ? 19 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 19),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: isMe ? Colors.white : c.ink,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// .bar — 진행 막대 (h5, line 배경, pri 채움)
class SnapBar extends StatelessWidget {
  const SnapBar({
    super.key,
    required this.value,
    this.height = 5,
    this.background,
    this.color,
  });
  final double value;
  final double height;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: height,
        color: background ?? c.line,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(color: color ?? c.pri),
        ),
      ),
    );
  }
}

/// .tag — fill 배경 알약 (13, pad 5 10)
class SnapTag extends StatelessWidget {
  const SnapTag({super.key, required this.label, this.icon});
  final String label;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Container(
      margin: const EdgeInsets.only(right: 4, bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            SnapIcon(icon!, size: 15, color: c.ink),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 13, color: c.ink)),
        ],
      ),
    );
  }
}

/// .empty — 가운데 안내 (아이콘 44, stroke 1.4)
class SnapEmpty extends StatelessWidget {
  const SnapEmpty({super.key, required this.icon, required this.text});
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    // 부모가 왼쪽 정렬이어도 항상 가로 전체를 차지해 가운데 정렬 (.empty)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 40),
      child: Column(
        children: [
          SnapIcon(icon, size: 44, color: c.mute, strokeWidth: 1.4),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45, color: c.mute),
          ),
        ],
      ),
    );
  }
}

/// .warn — 경고 상자
class SnapWarn extends StatelessWidget {
  const SnapWarn(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEFD6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Color(0xFF8A5200)),
    ),
  );
}

/// .hero — 280 높이, 가장자리까지
class SnapHero extends StatelessWidget {
  const SnapHero({super.key, required this.item});
  final PhotoItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Bleed(
      child: PhotoTile(
        item: item,
        height: 280,
        radius: 0,
        showDate: false,
        iconSize: 66,
      ),
    ),
  );
}

/// .map — 사선 줄무늬 지도 자리
class SnapMapBox extends StatelessWidget {
  const SnapMapBox({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: CustomPaint(
          painter: _StripePainter(c.soft, c.card),
          child: SizedBox(
            height: 90,
            width: double.infinity,
            child: Center(child: SnapIcon('pin', size: 30, color: c.ink)),
          ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.a, this.b);
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = b);
    // repeating-linear-gradient(45deg, a 0 10px, b 10px 20px)
    final p = Paint()
      ..color = a
      ..strokeWidth = 10;
    const step = 20 * 1.41421356;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) => old.a != a || old.b != b;
}

/// 앨범 카드 — 대표사진 1장 + 뒤에 사진이 겹쳐 쌓인 모양 + 이름 + "사진 N장".
/// 일반 사진 썸네일과 구분되도록 뒤쪽 두 장이 위로 살짝 보인다.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.cover,
    required this.title,
    required this.count,
    this.onTap,
    this.badge,
    this.locked = false,
  });

  /// 잠긴 앨범: 대표사진·장수를 숨기고 자물쇠만 보여 준다
  final bool locked;

  final PhotoItem cover;
  final String title;
  final int count;
  final VoidCallback? onTap;

  /// 이름 옆 작은 표시 (예: 카테고리)
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    Widget layer(double inset, double top, double t) => Positioned(
      left: inset,
      right: inset,
      top: top,
      bottom: 14 - top,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(c.pri, c.bg, t),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.bg, width: 1.5),
        ),
      ),
    );
    return Pressable(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1 / 1.06,
            child: Stack(
              fit: StackFit.expand,
              children: [
                layer(16, 0, 0.72),
                layer(8, 7, 0.5),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 14,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.bg, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: locked
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: ColoredBox(
                              color: c.card,
                              child: Center(
                                child: SnapIcon(
                                  'lock',
                                  size: 30,
                                  color: c.mute,
                                ),
                              ),
                            ),
                          )
                        : PhotoTile(item: cover, radius: 11, showDate: false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [locked ? '잠긴 앨범' : '사진 $count장', ?badge].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: c.mute),
          ),
        ],
      ),
    );
  }
}

/// 앨범 카드 2열 배치 (홀수 개면 마지막 칸은 비움 → 카드 크기 일정)
class AlbumCardGrid extends StatelessWidget {
  const AlbumCardGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 14),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ],
  );
}

/// 오른쪽 스크롤 바 + 날짜 말풍선 (사진 보관함 그리드용).
/// 손잡이를 끌거나 막대를 눌러 원하는 위치로 바로 이동하고, 스크롤하는 동안 [labelAt] 이 준
/// 날짜(그 위치에 보이는 사진의 촬영 날짜)를 손잡이 옆에 띄운다. 멈추면 잠시 뒤 말풍선만 사라진다.
class DateScrollbar extends StatefulWidget {
  const DateScrollbar({
    super.key,
    required this.controller,
    required this.labelAt,
  });
  final ScrollController controller;
  final String Function(double offset) labelAt;

  @override
  State<DateScrollbar> createState() => _DateScrollbarState();
}

class _DateScrollbarState extends State<DateScrollbar> {
  static const _thumbH = 46.0;
  bool _dragging = false;
  bool _showLabel = true; // 처음 열었을 때도 잠깐 보여줌
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    _scheduleHide();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hide?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() => _showLabel = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_dragging) setState(() => _showLabel = false);
    });
  }

  void _jumpTo(double dy, double trackH) {
    final p = widget.controller.position;
    final frac = ((dy - _thumbH / 2) / (trackH - _thumbH)).clamp(0.0, 1.0);
    widget.controller.jumpTo(frac * p.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return LayoutBuilder(
      builder: (context, k) {
        final ctl = widget.controller;
        if (!ctl.hasClients || !ctl.position.hasContentDimensions) {
          // 첫 프레임: 크기를 안 뒤 다시 그림
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          return const SizedBox.shrink();
        }
        final p = ctl.position;
        if (p.maxScrollExtent <= 0) return const SizedBox.shrink();
        final h = k.maxHeight;
        final frac = (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
        final top = (h - _thumbH) * frac;
        return Stack(
          children: [
            // 누르거나 끌 수 있는 막대 영역 (오른쪽 28)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 28,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) {
                  setState(() => _dragging = true);
                  _jumpTo(d.localPosition.dy, h);
                },
                onVerticalDragUpdate: (d) => _jumpTo(d.localPosition.dy, h),
                onVerticalDragEnd: (_) {
                  setState(() => _dragging = false);
                  _scheduleHide();
                },
                onTapDown: (d) => _jumpTo(d.localPosition.dy, h),
              ),
            ),
            // 손잡이
            Positioned(
              right: 3,
              top: top,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _dragging ? 8 : 6,
                  height: _thumbH,
                  decoration: BoxDecoration(
                    color: _dragging ? c.pri : c.ink.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            // 날짜 말풍선
            Positioned(
              right: 18,
              top: top + _thumbH / 2 - 16,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showLabel || _dragging ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.labelAt(p.pixels),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 크게 보는 사진 (검색된 사진 · 사진 상세 · 나의 기록): 가로 폭에 맞추고 높이는 사진 비율대로 → 사진 전체가 보인다.
/// 비율은 iOS 원본 크기(assetW/H)로, 없으면(웹 등) 이미지를 불러와 실제 크기로 정한다.
class FullWidthPhoto extends StatefulWidget {
  const FullWidthPhoto({
    super.key,
    required this.item,
    this.radius = 18,
    this.fallbackHeight = 280,
    this.maxHeight = 560,
    this.overlay = const [],
  });

  final PhotoItem item;
  final double radius;
  final double fallbackHeight;
  final double maxHeight;
  final List<Widget> overlay;

  @override
  State<FullWidthPhoto> createState() => _FullWidthPhotoState();
}

class _FullWidthPhotoState extends State<FullWidthPhoto> {
  double? _aspect; // 가로 / 세로
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FullWidthPhoto old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _aspect = null;
      _resolve();
    }
  }

  void _resolve() {
    final d = widget.item;
    if ((d.assetW ?? 0) > 0 && (d.assetH ?? 0) > 0) {
      _aspect = d.assetW! / d.assetH!;
      return;
    }
    final provider = photoImageProvider(d, logicalSize: 200);
    if (provider == null) return;
    _stopListening();
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final a = info.image.width / info.image.height;
      if (mounted && a.isFinite && a > 0) setState(() => _aspect = a);
    }, onError: (_, _) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _stopListening() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, k) {
      final w = k.hasBoundedWidth ? k.maxWidth : 360.0;
      final h = _aspect == null
          ? widget.fallbackHeight
          : (w / _aspect!).clamp(140.0, widget.maxHeight);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoTile(
              item: widget.item,
              radius: widget.radius,
              showDate: false,
              iconSize: 60,
              fit: BoxFit.contain, // 아주 긴 사진도 잘리지 않게
            ),
            ...widget.overlay,
          ],
        ),
      );
    },
  );
}
