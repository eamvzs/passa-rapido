/// Feriados e pontos facultativos que mudam o funcionamento dos serviços públicos.
/// Cálculo local (sem internet): datas fixas e datas que dependem da Páscoa.
library;

enum TipoDeFeriado { feriado, pontoFacultativo }

class Feriado {
  const Feriado(this.nome, this.tipo, this.data);

  final String nome;
  final TipoDeFeriado tipo;
  final DateTime data;

  String get rotulo => tipo == TipoDeFeriado.feriado ? 'feriado' : 'ponto facultativo';
}

/// Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher).
DateTime domingoDePascoa(int ano) {
  final a = ano % 19;
  final b = ano ~/ 100;
  final c = ano % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final mes = (h + l - 7 * m + 114) ~/ 31;
  final dia = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(ano, mes, dia);
}

/// Todos os feriados e pontos facultativos do [ano], em ordem de data.
/// [cidade] liga os feriados municipais conhecidos (hoje, o aniversário de São Paulo).
List<Feriado> feriadosDoAno(int ano, {String? cidade}) {
  final pascoa = domingoDePascoa(ano);
  DateTime depoisDaPascoa(int dias) => DateTime(pascoa.year, pascoa.month, pascoa.day + dias);

  final lista = <Feriado>[
    Feriado('Confraternização Universal', TipoDeFeriado.feriado, DateTime(ano, 1, 1)),
    if (cidade == 'São Paulo')
      Feriado('Aniversário da cidade de São Paulo', TipoDeFeriado.feriado, DateTime(ano, 1, 25)),
    Feriado('Carnaval', TipoDeFeriado.pontoFacultativo, depoisDaPascoa(-48)),
    Feriado('Carnaval', TipoDeFeriado.pontoFacultativo, depoisDaPascoa(-47)),
    Feriado('Sexta-feira Santa', TipoDeFeriado.feriado, depoisDaPascoa(-2)),
    Feriado('Tiradentes', TipoDeFeriado.feriado, DateTime(ano, 4, 21)),
    Feriado('Dia do Trabalho', TipoDeFeriado.feriado, DateTime(ano, 5, 1)),
    Feriado('Corpus Christi', TipoDeFeriado.pontoFacultativo, depoisDaPascoa(60)),
    Feriado('Revolução Constitucionalista (feriado em SP)', TipoDeFeriado.feriado, DateTime(ano, 7, 9)),
    Feriado('Independência do Brasil', TipoDeFeriado.feriado, DateTime(ano, 9, 7)),
    Feriado('Nossa Senhora Aparecida', TipoDeFeriado.feriado, DateTime(ano, 10, 12)),
    Feriado('Finados', TipoDeFeriado.feriado, DateTime(ano, 11, 2)),
    Feriado('Proclamação da República', TipoDeFeriado.feriado, DateTime(ano, 11, 15)),
    Feriado('Dia da Consciência Negra', TipoDeFeriado.feriado, DateTime(ano, 11, 20)),
    Feriado('Natal', TipoDeFeriado.feriado, DateTime(ano, 12, 25)),
  ];
  lista.sort((a, b) => a.data.compareTo(b.data));
  return lista;
}

/// O feriado (ou ponto facultativo) que cai exatamente em [dia], ou nulo.
Feriado? feriadoDe(DateTime dia, {String? cidade}) {
  for (final f in feriadosDoAno(dia.year, cidade: cidade)) {
    if (f.data.year == dia.year && f.data.month == dia.month && f.data.day == dia.day) return f;
  }
  return null;
}

/// Aviso para a ficha: hoje ou amanhã é feriado? Nulo quando não há o que avisar.
String? avisoDeFeriado(DateTime agora, {String? cidade}) {
  final hoje = feriadoDe(agora, cidade: cidade);
  if (hoje != null) {
    return 'Hoje é ${hoje.rotulo} (${hoje.nome}). Muitas unidades mudam o horário ou fecham: ligue antes de ir.';
  }
  final amanha = feriadoDe(DateTime(agora.year, agora.month, agora.day + 1), cidade: cidade);
  if (amanha != null) {
    return 'Amanhã é ${amanha.rotulo} (${amanha.nome}). Se for amanhã, confirme o horário da unidade.';
  }
  return null;
}
