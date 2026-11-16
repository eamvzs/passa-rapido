import '../core/formatos.dart';
import '../core/nivel_espera.dart';

/// Check-in ou observação do usuário em uma unidade.
class RegistroFila {
  const RegistroFila({
    required this.id,
    required this.unidadeId,
    required this.nomeUnidade,
    required this.tipo,
    required this.tamanho,
    required this.status,
    required this.chegadaEm,
    this.atendidoEm,
    this.esperaRealMin,
  });

  final int id;
  final int unidadeId;
  final String? nomeUnidade;
  final String tipo;
  final TamanhoFila tamanho;
  final String status;
  final DateTime chegadaEm;
  final DateTime? atendidoEm;
  final int? esperaRealMin;

  bool get aguardando => status == 'aguardando';
  bool get atendido => status == 'atendido';

  factory RegistroFila.deMapa(Map<String, dynamic> m) => RegistroFila(
        id: m['id'] as int,
        unidadeId: m['unidade_id'] as int,
        nomeUnidade: (m['unidade'] as Map<String, dynamic>?)?['nome'] as String?,
        tipo: m['tipo'] as String,
        tamanho: TamanhoFila.porCodigo(m['tamanho_fila'] as String?),
        status: m['status'] as String,
        chegadaEm: DateTime.parse(m['chegada_em'] as String).toLocal(),
        atendidoEm: DateTime.tryParse(m['atendido_em'] as String? ?? '')?.toLocal(),
        esperaRealMin: m['espera_real_min'] as int?,
      );
}

/// Aviso de um usuário sobre a situação da unidade.
class Relato {
  const Relato({
    required this.id,
    required this.unidadeId,
    required this.proprio,
    required this.autor,
    required this.tipo,
    required this.descricao,
    required this.confirmacoes,
    required this.criadoEm,
  });

  final int id;
  final int unidadeId;

  /// O aviso é da própria pessoa que está vendo (o banco calcula; o identificador do autor não sai do servidor).
  final bool proprio;
  final String autor;
  final String tipo;
  final String? descricao;
  final int confirmacoes;
  final DateTime criadoEm;

  static const rotulos = {
    'sem_medico': 'Falta de médico',
    'sem_vacina': 'Falta de vacina',
    'sem_medicamento': 'Falta de medicamento',
    'sistema_fora': 'Sistema fora do ar',
    'sem_senha': 'Senhas esgotadas',
    'atendimento_normal': 'Atendimento normal',
    'outro': 'Outro aviso',
  };

  String get rotulo => rotulos[tipo] ?? tipo;
  bool get positivo => tipo == 'atendimento_normal';

  factory Relato.deMapa(Map<String, dynamic> m) => Relato(
        id: m['id'] as int,
        unidadeId: m['unidade_id'] as int,
        proprio: m['proprio'] as bool? ?? false,
        autor: m['autor'] as String? ?? 'Cidadão',
        tipo: m['tipo'] as String,
        descricao: m['descricao'] as String?,
        confirmacoes: m['confirmacoes'] as int? ?? 0,
        criadoEm: DateTime.parse(m['criado_em'] as String).toLocal(),
      );
}

class Avaliacao {
  const Avaliacao({
    this.id,
    required this.autor,
    this.proprio = false,
    required this.nota,
    this.comentario,
    this.oculta = false,
    required this.criadoEm,
  });

  final int? id;
  final String autor;

  /// A avaliação é da própria pessoa que está vendo.
  final bool proprio;
  final int nota;
  final String? comentario;

  /// Comentário retirado depois de denúncias de várias pessoas; a nota continua valendo.
  final bool oculta;
  final DateTime criadoEm;

  factory Avaliacao.deMapa(Map<String, dynamic> m) => Avaliacao(
        id: m['id'] as int?,
        oculta: m['oculta'] as bool? ?? false,
        autor: m['autor'] as String? ?? 'Cidadão',
        proprio: m['proprio'] as bool? ?? false,
        nota: m['nota'] as int,
        comentario: m['comentario'] as String?,
        criadoEm: DateTime.parse(m['criado_em'] as String).toLocal(),
      );
}

class Favorito {
  const Favorito({required this.unidadeId, required this.nomeUnidade, required this.limiteMin, required this.alertaAtivo});

  final int unidadeId;
  final String nomeUnidade;
  final int limiteMin;
  final bool alertaAtivo;

