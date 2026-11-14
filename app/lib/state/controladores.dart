import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/nivel_espera.dart';
import '../data/localizacao.dart';
import '../data/repositorios.dart';
import '../models/colaboracao.dart';
import '../models/unidade.dart';

/// Preferências de acessibilidade, guardadas no aparelho.
class PreferenciasControlador extends ChangeNotifier {
  PreferenciasControlador(this._prefs)
      : altoContraste = _prefs.getBool(_chaveContraste) ?? false,
        fonteGrande = _prefs.getBool(_chaveFonte) ?? false;

  static const _chaveContraste = 'alto_contraste';
  static const _chaveFonte = 'fonte_grande';

  final SharedPreferences _prefs;
  bool altoContraste;
  bool fonteGrande;

  double get escalaDoTexto => fonteGrande ? 1.3 : 1.0;

  void definirAltoContraste(bool valor) {
    altoContraste = valor;
    _prefs.setBool(_chaveContraste, valor);
    notifyListeners();
  }

  void definirFonteGrande(bool valor) {
    fonteGrande = valor;
    _prefs.setBool(_chaveFonte, valor);
    notifyListeners();
  }
}

/// Sessão do usuário: login, cadastro, perfil e notificações em tempo real.
class SessaoControlador extends ChangeNotifier {
  SessaoControlador(this._db, this._comunidade) {
    _assinaturaAuth = _db.auth.onAuthStateChange.listen((_) => _aoMudarSessao());
    _aoMudarSessao();
  }

  final SupabaseClient _db;
  final ComunidadeRepositorio _comunidade;
  late final StreamSubscription<AuthState> _assinaturaAuth;
  RealtimeChannel? _canalNotificacoes;
  String? _usuarioCarregado;

  Perfil? perfil;
  List<Notificacao> notificacoes = const [];

  bool get autenticado => _db.auth.currentUser != null;
  String? get usuarioId => _db.auth.currentUser?.id;
  int get naoLidas => notificacoes.where((n) => !n.lida).length;

  Future<void> entrar(String email, String senha) async {
    try {
      await _db.auth.signInWithPassword(email: email.trim(), password: senha);
    } catch (e) {
      throw traduzirErro(e);
    }
  }

  Future<void> cadastrar(String nome, String email, String senha) async {
    try {
      final resposta = await _db.auth.signUp(
        email: email.trim(),
        password: senha,
        data: {'nome': nome.trim()},
      );
      if (resposta.session == null) {
        throw const ErroDeNegocio('Cadastro criado. Confirme o e-mail para entrar.');
      }
    } catch (e) {
      throw traduzirErro(e);
    }
  }

  Future<void> sair() => _db.auth.signOut();

  Future<void> recarregarPerfil() async {
    final id = usuarioId;
    if (id == null) return;
    try {
      perfil = await _comunidade.buscarPerfil(id);
      notificacoes = await _comunidade.listarNotificacoes();
      notifyListeners();
    } catch (_) {
      // Mantém os dados anteriores; a próxima ação tenta de novo.
    }
  }

  Future<void> marcarNotificacoesLidas() async {
    if (naoLidas == 0) return;
    await _comunidade.marcarNotificacoesLidas();
    await recarregarPerfil();
  }

  void _aoMudarSessao() {
    final id = usuarioId;
    if (id == _usuarioCarregado) return;
    _usuarioCarregado = id;
    _encerrarCanal();
    if (id == null) {
      perfil = null;
      notificacoes = const [];
      notifyListeners();
      return;
    }
    recarregarPerfil();
    _canalNotificacoes = _db
        .channel('notificacoes-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificacao',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'usuario_id',
            value: id,
          ),
          callback: (_) => recarregarPerfil(),
        )
        .subscribe();
  }

  void _encerrarCanal() {
    final canal = _canalNotificacoes;
    if (canal != null) _db.removeChannel(canal);
    _canalNotificacoes = null;
  }

  @override
  void dispose() {
    _assinaturaAuth.cancel();
    _encerrarCanal();
    super.dispose();
  }
}

/// Unidades do mapa, mantidas atualizadas pelo canal de tempo real.
class MapaControlador extends ChangeNotifier {
  MapaControlador(this._db, this._repositorio, this._localizacaoServico);

