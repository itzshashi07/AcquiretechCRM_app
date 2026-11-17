import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Acquiretech brand, taken from the website (acquiretechsoftwaresolution.in):
/// warm cream paper, charcoal ink, clay/cognac neutrals and the logo orange.
class Brand {
  // Ink and paper.
  static const deep = Color(0xFF0B0908);
  static const ink = Color(0xFF191411);
  static const inkSoft = Color(0xFF3B322A);
  static const surface = Color(0xFFF3EDE3);
  static const card = Color(0xFFFFFDF9);
  static const raised = Color(0xFFEBE4D7);
  static const border = Color(0xFFE2D9C9);
  static const text = Color(0xFF191411);
  static const muted = Color(0xFF615448);
  static const grey = Color(0xFF978A7B);

  // Accents.
  static const logo = Color(0xFFFF5B2C);
  static const accent = Color(0xFFEC5223);
  static const accentSoft = Color(0xFFFBE6DC);
  static const cognac = Color(0xFF7C5234);
  static const glow = Color(0xFFF2C29E);

  // Status.
  static const orange = Color(0xFFEC5223);
  static const success = Color(0xFF2F7D4F);
  static const blue = Color(0xFF2F62C9);
  static const amber = Color(0xFFB07A12);
  static const red = Color(0xFFC4351E);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deep, ink, Color(0xFF2B2019)],
    stops: [0, .5, 1],
  );

  static Color stage(String status) {
    final s = status.toLowerCase();
    if (s.isEmpty) return grey;
    if (s.contains('won') || s.contains('convert') || s.contains('complet')) return success;
    if (s.contains('lost') || s.contains('junk') || s.contains('cancel')) return grey;
    if (s == 'new' || s.contains('new lead') || s.contains('pending')) return orange;
    if (s.contains('contact') || s.contains('progress')) return blue;
    if (s.contains('urgent')) return red;
    return amber;
  }

  /// Text drawn on a tint of [color] needs a deeper shade to stay readable.
  static Color onTint(Color color) => Color.lerp(color, Colors.black, .28)!;

  static Color forName(String name) {
    const palette = [
      Color(0xFF7C5234),
      Color(0xFFD9542A),
      Color(0xFF5F6F35),
      Color(0xFF7A4B6E),
      Color(0xFF2F6F6A),
      Color(0xFF4A5A78),
      Color(0xFFA0522D),
    ];
    final hash = name.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
    return palette[hash % palette.length];
  }
}

const SystemUiOverlayStyle lightBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
);

const SystemUiOverlayStyle darkBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// Headlines use the website's editorial serif.
TextStyle display(double size, {Color color = Brand.text, FontWeight weight = FontWeight.w600}) => TextStyle(
      fontFamily: 'Fraunces',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.15,
      letterSpacing: -.4,
    );

/// Numbers line up in columns and do not jump while counting.
const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.accent,
    brightness: Brightness.light,
    primary: Brand.ink,
    onPrimary: Colors.white,
    secondary: Brand.accent,
    onSecondary: Colors.white,
    surface: Brand.surface,
    onSurface: Brand.text,
    error: Brand.red,
  ).copyWith(surfaceContainerHighest: Brand.raised, outline: Brand.border, outlineVariant: Brand.border);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.surface,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,
  );
  final text = base.textTheme.apply(bodyColor: Brand.text, displayColor: Brand.text, fontFamily: 'Inter');
  final radius = BorderRadius.circular(16);
  const label = TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700);
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: display(30),
      headlineSmall: display(24),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.2),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.4),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.surface,
      foregroundColor: Brand.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: lightBars,
      titleTextStyle: display(26),
    ),
    cardTheme: CardThemeData(
      color: Brand.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Brand.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Brand.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Brand.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Brand.ink, width: 1.4)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Brand.red)),
      labelStyle: const TextStyle(color: Brand.muted),
      floatingLabelStyle: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Brand.grey),
      prefixIconColor: Brand.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Brand.raised,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: label.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.ink,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: Brand.border),
        backgroundColor: Brand.card,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: label.copyWith(fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Brand.cognac, textStyle: label),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.ink,
      foregroundColor: Colors.white,
      elevation: 3,
      highlightElevation: 5,
      shape: StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Brand.accentSoft,
      height: 70,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Inter',
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Brand.ink : Brand.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Brand.accent : Brand.muted, size: 24),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.card,
      selectedColor: Brand.ink,
      side: const BorderSide(color: Brand.border),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: Brand.text),
      secondaryLabelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Brand.border,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: display(22),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Brand.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Brand.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.ink,
      actionTextColor: Brand.glow,
      contentTextStyle: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Brand.ink,
      unselectedLabelColor: Brand.muted,
      indicatorColor: Brand.accent,
      dividerColor: Brand.border,
      labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13.5),
      unselectedLabelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13.5),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.ink : Brand.raised),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.glow : Brand.card),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dividerTheme: const DividerThemeData(color: Brand.border, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.accent, linearTrackColor: Brand.raised),
    datePickerTheme: const DatePickerThemeData(backgroundColor: Brand.card, surfaceTintColor: Colors.transparent),
    timePickerTheme: const TimePickerThemeData(backgroundColor: Brand.card),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
    ),
  );
}
