import 'dart:math';

import '../models/unidade.dart';

const _nomesDosDias = ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'];

/// Uma hora de um dia da semana no histórico de espera de uma unidade.
class SlotSemanal {
  const SlotSemanal({required this.dia, required this.hora, required this.mediaMin, required this.amostras});

  /// 0 = domingo, como no banco.
  final int dia;
  final int hora;
  final int mediaMin;
  final int amostras;

  factory SlotSemanal.deMapa(Map<String, dynamic> m) => SlotSemanal(
        dia: m['dia_semana'] as int,
        hora: m['hora'] as int,
        mediaMin: m['media_espera_min'] as int,
        amostras: m['qtd_amostras'] as int,
      );

  /// "terça-feira às 14h (~12 min)".
  String get descricao => '${_nomesDosDias[dia]} às ${hora}h (~$mediaMin min)';
}

/// Melhor e pior janela da semana (menor e maior espera média). Em empate, vale a primeira da semana.
({SlotSemanal melhor, SlotSemanal pior})? melhorEPiorJanela(List<SlotSemanal> slots) {
  if (slots.isEmpty) return null;
  final ordenados = [...slots]..sort((a, b) => a.dia != b.dia ? a.dia.compareTo(b.dia) : a.hora.compareTo(b.hora));
  var melhor = ordenados.first;
  var pior = ordenados.first;
  for (final s in ordenados) {
    if (s.mediaMin < melhor.mediaMin) melhor = s;
    if (s.mediaMin > pior.mediaMin) pior = s;
  }
  return (melhor: melhor, pior: pior);
}

/// Resumo de um tipo de unidade (UPA, UBS...) neste momento.
class ResumoDoTipo {
  const ResumoDoTipo({
    required this.tipo,
    required this.total,
    required this.abertas,
    required this.esperaMediaMin,
    required this.somenteEstimativa,
  });

  final String tipo;
  final int total;
  final int abertas;

  /// Média da espera das unidades abertas com dado; nulo se nenhuma tem.
  final int? esperaMediaMin;

  /// Verdadeiro quando nenhuma das unidades da média tem fila informada por cidadãos (é só o modelo).
  final bool somenteEstimativa;
}

/// Agrupa as unidades por tipo e calcula quantas estão abertas e a espera média agora.
/// A ordem é da menor espera para a maior; tipos sem dado vão para o fim.
List<ResumoDoTipo> resumirPorTipo(List<Unidade> unidades) {
  final porTipo = <String, List<Unidade>>{};
  for (final u in unidades) {
    porTipo.putIfAbsent(u.tipo, () => []).add(u);
  }
  final resumos = [
    for (final e in porTipo.entries)
      () {
        final abertasComDado = e.value.where((u) => u.abertaAgora && u.esperaMin != null).toList();
        final media = abertasComDado.isEmpty
            ? null
            : (abertasComDado.map((u) => u.esperaMin!).reduce((a, b) => a + b) / abertasComDado.length).round();
        return ResumoDoTipo(
          tipo: e.key,
          total: e.value.length,
          abertas: e.value.where((u) => u.abertaAgora).length,
          esperaMediaMin: media,
          somenteEstimativa: abertasComDado.every((u) => !u.emTempoReal),
        );
      }(),
  ];
  resumos.sort((a, b) {
    if (a.esperaMediaMin == null && b.esperaMediaMin == null) return a.tipo.compareTo(b.tipo);
    if (a.esperaMediaMin == null) return 1;
    if (b.esperaMediaMin == null) return -1;
    return a.esperaMediaMin!.compareTo(b.esperaMediaMin!);
  });
  return resumos;
}

/// Esta unidade comparada às do mesmo tipo por perto.
class ComparacaoComVizinhas {
  const ComparacaoComVizinhas({
    required this.vizinhas,
    required this.mediaMin,
    required this.diferencaPct,
    required this.melhor,
    required this.raioKm,
  });

  /// Quantas unidades do mesmo tipo, abertas e com espera conhecida, entraram na conta.
  final int vizinhas;
  final int mediaMin;

  /// Positivo: esta unidade está mais cheia que a média das vizinhas. Negativo: mais vazia.
  final int diferencaPct;

  /// A vizinha com menor espera.
  final Unidade melhor;
  final double raioKm;
}

double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295; // pi / 180
  final a = 0.5 -
      cos((lat2 - lat1) * p) / 2 +
      cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
  return 12742 * asin(sqrt(a));
}

/// Compara [alvo] com as unidades do mesmo tipo a até [raioKm]. Nulo quando [alvo] está fechada ou sem espera,
/// ou quando não há ao menos 2 vizinhas para comparar.
ComparacaoComVizinhas? compararComVizinhas(Unidade alvo, List<Unidade> todas, {double raioKm = 5}) {
  final espera = alvo.esperaMin;
  if (espera == null || !alvo.abertaAgora) return null;
  final vizinhas = todas.where((u) =>
      u.id != alvo.id &&
      u.tipoUnidadeId == alvo.tipoUnidadeId &&
      u.abertaAgora &&
      u.esperaMin != null &&
      _distanciaKm(alvo.latitude, alvo.longitude, u.latitude, u.longitude) <= raioKm).toList();
  if (vizinhas.length < 2) return null;
  final media = (vizinhas.fold<int>(0, (soma, u) => soma + u.esperaMin!) / vizinhas.length).round();
  if (media <= 0) return null;
  vizinhas.sort((a, b) => a.esperaMin!.compareTo(b.esperaMin!));
  return ComparacaoComVizinhas(
    vizinhas: vizinhas.length,
    mediaMin: media,
    diferencaPct: ((espera - media) * 100 / media).round(),
    melhor: vizinhas.first,
    raioKm: raioKm,
  );
}
