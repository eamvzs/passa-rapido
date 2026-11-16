import 'package:flutter/material.dart';

/// Espaçamentos padrão do app.
abstract final class Espaco {
  static const double pp = 4;
  static const double p = 8;
  static const double m = 12;
  static const double g = 16;
  static const double gg = 24;
  static const double xg = 32;
}

/// Largura máxima do conteúdo em telas largas (tablet e navegador).
const larguraMaximaDoConteudo = 640.0;

/// Identidade visual do app: "institucional moderno" (azul-marinho e verde-menta, fundo neutro, tom confiável de serviço
/// público). A cor da marca fica fora da escala verde-amarelo-vermelho das filas, que tem significado fixo.
/// O tema é montado a partir de uma paleta (`PaletaVisual`), o que permite criar outras identidades no futuro.
enum EstiloVisual {
  institucional('institucional', 'Institucional moderno', 'Azul-marinho e verde-menta, fundo neutro: tom confiável de serviço público.');

  const EstiloVisual(this.codigo, this.nome, this.descricao);

  final String codigo;
  final String nome;
  final String descricao;

  /// Estilo usado pelo app.
  static const padrao = institucional;

  PaletaVisual get paleta => _paletas[this]!;
}

/// Tudo o que muda de um estilo para o outro: cores (claro e escuro), formas e peso do texto.
class PaletaVisual {
  const PaletaVisual({
    required this.primaria,
    required this.primariaEscuro,
    required this.destaque,
    required this.destaque2,
    required this.superficie,
    required this.superficieEscuro,
    required this.cartao,
    required this.cartaoEscuro,
    required this.borda,
    required this.bordaEscuro,
    required this.heroClaro,
    required this.heroEscuro,
    this.raioCartao = 20,
    this.raioBotao = 14,
    this.pilula = false,
    this.espessuraBorda = 1,
    this.sombra = false,
    this.escalaTexto = 1.0,
  });

  final Color primaria;
  final Color primariaEscuro;

  /// Cores de destaque usadas só em enfeites (cartões de destaque, medalhas); nunca para texto corrido.
  final Color destaque;
  final Color destaque2;
  final Color superficie;
  final Color superficieEscuro;
  final Color cartao;
  final Color cartaoEscuro;
  final Color borda;
  final Color bordaEscuro;
  final List<Color> heroClaro;
  final List<Color> heroEscuro;
  final double raioCartao;
  final double raioBotao;
  final bool pilula;
  final double espessuraBorda;
  final bool sombra;

  /// Fator aplicado ao tamanho dos textos (o estilo de alto contraste usa letras um pouco maiores).
  final double escalaTexto;
}

const _paletas = <EstiloVisual, PaletaVisual>{
  EstiloVisual.institucional: PaletaVisual(
    primaria: Color(0xFF1B3A6B),
    primariaEscuro: Color(0xFF9CC0FF),
    destaque: Color(0xFF5EEAD4),
    destaque2: Color(0xFFBBD4FF),
    superficie: Color(0xFFF2F5F9),
    superficieEscuro: Color(0xFF0D1420),
    cartao: Colors.white,
    cartaoEscuro: Color(0xFF16202F),
    borda: Color(0xFFDDE4EE),
    bordaEscuro: Color(0xFF27364B),
    heroClaro: [Color(0xFF244C8A), Color(0xFF0F2447)],
    heroEscuro: [Color(0xFF1D3F73), Color(0xFF0B1A33)],
    raioCartao: 16,
    raioBotao: 12,
  ),
};

/// Cores e formas do estilo atual para quem não é ThemeData: cartões de destaque (gradiente), logo e raios.
/// Leia com `IdentidadeVisual.de(context)`.
class IdentidadeVisual extends ThemeExtension<IdentidadeVisual> {
  const IdentidadeVisual({
    required this.heroInicio,
    required this.heroFim,
    required this.destaque,
    required this.destaque2,
    required this.raioCartao,
    required this.raioBotao,
  });

  final Color heroInicio;
  final Color heroFim;
  final Color destaque;
  final Color destaque2;
  final double raioCartao;
  final double raioBotao;

