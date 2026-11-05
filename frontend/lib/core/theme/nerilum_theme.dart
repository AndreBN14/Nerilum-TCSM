import 'package:flutter/material.dart';

abstract final class NerilumColors {
  static const background = Color(0xFF0B0D0C);
  static const surface = Color(0xFF1D201E);
  static const surfaceRaised = Color(0xFF272B28);
  static const field = Color(0xFF303431);
  static const mint = Color(0xFFC8F5D4);
  static const mintSecondary = Color(0xFF9BD9B5);
  static const mintDarkText = Color(0xFF102017);
  static const textPrimary = Color(0xFFF5F7F5);
  static const textSecondary = Color(0xFFA6ADA7);
  static const border = Color(0xFF39413B);
  static const error = Color(0xFFF0A7A2);
}

class NerilumPalette extends ThemeExtension<NerilumPalette> {
  const NerilumPalette({
    required this.background,
    required this.glow,
    required this.surface,
    required this.surfaceRaised,
    required this.mint,
    required this.mintSecondary,
    required this.mintDarkText,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.error,
  });

  final Color background;
  final Color glow;
  final Color surface;
  final Color surfaceRaised;
  final Color mint;
  final Color mintSecondary;
  final Color mintDarkText;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color error;

  static const dark = NerilumPalette(
    background: NerilumColors.background,
    glow: Color(0xFF1A2B23),
    surface: NerilumColors.surface,
    surfaceRaised: NerilumColors.surfaceRaised,
    mint: NerilumColors.mint,
    mintSecondary: NerilumColors.mintSecondary,
    mintDarkText: NerilumColors.mintDarkText,
    textPrimary: NerilumColors.textPrimary,
    textSecondary: NerilumColors.textSecondary,
    border: NerilumColors.border,
    error: NerilumColors.error,
  );

  static const light = NerilumPalette(
    background: Color(0xFFF4F7F2),
    glow: Color(0xFFDCEDE2),
    surface: Colors.white,
    surfaceRaised: Color(0xFFE7F0E9),
    mint: Color(0xFF216B49),
    mintSecondary: Color(0xFF356F51),
    mintDarkText: Colors.white,
    textPrimary: Color(0xFF16281C),
    textSecondary: Color(0xFF4D6053),
    border: Color(0xFFCCD9CE),
    error: Color(0xFFAA3039),
  );

  static NerilumPalette of(BuildContext context) =>
      Theme.of(context).extension<NerilumPalette>()!;

  @override
  NerilumPalette copyWith({
    Color? background,
    Color? glow,
    Color? surface,
    Color? surfaceRaised,
    Color? mint,
    Color? mintSecondary,
    Color? mintDarkText,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? error,
  }) => NerilumPalette(
    background: background ?? this.background,
    glow: glow ?? this.glow,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    mint: mint ?? this.mint,
    mintSecondary: mintSecondary ?? this.mintSecondary,
    mintDarkText: mintDarkText ?? this.mintDarkText,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    border: border ?? this.border,
    error: error ?? this.error,
  );

  @override
  NerilumPalette lerp(ThemeExtension<NerilumPalette>? other, double t) {
    if (other is! NerilumPalette) return this;
    return NerilumPalette(
      background: Color.lerp(background, other.background, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      mintSecondary: Color.lerp(mintSecondary, other.mintSecondary, t)!,
      mintDarkText: Color.lerp(mintDarkText, other.mintDarkText, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

abstract final class NerilumTheme {
  static ThemeData get dark => _build(NerilumPalette.dark, Brightness.dark);
  static ThemeData get light => _build(NerilumPalette.light, Brightness.light);

  static ThemeData _build(NerilumPalette colors, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return base.copyWith(
      extensions: [colors],
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.mint,
        brightness: brightness,
        primary: colors.mint,
        onPrimary: colors.mintDarkText,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: colors.error,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        labelStyle: TextStyle(color: colors.textSecondary),
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colors.mint),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colors.error),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.mint,
          foregroundColor: colors.mintDarkText,
          minimumSize: const Size.fromHeight(58),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size.fromHeight(58),
          shape: const StadiumBorder(),
          side: BorderSide(color: colors.border, width: 1.5),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.mint),
      ),
    );
  }
}
