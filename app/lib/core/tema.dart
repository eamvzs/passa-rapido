import 'package:flutter/material.dart';

const _corPrincipal = Color(0xFF0D47A1);

/// Tema do app. O modo de alto contraste usa preto e branco puros e bordas visíveis.
ThemeData construirTema({required bool altoContraste}) {
  final esquema = altoContraste
      ? const ColorScheme.highContrastLight(primary: Colors.black, secondary: Color(0xFF0D47A1))
      : ColorScheme.fromSeed(seedColor: _corPrincipal);

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: altoContraste ? Colors.white : esquema.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.primary,
      foregroundColor: esquema.onPrimary,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: altoContraste ? 0 : 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: altoContraste ? const BorderSide(color: Colors.black, width: 1.5) : BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