  LinearGradient get gradiente =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [heroInicio, heroFim]);

  static IdentidadeVisual de(BuildContext context) =>
      Theme.of(context).extension<IdentidadeVisual>() ?? _padrao;

  static const _padrao = IdentidadeVisual(
    heroInicio: Color(0xFF3558E8),
    heroFim: Color(0xFF1A2F9E),
    destaque: Color(0xFFFFD54F),
    destaque2: Color(0xFF8FD3FF),
    raioCartao: 24,
    raioBotao: 14,
  );

  @override
  IdentidadeVisual copyWith({
    Color? heroInicio,
    Color? heroFim,
    Color? destaque,
    Color? destaque2,
    double? raioCartao,
    double? raioBotao,
  }) =>
      IdentidadeVisual(
        heroInicio: heroInicio ?? this.heroInicio,
        heroFim: heroFim ?? this.heroFim,
        destaque: destaque ?? this.destaque,
        destaque2: destaque2 ?? this.destaque2,
        raioCartao: raioCartao ?? this.raioCartao,
        raioBotao: raioBotao ?? this.raioBotao,
      );

  @override
  IdentidadeVisual lerp(ThemeExtension<IdentidadeVisual>? outro, double t) {
    if (outro is! IdentidadeVisual) return this;
    return IdentidadeVisual(
      heroInicio: Color.lerp(heroInicio, outro.heroInicio, t)!,
      heroFim: Color.lerp(heroFim, outro.heroFim, t)!,
      destaque: Color.lerp(destaque, outro.destaque, t)!,
      destaque2: Color.lerp(destaque2, outro.destaque2, t)!,
      raioCartao: raioCartao + (outro.raioCartao - raioCartao) * t,
      raioBotao: raioBotao + (outro.raioBotao - raioBotao) * t,
    );
  }
}

