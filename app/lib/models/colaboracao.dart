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
    required this.usuarioId,
    required this.autor,
    required this.tipo,
    required this.descricao,
    required this.confirmacoes,
    required this.criadoEm,
  });

  final int id;
  final int unidadeId;
  final String usuarioId;
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
        usuarioId: m['usuario_id'] as String,
        autor: (m['usuario'] as Map<String, dynamic>?)?['nome'] as String? ?? 'Cidadão',
        tipo: m['tipo'] as String,
        descricao: m['descricao'] as String?,
        confirmacoes: m['confirmacoes'] as int? ?? 0,
        criadoEm: DateTime.parse(m['criado_em'] as String).toLocal(),
      );
}

class Avaliacao {
  const Avaliacao({required this.autor, required this.usuarioId, required this.nota, this.comentario, required this.criadoEm});

  final String autor;
  final String usuarioId;
  final int nota;
  final String? comentario;
  final DateTime criadoEm;

  factory Avaliacao.deMapa(Map<String, dynamic> m) => Avaliacao(
        autor: (m['usuario'] as Map<String, dynamic>?)?['nome'] as String? ?? 'Cidadão',
        usuarioId: m['usuario_id'] as String,
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
  const Perfil({required this.id, required this.nome, required this.pontos, required this.nivel});

  final String id;
  final String nome;
  final int pontos;
  final String nivel;

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
