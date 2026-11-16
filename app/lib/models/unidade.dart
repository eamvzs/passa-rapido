import '../core/nivel_espera.dart';

/// Unidade de atendimento com a situação atual da fila, como vem de `vw_mapa_unidades`.
class Unidade {
  const Unidade({
    required this.id,
    required this.nome,
    required this.endereco,
    required this.bairro,
    required this.cidade,
    required this.latitude,
    required this.longitude,
    required this.telefone,
    required this.tipoUnidadeId,
    required this.tipo,
    required this.esperaMin,
    required this.nivel,
    required this.fonte,
    required this.confianca,
    required this.pessoasAguardando,
    required this.atualizadoEm,
    required this.abertaAgora,
    required this.notaMedia,
    required this.qtdAvaliacoes,
    required this.relatosAtivos,
    this.origem = 'demonstracao',
    this.horarioPadrao = true,
  });

  final int id;
  final String nome;
  final String endereco;
  final String? bairro;
  final String cidade;
  final double latitude;
  final double longitude;
  final String? telefone;
  final int tipoUnidadeId;
  final String tipo;
  final int? esperaMin;
  final NivelEspera nivel;

  /// `tempo_real`, `historico` ou `sem_dados`.
  final String fonte;
  final int confianca;
  final int pessoasAguardando;
  final DateTime? atualizadoEm;
  final bool abertaAgora;
  final double? notaMedia;
  final int qtdAvaliacoes;
  final int relatosAtivos;

  /// `cnes` (cadastro oficial do Ministério da Saúde), `openstreetmap` (cadastro colaborativo)
  /// ou `demonstracao` (dado de exemplo).
  final String origem;

  /// Verdadeiro quando o horário é o padrão do tipo de unidade, não o publicado pela própria unidade.
  final bool horarioPadrao;

  bool get dadosReais => origem != 'demonstracao';

  /// Crédito da fonte do cadastro (nome, endereço e localização), exigido pelas licenças dos dados.
  String? get creditoDoCadastro => switch (origem) {
        'cnes' => 'Cadastro da unidade: CNES/DATASUS, Ministério da Saúde',
        'openstreetmap' => 'Cadastro da unidade: © colaboradores do OpenStreetMap',
        _ => null,
      };

  /// Espera lida direto do sistema de um órgão conveniado (`oficial`).
  bool get oficial => fonte == 'oficial';

  /// Fila informada por cidadãos ou lida do órgão: dado real, não estimativa do modelo.
  bool get emTempoReal => fonte == 'tempo_real' || oficial;

  /// Espera vinda do modelo (histórico estimado), ainda sem registro de cidadão para este horário.
  bool get estimada => fonte == 'historico';

  factory Unidade.deMapa(Map<String, dynamic> m) => Unidade(
        id: m['id'] as int,
        nome: m['nome'] as String,
        endereco: m['endereco'] as String,
        bairro: m['bairro'] as String?,
        cidade: m['cidade'] as String,
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        telefone: m['telefone'] as String?,
        tipoUnidadeId: m['tipo_unidade_id'] as int,
        tipo: m['tipo'] as String,
        esperaMin: m['espera_estimada_min'] as int?,
        nivel: NivelEspera.porCodigo(m['nivel'] as String?),
        fonte: m['fonte'] as String? ?? 'sem_dados',
        confianca: (m['confianca'] as num?)?.toInt() ?? 0,
        pessoasAguardando: (m['pessoas_aguardando'] as num?)?.toInt() ?? 0,
        atualizadoEm: DateTime.tryParse(m['atualizado_em'] as String? ?? '')?.toLocal(),
        abertaAgora: m['aberta_agora'] as bool? ?? false,
        notaMedia: (m['nota_media'] as num?)?.toDouble(),
        qtdAvaliacoes: (m['qtd_avaliacoes'] as num?)?.toInt() ?? 0,
        relatosAtivos: (m['relatos_ativos'] as num?)?.toInt() ?? 0,
        origem: m['origem'] as String? ?? 'demonstracao',
        horarioPadrao: m['horario_padrao'] as bool? ?? true,
      );

  /// Aplica uma atualização em tempo real da tabela `situacao_unidade`.
  Unidade comSituacao(Map<String, dynamic> s) => Unidade(
        id: id,
        nome: nome,
        endereco: endereco,
        bairro: bairro,
        cidade: cidade,
        latitude: latitude,
        longitude: longitude,
        telefone: telefone,
        tipoUnidadeId: tipoUnidadeId,
        tipo: tipo,
        esperaMin: s['espera_estimada_min'] as int?,
        nivel: NivelEspera.porCodigo(s['nivel'] as String?),
        fonte: s['fonte'] as String? ?? 'sem_dados',
        confianca: (s['confianca'] as num?)?.toInt() ?? 0,
        pessoasAguardando: (s['pessoas_aguardando'] as num?)?.toInt() ?? 0,
        atualizadoEm: DateTime.tryParse(s['atualizado_em'] as String? ?? '')?.toLocal(),
        abertaAgora: abertaAgora,
        notaMedia: notaMedia,
        qtdAvaliacoes: qtdAvaliacoes,
        relatosAtivos: relatosAtivos,
        origem: origem,
        horarioPadrao: horarioPadrao,
      );
}