ThemeData construirTema({
  required Brightness brilho,
  required bool altoContraste,
  EstiloVisual estilo = EstiloVisual.padrao,
}) {
  final p = estilo.paleta;
  final escuro = brilho == Brightness.dark;
  final primaria = escuro ? p.primariaEscuro : p.primaria;
  final superficie = escuro ? p.superficieEscuro : p.superficie;
  final ColorScheme esquema;
  if (altoContraste) {
    esquema = escuro
        ? const ColorScheme.highContrastDark(primary: Colors.white, secondary: Color(0xFF9DB2FF))
        : ColorScheme.highContrastLight(primary: Colors.black, secondary: p.primaria);
  } else {
    esquema = ColorScheme.fromSeed(seedColor: p.primaria, brightness: brilho).copyWith(
      primary: primaria,
      onPrimary: escuro ? superficie : Colors.white,
      secondary: escuro ? p.destaque2 : p.primaria,
      tertiary: escuro ? p.destaque : p.primaria,
      surface: superficie,
      surfaceContainerLowest: escuro ? Color.lerp(superficie, Colors.black, 0.3) : Colors.white,
    );
  }

  final fundoDoCartao = altoContraste ? esquema.surface : (escuro ? p.cartaoEscuro : p.cartao);
  final borda = altoContraste ? esquema.onSurface : (escuro ? p.bordaEscuro : p.borda);
  final espessura = altoContraste ? 1.5 : p.espessuraBorda;
  final raioBotao = p.pilula ? 999.0 : p.raioBotao;
  final formaBotao = p.pilula
      ? const StadiumBorder()
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.raioBotao)) as OutlinedBorder;
  final forma14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.pilula ? 18 : p.raioBotao));
  final bordaDoBotao = BorderSide(
    color: altoContraste ? esquema.onSurface : (p.espessuraBorda >= 2 ? borda : esquema.outlineVariant),
    width: p.espessuraBorda >= 2 ? 2 : 1,
  );
  final raioCampo = p.pilula ? 20.0 : p.raioBotao;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    brightness: brilho,
    fontFamily: 'Jakarta',
  );
  final fortes = p.escalaTexto > 1.0;
  final texto = base.textTheme
      .copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.4, fontWeight: fortes ? FontWeight.w500 : null),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4, fontWeight: fortes ? FontWeight.w500 : null),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          height: 1.35,
          color: esquema.onSurfaceVariant,
          fontWeight: fortes ? FontWeight.w500 : null,
        ),
      )
      .apply(bodyColor: esquema.onSurface, displayColor: esquema.onSurface);

  final minimoBotao = Size(48, p.pilula ? 56 : 54);

  return base.copyWith(
    textTheme: texto,
    scaffoldBackgroundColor: esquema.surface,
    dividerColor: borda,
    extensions: [
      IdentidadeVisual(
        heroInicio: (escuro ? p.heroEscuro : p.heroClaro).first,
        heroFim: (escuro ? p.heroEscuro : p.heroClaro).last,
        destaque: p.destaque,
        destaque2: p.destaque2,
        raioCartao: p.raioCartao + 4,
        raioBotao: raioBotao,
      ),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.surface,
      foregroundColor: esquema.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Jakarta',
        fontSize: 22,
        fontWeight: fortes ? FontWeight.w800 : FontWeight.w700,
        letterSpacing: -0.2,
        color: esquema.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: p.sombra ? 2 : 0,
      shadowColor: p.sombra ? p.primaria.withValues(alpha: escuro ? 0.5 : 0.28) : null,
      margin: EdgeInsets.zero,
      color: fundoDoCartao,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.raioCartao),
        side: espessura == 0 ? BorderSide.none : BorderSide(color: borda, width: espessura),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minimoBotao,
        shape: formaBotao,
        elevation: p.sombra ? 2 : 0,
        shadowColor: p.sombra ? p.primaria.withValues(alpha: 0.4) : null,
        textStyle: texto.labelLarge?.copyWith(fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minimoBotao,
        shape: formaBotao,
        side: bordaDoBotao,
        textStyle: texto.labelLarge?.copyWith(fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: p.pilula ? const StadiumBorder() : null,
        textStyle: texto.labelLarge,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: formaBotao,
        side: bordaDoBotao,
        selectedBackgroundColor: esquema.primary.withValues(alpha: escuro ? 0.3 : 0.14),
        selectedForegroundColor: esquema.primary,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.raioCartao > 12 && p.raioBotao > 8 ? 24 : 8)),
      side: espessura == 0 ? BorderSide(color: borda) : BorderSide(color: borda, width: espessura >= 2 ? 1.5 : 1),
      backgroundColor: fundoDoCartao,
      selectedColor: esquema.primary,
      checkmarkColor: esquema.onPrimary,
      showCheckmark: false,
      labelStyle: texto.labelLarge,
      secondaryLabelStyle: texto.labelLarge?.copyWith(color: esquema.onPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fundoDoCartao,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(raioCampo),
        borderSide: BorderSide(color: borda, width: espessura == 0 ? 1 : espessura),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(raioCampo),
        borderSide: BorderSide(color: borda, width: espessura == 0 ? 1 : espessura),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(raioCampo),
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: p.pilula ? 76 : 72,
      backgroundColor: fundoDoCartao,
      surfaceTintColor: Colors.transparent,
      elevation: p.sombra ? 8 : null,
      shadowColor: p.sombra ? p.primaria.withValues(alpha: 0.3) : null,
      indicatorColor: esquema.primary.withValues(alpha: escuro ? 0.28 : (fortes ? 0.2 : 0.12)),
      indicatorShape: p.pilula ? const StadiumBorder() : null,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (estados) => texto.labelMedium?.copyWith(
          fontWeight: estados.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
          color: estados.contains(WidgetState.selected) ? esquema.primary : esquema.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (estados) => IconThemeData(
          color: estados.contains(WidgetState.selected) ? esquema.primary : esquema.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: fundoDoCartao,
      indicatorColor: esquema.primary.withValues(alpha: escuro ? 0.28 : (fortes ? 0.2 : 0.12)),
      indicatorShape: p.pilula ? const StadiumBorder() : null,
      selectedIconTheme: IconThemeData(color: esquema.primary),
      selectedLabelTextStyle: texto.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: esquema.primary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: fundoDoCartao,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(p.pilula ? 32 : (fortes ? 12 : 28))),
      ),
      dragHandleColor: esquema.outlineVariant,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: forma14,
      backgroundColor: escuro ? const Color(0xFFE8EAF2) : const Color(0xFF151824),
      contentTextStyle: texto.bodyMedium?.copyWith(color: escuro ? const Color(0xFF151824) : Colors.white),
    ),
    listTileTheme: ListTileThemeData(shape: forma14),
    dialogTheme: DialogThemeData(
      backgroundColor: fundoDoCartao,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.raioCartao + 4)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: fundoDoCartao,
      foregroundColor: esquema.primary,
      elevation: p.sombra ? 5 : 3,
      shape: p.raioBotao <= 8 ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : const CircleBorder(),
    ),
  );
}
