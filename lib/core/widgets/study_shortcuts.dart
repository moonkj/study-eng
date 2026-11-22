import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 학습 화면의 하드웨어 키보드 단축키 (iPad).
/// - 키를 누르고 있을 때 반복 입력은 무시한다 (←·→ 넘기기만 반복 허용). 연타로 평가가 여러 번 들어가지 않게.
/// - 버튼에 포커스가 있을 때(Tab 으로 이동한 경우) Space·Enter 는 그 버튼이 받도록 양보한다.
class StudyShortcuts extends StatefulWidget {
  const StudyShortcuts({super.key, required this.bindings, required this.child});

  final Map<SingleActivator, VoidCallback> bindings;
  final Widget child;

  @override
  State<StudyShortcuts> createState() => _StudyShortcutsState();
}

class _StudyShortcutsState extends State<StudyShortcuts> {
  final _node = FocusScopeNode(debugLabel: 'study-screen');

  static final _repeatable = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};
  static final _activate = {LogicalKeyboardKey.space, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter};

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent && !_repeatable.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (_activate.contains(event.logicalKey) && !node.hasPrimaryFocus) return KeyEventResult.ignored;
    for (final e in widget.bindings.entries) {
      final a = e.key;
      if (_sameKey(a.trigger, event) &&
          a.control == HardwareKeyboard.instance.isControlPressed &&
          a.meta == HardwareKeyboard.instance.isMetaPressed &&
          a.shift == HardwareKeyboard.instance.isShiftPressed &&
          a.alt == HardwareKeyboard.instance.isAltPressed) {
        e.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 글자 키는 자판 배열(한글 두벌식 등)과 상관없이 물리 키 위치로도 맞춘다
  static bool _sameKey(LogicalKeyboardKey trigger, KeyEvent event) {
    if (trigger == event.logicalKey) return true;
    final id = trigger.keyId;
    if (id >= 0x61 && id <= 0x7a) return event.physicalKey.usbHidUsage == 0x00070004 + (id - 0x61);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // FocusScope: 포커스를 가진 위젯이 사라지면(카드 교체 등) 이 화면으로 돌아와 단축키가 계속 동작한다
    return FocusScope(node: _node, autofocus: true, onKeyEvent: _onKey, child: widget.child);
  }
}
