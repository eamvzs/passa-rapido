import 'dart:math';

import '../models/unidade.dart';

/// Percebe que a pessoa está dentro de uma unidade há um tempo e é hora de perguntar "como está a fila?".
/// Lógica pura (sem GPS nem relógio próprio) para poder ser testada: quem chama passa a posição e a hora.
class DetectorDePresenca {
  DetectorDePresenca({
    this.raioM = 120,
    this.permanencia = const Duration(minutes: 10),
    this.silencio = const Duration(hours: 3),
  });

  final double raioM;
  final Duration permanencia;

  /// Depois de perguntar (ou da pessoa dispensar), não pergunta de novo sobre a mesma unidade neste prazo.
  final Duration silencio;

  int? _unidadeAtual;
  DateTime? _desde;
  final Map<int, DateTime> _perguntadoEm = {};

  /// Marca a unidade como já perguntada/dispensada em [agora].
  void silenciar(int unidadeId, DateTime agora) => _perguntadoEm[unidadeId] = agora;

  /// Devolve o id da unidade sobre a qual perguntar agora, ou nulo.
  /// [posicao] é (latitude, longitude). Só conta unidade aberta.
  int? atualizar({
    required (double, double) posicao,
    required Iterable<Unidade> unidades,
    required DateTime agora,
  }) {
    Unidade? mais;
    var menor = raioM;
    for (final u in unidades) {
      if (!u.abertaAgora) continue;
      final m = _metros(posicao.$1, posicao.$2, u.latitude, u.longitude);
      if (m <= menor) {
        menor = m;
        mais = u;
      }
    }
    if (mais == null) {
      _unidadeAtual = null;
      _desde = null;
      return null;
    }
    if (_unidadeAtual != mais.id) {
      _unidadeAtual = mais.id;
      _desde = agora;
      return null;
    }
    if (agora.difference(_desde!) < permanencia) return null;
    final ultima = _perguntadoEm[mais.id];
    if (ultima != null && agora.difference(ultima) < silencio) return null;
    _perguntadoEm[mais.id] = agora;
    return mais.id;
  }

  static double _metros(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a));
  }
}
