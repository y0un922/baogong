import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart';
import '../../ide/terminal/terminal_settings.dart';
import '../../l10n/l10n.dart';
import '../../platform/app_platform.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Terminal (see [TerminalSettings] for the keys): the cursor,
/// the scrollback and, on macOS, the Option key. The terminal's font and
/// size are Appearance's, with the code's.
class TerminalSettingsPage extends StatelessWidget {
  const TerminalSettingsPage({super.key, this.settings});

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  void _write(String key, Object? value) {
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings.update(key, value).catchError((Object error) {
        debugPrint('$key not kept: $error');
      }),
    );
  }

  void _selectCursorStyle(TerminalCursorStyle style) {
    TerminalSettings.cursorStyle.value = style;
    _write(
      TerminalSettings.cursorStyleKey,
      TerminalSettings.cursorStyleSetting(style),
    );
  }

  void _selectCursorBlinking(bool on) {
    TerminalSettings.cursorBlinking.value = on;
    _write(
      TerminalSettings.cursorBlinkingKey,
      TerminalSettings.boolSetting(on),
    );
  }

  void _selectScrollback(int lines) {
    TerminalSettings.scrollback.value = lines;
    _write(
      TerminalSettings.scrollbackKey,
      TerminalSettings.scrollbackSetting(lines),
    );
  }

  void _selectMacOptionIsMeta(bool on) {
    TerminalSettings.macOptionIsMeta.value = on;
    _write(
      TerminalSettings.macOptionIsMetaKey,
      TerminalSettings.boolSetting(on),
    );
  }

  void _selectCopyOnSelection(bool on) {
    TerminalSettings.copyOnSelection.value = on;
    _write(
      TerminalSettings.copyOnSelectionKey,
      TerminalSettings.boolSetting(on),
    );
  }

  static String _cursorStyleName(
    BuildContext context,
    TerminalCursorStyle style,
  ) => switch (style) {
    TerminalCursorStyle.block => context.l10n.terminalSettingsCursorBlock,
    TerminalCursorStyle.line => context.l10n.terminalSettingsCursorLine,
    TerminalCursorStyle.underline =>
      context.l10n.terminalSettingsCursorUnderline,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: TerminalSettings.changes,
    builder: (context, _) => _page(context),
  );

  Widget _page(BuildContext context) {
    final l10n = context.l10n;
    final style = TerminalSettings.cursorStyle.value;
    final styleShown = _cursorStyleName(context, style);
    final scrollback = TerminalSettings.scrollback.value;
    final scrollbackShown = l10n.terminalSettingsScrollbackLines('$scrollback');
    return SettingsPage(
      title: l10n.settingsSectionTerminal,
      description: l10n.terminalSettingsDescription,
      children: [
        SettingsCard(
          children: [
            SettingsRow(
              label: l10n.terminalSettingsCursorStyle,
              trailing: SettingsDropdown(
                current: styleShown,
                width: 220,
                semanticLabel: l10n.terminalSettingsCursorStyleLabel(
                  styleShown,
                ),
                entries: () => ideMenuGroups([
                  [
                    for (final choice in TerminalCursorStyle.values)
                      IdeMenuAction(
                        _cursorStyleName(context, choice),
                        checked: choice == style,
                        onSelected: () => _selectCursorStyle(choice),
                      ),
                  ],
                ]),
              ),
            ),
            SettingsSwitchRow(
              label: l10n.terminalSettingsCursorBlinking,
              description: l10n.terminalSettingsCursorBlinkingDescription,
              value: TerminalSettings.cursorBlinking.value,
              onChanged: _selectCursorBlinking,
            ),
            SettingsRow(
              label: l10n.terminalSettingsScrollback,
              description: l10n.terminalSettingsScrollbackDescription,
              trailing: SettingsDropdown(
                current: scrollbackShown,
                width: 220,
                semanticLabel: l10n.terminalSettingsScrollbackLabel(
                  scrollbackShown,
                ),
                entries: () => ideMenuGroups([
                  [
                    for (final lines in TerminalSettings.scrollbackSteps)
                      IdeMenuAction(
                        l10n.terminalSettingsScrollbackLines('$lines'),
                        checked: lines == scrollback,
                        onSelected: () => _selectScrollback(lines),
                      ),
                  ],
                ]),
              ),
            ),
            SettingsSwitchRow(
              label: l10n.terminalSettingsCopyOnSelection,
              description: l10n.terminalSettingsCopyOnSelectionDescription,
              value: TerminalSettings.copyOnSelection.value,
              onChanged: _selectCopyOnSelection,
            ),
            if (AppPlatform.isMacOS)
              SettingsSwitchRow(
                label: l10n.terminalSettingsOptionIsMeta,
                description: l10n.terminalSettingsOptionIsMetaDescription,
                value: TerminalSettings.macOptionIsMeta.value,
                onChanged: _selectMacOptionIsMeta,
              ),
          ],
        ),
      ],
    );
  }
}