  factory Favorito.deMapa(Map<String, dynamic> m) => Favorito(
        unidadeId: m['unidade_id'] as int,
        nomeUnidade: (m['unidade'] as Map<String, dynamic>?)?['nome'] as String? ?? '',
        limiteMin: m['limite_espera_min'] as int,
        alertaAtivo: m['alerta_ativo'] as bool? ?? true,
      );
}

class Notificacao {
  const Notificacao({
    required this.id,
    required this.unidadeId,
    required this.titulo,
    required this.mensagem,
    required this.lida,
    required this.criadoEm,
  });

  final int id;
  final int? unidadeId;
  final String titulo;
  final String mensagem;
  final bool lida;
  final DateTime criadoEm;

  factory Notificacao.deMapa(Map<String, dynamic> m) => Notificacao(
        id: m['id'] as int,
        unidadeId: m['unidade_id'] as int?,
        titulo: m['titulo'] as String,
        mensagem: m['mensagem'] as String,
        lida: m['lida'] as bool? ?? false,
        criadoEm: DateTime.parse(m['criado_em'] as String).toLocal(),
      );
}

class Perfil {
  const Perfil({
    required this.id,
    required this.nome,
    required this.pontos,
    required this.nivel,
    this.confiabilidade = 50,
  });

  final String id;
  final String nome;
  final int pontos;
  final String nivel;

  /// De 0 a 100: o quanto a fila que a pessoa informa concorda com a espera que ela mede.
  final int confiabilidade;

  static const rotulosNivel = {
    'iniciante': 'Iniciante',
    'colaborador': 'Colaborador',
    'confiavel': 'Confiável',
  };

  String get rotuloNivel => rotulosNivel[nivel] ?? nivel;

  /// Pontos que faltam para o próximo nível, ou nulo no nível máximo.
  int? get pontosParaProximoNivel {
    if (pontos < 50) return 50 - pontos;
    if (pontos < 200) return 200 - pontos;
    return null;
  }

  double get progressoNoNivel {
    if (pontos < 50) return pontos / 50;
    if (pontos < 200) return (pontos - 50) / 150;
    return 1;
  }

  factory Perfil.deMapa(Map<String, dynamic> m) => Perfil(
        id: m['id'] as String,
        nome: m['nome'] as String,
        pontos: m['pontos'] as int? ?? 0,
        nivel: m['nivel'] as String? ?? 'iniciante',
        confiabilidade: (m['confiabilidade'] as num?)?.toInt() ?? 50,
      );
}

class PosicaoRanking {
  const PosicaoRanking({required this.posicao, required this.usuarioId, required this.nome, required this.pontos, required this.nivel});

  final int posicao;
  final String usuarioId;
  final String nome;
  final int pontos;
  final String nivel;

  factory PosicaoRanking.deMapa(Map<String, dynamic> m) => PosicaoRanking(
        posicao: (m['posicao'] as num).toInt(),
        usuarioId: m['usuario_id'] as String,
        nome: m['nome'] as String,
        pontos: m['pontos'] as int,
        nivel: m['nivel'] as String,
      );
}

class PainelGeral {
  const PainelGeral({
    required this.unidadesMonitoradas,
    required this.unidadesComDados,
    required this.registrosHoje,
    required this.esperaMediaMin,
    required this.colaboradores7Dias,
  });

  final int unidadesMonitoradas;
  final int unidadesComDados;
  final int registrosHoje;
  final int? esperaMediaMin;
  final int colaboradores7Dias;

  factory PainelGeral.deMapa(Map<String, dynamic> m) => PainelGeral(
        unidadesMonitoradas: (m['unidades_monitoradas'] as num).toInt(),
        unidadesComDados: (m['unidades_com_dados'] as num).toInt(),
        registrosHoje: (m['registros_hoje'] as num).toInt(),
        esperaMediaMin: (m['espera_media_geral_min'] as num?)?.toInt(),
        colaboradores7Dias: (m['colaboradores_7_dias'] as num).toInt(),
      );
}

class IndicadorUnidade {
  const IndicadorUnidade({
    required this.unidadeId,
    required this.nome,
    required this.tipo,
    required this.registros7Dias,
    required this.esperaMediaMin,
    required this.horaPico,
  });

  final int unidadeId;
  final String nome;
  final String tipo;
  final int registros7Dias;
  final int? esperaMediaMin;
  final int? horaPico;

  factory IndicadorUnidade.deMapa(Map<String, dynamic> m) => IndicadorUnidade(
        unidadeId: m['unidade_id'] as int,
        nome: m['nome'] as String,
        tipo: m['tipo'] as String,
        registros7Dias: (m['registros_7_dias'] as num).toInt(),
        esperaMediaMin: (m['espera_media_min'] as num?)?.toInt(),
        horaPico: (m['hora_pico'] as num?)?.toInt(),
      );
}


