import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A friendly, human-readable label for a [LogicalKeyboardKey] — e.g. "←",
/// "Enter", "Space", "R". Used by every rebind UI so a captured key reads the
/// same everywhere. Falls back to the key's debug name (or its id in hex) for
/// the rare key that has no printable label.
String keyLabel(LogicalKeyboardKey key) {
  // A few keys whose `keyLabel` is ugly or empty — show a nicer glyph/word.
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.enter) return 'Enter';
  if (key == LogicalKeyboardKey.numpadEnter) return 'Enter';
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  final String label = key.keyLabel;
  if (label.isNotEmpty) return label.length == 1 ? label.toUpperCase() : label;
  return key.debugName ?? '0x${key.keyId.toRadixString(16)}';
}

/// Captures the next key press (for rebinding a shortcut). Returns the pressed
/// [LogicalKeyboardKey], or null if the user cancelled (Esc / Cancel). Bare
/// modifier keys (Shift/Ctrl/Alt/Meta) are ignored so an action can't be bound
/// to a modifier that already means something.
Future<LogicalKeyboardKey?> captureKey(BuildContext context) =>
    showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (BuildContext ctx) => const KeyCaptureDialog(),
    );

/// The "Press a key…" dialog body behind [captureKey].
class KeyCaptureDialog extends StatelessWidget {
  const KeyCaptureDialog({super.key});

  // Not `const`: LogicalKeyboardKey overrides ==, which Dart forbids in a const
  // set (const_set_element_not_primitive_equality).
  static final Set<LogicalKeyboardKey> _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Press a key'),
      content: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          if (_modifiers.contains(event.logicalKey)) {
            return KeyEventResult.ignored;
          }
          Navigator.pop(context, event.logicalKey);
          return KeyEventResult.handled;
        },
        child: const SizedBox(
          height: 44,
          child: Center(child: Text('Press any key…  (Esc to cancel)')),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
