import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/busca.dart';
import '../core/nivel_espera.dart';
import '../core/plano.dart';
import '../core/tema.dart' show EstiloVisual;
import '../core/presenca.dart';
import '../data/localizacao.dart';
import '../data/repositorios.dart';
import '../models/colaboracao.dart';
import '../models/unidade.dart';

/// Preferências de acessibilidade, guardadas no aparelho.
class PreferenciasControlador extends ChangeNotifier {
  PreferenciasControlador(this._prefs)
      : altoContraste = _prefs.getBool(_chaveContraste) ?? false,
        fonteGrande = _prefs.getBool(_chaveFonte) ?? false,
        apresentacaoVista = _prefs.getBool(_chaveApresentacao) ?? false,
        modoLeve = _prefs.getBool(_chaveModoLeve) ?? false,
        modoDoTema = ThemeMode.values.firstWhere(
          (m) => m.name == _prefs.getString(_chaveTema),
          orElse: () => ThemeMode.system,
        );

  static const _chaveContraste = 'alto_contraste';
  static const _chaveFonte = 'fonte_grande';
  static const _chaveApresentacao = 'apresentacao_vista';
  static const _chaveTema = 'modo_do_tema';
  static const _chaveModoLeve = 'modo_leve';

  final SharedPreferences _prefs;
  bool altoContraste;
  bool fonteGrande;
  bool apresentacaoVista;
  ThemeMode modoDoTema;

  /// Identidade visual do app (cores, formas e botões).
  final EstiloVisual estilo = EstiloVisual.padrao;

  /// Modo econômico: lista de unidades por distância, sem baixar o mapa (poupa dados e funciona melhor em sinal fraco).
  bool modoLeve;

  void definirModoLeve(bool valor) {
    modoLeve = valor;
    _prefs.setBool(_chaveModoLeve, valor);
    notifyListeners();
  }

  void concluirApresentacao() {
    apresentacaoVista = true;
    _prefs.setBool(_chaveApresentacao, true);
    notifyListeners();
  }

  void definirModoDoTema(ThemeMode modo) {
    modoDoTema = modo;
    _prefs.setString(_chaveTema, modo.name);
    notifyListeners();
  }

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
  SessaoControlador(this._db, this._comunidade, this._fila) {
    _assinaturaAuth = _db.auth.onAuthStateChange.listen((estado) {
      if (estado.event == AuthChangeEvent.passwordRecovery) {
        recuperacaoPendente = true;
        notifyListeners();
      }
      _aoMudarSessao();
    });
    _aoMudarSessao();
  }

  final SupabaseClient _db;
  final ComunidadeRepositorio _comunidade;
  final FilaRepositorio _fila;
  late final StreamSubscription<AuthState> _assinaturaAuth;
  RealtimeChannel? _canalNotificacoes;
  String? _usuarioCarregado;

  Perfil? perfil;
  List<Notificacao> notificacoes = const [];
  List<Favorito> favoritos = const [];
  List<RegistroFila> historico = const [];
  bool dadosCarregados = false;

  /// Verdadeiro quando a pessoa chegou pelo link do e-mail de recuperação de senha.
  bool recuperacaoPendente = false;

  /// Alerta que acabou de chegar em tempo real e ainda não foi mostrado na tela.
  Notificacao? alertaPendente;

  void consumirAlerta() => alertaPendente = null;

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

  /// [aceitouTermos] é gravado no perfil, com a data, pelo gatilho do banco.
  Future<void> cadastrar(String nome, String email, String senha, {required bool aceitouTermos}) async {
    try {
      final resposta = await _db.auth.signUp(
        email: email.trim(),
        password: senha,
        data: {'nome': nome.trim(), 'aceitou_termos': aceitouTermos},
      );
      if (resposta.session == null) {
        throw const ErroDeNegocio('Cadastro criado. Confirme o e-mail para entrar.');
      }
    } catch (e) {
      throw traduzirErro(e);
    }
  }

  Future<void> sair() => _db.auth.signOut();