/// Recursos de acessibilidade física que as pessoas confirmam em cada unidade.
enum RecursoDeAcessibilidade {
  rampa('rampa', 'Rampa de acesso'),
  elevador('elevador', 'Elevador'),
  banheiroAdaptado('banheiro_adaptado', 'Banheiro adaptado'),
  pisoTatil('piso_tatil', 'Piso tátil'),
  libras('libras', 'Atendimento em Libras'),
  filaPreferencial('fila_preferencial', 'Fila preferencial'),
  vagaPcd('vaga_pcd', 'Vaga para pessoa com deficiência');

  const RecursoDeAcessibilidade(this.codigo, this.rotulo);

  final String codigo;
  final String rotulo;

  static RecursoDeAcessibilidade? porCodigo(String? codigo) {
    for (final r in values) {
      if (r.codigo == codigo) return r;
    }
    return null;
  }
}

/// Quantas pessoas disseram que o recurso existe e quantas disseram que não.
class ContagemDeRecurso {
  const ContagemDeRecurso({required this.recurso, required this.sim, required this.nao});

  final RecursoDeAcessibilidade recurso;
  final int sim;
  final int nao;

  int get total => sim + nao;

  /// Só vale como "existe" quando há mais confirmações que negativas.
  bool get existe => sim > nao;
  bool get inexiste => nao > sim;

  String get resumo {
    if (total == 0) return 'Sem confirmação ainda';
    if (existe) return sim == 1 ? 'Confirmado por 1 pessoa' : 'Confirmado por $sim pessoas';
    if (inexiste) return nao == 1 ? '1 pessoa diz que não tem' : '$nao pessoas dizem que não tem';
    return 'Opiniões divididas';
  }

  static ContagemDeRecurso? deMapa(Map<String, dynamic> m) {
    final recurso = RecursoDeAcessibilidade.porCodigo(m['recurso'] as String?);
    if (recurso == null) return null;
    return ContagemDeRecurso(recurso: recurso, sim: (m['sim'] as num).toInt(), nao: (m['nao'] as num).toInt());
  }
}

/// Contribuição da pessoa nos últimos 7 dias.
class ImpactoSemanal {
  const ImpactoSemanal({
    required this.registros,
    required this.unidades,
    required this.pontos,
    required this.avisos,
    required this.avaliacoes,
    required this.sugestoesAceitas,
  });

  final int registros;
  final int unidades;
  final int pontos;
  final int avisos;
  final int avaliacoes;
  final int sugestoesAceitas;

  int get contribuicoes => registros + avisos + avaliacoes + sugestoesAceitas;

  factory ImpactoSemanal.deMapa(Map<String, dynamic> m) => ImpactoSemanal(
        registros: (m['registros_7d'] as num).toInt(),
        unidades: (m['unidades_7d'] as num).toInt(),
        pontos: (m['pontos_7d'] as num).toInt(),
        avisos: (m['avisos_7d'] as num).toInt(),
        avaliacoes: (m['avaliacoes_7d'] as num).toInt(),
        sugestoesAceitas: (m['sugestoes_aceitas'] as num).toInt(),
      );
}

/// Sugestão de correção à espera de análise (tela de moderação).
class SugestaoPendente {
  const SugestaoPendente({
    required this.id,
    required this.unidadeId,
    required this.unidadeNome,
    required this.unidadeEndereco,
    required this.campo,
    required this.descricao,
    required this.autor,
    required this.apoios,
    required this.criadoEm,
    this.latitude,
    this.longitude,
    this.unidadeLatitude,
    this.unidadeLongitude,
  });

  final int id;
  final int unidadeId;
  final String unidadeNome;
  final String unidadeEndereco;
  final String campo;
  final String descricao;
  final String autor;

  /// Outras sugestões pendentes sobre o mesmo item da mesma unidade.
  final int apoios;
  final DateTime criadoEm;
  final double? latitude;
  final double? longitude;
  final double? unidadeLatitude;
  final double? unidadeLongitude;

  static const rotulosDoCampo = {
    'localizacao': 'Localização no mapa',
    'telefone': 'Telefone',
    'endereco': 'Endereço',
    'nome': 'Nome',
    'fechada': 'Unidade fechada',
    'horario': 'Horário de funcionamento',
    'outro': 'Outro',
  };

  String get rotuloDoCampo => rotulosDoCampo[campo] ?? campo;

