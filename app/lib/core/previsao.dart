import '../models/unidade.dart';

/// Como está o horário atual em relação ao que é típico para a unidade.
enum Momento { bom, normal, pico }

class AnaliseDoMomento {
  const AnaliseDoMomento(this.momento, this.texto);

  final Momento momento;
  final String texto;
}

/// Compara a espera de agora com a espera típica da mesma hora (como o "ao vivo × típico" do Google Maps).
///
/// - Com fila informada por cidadãos ([esperaAoVivo]): "X% mais vazia/cheia que o normal" quando a diferença é de
///   20% ou mais; senão, "dentro do normal".
/// - Sem fila informada: usa só a curva típica do dia. A hora entre as mais vazias vira "bom momento para ir"; a
///   entre as mais cheias vira "horário de pico".
/// Devolve nulo quando não há dados suficientes (sem previsão para a hora, ou curva quase plana).
AnaliseDoMomento? analisarMomento(List<PrevisaoHora> previsao, int hora, {int? esperaAoVivo}) {
  if (previsao.isEmpty) return null;
  final atual = previsao.where((p) => p.hora == hora).firstOrNull;
  if (atual == null) return null;

  final medias = previsao.map((p) => p.mediaMin);
  final minimo = medias.reduce((a, b) => a < b ? a : b);
  final maximo = medias.reduce((a, b) => a > b ? a : b);

  if (esperaAoVivo != null && atual.mediaMin >= 10) {
    final pct = ((esperaAoVivo - atual.mediaMin) * 100 / atual.mediaMin).round();
    if (pct <= -20) return AnaliseDoMomento(Momento.bom, '${-pct}% mais vazia que o normal para este horário');
    if (pct >= 20) return AnaliseDoMomento(Momento.pico, '$pct% mais cheia que o normal para este horário');
    return const AnaliseDoMomento(Momento.normal, 'Dentro do normal para este horário');
  }

  if (maximo <= minimo * 1.3) return null; // curva quase plana: não há o que recomendar
  if (atual.mediaMin <= minimo * 1.15) {
    return const AnaliseDoMomento(Momento.bom, 'Bom momento para ir: costuma estar entre os horários mais vazios');
  }
  if (atual.mediaMin >= maximo * 0.9) {
    return const AnaliseDoMomento(Momento.pico, 'Horário de pico: costuma estar cheio agora. Se puder, vá mais tarde');
  }
  return null;
}