  /// Apaga a conta e todos os dados pessoais, e encerra a sessão.
  Future<void> excluirConta() async {
    try {
      await _comunidade.excluirMinhaConta();
      await _db.auth.signOut();
    } catch (e) {
      throw traduzirErro(e);
    }
  }

  /// Envia o e-mail de recuperação. A resposta é a mesma exista o e-mail ou não.
  Future<void> enviarRecuperacaoDeSenha(String email) async {
    try {
      await _db.auth.resetPasswordForEmail(email.trim());
    } catch (e) {
      throw traduzirErro(e);
    }
  }

  Future<void> definirNovaSenha(String senha) async {
    try {
      await _db.auth.updateUser(UserAttributes(password: senha));
      recuperacaoPendente = false;
      notifyListeners();
    } catch (e) {
      throw traduzirErro(e);
    }
  }

  Future<void> recarregarPerfil() async {
    final id = usuarioId;
    if (id == null) return;
    try {
      final (novoPerfil, novasNotificacoes, novosFavoritos, novoHistorico) = await (
        _comunidade.buscarPerfil(id),
        _comunidade.listarNotificacoes(),
        _comunidade.listarFavoritos(),
        _fila.historico(),
      ).wait;
      perfil = novoPerfil;
      notificacoes = novasNotificacoes;
      favoritos = novosFavoritos;
      historico = novoHistorico;
      dadosCarregados = true;
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
      favoritos = const [];
      historico = const [];
      dadosCarregados = false;
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
          callback: (carga) {
            alertaPendente = Notificacao.deMapa(carga.newRecord);
            notifyListeners();
            recarregarPerfil();
          },
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

  static const _distancia = Distance();

  List<Unidade> _unidades = const [];
  List<TipoUnidade> tipos = const [];
  List<Servico> servicos = const [];
  int? filtroTipoId;
  Servico? filtroServico;
  Set<int>? _idsDoServico;
  String busca = '';
  bool somenteAbertas = false;
  StreamSubscription<Localizacao>? _assinaturaLocalizacao;
  final Set<int> _proximasDispensadas = {};
  bool carregando = true;

  /// Falha na primeira carga: não há nada para mostrar além do erro.
  String? erro;

  /// Falha ao atualizar quando já há dados na tela: os dados antigos continuam visíveis.
  String? avisoDeConexao;
  Localizacao? localizacao;

  /// Identificador da última unidade alterada em tempo real, para destacar no mapa.
  int? ultimaAtualizada;

  /// Texto pesquisável de cada unidade, calculado uma vez por objeto (as listas novas trazem objetos novos).
  final _indiceDeBusca = Expando<String>();

  String _textoDe(Unidade u) => _indiceDeBusca[u] ??=
      textoPesquisavel(nome: u.nome, bairro: u.bairro, tipo: u.tipo, endereco: u.endereco);

  /// Unidades depois do filtro por tipo e da busca por nome, bairro, endereço ou tipo (todas as palavras).
  List<Unidade> get unidades {
    final palavras = palavrasDaBusca(busca);
    if (filtroTipoId == null && filtroServico == null && palavras.isEmpty && !somenteAbertas) return _unidades;
    return _unidades
        .where((u) =>
            (!somenteAbertas || u.abertaAgora) &&
            (filtroTipoId == null || u.tipoUnidadeId == filtroTipoId) &&
            (_idsDoServico == null || _idsDoServico!.contains(u.id)) &&
            (palavras.isEmpty || combinaComBusca(_textoDe(u), palavras)))
        .toList(growable: false);
  }

  /// Todas as unidades carregadas, sem busca nem filtros (para os totais do painel).
  List<Unidade> get todasAsUnidades => _unidades;

  void definirSomenteAbertas(bool valor) {
    if (somenteAbertas == valor) return;
    somenteAbertas = valor;
    notifyListeners();
  }

  void alternarSomenteAbertas() => definirSomenteAbertas(!somenteAbertas);

  bool get localizacaoReal => localizacao?.real ?? false;

  /// Ponto escolhido no mapa para buscar a partir de outro lugar (por exemplo, para ajudar um familiar).
  /// Nulo: vale a localização da própria pessoa.
  LatLng? pontoDeReferencia;

  void definirPontoDeReferencia(LatLng? ponto) {
    pontoDeReferencia = ponto;
    notifyListeners();
  }

  /// A localização usada para distâncias e recomendações: o ponto de referência, se houver; senão a da pessoa.
  Localizacao? get localizacaoParaBusca =>
      pontoDeReferencia == null ? localizacao : Localizacao(pontoDeReferencia!, real: true);

  /// Raio, em metros, para sugerir o registro de chegada.
  static const raioDeChegadaM = 150.0;

  /// Unidade aberta a menos de [raioDeChegadaM] da pessoa, se houver e se não foi dispensada.
  Unidade? get unidadeProxima {
    final origem = localizacao;
    if (origem == null || !origem.real) return null;
    Unidade? melhor;
    var menor = raioDeChegadaM;
    for (final u in _unidades) {
      if (!u.abertaAgora || _proximasDispensadas.contains(u.id)) continue;
      final metros = _distancia.as(LengthUnit.Meter, origem.ponto, LatLng(u.latitude, u.longitude));
      if (metros <= menor) {
        menor = metros;
        melhor = u;
      }
    }
    return melhor;
  }

  void dispensarProxima(int unidadeId) {
    _proximasDispensadas.add(unidadeId);
    notifyListeners();
  }

  Future<void> filtrarPorServico(Servico? servico) async {
    if (servico == null) {
      filtroServico = null;
      _idsDoServico = null;
      notifyListeners();
      return;
    }
    try {
      _idsDoServico = await _repositorio.unidadesDoServico(servico.id);
      filtroServico = servico;
    } catch (_) {
      avisoDeConexao = 'Não foi possível filtrar por serviço.';
    }
    notifyListeners();
  }

  /// Distância até a unidade, ou nulo quando não sabemos onde o usuário está.
  double? distanciaKm(Unidade unidade) {
    final origem = localizacaoParaBusca;
    if (origem == null || !origem.real) return null;
    return _distancia.as(LengthUnit.Meter, origem.ponto, LatLng(unidade.latitude, unidade.longitude)) / 1000;
  }

  void buscar(String termo) {
    busca = termo;
    notifyListeners();
  }

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
    _assinaturaLocalizacao ??= _localizacaoServico.acompanhar().listen((nova) {
      localizacao = nova;
      notifyListeners();
    });
  }

  Future<void> carregar() async {
    carregando = true;
    erro = null;
    avisoDeConexao = null;
    notifyListeners();
    try {
      // Tipos e serviços são complementos: se falharem (sem conexão), o mapa segue com o que as unidades já dizem.
      final tiposBuscados = _repositorio.listarTipos().then<List<TipoUnidade>?>((v) => v, onError: (_) => null);
      final servicosBuscados = _repositorio.listarTodosServicos().then<List<Servico>?>((v) => v, onError: (_) => null);
      _unidades = await _repositorio.listarMapa();
      final tiposRecebidos = await tiposBuscados;
      final servicosRecebidos = await servicosBuscados;
      final copia = _repositorio.cacheUsadoEm;
      if (copia != null) {
        final hora = '${copia.hour.toString().padLeft(2, '0')}:${copia.minute.toString().padLeft(2, '0')}';
        avisoDeConexao = 'Sem conexão. Mostrando os dados salvos às $hora; as esperas podem ter mudado.';
      }
      servicos = servicosRecebidos ?? servicos;
      tipos = (tiposRecebidos ?? _tiposDasUnidades(_unidades))
        ..sort((a, b) => _ordemDoTipo(a.nome).compareTo(_ordemDoTipo(b.nome)));
    } catch (e) {
      final mensagem = traduzirErro(e).mensagem;
      if (_unidades.isEmpty) {
        erro = mensagem;
      } else {
        avisoDeConexao = mensagem;
      }
    }
    carregando = false;
    notifyListeners();
  }

  /// Tipos que aparecem nas unidades carregadas (usado quando a lista de tipos não pôde ser baixada).
  static List<TipoUnidade> _tiposDasUnidades(List<Unidade> unidades) {
    final porId = <int, String>{for (final u in unidades) u.tipoUnidadeId: u.tipo};
    return [for (final e in porId.entries) TipoUnidade(id: e.key, nome: e.value)];
  }

  /// Urgência primeiro: é o que a pessoa mais precisa achar rápido.
  static int _ordemDoTipo(String nome) {
    const ordem = ['UPA', 'Pronto-socorro', 'UBS', 'Poupatempo', 'INSS', 'CRAS'];
    final i = ordem.indexOf(nome);
    return i == -1 ? ordem.length : i;
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
    _assinaturaLocalizacao?.cancel();
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
    double? latitude,
    double? longitude,
  }) =>
      _executar(() async {
        final registro = await _repositorio.registrar(
          unidadeId: unidadeId,
          tamanho: tamanho,
          estouNaFila: estouNaFila,
          latitude: latitude,
          longitude: longitude,
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


/// Aba selecionada. Fica num controlador para outras telas poderem levar a pessoa a uma aba (ex.: da triagem ao mapa).
class NavegacaoControlador extends ChangeNotifier {
  static const mapa = 0;
  static const rapido = 1;
  static const painel = 2;
  static const perfil = 3;

  int aba = mapa;

  void irPara(int nova) {
    if (nova == aba) return;
    aba = nova;
    notifyListeners();
  }
}

/// Compromisso marcado ("estar na UBS às 14h") e a hora de sair de casa; fica só no aparelho.
class PlanoControlador extends ChangeNotifier {
  PlanoControlador(this._prefs) {
    final lido = PlanoDeIda.deJson(_prefs.getString(_chave));
    if (lido != null && !lido.venceu(DateTime.now())) {
      plano = lido;
    } else if (lido != null) {
      _prefs.remove(_chave);
    }
  }

  static const _chave = 'plano_de_ida';
  final SharedPreferences _prefs;
  PlanoDeIda? plano;

  Future<void> definir(PlanoDeIda novo) async {
    plano = novo;
    await _prefs.setString(_chave, novo.toJson());
    notifyListeners();
  }

  Future<void> limpar() async {
    plano = null;
    await _prefs.remove(_chave);
    notifyListeners();
  }
}

/// Pergunta "como está a fila?" a quem está dentro de uma unidade há alguns minutos.
/// A posição é só lida no aparelho; nada sai dele além do registro que a pessoa decidir enviar.
class PresencaControlador extends ChangeNotifier {
  PresencaControlador(this._mapa, this._sessao, this._fila, {Duration intervalo = const Duration(seconds: 30)}) {
    _relogio = Timer.periodic(intervalo, (_) => verificar());
  }

  final MapaControlador _mapa;
  final SessaoControlador _sessao;
  final FilaControlador _fila;
  final _detector = DetectorDePresenca();
  late final Timer _relogio;

  /// Unidade sobre a qual perguntar agora.
  int? pendente;

  void verificar({DateTime? agora}) {
    if (pendente != null || !_sessao.autenticado || _fila.ativo != null) return;
    final posicao = _mapa.localizacao;
    if (posicao == null || !posicao.real) return;
    pendente = _detector.atualizar(
      posicao: (posicao.ponto.latitude, posicao.ponto.longitude),
      unidades: _mapa.todasAsUnidades,
      agora: agora ?? DateTime.now(),
    );
    if (pendente != null) notifyListeners();
  }

  /// A pessoa respondeu ou dispensou: encerra a pergunta e não repete por algumas horas.
  void encerrar() {
    final id = pendente;
    if (id != null) _detector.silenciar(id, DateTime.now());
    pendente = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _relogio.cancel();
    super.dispose();
  }
}