  factory SugestaoPendente.deMapa(Map<String, dynamic> m) => SugestaoPendente(
        id: m['id'] as int,
        unidadeId: m['unidade_id'] as int,
        unidadeNome: m['unidade_nome'] as String,
        unidadeEndereco: m['unidade_endereco'] as String,
        campo: m['campo'] as String,
        descricao: m['descricao'] as String,
        autor: m['autor'] as String? ?? 'Cidadão',
        apoios: (m['apoios'] as num?)?.toInt() ?? 0,
        criadoEm: DateTime.parse(m['criado_em'] as String).toLocal(),
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        unidadeLatitude: (m['unidade_latitude'] as num?)?.toDouble(),
        unidadeLongitude: (m['unidade_longitude'] as num?)?.toDouble(),
      );
}

/// Conteúdo denunciado (aviso ou avaliação) à espera da decisão do moderador.
class DenunciaPendente {
  const DenunciaPendente({
    required this.alvo,
    required this.alvoId,
    required this.unidadeNome,
    required this.texto,
    required this.denuncias,
    required this.motivos,
    required this.oculto,
  });

  final String alvo;
  final int alvoId;
  final String? unidadeNome;
  final String texto;
  final int denuncias;
  final String motivos;
  final bool oculto;

  String get rotuloDoAlvo => alvo == 'relato' ? 'Aviso' : 'Avaliação';

  factory DenunciaPendente.deMapa(Map<String, dynamic> m) => DenunciaPendente(
        alvo: m['alvo'] as String,
        alvoId: (m['alvo_id'] as num).toInt(),
        unidadeNome: m['unidade_nome'] as String?,
        texto: m['texto'] as String? ?? '',
        denuncias: (m['denuncias'] as num).toInt(),
        motivos: m['motivos'] as String? ?? '',
        oculto: m['oculto'] as bool? ?? false,
      );
}

/// Uma linha da visão por região: bairro e tipo de unidade, com números agregados.
class RegiaoDaGestao {
  const RegiaoDaGestao({
    required this.cidade,
    required this.bairro,
    required this.tipo,
    required this.unidades,
    required this.abertasAgora,
    required this.esperaMediaMin,
    required this.unidadesComFilaReal,
    required this.registros7Dias,
    required this.horaPico,
    required this.esperaPicoMin,
  });

  final String cidade;
  final String bairro;
  final String tipo;
  final int unidades;
  final int abertasAgora;
  final int? esperaMediaMin;
  final int unidadesComFilaReal;
  final int registros7Dias;
  final int? horaPico;
  final int? esperaPicoMin;

  /// Sem nenhuma unidade com fila real: todo número da linha é estimativa do modelo.
  bool get somenteEstimativa => unidadesComFilaReal == 0;

  factory RegiaoDaGestao.deMapa(Map<String, dynamic> m) => RegiaoDaGestao(
        cidade: m['cidade'] as String,
        bairro: m['bairro'] as String,
        tipo: m['tipo'] as String,
        unidades: (m['unidades'] as num).toInt(),
        abertasAgora: (m['abertas_agora'] as num).toInt(),
        esperaMediaMin: (m['espera_media_min'] as num?)?.toInt(),
        unidadesComFilaReal: (m['unidades_com_fila_real'] as num).toInt(),
        registros7Dias: (m['registros_7d'] as num?)?.toInt() ?? 0,
        horaPico: (m['hora_pico'] as num?)?.toInt(),
        esperaPicoMin: (m['espera_pico_min'] as num?)?.toInt(),
      );
}

/// Texto CSV (separador ponto e vírgula, aberto direto no Excel em português) da visão por região.
/// Campos de texto são entre aspas e iniciados por fórmula (=, +, -, @) ganham apóstrofo, para não executar
/// fórmula ao abrir a planilha.
String regioesParaCsv(List<RegiaoDaGestao> regioes) {
  final linhas = <String>[
    'cidade;bairro;tipo;unidades;abertas_agora;espera_media_min;unidades_com_fila_real;registros_7_dias;hora_pico;espera_pico_min;somente_estimativa',
    for (final r in regioes)
      [
        campoCsv(r.cidade),
        campoCsv(r.bairro),
        campoCsv(r.tipo),
        r.unidades,
        r.abertasAgora,
        r.esperaMediaMin ?? '',
        r.unidadesComFilaReal,
        r.registros7Dias,
        r.horaPico ?? '',
        r.esperaPicoMin ?? '',
        r.somenteEstimativa ? 'sim' : 'nao',
      ].join(';'),
  ];
  return linhas.join('\n');
}