  final SupabaseClient _db;
  final UnidadeRepositorio _repositorio;
  final LocalizacaoServico _localizacaoServico;
  RealtimeChannel? _canal;

  List<Unidade> _unidades = const [];
  List<TipoUnidade> tipos = const [];
  int? filtroTipoId;
  bool carregando = true;
  String? erro;
  Localizacao? localizacao;

  /// Identificador da última unidade alterada em tempo real, para destacar no mapa.
  int? ultimaAtualizada;

  List<Unidade> get unidades => filtroTipoId == null
      ? _unidades
      : _unidades.where((u) => u.tipoUnidadeId == filtroTipoId).toList(growable: false);

  Unidade? porId(int id) {
    for (final u in _unidades) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<void> iniciar() async {
    await carregar();
    _canal ??= _db
        .channel('situacao-unidades')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'situacao_unidade',
          callback: (carga) => _aplicarSituacao(carga.newRecord),
        )
        .subscribe();
    localizacao = await _localizacaoServico.obter();
    notifyListeners();
  }

  Future<void> carregar() async {
    carregando = true;
    erro = null;
    notifyListeners();
    try {
      final resultados = await Future.wait([_repositorio.listarMapa(), _repositorio.listarTipos()]);
      _unidades = resultados[0] as List<Unidade>;
      tipos = resultados[1] as List<TipoUnidade>;
    } catch (e) {
      erro = traduzirErro(e).mensagem;
    }
    carregando = false;
    notifyListeners();
  }

  void filtrarPorTipo(int? tipoId) {
    filtroTipoId = tipoId;
    notifyListeners();
  }

  void _aplicarSituacao(Map<String, dynamic> situacao) {
    final id = situacao['unidade_id'] as int?;
    if (id == null) return;
    _unidades = [
      for (final u in _unidades) u.id == id ? u.comSituacao(situacao) : u,
    ];
    ultimaAtualizada = id;
    notifyListeners();
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) _db.removeChannel(canal);
    super.dispose();
  }
}

/// Permanência do usuário em uma fila: chegada, atendimento, saída ou desistência.
class FilaControlador extends ChangeNotifier {
  FilaControlador(this._repositorio);

  final FilaRepositorio _repositorio;
  RegistroFila? ativo;
  bool ocupado = false;
  String? _usuarioSincronizado;
  bool _sincronizado = false;

  /// Recarrega o registro ativo quando o usuário entra, sai ou troca de conta.
  void sincronizarUsuario(String? usuarioId) {
    if (_sincronizado && usuarioId == _usuarioSincronizado) return;
    _sincronizado = true;
    _usuarioSincronizado = usuarioId;
    Future.microtask(() => carregar(autenticado: usuarioId != null));
  }

  Future<void> carregar({required bool autenticado}) async {
    if (!autenticado) {
      ativo = null;
      notifyListeners();
      return;
    }
    try {
      ativo = await _repositorio.registroAtivo();
      notifyListeners();
    } catch (_) {
      // Sem registro ativo conhecido; o banner simplesmente não aparece.
    }
  }

  Future<RegistroFila> registrar({
    required int unidadeId,
    required TamanhoFila tamanho,
    required bool estouNaFila,
  }) =>
      _executar(() async {
        final registro = await _repositorio.registrar(
          unidadeId: unidadeId,
          tamanho: tamanho,
          estouNaFila: estouNaFila,
        );
        if (estouNaFila) ativo = registro;
        return registro;
      });

  Future<RegistroFila> marcarAtendido() => _executar(() async {
        final registro = await _repositorio.marcarAtendido(ativo!.id);
        ativo = registro;
        return registro;
      });

  Future<void> marcarSaida() => _executar(() async {
        await _repositorio.marcarSaida(ativo!.id);
        ativo = null;
      });

  Future<void> desistir() => _executar(() async {
        await _repositorio.desistir(ativo!.id);
        ativo = null;
      });

  Future<T> _executar<T>(Future<T> Function() acao) async {
    ocupado = true;
    notifyListeners();
    try {
      return await acao();
    } catch (e) {
      throw traduzirErro(e);
    } finally {
      ocupado = false;
      notifyListeners();
    }
  }
}