class TipoUnidade {
  const TipoUnidade({required this.id, required this.nome});

  final int id;
  final String nome;

  factory TipoUnidade.deMapa(Map<String, dynamic> m) =>
      TipoUnidade(id: m['id'] as int, nome: m['nome'] as String);
}

class Servico {
  const Servico({required this.id, required this.nome, this.descricao, this.documentos});

  final int id;
  final String nome;
  final String? descricao;
  final String? documentos;

  factory Servico.deMapa(Map<String, dynamic> m) => Servico(
        id: m['id'] as int,
        nome: m['nome'] as String,
        descricao: m['descricao'] as String?,
        documentos: m['documentos_necessarios'] as String?,
      );
}

class HorarioFuncionamento {
  const HorarioFuncionamento({required this.diaSemana, required this.abre, required this.fecha});

  final int diaSemana;
  final String abre;
  final String fecha;

  bool get dia24Horas => abre.startsWith('00:00') && fecha.startsWith('23:59');

  factory HorarioFuncionamento.deMapa(Map<String, dynamic> m) => HorarioFuncionamento(
        diaSemana: m['dia_semana'] as int,
        abre: (m['abre'] as String).substring(0, 5),
        fecha: (m['fecha'] as String).substring(0, 5),
      );
}

/// "Abre hoje às 08:00", "Abre amanhã às 08:00" ou "Abre segunda-feira às 08:00"; nulo se não há horário.
/// `agora` deve estar no fuso da unidade (o app usa o horário do aparelho).
String? proximaAbertura(List<HorarioFuncionamento> horarios, DateTime agora) {
  if (horarios.isEmpty) return null;
  const nomes = ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'];
  final hoje = agora.weekday % 7; // domingo = 0, como no banco
  final minutosAgora = agora.hour * 60 + agora.minute;
  for (var desloc = 0; desloc <= 7; desloc++) {
    final dia = (hoje + desloc) % 7;
    for (final h in horarios.where((h) => h.diaSemana == dia)) {
      final partes = h.abre.split(':');
      final minutosAbre = int.parse(partes[0]) * 60 + int.parse(partes[1]);
      if (desloc == 0 && minutosAbre <= minutosAgora) continue; // já abriu hoje (ou já passou)
      final quando = desloc == 0 ? 'hoje' : (desloc == 1 ? 'amanhã' : nomes[dia]);
      return 'Abre $quando às ${h.abre}';
    }
  }
  return null;
}

/// Espera média prevista para uma hora do dia (`fn_melhor_horario`).
class PrevisaoHora {
  const PrevisaoHora({required this.hora, required this.mediaMin, required this.amostras, required this.melhor});

  final int hora;
  final int mediaMin;
  final int amostras;
  final bool melhor;

  factory PrevisaoHora.deMapa(Map<String, dynamic> m) => PrevisaoHora(
        hora: m['hora'] as int,
        mediaMin: m['media_espera_min'] as int,
        amostras: m['qtd_amostras'] as int,
        melhor: m['melhor'] as bool? ?? false,
      );
}

/// Unidade recomendada pelo menor tempo total (`fn_recomendar_unidades`).
class Recomendacao {
  const Recomendacao({
    required this.unidadeId,
    required this.nome,
    required this.tipo,
    required this.distanciaKm,
    required this.esperaMin,
    required this.deslocamentoMin,
    required this.tempoTotalMin,
    required this.nivel,
    required this.confianca,
  });

  final int unidadeId;
  final String nome;
  final String tipo;
  final double distanciaKm;
  final int? esperaMin;
  final int deslocamentoMin;
  final int? tempoTotalMin;
  final NivelEspera nivel;
  final int confianca;

  factory Recomendacao.deMapa(Map<String, dynamic> m) => Recomendacao(
        unidadeId: m['unidade_id'] as int,
        nome: m['nome'] as String,
        tipo: m['tipo'] as String,
        distanciaKm: (m['distancia_km'] as num).toDouble(),
        esperaMin: m['espera_estimada_min'] as int?,
        deslocamentoMin: m['deslocamento_min'] as int,
        tempoTotalMin: m['tempo_total_min'] as int?,
        nivel: NivelEspera.porCodigo(m['nivel'] as String?),
        confianca: (m['confianca'] as num?)?.toInt() ?? 0,
      );
}
