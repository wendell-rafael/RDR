import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Paleta ────────────────────────────────────────────────────────────────
  // Preto azulado como base, azul elétrico como acento.

  static const _black = Color(0xFF06090F); // fundo da tela
  static const _surface = Color(0xFF0B1018); // superfície base
  static const _surfaceLow = Color(0xFF0F1621); // cards
  static const _surfaceHigh = Color(0xFF16202E); // cards elevados, campos
  static const _surfaceHighest = Color(0xFF1D2837); // faixas, chips ativos

  static const _blue = Color(0xFF4C8DFF); // acento principal
  static const _blueDeep = Color(0xFF14284A); // container do acento
  static const _blueSoft = Color(0xFFCEE0FF); // texto sobre container
  static const _cyan = Color(0xFF3FD8E0); // acento secundário

  static const _outline = Color(0xFF243040);
  static const _outlineSoft = Color(0xFF1A2331);
  static const _textPrimary = Color(0xFFE6ECF5);
  static const _textMuted = Color(0xFF8E9BB0);

  /// Cores semânticas — usadas em status, troféu e alertas.
  static const success = Color(0xFF3DD68C);
  static const warning = Color(0xFFF5B33C);
  static const gold = Color(0xFFFFC94A);
  static const danger = Color(0xFFFF6B6B);

  /// Tons de azul dos cards da home, do mais claro ao mais escuro.
  static const homeAccents = [
    Color(0xFF4C8DFF),
    Color(0xFF2F6FE0),
    Color(0xFF2455B8),
    Color(0xFF1B3E8C),
  ];

  static const _colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _blue,
    onPrimary: Color(0xFF04101F),
    primaryContainer: _blueDeep,
    onPrimaryContainer: _blueSoft,
    secondary: _cyan,
    onSecondary: Color(0xFF04161A),
    secondaryContainer: Color(0xFF10333A),
    onSecondaryContainer: Color(0xFFB9F0F5),
    tertiary: warning,
    onTertiary: Color(0xFF231600),
    tertiaryContainer: Color(0xFF3B2A08),
    onTertiaryContainer: Color(0xFFFFE2B0),
    error: danger,
    onError: Color(0xFF2A0A0A),
    errorContainer: Color(0xFF4A1A1D),
    onErrorContainer: Color(0xFFFFD6D6),
    surface: _surface,
    onSurface: _textPrimary,
    onSurfaceVariant: _textMuted,
    surfaceContainerLowest: _black,
    surfaceContainerLow: _surfaceLow,
    surfaceContainer: _surfaceLow,
    surfaceContainerHigh: _surfaceHigh,
    surfaceContainerHighest: _surfaceHighest,
    outline: _outline,
    outlineVariant: _outlineSoft,
    inverseSurface: _textPrimary,
    onInverseSurface: _black,
    inversePrimary: _blueDeep,
    scrim: Color(0xCC000000),
    shadow: Color(0xFF000000),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _colorScheme,
    scaffoldBackgroundColor: _black,
    canvasColor: _black,
    splashFactory: InkSparkle.splashFactory,

    // Sem sombra: separação por cor de superfície e contorno fino.
    cardTheme: CardThemeData(
      elevation: 0,
      color: _surfaceLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _outlineSoft),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: _black,
      foregroundColor: _textPrimary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: _textPrimary,
      ),
    ),

    tabBarTheme: const TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: _outlineSoft,
      labelColor: _blue,
      unselectedLabelColor: _textMuted,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        foregroundColor: _blue,
        side: const BorderSide(color: _outline),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        elevation: 0,
        backgroundColor: _surfaceHigh,
        foregroundColor: _textPrimary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _blue,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: _textPrimary),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceHigh,
      hintStyle: const TextStyle(color: _textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _blue, width: 1.6),
      ),
    ),

    // Números grandes com espaçamento negativo — placar e cronômetro ficam
    // mais compactos e menos "widget padrão".
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
        color: _textPrimary,
      ),
      displayMedium: TextStyle(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
        color: _textPrimary,
      ),
      headlineLarge: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: _textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: _textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: _textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: _textPrimary,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: _textPrimary),
      bodyMedium: TextStyle(fontSize: 14, color: _textPrimary),
      bodySmall: TextStyle(fontSize: 12.5, color: _textMuted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _textMuted,
      ),
    ),

    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: _textMuted,
      textColor: _textPrimary,
    ),

    dividerTheme: const DividerThemeData(
      space: 1,
      thickness: 1,
      color: _outlineSoft,
    ),

    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: const BorderSide(color: _outline, width: 1.6),
    ),

    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(_outline),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      shape: CircleBorder(),
      backgroundColor: _blue,
      foregroundColor: Color(0xFF04101F),
      elevation: 0,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: _surfaceLow,
      selectedColor: _blueDeep,
      side: const BorderSide(color: _outline),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: _surfaceLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surfaceLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: _surfaceHighest,
      contentTextStyle: const TextStyle(color: _textPrimary, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: _blue),
  );

  // Cores de time (5 fixas) — identificam os times, mantidas bem distintas.
  static const List<Color> teamColors = [
    Color(0xFF4C8DFF), // azul
    Color(0xFFFF5C5C), // vermelho
    Color(0xFF3DD68C), // verde
    Color(0xFFFFA33C), // laranja
    Color(0xFFB07CFF), // roxo
  ];
}
