import 'package:flutter/foundation.dart';

/// VS Code's `terminal.integrated.cursorStyle`: `line` is xterm.js' `bar`.
enum TerminalCursorStyle {
  block('block'),
  line('bar'),
  underline('underline');

  const TerminalCursorStyle(this.xterm);

  /// The value of xterm.js' `cursorStyle` option.
  final String xterm;
}

/// The terminal's cursor, scrollback, Option key and copying:
/// settings.json's `terminal.integrated.cursorStyle`, `.cursorBlinking`,
/// `.scrollback`, `.macOptionIsMeta` and `.copyOnSelection`, as Settings →
/// Terminal picks them and VS Code keeps them. Unset: VS Code's defaults. A
/// value is kept only when it differs from its default (see the `…Setting`
/// functions).
abstract final class TerminalSettings {
  static const cursorStyleKey = 'terminal.integrated.cursorStyle';
  static const cursorBlinkingKey = 'terminal.integrated.cursorBlinking';
  static const scrollbackKey = 'terminal.integrated.scrollback';
  static const macOptionIsMetaKey = 'terminal.integrated.macOptionIsMeta';
  static const copyOnSelectionKey = 'terminal.integrated.copyOnSelection';

  static const defaultScrollback = 1000;

  /// The most lines kept: the buffer takes room for all of them at once.
  static const maxScrollback = 100000;

  /// The choices Settings → Terminal offers, fewest first.
  static const scrollbackSteps = <int>[1000, 5000, 10000, 50000, 100000];

  static final ValueNotifier<TerminalCursorStyle> cursorStyle = ValueNotifier(
    TerminalCursorStyle.block,
  );
  static final ValueNotifier<bool> cursorBlinking = ValueNotifier(false);
  static final ValueNotifier<int> scrollback = ValueNotifier(defaultScrollback);

  /// Whether Option sends Meta (Esc then the key) instead of the character
  /// macOS types with it (⌥B is `∫`).
  static final ValueNotifier<bool> macOptionIsMeta = ValueNotifier(false);

  /// Whether what is selected in a terminal is copied as it is selected.
  static final ValueNotifier<bool> copyOnSelection = ValueNotifier(false);

  /// All of them, for whoever follows any.
  static final Listenable changes = Listenable.merge([
    cursorStyle,
    cursorBlinking,
    scrollback,
    macOptionIsMeta,
    copyOnSelection,
  ]);

  static TerminalCursorStyle parseCursorStyle(Object? value) =>
      TerminalCursorStyle.values
          .where((style) => style.name == value)
          .firstOrNull ??
      TerminalCursorStyle.block;

  static String? cursorStyleSetting(TerminalCursorStyle style) =>
      style == TerminalCursorStyle.block ? null : style.name;

  static bool parseBool(Object? value) => value == true;

  static bool? boolSetting(bool on) => on ? true : null;

  /// [value] as settings.json has it, from 0 to [maxScrollback].
  static int parseScrollback(Object? value) => switch (value) {
    final num lines when lines.isFinite =>
      lines.round().clamp(0, maxScrollback),
    _ => defaultScrollback,
  };

  static int? scrollbackSetting(int lines) =>
      lines == defaultScrollback ? null : lines;

  /// Sets the notifiers from [read] now and whenever [changes] notifies.
  static void follow(Listenable changes, Object? Function(String key) read) {
    void update() {
      cursorStyle.value = parseCursorStyle(read(cursorStyleKey));
      cursorBlinking.value = parseBool(read(cursorBlinkingKey));
      scrollback.value = parseScrollback(read(scrollbackKey));
      macOptionIsMeta.value = parseBool(read(macOptionIsMetaKey));
      copyOnSelection.value = parseBool(read(copyOnSelectionKey));
    }

    update();
    changes.addListener(update);
  }
}
