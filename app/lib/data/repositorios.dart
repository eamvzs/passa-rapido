import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/nivel_espera.dart';
import '../models/colaboracao.dart';
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
    return const ErroDeNegocio('Não foi possível concluir. Tente de novo.');
  }
  if (erro is AuthException) {
    final texto = erro.message.toLowerCase();
    if (texto.contains('invalid login')) return const ErroDeNegocio('E-mail ou senha incorretos.');
    if (texto.contains('already registered')) return const ErroDeNegocio('Este e-mail já tem cadastro.');
    if (texto.contains('password')) return const ErroDeNegocio('A senha precisa ter pelo menos 6 caracteres.');
    return const ErroDeNegocio('Não foi possível entrar. Confira os dados.');
  }
  return const ErroDeNegocio('Sem conexão. Verifique a internet e tente de novo.');
}

List<Map<String, dynamic>> _lista(dynamic dados) =>
    (dados as List).cast<Map<String, dynamic>>();

/// Consultas de unidades, previsão, recomendação e indicadores.
class UnidadeRepositorio {
  UnidadeRepositorio(this._db);
  final SupabaseClient _db;

  Future<List<Unidade>> listarMapa() async {
    final dados = await _db.from('vw_mapa_unidades').select().order('nome');
    return dados.map(Unidade.deMapa).toList();
  }

  Future<Unidade?> buscar(int id) async {
    final dados = await _db.from('vw_mapa_unidades').select().eq('id', id).maybeSingle();
    return dados == null ? null : Unidade.deMapa(dados);
  }

  Future<List<TipoUnidade>> listarTipos() async {
    final dados = await _db.from('tipo_unidade').select('id, nome').order('id');
    return dados.map(TipoUnidade.deMapa).toList();
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
  }) async {
    final dados = await _db
        .from('registro_fila')
        .insert({
          'unidade_id': unidadeId,
          'tamanho_fila': tamanho.codigo,
          'tipo': estouNaFila ? 'checkin' : 'observacao',
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
        .from('relato')
        .select('*, usuario:usuario!relato_usuario_id_fkey(nome)')
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
        .from('avaliacao')
        .select('*, usuario:usuario!avaliacao_usuario_id_fkey(nome)')
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

  Future<Perfil?> buscarPerfil(String usuarioId) async {
    final dados = await _db.from('usuario').select().eq('id', usuarioId).maybeSingle();
    return dados == null ? null : Perfil.deMapa(dados);
  }
}
