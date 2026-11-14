import 'package:flutter/material.dart';

/// Faixa de espera de uma unidade, calculada pelo banco.
enum NivelEspera {
  semDados('sem_dados', 'Sem dados', Color(0xFF757575), Icons.help_outline),
  baixa('baixa', 'Fila baixa', Color(0xFF2E7D32), Icons.sentiment_satisfied_alt),
  moderada('moderada', 'Fila moderada', Color(0xFFF9A825), Icons.sentiment_neutral),
  alta('alta', 'Fila alta', Color(0xFFEF6C00), Icons.sentiment_dissatisfied),
  critica('critica', 'Fila muito alta', Color(0xFFC62828), Icons.warning_amber);

  const NivelEspera(this.codigo, this.rotulo, this.cor, this.icone);

  final String codigo;
  final String rotulo;
  final Color cor;
  final IconData icone;

  /// Cor do texto que garante contraste sobre [cor].
  Color get corDoTexto => this == moderada ? Colors.black : Colors.white;

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
