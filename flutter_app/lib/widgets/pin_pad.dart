import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// 비밀번호 4자리 입력: 제목 · 안내 · 점 4개 · 오류 문구 · 숫자 키패드.
/// 4자리를 다 누르면 [onComplete] 를 부른다. 오류 문구를 돌려주면 점을 비우고 그 문구를 보여 준다.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.message,
    required this.onComplete,
    this.footer,
  });

  final String title;
  final String message;

  /// 4자리 입력 완료 → null 이면 성공, 문자열이면 오류 문구
  final Future<String?> Function(String pin) onComplete;
  final Widget? footer;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _press(String key) async {
    if (_busy) return;
    if (key == 'del') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
      return;
    }
    if (_pin.length >= 4) return;
    setState(() {
      _pin += key;
      _error = null;
    });
    if (_pin.length < 4) return;
    _busy = true;
    final err = await widget.onComplete(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    Widget key(String label, {String? value, Widget? child}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: label.isEmpty && child == null
            ? const SizedBox(height: 56)
            : Pressable(
                onTap: () => _press(value ?? label),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      child ??
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                ),
              ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
          child: SnapIcon('lock', size: 24, color: c.pri),
        ),
        const SizedBox(height: 12),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          keepWords(widget.message),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.45, color: c.mute),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? c.pri : Colors.transparent,
                  border: Border.all(
                    color: i < _pin.length ? c.pri : c.line,
                    width: 1.6,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 34,
          child: Center(
            child: Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFFD93A2B)),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(children: [for (final k in row) key(k)]),
              Row(
                children: [
                  key(''),
                  key('0'),
                  key(
                    '⌫',
                    value: 'del',
                    child: SnapIcon('back', size: 20, color: c.ink),
                  ),
                ],
              ),
            ],
          ),
        ),
        ?widget.footer,
      ],
    );
  }
}

/// 새 비밀번호 4자리를 두 번 입력받는다. 취소하면 null.
Future<String?> showPinSetup(BuildContext context) {
  final c = context.sc;
  String? first;
  var mismatch = false;
  return showSnapDialog<String>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => Dialog(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
        child: StatefulBuilder(
          builder: (ctx, setState) => PinPad(
            key: ValueKey(first == null),
            title: first == null ? '앨범 비밀번호 설정' : '한 번 더 입력',
            message: first != null
                ? '확인을 위해 같은 숫자 4자리를 입력하세요.'
                : mismatch
                ? '비밀번호가 달랐어요. 처음부터 다시 입력하세요.'
                : '앨범을 열 때 쓸 숫자 4자리를 입력하세요.',
            onComplete: (pin) async {
              if (first == null) {
                setState(() => first = pin);
                return null;
              }
              if (pin != first) {
                setState(() {
                  first = null;
                  mismatch = true;
                });
                return null;
              }
              Navigator.of(ctx).pop(pin);
              return null;
            },
            footer: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SnapButton(
                label: '취소',
                ghost: true,
                top: 4,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
