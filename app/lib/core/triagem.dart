/// Orientação informativa de qual serviço procurar, a partir de sinais de alerta conhecidos.
/// NÃO é diagnóstico nem substitui avaliação profissional. O conteúdo ainda precisa de revisão por
/// profissional de saúde antes de qualquer lançamento (ver docs/seguranca-e-privacidade.md).
library;

enum GravidadeDoSinal { emergencia, urgencia }

class SinalDeAlerta {
  const SinalDeAlerta(this.id, this.texto, this.gravidade);

  final String id;
  final String texto;
  final GravidadeDoSinal gravidade;
}

const sinaisDeAlerta = <SinalDeAlerta>[
  // Ligar 192 (SAMU)
  SinalDeAlerta('dor_peito', 'Dor forte ou aperto no peito', GravidadeDoSinal.emergencia),
  SinalDeAlerta('falta_ar', 'Falta de ar intensa, dificuldade para respirar', GravidadeDoSinal.emergencia),
  SinalDeAlerta('avc', 'Boca torta, fraqueza num lado do corpo ou fala enrolada, de repente', GravidadeDoSinal.emergencia),
  SinalDeAlerta('convulsao', 'Convulsão', GravidadeDoSinal.emergencia),
  SinalDeAlerta('desmaio', 'Desmaio ou confusão mental repentina', GravidadeDoSinal.emergencia),
  SinalDeAlerta('sangramento', 'Sangramento forte que não para', GravidadeDoSinal.emergencia),
  SinalDeAlerta('trauma', 'Acidente grave, queda de altura ou golpe forte na cabeça', GravidadeDoSinal.emergencia),
  SinalDeAlerta('alergia', 'Inchaço de boca ou garganta após comer, picada ou remédio', GravidadeDoSinal.emergencia),
  SinalDeAlerta('engasgo', 'Engasgo que não resolve', GravidadeDoSinal.emergencia),
  SinalDeAlerta('queimadura', 'Queimadura extensa ou no rosto', GravidadeDoSinal.emergencia),
  // UPA ou pronto-socorro
  SinalDeAlerta('febre_alta', 'Febre alta (acima de 39 °C) ou febre há mais de 3 dias', GravidadeDoSinal.urgencia),
  SinalDeAlerta('vomito', 'Vômito ou diarreia que não param, com sinais de desidratação', GravidadeDoSinal.urgencia),
  SinalDeAlerta('dor_forte', 'Dor forte que não melhora (barriga, ouvido, cabeça)', GravidadeDoSinal.urgencia),
  SinalDeAlerta('fratura', 'Suspeita de fratura ou corte profundo', GravidadeDoSinal.urgencia),
  SinalDeAlerta('chiado', 'Falta de ar leve ou chiado no peito', GravidadeDoSinal.urgencia),
  SinalDeAlerta('crianca', 'Criança muito molinha, sem querer beber líquidos', GravidadeDoSinal.urgencia),
];

enum Orientacao { samu, upaOuProntoSocorro, ubs }

class ResultadoDaTriagem {
  const ResultadoDaTriagem(this.orientacao, this.titulo, this.texto, this.tiposDeUnidade);

  final Orientacao orientacao;
  final String titulo;
  final String texto;

  /// Tipos de unidade para mostrar no mapa; vazio quando a orientação é ligar 192.
  final List<String> tiposDeUnidade;
}

/// Regra: qualquer sinal de emergência manda ligar 192; senão qualquer sinal de urgência manda para UPA ou
/// pronto-socorro; sem sinais, a porta de entrada é a UBS. A pessoa sempre pode procurar atendimento antes.
ResultadoDaTriagem avaliarTriagem(Set<String> marcados) {
  final sinais = sinaisDeAlerta.where((s) => marcados.contains(s.id));
  if (sinais.any((s) => s.gravidade == GravidadeDoSinal.emergencia)) {
    return const ResultadoDaTriagem(
      Orientacao.samu,
      'Ligue 192 (SAMU) agora',
      'Esses sinais podem indicar uma emergência. Não espere em fila e não vá dirigindo. '
          'Se estiver sozinho, peça ajuda a alguém por perto.',
      [],
    );
  }
  if (sinais.isNotEmpty) {
    return const ResultadoDaTriagem(
      Orientacao.upaOuProntoSocorro,
      'Procure uma UPA ou um pronto-socorro hoje',
      'Esses sinais pedem avaliação médica no mesmo dia. Veja no mapa qual está com menos fila. '
          'Se piorar no caminho, ligue 192.',
      ['UPA', 'Pronto-socorro'],
    );
  }
  return const ResultadoDaTriagem(
    Orientacao.ubs,
    'Uma UBS costuma resolver',
    'Sem sinais de alerta, a Unidade Básica de Saúde é a porta de entrada: consultas, vacinas, receitas e '
        'acompanhamento. Se algum sinal aparecer ou piorar, volte aqui ou ligue 192.',
    ['UBS'],
  );
}

const avisoDaTriagem =
    'Esta orientação é informativa e não substitui avaliação profissional. Na dúvida, procure atendimento.';
