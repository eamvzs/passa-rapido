import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/nivel_espera.dart';
import '../models/colaboracao.dart';
import '../core/insights.dart';
import '../models/unidade.dart';

/// Erro com mensagem pronta para mostrar ao usuário.
class ErroDeNegocio implements Exception {
  const ErroDeNegocio(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// Converte erros do backend em mensagens compreensíveis.
/// Os códigos PR00x são levantados pelas rotinas do banco.
ErroDeNegocio traduzirErro(Object erro) {
  if (erro is ErroDeNegocio) return erro;
  if (erro is PostgrestException) {
    if (erro.code != null && erro.code!.startsWith('PR')) return ErroDeNegocio(erro.message);
    if (erro.code == '42501') return const ErroDeNegocio('Entre na sua conta para fazer isso.');
    if (erro.code == 'PGRST204' || erro.code == '42703') {
      return const ErroDeNegocio('O banco de dados ainda não recebeu a última atualização. Rode os scripts SQL novos.');
    }
    return const ErroDeNegocio('Não foi possível concluir. Tente de novo.');
  }
  if (erro is AuthException) {
    final texto = erro.message.toLowerCase();
    if (texto.contains('invalid login')) return const ErroDeNegocio('E-mail ou senha incorretos.');
    if (texto.contains('already registered')) return const ErroDeNegocio('Este e-mail já tem cadastro.');
    if (texto.contains('rate limit')) return const ErroDeNegocio('Muitas tentativas. Aguarde alguns minutos e tente de novo.');
    if (texto.contains('password')) return const ErroDeNegocio('A senha não atende aos requisitos. Use pelo menos 8 caracteres.');
    return const ErroDeNegocio('Não foi possível entrar. Confira os dados.');
  }
  return const ErroDeNegocio('Sem conexão. Verifique a internet e tente de novo.');
}

List<Map<String, dynamic>> _lista(dynamic dados) =>
    (dados as List).cast<Map<String, dynamic>>();

/// Consultas de unidades, previsão, recomendação e indicadores.
class UnidadeRepositorio {
  UnidadeRepositorio(this._db, [this._prefs]);
  final SupabaseClient _db;
  final SharedPreferences? _prefs;

  static const _chaveCache = 'cache_unidades_v1';
  static const _chaveCacheEm = 'cache_unidades_em_v1';
  static const _tamanhoDaPagina = 1000;

  /// Quando a lista de unidades veio do aparelho (sem conexão), a hora em que ela foi salva; senão, nulo.
  DateTime? cacheUsadoEm;

  /// Todas as unidades, em páginas (a API devolve no máximo 1000 linhas por resposta). Cada carga bem-sucedida
  /// fica salva no aparelho; sem conexão, o app mostra a última cópia e avisa a hora dela.
  Future<List<Unidade>> listarMapa() async {
    try {
      final linhas = <Map<String, dynamic>>[];
      var inicio = 0;
      while (true) {
        final pagina = await _db
            .from('vw_mapa_unidades')
            .select()
            .order('id')
            .range(inicio, inicio + _tamanhoDaPagina - 1);
        linhas.addAll(pagina);
        if (pagina.length < _tamanhoDaPagina) break;
        inicio += _tamanhoDaPagina;
      }
      cacheUsadoEm = null;
      await _guardarCache(linhas);
      return linhas.map(Unidade.deMapa).toList();
    } catch (_) {
      final copia = _lerCache();
      if (copia == null) rethrow;
      cacheUsadoEm = copia.$2;
      return copia.$1.map(Unidade.deMapa).toList();
    }
  }

  Future<void> _guardarCache(List<Map<String, dynamic>> linhas) async {
    try {
      await _prefs?.setString(_chaveCache, jsonEncode(linhas));
      await _prefs?.setString(_chaveCacheEm, DateTime.now().toIso8601String());
    } catch (_) {
      // Sem espaço no aparelho: o app funciona igual, só não terá a cópia.
    }
  }

  (List<Map<String, dynamic>>, DateTime)? _lerCache() {
    try {
      final texto = _prefs?.getString(_chaveCache);
      final em = DateTime.tryParse(_prefs?.getString(_chaveCacheEm) ?? '');
      if (texto == null || em == null) return null;
      final lista = (jsonDecode(texto) as List).cast<Map<String, dynamic>>();
      return lista.isEmpty ? null : (lista, em);
    } catch (_) {
      return null;
    }
  }

  /// Apaga a cópia salva (usada ao sair da conta ou ao excluí-la).
  Future<void> limparCache() async {
    await _prefs?.remove(_chaveCache);
    await _prefs?.remove(_chaveCacheEm);
  }

  /// Confirmações de acessibilidade da unidade, por recurso.
  Future<List<ContagemDeRecurso>> acessibilidade(int unidadeId) async {
    final dados = await _db.from('vw_acessibilidade_unidade').select().eq('unidade_id', unidadeId);
    return dados.map(ContagemDeRecurso.deMapa).whereType<ContagemDeRecurso>().toList();
  }

  /// Visão agregada por bairro e tipo, para a gestão.
  Future<List<RegiaoDaGestao>> regioes() async {
    final dados = await _db.from('vw_gestao_regiao').select().order('cidade').order('bairro').order('tipo');
    return dados.map(RegiaoDaGestao.deMapa).toList();
  }

  Future<Unidade?> buscar(int id) async {
    final dados = await _db.from('vw_mapa_unidades').select().eq('id', id).maybeSingle();
    return dados == null ? null : Unidade.deMapa(dados);
  }

  /// Histórico da semana inteira (dia x hora) de uma unidade, para o mapa de calor "quando ir".
  Future<List<SlotSemanal>> historicoSemanal(int unidadeId) async {
    final dados = await _db
        .from('historico_espera')
        .select('dia_semana, hora, media_espera_min, qtd_amostras')
        .eq('unidade_id', unidadeId);
    return dados.map(SlotSemanal.deMapa).toList();
  }

  Future<List<TipoUnidade>> listarTipos() async {
    final dados = await _db.from('tipo_unidade').select('id, nome').order('id');
    return dados.map(TipoUnidade.deMapa).toList();
  }

  Future<List<Servico>> listarTodosServicos() async {
    final dados = await _db.from('servico').select().order('nome');
    return dados.map(Servico.deMapa).toList();
  }

  /// Códigos das unidades que oferecem o serviço.
  Future<Set<int>> unidadesDoServico(int servicoId) async {
    final dados = await _db.from('unidade_servico').select('unidade_id').eq('servico_id', servicoId);
    return {for (final linha in dados) linha['unidade_id'] as int};
  }

  Future<List<Servico>> listarServicos(int unidadeId) async {
    final dados = await _db
        .from('unidade_servico')
        .select('servico(id, nome, descricao, documentos_necessarios)')
        .eq('unidade_id', unidadeId);
    return dados.map((m) => Servico.deMapa(m['servico'] as Map<String, dynamic>)).toList();
  }

  Future<List<HorarioFuncionamento>> listarHorarios(int unidadeId) async {
    final dados = await _db
        .from('horario_funcionamento')
        .select()
        .eq('unidade_id', unidadeId)
        .order('dia_semana');
    return dados.map(HorarioFuncionamento.deMapa).toList();
  }

  /// [diaSemana] de 0 (domingo) a 6 (sábado).
  Future<List<PrevisaoHora>> melhorHorario(int unidadeId, int diaSemana) async {
    final dados = await _db.rpc('fn_melhor_horario', params: {
      'p_unidade_id': unidadeId,
      'p_dia_semana': diaSemana,
    });
    return _lista(dados).map(PrevisaoHora.deMapa).toList();
  }

  Future<List<Recomendacao>> recomendar({
    required double latitude,
    required double longitude,
    int? tipoUnidadeId,
    double raioKm = 15,
  }) async {
    final dados = await _db.rpc('fn_recomendar_unidades', params: {
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_tipo_unidade_id': tipoUnidadeId,
      'p_raio_km': raioKm,
    });
    return _lista(dados).map(Recomendacao.deMapa).toList();
  }

  Future<PainelGeral> painelGeral() async {
    final dados = await _db.rpc('fn_painel_geral');
    return PainelGeral.deMapa(_lista(dados).first);
  }

  Future<List<IndicadorUnidade>> indicadores() async {
    final dados = await _db
        .from('vw_indicadores_unidade')
        .select()
        .gt('registros_7_dias', 0)
        .order('espera_media_min', ascending: false)
        .limit(10);
    return dados.map(IndicadorUnidade.deMapa).toList();
  }

  Future<List<PosicaoRanking>> ranking() async {
    final dados = await _db.from('vw_ranking_colaboradores').select().order('posicao').limit(10);
    return dados.map(PosicaoRanking.deMapa).toList();
  }
}

/// Registros de fila do usuário autenticado.
class FilaRepositorio {
  FilaRepositorio(this._db);
  final SupabaseClient _db;

  static const _colunas = '*, unidade:unidade!registro_fila_unidade_id_fkey(nome)';

  /// Registro em andamento: aguardando ou atendido sem saída marcada.
  Future<RegistroFila?> registroAtivo() async {
    final dados = await _db
        .from('registro_fila')
        .select(_colunas)
        .inFilter('status', ['aguardando', 'atendido'])
        .eq('tipo', 'checkin')
        .order('chegada_em', ascending: false)
        .limit(1)
        .maybeSingle();
    return dados == null ? null : RegistroFila.deMapa(dados);
  }

  Future<RegistroFila> registrar({
    required int unidadeId,
    required TamanhoFila tamanho,
    required bool estouNaFila,
    double? latitude,
    double? longitude,
  }) async {
    final dados = await _db
        .from('registro_fila')
        .insert({
          'unidade_id': unidadeId,
          'tamanho_fila': tamanho.codigo,
          'tipo': estouNaFila ? 'checkin' : 'observacao',
          'latitude': ?latitude,
          'longitude': ?longitude,
        })
        .select(_colunas)
        .single();
    return RegistroFila.deMapa(dados);
  }

  Future<RegistroFila> marcarAtendido(int id) => _atualizar(id, {'atendido_em': _agora()});

  Future<RegistroFila> marcarSaida(int id) => _atualizar(id, {'saida_em': _agora()});

  Future<RegistroFila> desistir(int id) =>
      _atualizar(id, {'status': 'desistiu', 'saida_em': _agora()});

  Future<List<RegistroFila>> historico() async {
    final dados = await _db
        .from('registro_fila')
        .select(_colunas)
        .order('chegada_em', ascending: false)
        .limit(30);
    return dados.map(RegistroFila.deMapa).toList();
  }

  Future<RegistroFila> _atualizar(int id, Map<String, dynamic> valores) async {
    final dados =
        await _db.from('registro_fila').update(valores).eq('id', id).select(_colunas).single();
    return RegistroFila.deMapa(dados);
  }

  String _agora() => DateTime.now().toUtc().toIso8601String();
}

/// Relatos, avaliações, favoritos, notificações e perfil.
class ComunidadeRepositorio {
  ComunidadeRepositorio(this._db);
  final SupabaseClient _db;

  Future<List<Relato>> listarRelatos(int unidadeId) async {
    final dados = await _db
        .from('vw_relato_publico')
        .select()
        .eq('unidade_id', unidadeId)
        .gt('expira_em', DateTime.now().toUtc().toIso8601String())
        .order('criado_em', ascending: false)
        .limit(20);
    return dados.map(Relato.deMapa).toList();
  }

  Future<void> criarRelato({required int unidadeId, required String tipo, String? descricao}) =>
      _db.from('relato').insert({
        'unidade_id': unidadeId,
        'tipo': tipo,
        if (descricao != null && descricao.trim().isNotEmpty) 'descricao': descricao.trim(),
      });

  Future<void> confirmarRelato(int relatoId) =>
      _db.rpc('confirmar_relato', params: {'p_relato_id': relatoId});

  Future<List<Avaliacao>> listarAvaliacoes(int unidadeId) async {
    final dados = await _db
        .from('vw_avaliacao_publica')
        .select()
        .eq('unidade_id', unidadeId)
        .order('criado_em', ascending: false)
        .limit(20);
    return dados.map(Avaliacao.deMapa).toList();
  }

  Future<void> avaliar({required int unidadeId, required int nota, String? comentario}) =>
      _db.from('avaliacao').upsert({
        'unidade_id': unidadeId,
        'usuario_id': _db.auth.currentUser!.id,
        'nota': nota,
        'comentario': (comentario == null || comentario.trim().isEmpty) ? null : comentario.trim(),
      }, onConflict: 'unidade_id,usuario_id');

  /// Sugere uma correção nos dados da unidade; fica pendente até ser analisada (`prc_analisar_sugestao`).
  Future<void> sugerirCorrecao({
    required int unidadeId,
    required String campo,
    required String descricao,
    double? latitude,
    double? longitude,
  }) =>
      _db.from('sugestao_correcao').insert({
        'unidade_id': unidadeId,
        'usuario_id': _db.auth.currentUser!.id,
        'campo': campo,
        'descricao': descricao.trim(),
        'latitude': ?latitude,
        'longitude': ?longitude,
      });

  /// Meus votos de acessibilidade na unidade: recurso -> existe?
  Future<Map<RecursoDeAcessibilidade, bool>> meusVotosDeAcessibilidade(int unidadeId) async {
    final dados = await _db.from('acessibilidade_voto').select('recurso, existe').eq('unidade_id', unidadeId);
    return {
      for (final linha in dados)
        ?RecursoDeAcessibilidade.porCodigo(linha['recurso'] as String?): linha['existe'] as bool,
    };
  }

  Future<void> votarAcessibilidade({
    required int unidadeId,
    required RecursoDeAcessibilidade recurso,
    required bool existe,
  }) =>
      _db.from('acessibilidade_voto').upsert({
        'unidade_id': unidadeId,
        'usuario_id': _db.auth.currentUser!.id,
        'recurso': recurso.codigo,
        'existe': existe,
      }, onConflict: 'unidade_id,usuario_id,recurso');

  /// [alvo] é `relato` ou `avaliacao`; [motivo] é `falso`, `ofensivo`, `spam` ou `outro`.
  Future<void> denunciar({required String alvo, required int alvoId, required String motivo}) =>
      _db.from('denuncia').insert({
        'alvo': alvo,
        'alvo_id': alvoId,
        'usuario_id': _db.auth.currentUser!.id,
        'motivo': motivo,
      });

  Future<ImpactoSemanal> meuImpacto() async {
    final dados = await _db.rpc('fn_meu_impacto');
    return ImpactoSemanal.deMapa(_lista(dados).first);
  }

  Future<bool> souModerador() async => (await _db.rpc('fn_sou_moderador')) == true;

  Future<List<SugestaoPendente>> listarSugestoesPendentes() async {
    final dados = await _db.rpc('fn_listar_sugestoes_pendentes');
    return _lista(dados).map(SugestaoPendente.deMapa).toList();
  }

  Future<void> analisarSugestao(int id, {required bool aceitar}) =>
      _db.rpc('fn_analisar_sugestao', params: {'p_id': id, 'p_aceitar': aceitar});

  Future<List<DenunciaPendente>> listarDenunciasPendentes() async {
    final dados = await _db.rpc('fn_listar_denuncias_pendentes');
    return _lista(dados).map(DenunciaPendente.deMapa).toList();
  }

  Future<void> resolverDenuncia(String alvo, int alvoId, {required bool restaurar}) => _db.rpc(
        'fn_resolver_denuncia',
        params: {'p_alvo': alvo, 'p_alvo_id': alvoId, 'p_restaurar': restaurar},
      );

  Future<List<Favorito>> listarFavoritos() async {
    final dados = await _db.from('favorito').select('*, unidade:unidade!favorito_unidade_id_fkey(nome)').order('criado_em');
    return dados.map(Favorito.deMapa).toList();
  }

  Future<void> salvarFavorito({required int unidadeId, required int limiteMin}) =>
      _db.from('favorito').upsert({
        'unidade_id': unidadeId,
        'usuario_id': _db.auth.currentUser!.id,
        'limite_espera_min': limiteMin,
        'alerta_ativo': true,
      }, onConflict: 'usuario_id,unidade_id');

  Future<void> removerFavorito(int unidadeId) => _db
      .from('favorito')
      .delete()
      .eq('unidade_id', unidadeId)
      .eq('usuario_id', _db.auth.currentUser!.id);

  Future<List<Notificacao>> listarNotificacoes() async {
    final dados =
        await _db.from('notificacao').select().order('criado_em', ascending: false).limit(30);
    return dados.map(Notificacao.deMapa).toList();
  }

  Future<void> marcarNotificacoesLidas() => _db
      .from('notificacao')
      .update({'lida': true})
      .eq('usuario_id', _db.auth.currentUser!.id)
      .eq('lida', false);

  /// Exclusão definitiva da conta e de todos os dados pessoais (LGPD).
  Future<void> excluirMinhaConta() => _db.rpc('excluir_minha_conta');

  Future<Perfil?> buscarPerfil(String usuarioId) async {
    final dados = await _db.from('usuario').select().eq('id', usuarioId).maybeSingle();
    return dados == null ? null : Perfil.deMapa(dados);
  }
}
