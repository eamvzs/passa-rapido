import 'package:flutter/material.dart';

/// Faixa de espera de uma unidade, calculada pelo banco.
enum NivelEspera {
  semDados('sem_dados', 'Sem dados', Color(0xFF667085), Icons.help_outline_rounded),
  baixa('baixa', 'Fila baixa', Color(0xFF16803C), Icons.sentiment_satisfied_alt_rounded),
  moderada('moderada', 'Fila moderada', Color(0xFFF2B01E), Icons.sentiment_neutral_rounded),
  alta('alta', 'Fila alta', Color(0xFFBF5500), Icons.sentiment_dissatisfied_rounded),
  critica('critica', 'Fila muito alta', Color(0xFFD22F2F), Icons.warning_amber_rounded);

  const NivelEspera(this.codigo, this.rotulo, this.cor, this.icone);

  final String codigo;
  final String rotulo;
  final Color cor;
  final IconData icone;

  /// Cor do texto que garante contraste sobre [cor].
  Color get corDoTexto => this == moderada ? const Color(0xFF231A00) : Colors.white;

  /// Fundo suave para blocos grandes, onde a cor cheia cansaria a vista.
  Color fundoSuave(Brightness brilho) =>
      cor.withValues(alpha: brilho == Brightness.dark ? 0.22 : 0.12);

  /// Cor para texto colorido sobre fundo claro ou escuro, com contraste suficiente.
  Color corSobreSuperficie(Brightness brilho) {
    if (brilho == Brightness.dark) {
      return switch (this) {
        semDados => const Color(0xFFB4BAC8),
        baixa => const Color(0xFF6FD694),
        moderada => const Color(0xFFFFCF5C),
        alta => const Color(0xFFFFA45C),
        critica => const Color(0xFFFF8A80),
      };
    }
    return switch (this) {
      semDados => const Color(0xFF4B5565),
      baixa => const Color(0xFF12692F),
      moderada => const Color(0xFF8A5A00),
      alta => const Color(0xFFB04E00),
      critica => const Color(0xFFB3261E),
    };
  }

  static NivelEspera porCodigo(String? codigo) => values.firstWhere(
        (n) => n.codigo == codigo,
        orElse: () => semDados,
      );

  static NivelEspera porMinutos(int? minutos) {
    if (minutos == null) return semDados;
    if (minutos <= 15) return baixa;
    if (minutos <= 45) return moderada;
    if (minutos <= 90) return alta;
    return critica;
  }
}

/// Percepção do tamanho da fila informada pelo usuário.
enum TamanhoFila {
  semFila('sem_fila', 'Sem fila', 'Atendimento imediato'),
  curta('curta', 'Curta', 'Até 15 minutos'),
  media('media', 'Média', 'Cerca de 40 minutos'),
  longa('longa', 'Longa', 'Mais de 1 hora'),
  lotada('lotada', 'Lotada', 'Mais de 2 horas');

  const TamanhoFila(this.codigo, this.rotulo, this.descricao);

  final String codigo;
  final String rotulo;
  final String descricao;

  static TamanhoFila porCodigo(String? codigo) =>
      values.firstWhere((t) => t.codigo == codigo, orElse: () => media);
}
