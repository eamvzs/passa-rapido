import 'dart:convert';

/// Compromisso do cidadão: "tenho que estar na unidade X às 14h". O app calcula a hora de sair.
class PlanoDeIda {
  const PlanoDeIda({
    required this.unidadeId,
    required this.nomeUnidade,
    required this.horario,
    required this.saida,
    required this.deslocamentoMin,
  });

  final int unidadeId;
  final String nomeUnidade;

  /// Hora marcada do atendimento.
  final DateTime horario;

  /// Hora de sair de casa.
  final DateTime saida;
  final int deslocamentoMin;

  /// Folga para imprevistos e para achar o local.
  static const folgaMin = 15;

  /// Média urbana conservadora, a mesma usada pelo banco para estimar deslocamento (20 km/h).
  static const velocidadeKmH = 20.0;

  static int deslocamentoPorDistancia(double km) => (km / velocidadeKmH * 60).ceil().clamp(1, 600);

  /// Cria o plano calculando a saída: horário marcado menos deslocamento menos folga.
  factory PlanoDeIda.calcular({
    required int unidadeId,
    required String nomeUnidade,
    required DateTime horario,
    required int deslocamentoMin,
  }) =>
      PlanoDeIda(
        unidadeId: unidadeId,
        nomeUnidade: nomeUnidade,
        horario: horario,
        saida: horario.subtract(Duration(minutes: deslocamentoMin + folgaMin)),
        deslocamentoMin: deslocamentoMin,
      );

  /// O plano já passou (com tolerância de 1 hora depois do horário marcado)?
  bool venceu(DateTime agora) => agora.isAfter(horario.add(const Duration(hours: 1)));

  Map<String, dynamic> paraMapa() => {
        'unidade_id': unidadeId,
        'nome': nomeUnidade,
        'horario': horario.toIso8601String(),
        'saida': saida.toIso8601String(),
        'deslocamento_min': deslocamentoMin,
      };

  String toJson() => jsonEncode(paraMapa());

  /// Lê o plano gravado; devolve nulo se o texto estiver corrompido (o app segue sem plano).
  static PlanoDeIda? deJson(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    try {
      final m = jsonDecode(texto) as Map<String, dynamic>;
      return PlanoDeIda(
        unidadeId: m['unidade_id'] as int,
        nomeUnidade: m['nome'] as String,
        horario: DateTime.parse(m['horario'] as String),
        saida: DateTime.parse(m['saida'] as String),
        deslocamentoMin: m['deslocamento_min'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}
