import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/agendamento.dart';
import '../../core/documentos.dart';
import '../../core/feriados.dart';
import '../../core/plano.dart';
import '../../core/formatos.dart';
import '../../core/insights.dart';
import '../../core/previsao.dart';
import '../../core/nivel_espera.dart';
import '../../data/repositorios.dart';
import '../../models/colaboracao.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../../core/tema.dart';
import '../componentes/comuns.dart';
import 'mapa_tela.dart' show abrirRota, ligarPara;

/// Ficha da unidade: situação ao vivo, registro de fila, avisos, previsão, serviços e avaliações.
class UnidadeDetalheTela extends StatefulWidget {
  const UnidadeDetalheTela({super.key, required this.unidadeId});

  final int unidadeId;

  @override
  State<UnidadeDetalheTela> createState() => _UnidadeDetalheTelaState();
}

class _UnidadeDetalheTelaState extends State<UnidadeDetalheTela> {
  final _voz = FlutterTts();
  late final UnidadeRepositorio _unidades = context.read<UnidadeRepositorio>();
  late final ComunidadeRepositorio _comunidade = context
      .read<ComunidadeRepositorio>();

  List<Servico> _servicos = const [];
  List<HorarioFuncionamento> _horarios = const [];
  List<Relato> _relatos = const [];
  List<Avaliacao> _avaliacoes = const [];
  List<PrevisaoHora> _previsao = const [];
  List<SlotSemanal> _semana = const [];
  List<ContagemDeRecurso> _acessibilidade = const [];
  Map<RecursoDeAcessibilidade, bool> _meusVotos = const {};
  Favorito? _favorito;
  int _diaPrevisao = DateTime.now().weekday % 7;
  bool _carregando = true;
  int _aba = 0;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  @override
  void dispose() {
    _voz.stop();
    super.dispose();
  }

  /// Cada seção carrega de forma independente: a falha de uma não esvazia as outras.
  Future<void> _carregarTudo() async {
    final id = widget.unidadeId;
    final autenticado = context.read<SessaoControlador>().autenticado;
    var houveFalha = false;

    Future<List<T>> seguro<T>(Future<List<T>> consulta, List<T> atual) async {
      try {
        return await consulta;
      } catch (_) {
        houveFalha = true;
        return atual;
      }
    }

    final (
      servicos,
      horarios,
      relatos,
      avaliacoes,
      previsao,
      favoritos,
      semana,
    ) = await (
      seguro(_unidades.listarServicos(id), _servicos),
      seguro(_unidades.listarHorarios(id), _horarios),
      seguro(_comunidade.listarRelatos(id), _relatos),
      seguro(_comunidade.listarAvaliacoes(id), _avaliacoes),
      seguro(_unidades.melhorHorario(id, _diaPrevisao), _previsao),
      seguro(
        autenticado
            ? _comunidade.listarFavoritos()
            : Future.value(<Favorito>[]),
        <Favorito>[],
      ),
      seguro(_unidades.historicoSemanal(id), _semana),
    ).wait;
    if (!mounted) return;
    setState(() {
      _servicos = servicos;
      _horarios = horarios;
      _relatos = relatos;
      _avaliacoes = avaliacoes;
      _previsao = previsao;
      _semana = semana;
      _favorito = favoritos.where((f) => f.unidadeId == id).firstOrNull;
      _carregando = false;
    });
    if (houveFalha) {
      mostrarMensagem(
        context,
        'Parte das informações não carregou. Tente atualizar.',
      );
    }
    _carregarAcessibilidade();
  }

  /// Confirmações de acessibilidade são um extra: se falharem, o resto da ficha segue normal.
  Future<void> _carregarAcessibilidade() async {
    try {
      final autenticado = context.read<SessaoControlador>().autenticado;
      final contagens = await _unidades.acessibilidade(widget.unidadeId);
      final votos = autenticado
          ? await _comunidade.meusVotosDeAcessibilidade(widget.unidadeId)
          : const <RecursoDeAcessibilidade, bool>{};
      if (!mounted) return;
      setState(() {
        _acessibilidade = contagens;
        _meusVotos = votos;
      });
    } catch (_) {
      // Mantém o que já havia.
    }
  }

  Future<void> _votarAcessibilidade(
    RecursoDeAcessibilidade recurso,
    bool existe,
  ) async {
    if (!await garantirLogin(context) || !mounted) return;
    try {
      await _comunidade.votarAcessibilidade(
        unidadeId: widget.unidadeId,
        recurso: recurso,
        existe: existe,
      );
      if (!mounted) return;
      mostrarMensagem(context, 'Obrigado! Sua resposta ajuda quem precisa.');
      await _carregarAcessibilidade();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  /// Denuncia um aviso ou uma avaliação. Com denúncias de pessoas confiáveis suficientes, o conteúdo some.
  Future<void> _denunciar(String alvo, int? alvoId) async {
    if (alvoId == null || !await garantirLogin(context) || !mounted) return;
    final motivo = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (contexto) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Por que denunciar?',
                style: Theme.of(contexto).textTheme.titleMedium,
              ),
            ),
            for (final (codigo, rotulo) in const [
              ('falso', 'Informação falsa ou enganosa'),
              ('ofensivo', 'Ofensivo ou desrespeitoso'),
              ('spam', 'Propaganda ou spam'),
              ('outro', 'Outro motivo'),
            ])
              ListTile(
                title: Text(rotulo),
                onTap: () => Navigator.of(contexto).pop(codigo),
              ),
          ],
        ),
      ),
    );
    if (motivo == null || !mounted) return;
    try {
      await _comunidade.denunciar(alvo: alvo, alvoId: alvoId, motivo: motivo);
      if (mounted) {
        mostrarMensagem(
          context,
          'Denúncia enviada. Obrigado por ajudar a manter o app confiável.',
        );
      }
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  /// "Tenho horário às 14h": o app calcula a hora de sair e guarda o plano no aparelho.
  Future<void> _planejarIda(Unidade unidade, double? distanciaKm) async {
    final agora = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: agora,
      firstDate: DateTime(agora.year, agora.month, agora.day),
      lastDate: agora.add(const Duration(days: 180)),
      helpText: 'Qual o dia do atendimento?',
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Que horas é o atendimento?',
    );
    if (hora == null || !mounted) return;
    final horario = DateTime(
      dia.year,
      dia.month,
      dia.day,
      hora.hour,
      hora.minute,
    );
    if (!horario.isAfter(agora)) {
      mostrarMensagem(
        context,
        'Esse horário já passou. Escolha uma data futura.',
      );
      return;
    }
    final deslocamento = distanciaKm == null
        ? 30
        : PlanoDeIda.deslocamentoPorDistancia(distanciaKm);
    final plano = PlanoDeIda.calcular(
      unidadeId: unidade.id,
      nomeUnidade: unidade.nome,
      horario: horario,
      deslocamentoMin: deslocamento,
    );
    await context.read<PlanoControlador>().definir(plano);
    if (!mounted) return;
    final saida = TimeOfDay.fromDateTime(plano.saida).format(context);
    mostrarSucesso(
      context,
      'Plano salvo. Saia às $saida'
      '${distanciaKm == null ? ' (sem a sua localização, contamos 30 min de caminho)' : ''}.',
    );
  }

  Future<void> _trocarDia(int dia) async {
    setState(() => _diaPrevisao = dia);
    try {
      final previsao = await _unidades.melhorHorario(widget.unidadeId, dia);
      if (mounted) setState(() => _previsao = previsao);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  Future<void> _informarFila({required bool estouNaFila}) async {
    if (!await garantirLogin(context) || !mounted) return;
    final tamanho = await showModalBottomSheet<TamanhoFila>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EscolherTamanho(estouNaFila: estouNaFila),
    );
    if (tamanho == null || !mounted) return;
    try {
      final localizacao = context.read<MapaControlador>().localizacao;
      await context.read<FilaControlador>().registrar(
        unidadeId: widget.unidadeId,
        tamanho: tamanho,
        estouNaFila: estouNaFila,
        latitude: localizacao != null && localizacao.real
            ? localizacao.ponto.latitude
            : null,
        longitude: localizacao != null && localizacao.real
            ? localizacao.ponto.longitude
            : null,
      );
      if (!mounted) return;
      await context.read<SessaoControlador>().recarregarPerfil();
      if (!mounted) return;
      mostrarSucesso(
        context,
        estouNaFila
            ? 'Chegada registrada. Avise quando for atendido.'
            : 'Obrigado por informar!',
        pontos: estouNaFila ? 5 : 3,
      );
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  Future<void> _novoRelato() async {
    if (!await garantirLogin(context) || !mounted) return;
    final dados = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _NovoRelato(),
    );
    if (dados == null) return;
    await _executar(
      () => _comunidade.criarRelato(
        unidadeId: widget.unidadeId,
        tipo: dados.$1,
        descricao: dados.$2,
      ),
      'Aviso publicado.',
      pontos: 3,
    );
  }

  Future<void> _confirmarRelato(Relato relato) async {
    if (!await garantirLogin(context)) return;
    await _executar(
      () => _comunidade.confirmarRelato(relato.id),
      'Confirmação registrada.',
    );
  }

  Future<void> _avaliar() async {
    if (!await garantirLogin(context) || !mounted) return;
    final unidade = context.read<MapaControlador>().porId(widget.unidadeId);
    if (await pedirAvaliacao(
      context,
      unidadeId: widget.unidadeId,
      nomeUnidade: unidade?.nome,
    )) {
      await _carregarTudo();
    }
  }

  Future<void> _alternarFavorito() async {
    if (!await garantirLogin(context) || !mounted) return;
    final resultado = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ConfigurarAlerta(limiteAtual: _favorito?.limiteMin),
    );
    if (resultado == null) return;
    if (resultado < 0) {
      await _executar(
        () => _comunidade.removerFavorito(widget.unidadeId),
        'Alerta removido.',
      );
    } else {
      await _executar(
        () => _comunidade.salvarFavorito(
          unidadeId: widget.unidadeId,
          limiteMin: resultado,
        ),
        'Você será avisado quando a espera ficar em até $resultado min.',
      );
    }
  }

  Future<void> _executar(
    Future<void> Function() acao,
    String sucesso, {
    int? pontos,
  }) async {
    try {
      await acao();
      if (!mounted) return;
      mostrarSucesso(context, sucesso, pontos: pontos);
      await Future.wait([
        _carregarTudo(),
        context.read<SessaoControlador>().recarregarPerfil(),
      ]);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  /// Copia um texto pronto (e o link do app, na web) para colar no WhatsApp.
  Future<void> _compartilhar(Unidade unidade) async {
    final espera = unidade.esperaMin == null
        ? 'sem informação de espera'
        : '${unidade.estimada ? 'espera estimada de ' : 'espera de '}${formatarEspera(unidade.esperaMin)}';
    final link = kIsWeb
        ? '${Uri.base.origin}/#/unidade/${unidade.id}'
        : 'https://www.google.com/maps/search/?api=1&query=${unidade.latitude},${unidade.longitude}';
    final texto =
        '${unidade.nome} (${unidade.tipo})\n${unidade.endereco}\n$espera agora.\nVeja no Passa Rápido: $link';
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) {
      mostrarMensagem(context, 'Texto copiado. É só colar no WhatsApp.');
    }
  }

  Future<void> _sugerirCorrecao(Unidade unidade) async {
    if (!await garantirLogin(context) || !mounted) return;
    final localizacao = context.read<MapaControlador>().localizacao;
    final dados = await showModalBottomSheet<_DadosDaSugestao>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NovaSugestao(
        podeUsarMinhaPosicao: localizacao != null && localizacao.real,
      ),
    );
    if (dados == null) return;
    await _executar(
      () => _comunidade.sugerirCorrecao(
        unidadeId: widget.unidadeId,
        campo: dados.campo,
        descricao: dados.descricao,
        latitude: dados.usarMinhaPosicao ? localizacao?.ponto.latitude : null,
        longitude: dados.usarMinhaPosicao ? localizacao?.ponto.longitude : null,
      ),
      'Obrigado! Sua sugestão foi enviada para análise.',
    );
  }

  Future<void> _abrirAgendamento(Agendamento a) async {
    final abriu = await launchUrl(
      Uri.parse(a.url),
      mode: LaunchMode.externalApplication,
    );
    if (!abriu && mounted) {
      mostrarMensagem(context, 'Não foi possível abrir o endereço.');
    }
  }

  Future<void> _ouvir(Unidade unidade) async {
    final melhor = _previsao.where((p) => p.melhor).firstOrNull;
    final texto = StringBuffer('${unidade.nome}. ${unidade.nivel.rotulo}. ')
      ..write(
        unidade.esperaMin == null
            ? 'Ainda não há informação de espera. '
            : 'Espera estimada de ${formatarEspera(unidade.esperaMin).replaceAll('h', 'horas').replaceAll('min', 'minutos')}. ',
      )
      ..write(
        unidade.abertaAgora
            ? 'A unidade está aberta. '
            : 'A unidade está fechada agora. ',
      )
      ..write(
        _relatos.where((r) => !r.positivo).isEmpty
            ? ''
            : 'Avisos: ${_relatos.where((r) => !r.positivo).map((r) => r.rotulo).toSet().join(', ')}. ',
      )
      ..write(
        melhor == null
            ? ''
            : 'O melhor horário costuma ser às ${melhor.hora} horas.',
      );
    await _voz.setLanguage('pt-BR');
    await _voz.speak(texto.toString());
  }

  @override
  Widget build(BuildContext context) {
    // A situação vem do controlador do mapa, então muda ao vivo com a tela aberta.
    final unidade = context.select<MapaControlador, Unidade?>(
      (m) => m.porId(widget.unidadeId),
    );
    final filaAtiva = context.select<FilaControlador, RegistroFila?>(
      (f) => f.ativo,
    );
    final tema = Theme.of(context);

    if (unidade == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final distancia = context.read<MapaControlador>().distanciaKm(unidade);

    return Scaffold(
      appBar: AppBar(
        title: Text(unidade.tipo),
        actions: [
          IconButton(
            tooltip: 'Compartilhar esta unidade',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _compartilhar(unidade),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarTudo,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Espaco.g,
                Espaco.p,
                Espaco.g,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: LarguraMaxima(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Cabecalho(
                        unidade: unidade,
                        distanciaKm: distancia,
                        proximaAbertura: proximaAbertura(
                          _horarios,
                          DateTime.now(),
                        ),
                        momento:
                            _diaPrevisao == DateTime.now().weekday % 7 &&
                                !_carregando
                            ? analisarMomento(
                                _previsao,
                                DateTime.now().hour,
                                esperaAoVivo:
                                    unidade.emTempoReal && unidade.abertaAgora
                                    ? unidade.esperaMin
                                    : null,
                              )
                            : null,
                      ),
                      const SizedBox(height: Espaco.m),
                      Row(
                        children: [
                          _AcaoRapida(
                            icone: Icons.directions_rounded,
                            rotulo: 'Como chegar',
                            aoTocar: () => abrirRota(context, unidade),
                          ),
                          if ((unidade.telefone ?? '')
                                  .replaceAll(RegExp(r'\D'), '')
                                  .length >=
                              8)
                            _AcaoRapida(
                              icone: Icons.call_rounded,
                              rotulo: 'Ligar',
                              dica: 'Ligar para a unidade: ${unidade.telefone}',
                              aoTocar: () => ligarPara(context, unidade),
                            ),
                          _AcaoRapida(
                            icone: Icons.volume_up_rounded,
                            rotulo: 'Ouvir',
                            dica: 'Ouvir a situação da unidade',
                            aoTocar: () => _ouvir(unidade),
                          ),
                          _AcaoRapida(
                            icone: _favorito == null
                                ? Icons.notifications_none_rounded
                                : Icons.notifications_active_rounded,
                            rotulo: _favorito == null
                                ? 'Criar alerta'
                                : 'Alerta ativo',
                            dica: _favorito == null
                                ? 'Criar alerta de fila baixa'
                                : 'Alerta de fila baixa ativo. Toque para editar ou remover.',
                            destacada: _favorito != null,
                            aoTocar: _alternarFavorito,
                          ),
                        ],
                      ),
                      if (avisoDeFeriado(DateTime.now(), cidade: unidade.cidade)
                          case final aviso?)
                        Padding(
                          padding: const EdgeInsets.only(top: Espaco.m),
                          child: _AvisoDeFeriado(texto: aviso),
                        ),
                      if (_favorito != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Espaco.p),
                          child: Text(
                            'Você será avisado quando a espera ficar em até ${_favorito!.limiteMin} min.',
                            style: tema.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // As abas ficam fixas no topo ao rolar: dá para trocar de seção sem voltar ao começo da tela.
            SliverPersistentHeader(
              pinned: true,
              delegate: _AbasFixas(
                aba: _aba,
                aoTrocar: (i) => setState(() => _aba = i),
                fundo: tema.scaffoldBackgroundColor,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Espaco.g,
                0,
                Espaco.g,
                Espaco.xg,
              ),
              sliver: SliverToBoxAdapter(
                child: LarguraMaxima(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_aba == 0) ...[
                        Secao(
                          icone: Icons.campaign_rounded,
                          titulo: 'Avisos da comunidade',
                          acao: TextButton.icon(
                            onPressed: _novoRelato,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Avisar'),
                          ),
                          child: _carregando
                              ? const Esqueleto(linhas: 2)
                              : _relatos.isEmpty
                              ? const EstadoVazio(
                                  icone: Icons.check_circle_outline_rounded,
                                  texto: 'Nenhum aviso nas últimas horas.',
                                )
                              : Column(
                                  children: [
                                    for (final relato in _relatos)
                                      _RelatoItem(
                                        relato: relato,
                                        proprio: relato.proprio,
                                        aoConfirmar: () =>
                                            _confirmarRelato(relato),
                                        aoDenunciar: () =>
                                            _denunciar('relato', relato.id),
                                      ),
                                  ],
                                ),
                        ),
                        Secao(
                          icone: Icons.schedule_rounded,
                          titulo: 'Melhor horário para ir',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SeletorDeDia(
                                dia: _diaPrevisao,
                                aoTrocar: _trocarDia,
                              ),
                              const SizedBox(height: Espaco.m),
                              if (_carregando)
                                const Esqueleto(linhas: 4)
                              else
                                _GraficoPrevisao(previsao: _previsao),
                              if (!_carregando && _semana.isNotEmpty) ...[
                                const SizedBox(height: Espaco.g),
                                _MapaDeCalor(slots: _semana),
                              ],
                            ],
                          ),
                        ),
                        if (compararComVizinhas(
                              unidade,
                              context.read<MapaControlador>().todasAsUnidades,
                            )
                            case final c?)
                          Secao(
                            icone: Icons.compare_arrows_rounded,
                            titulo: 'Comparada às vizinhas',
                            child: _Comparacao(
                              unidade: unidade,
                              comparacao: c,
                              aoAbrirMelhor: () =>
                                  abrirUnidade(context, c.melhor.id),
                            ),
                          ),
                      ],
                      if (_aba == 1) ...[
                        Secao(
                          icone: Icons.event_note_rounded,
                          titulo: 'Planeje sua ida',
                          child: _PlanoDeIda(
                            unidadeId: unidade.id,
                            aoPlanejar: () => _planejarIda(unidade, distancia),
                          ),
                        ),
                        if (agendamentoDoTipo(unidade.tipo)
                            case final agendamento?)
                          Secao(
                            icone: Icons.event_available_rounded,
                            titulo: 'Antes de ir',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  agendamento.nota,
                                  style: tema.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: Espaco.m),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _abrirAgendamento(agendamento),
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: Text(agendamento.rotulo),
                                ),
                              ],
                            ),
                          ),
                        Secao(
                          icone: Icons.backpack_rounded,
                          titulo: 'O que levar',
                          child: _OQueLevar(tipo: unidade.tipo),
                        ),
                      ],
                      if (_aba == 2) ...[
                        Secao(
                          icone: Icons.assignment_rounded,
                          titulo: 'Serviços e documentos',
                          child: _carregando
                              ? const Esqueleto()
                              : _servicos.isEmpty
                              ? const EstadoVazio(
                                  icone: Icons.list_alt_rounded,
                                  texto: 'Serviços não informados.',
                                )
                              : Column(
                                  children: [
                                    for (final servico in _servicos)
                                      Theme(
                                        data: tema.copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: EdgeInsets.zero,
                                          title: Text(
                                            servico.nome,
                                            style: tema.textTheme.titleSmall,
                                          ),
                                          subtitle: servico.descricao == null
                                              ? null
                                              : Text(
                                                  servico.descricao!,
                                                  style:
                                                      tema.textTheme.bodySmall,
                                                ),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                bottom: Espaco.m,
                                              ),
                                          expandedAlignment:
                                              Alignment.centerLeft,
                                          children: [
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(
                                                Espaco.m,
                                              ),
                                              decoration: BoxDecoration(
                                                color: tema.colorScheme.primary
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.folder_open_rounded,
                                                    size: 20,
                                                    color: tema
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                  const SizedBox(
                                                    width: Espaco.p,
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      'Leve: ${servico.documentos ?? 'documento com foto'}',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        Secao(
                          icone: Icons.access_time_filled_rounded,
                          titulo: 'Horário de funcionamento',
                          child: _carregando
                              ? const Esqueleto(linhas: 2)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Horarios(horarios: _horarios),
                                    if (unidade.horarioPadrao)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: Espaco.p,
                                        ),
                                        child: Text(
                                          'Horário padrão para este tipo de unidade. Confirme no local.',
                                          style: tema.textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        Secao(
                          icone: Icons.accessible_forward_rounded,
                          titulo: 'Acessibilidade e prioridade',
                          child: _Acessibilidade(
                            contagens: _acessibilidade,
                            meusVotos: _meusVotos,
                            aoVotar: _votarAcessibilidade,
                          ),
                        ),
                      ],
                      if (_aba == 3) ...[
                        Secao(
                          icone: Icons.star_rounded,
                          titulo: 'Avaliações',
                          acao: TextButton.icon(
                            onPressed: _avaliar,
                            icon: const Icon(Icons.star_border_rounded),
                            label: const Text('Avaliar'),
                          ),
                          child: _carregando
                              ? const Esqueleto(linhas: 2)
                              : _avaliacoes.isEmpty
                              ? const EstadoVazio(
                                  icone: Icons.reviews_outlined,
                                  texto: 'Ainda sem avaliações. Conte como foi o seu atendimento.',
                                )
                              : Column(
                                  children: [
                                    for (final a in _avaliacoes)
                                      _AvaliacaoItem(
                                        avaliacao: a,
                                        proprio: a.proprio,
                                        aoDenunciar: () =>
                                            _denunciar('avaliacao', a.id),
                                      ),
                                  ],
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: Espaco.m),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _sugerirCorrecao(unidade),
                              icon: const Icon(Icons.edit_location_alt_rounded),
                              label: const Text(
                                'Algo errado nos dados? Sugerir correção',
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: Espaco.g),
                      Container(
                        padding: const EdgeInsets.all(Espaco.m),
                        decoration: BoxDecoration(
                          color: tema.colorScheme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.emergency_share_rounded,
                              color: tema.colorScheme.error,
                            ),
                            const SizedBox(width: Espaco.m),
                            const Expanded(
                              child: Text(
                                'Emergência? Não espere: ligue 192 (SAMU). '
                                'Com registros, os tempos vêm de outros cidadãos; sem registros, são estimativas do modelo.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BarraDeAcao(
        filaAtiva: filaAtiva,
        aberta: unidade.abertaAgora,
        aoChegar: () => _informarFila(estouNaFila: true),
        aoInformar: () => _informarFila(estouNaFila: false),
      ),
    );
  }
}

/// Bloco principal da ficha: espera em destaque sobre a cor do nível.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.unidade,
    required this.distanciaKm,
    this.proximaAbertura,
    this.momento,
  });

  final Unidade unidade;
  final double? distanciaKm;
  final String? proximaAbertura;
  final AnaliseDoMomento? momento;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final fechada = !unidade.abertaAgora;
    final nivel = fechada ? NivelEspera.semDados : unidade.nivel;
    final cor = nivel.corSobreSuperficie(tema.brightness);
    final origem = fechada
        ? (proximaAbertura == null
              ? 'Fora do horário de funcionamento'
              : 'Fora do horário. $proximaAbertura')
        : switch (unidade.fonte) {
            'tempo_real' =>
              'Informado por cidadãos · atualizado ${formatarHaQuantoTempo(unidade.atualizadoEm)}',
            'oficial' =>
              'Dado oficial do órgão responsável · atualizado ${formatarHaQuantoTempo(unidade.atualizadoEm)}',
            'historico' => 'Estimativa inicial para este dia e horário, ainda sem informações de cidadãos',
            _ => 'Ninguém informou a fila ainda. Seja o primeiro.',
          };

    return Container(
      padding: const EdgeInsets.all(Espaco.gg),
      decoration: BoxDecoration(
        color: nivel.fundoSuave(tema.brightness),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: nivel.cor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(unidade.nome, style: tema.textTheme.headlineSmall),
          ),
          const SizedBox(height: 2),
          Text(
            [
              ?unidade.bairro,
              unidade.cidade,
              if (distanciaKm != null) formatarDistancia(distanciaKm),
            ].join(' · '),
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: Espaco.g),
          Semantics(
            label: fechada
                ? 'Fechada agora'
                : unidade.estimada
                ? 'Estimativa: ${nivel.rotulo.toLowerCase()}, espera típica de ${formatarEspera(unidade.esperaMin)}'
                : '${nivel.rotulo}, espera de ${formatarEspera(unidade.esperaMin)}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  fechada ? Icons.lock_clock_rounded : nivel.icone,
                  color: cor,
                  size: 40,
                ),
                const SizedBox(width: Espaco.p),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      fechada
                          ? 'Fechada'
                          : '${unidade.estimada ? '~' : ''}${formatarEspera(unidade.esperaMin)}',
                      style: tema.textTheme.displaySmall?.copyWith(
                        color: cor,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaco.pp),
          Text(
            fechada
                ? 'Sem atendimento agora'
                : unidade.estimada
                ? 'Estimativa: ${nivel.rotulo.toLowerCase()}'
                : nivel.rotulo,
            style: tema.textTheme.titleMedium?.copyWith(color: cor),
          ),
          const SizedBox(height: Espaco.m),
          Text(origem, style: tema.textTheme.bodySmall),
          if (momento != null && !fechada) ...[
            const SizedBox(height: Espaco.m),
            _SeloDoMomento(analise: momento!),
          ],
          if (unidade.emTempoReal && !fechada) ...[
            const SizedBox(height: Espaco.m),
            Row(
              children: [
                Expanded(
                  child: _Metrica(
                    icone: Icons.verified_rounded,
                    valor: '${unidade.confianca}%',
                    rotulo: 'confiança da estimativa',
                  ),
                ),
                const SizedBox(width: Espaco.p),
                Expanded(
                  child: _Metrica(
                    icone: Icons.groups_rounded,
                    valor: '${unidade.pessoasAguardando}',
                    rotulo: unidade.pessoasAguardando == 1
                        ? 'pessoa na fila pelo app'
                        : 'pessoas na fila pelo app',
                  ),
                ),
              ],
            ),
          ],
          if (unidade.notaMedia != null) ...[
            const SizedBox(height: Espaco.m),
            Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: Color(0xFFF2B01E),
                ),
                const SizedBox(width: 4),
                Text(
                  '${unidade.notaMedia!.toStringAsFixed(1).replaceAll('.', ',')} '
                  '(${unidade.qtdAvaliacoes} ${unidade.qtdAvaliacoes == 1 ? 'avaliação' : 'avaliações'})',
                  style: tema.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
          const SizedBox(height: Espaco.p),
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 18,
                color: tema.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(unidade.endereco, style: tema.textTheme.bodySmall),
              ),
            ],
          ),
          if (unidade.creditoDoCadastro case final credito?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(credito, style: tema.textTheme.labelSmall),
            ),
        ],
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica({
    required this.icone,
    required this.valor,
    required this.rotulo,
  });

  final IconData icone;
  final String valor;
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Espaco.m),
      decoration: BoxDecoration(
        color: tema.cardTheme.color?.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icone, size: 20, color: tema.colorScheme.onSurfaceVariant),
          const SizedBox(width: Espaco.p),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valor, style: tema.textTheme.titleMedium),
                Text(rotulo, style: tema.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcaoRapida extends StatelessWidget {
  const _AcaoRapida({
    required this.icone,
    required this.rotulo,
    required this.aoTocar,
    this.dica,
    this.destacada = false,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback aoTocar;
  final String? dica;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.primary;
    return Expanded(
      child: Semantics(
        button: true,
        label: dica ?? rotulo,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Espaco.p),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: destacada ? cor : cor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icone,
                    color: destacada ? tema.colorScheme.onPrimary : cor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  rotulo,
                  style: tema.textTheme.labelMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ação principal sempre ao alcance do polegar, no rodapé da ficha.
class _BarraDeAcao extends StatelessWidget {
  const _BarraDeAcao({
    required this.filaAtiva,
    required this.aberta,
    required this.aoChegar,
    required this.aoInformar,
  });

  final RegistroFila? filaAtiva;
  final bool aberta;
  final VoidCallback aoChegar;
  final VoidCallback aoInformar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tema.cardTheme.color,
        border: Border(top: BorderSide(color: tema.dividerColor)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Espaco.m),
          child: LarguraMaxima(
            ajustarAltura: true,
            child: filaAtiva != null
                ? const FaixaFilaAtiva()
                : !aberta
                ? Row(
                    children: [
                      Icon(
                        Icons.lock_clock_rounded,
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Espaco.m),
                      const Expanded(
                        child: Text(
                          'Unidade fechada agora. Veja acima o melhor horário para ir.',
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, limites) {
                      final cheguei = FilledButton.icon(
                        onPressed: aoChegar,
                        icon: const Icon(Icons.how_to_reg_rounded),
                        label: const Text('Cheguei na fila'),
                      );
                      final informar = OutlinedButton(
                        onPressed: aoInformar,
                        child: const Text('Só informar'),
                      );
                      // Em telas muito estreitas os botões ficam um sobre o outro, sem cortar o texto.
                      if (limites.maxWidth < 340) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            cheguei,
                            const SizedBox(height: Espaco.p),
                            informar,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 4, child: informar),
                          const SizedBox(width: Espaco.p),
                          Expanded(flex: 5, child: cheguei),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _RelatoItem extends StatelessWidget {
  const _RelatoItem({
    required this.relato,
    required this.proprio,
    required this.aoConfirmar,
    required this.aoDenunciar,
  });

  final Relato relato;
  final bool proprio;
  final VoidCallback aoConfirmar;
  final VoidCallback aoDenunciar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = relato.positivo
        ? NivelEspera.baixa.corSobreSuperficie(tema.brightness)
        : tema.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              relato.positivo
                  ? Icons.check_circle_rounded
                  : Icons.campaign_rounded,
              color: cor,
              size: 22,
            ),
          ),
          const SizedBox(width: Espaco.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(relato.rotulo, style: tema.textTheme.titleSmall),
                if (relato.descricao != null) Text(relato.descricao!),
                Text(
                  '${relato.autor} · ${formatarHaQuantoTempo(relato.criadoEm)}'
                  '${relato.confirmacoes > 0 ? ' · ${relato.confirmacoes} ${relato.confirmacoes == 1 ? 'confirmou' : 'confirmaram'}' : ''}',
                  style: tema.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!proprio) ...[
            IconButton(
              tooltip: 'Confirmar este aviso',
              icon: const Icon(Icons.thumb_up_outlined),
              onPressed: aoConfirmar,
            ),
            IconButton(
              tooltip: 'Denunciar este aviso',
              icon: const Icon(Icons.flag_outlined),
              onPressed: aoDenunciar,
            ),
          ],
        ],
      ),
    );
  }
}

class _SeletorDeDia extends StatelessWidget {
  const _SeletorDeDia({required this.dia, required this.aoTrocar});

  final int dia;
  final ValueChanged<int> aoTrocar;

  @override
  Widget build(BuildContext context) {
    final hoje = DateTime.now().weekday % 7;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(i == hoje ? 'Hoje' : diasDaSemana[i]),
                selected: dia == i,
                onSelected: (_) => aoTrocar(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barras de espera média por hora. A descrição em texto repete a conclusão do gráfico.
class _GraficoPrevisao extends StatelessWidget {
  const _GraficoPrevisao({required this.previsao});

  final List<PrevisaoHora> previsao;

  @override
  Widget build(BuildContext context) {
    if (previsao.isEmpty) {
      return const EstadoVazio(
        icone: Icons.bar_chart_rounded,
        texto: 'Sem histórico para este dia. A unidade pode estar fechada.',
      );
    }
    final tema = Theme.of(context);
    final melhor = previsao.firstWhere(
      (p) => p.melhor,
      orElse: () => previsao.first,
    );
    final pior = previsao.reduce((a, b) => a.mediaMin >= b.mediaMin ? a : b);
    final teto = (pior.mediaMin * 1.2)
        .ceilToDouble()
        .clamp(10, 1000)
        .toDouble();
    final intervaloDeRotulos = previsao.length > 12 ? 3 : 1;
    final totalDeRegistros = previsao.fold<int>(
      0,
      (soma, p) => soma + p.amostras,
    );
    final soEstimativa = totalDeRegistros == 0;
    final algumaEstimada = previsao.any((p) => p.amostras == 0);
    final corDosEixos = tema.textTheme.labelSmall?.copyWith(
      color: tema.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _DestaqueDeHorario(
                rotulo: soEstimativa
                    ? 'Melhor horário (estimado)'
                    : 'Melhor horário',
                hora: melhor.hora,
                minutos: melhor.mediaMin,
                nivel: NivelEspera.porMinutos(melhor.mediaMin),
              ),
            ),
            const SizedBox(width: Espaco.p),
            Expanded(
              child: _DestaqueDeHorario(
                rotulo: soEstimativa
                    ? 'Horário de pico (estimado)'
                    : 'Horário de pico',
                hora: pior.hora,
                minutos: pior.mediaMin,
                nivel: NivelEspera.porMinutos(pior.mediaMin),
              ),
            ),
          ],
        ),
        const SizedBox(height: Espaco.g),
        SizedBox(
          height: 170,
          child: ExcludeSemantics(
            child: BarChart(
              BarChartData(
                maxY: teto,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: tema.dividerColor, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (grupo, _, barra, _) => BarTooltipItem(
                      '${grupo.x}h\n${formatarEspera(barra.toY.round())}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (valor, meta) => valor == meta.max
                          ? const SizedBox.shrink()
                          : SideTitleWidget(
                              meta: meta,
                              child: Text(
                                '${valor.round()}',
                                style: corDosEixos,
                              ),
                            ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (valor, meta) => SideTitleWidget(
                        meta: meta,
                        child: valor.round() % intervaloDeRotulos == 0
                            ? Text('${valor.round()}h', style: corDosEixos)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (final p in previsao)
                    BarChartGroupData(
                      x: p.hora,
                      barRods: [
                        BarChartRodData(
                          toY: p.mediaMin.toDouble(),
                          width: previsao.length > 12 ? 8 : 16,
                          color: NivelEspera.porMinutos(p.mediaMin).cor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          borderSide: p.melhor
                              ? BorderSide(
                                  color: tema.colorScheme.onSurface,
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Espaco.pp),
        Text(
          soEstimativa
              ? 'Estimativa do modelo para este tipo de unidade, em minutos de espera por hora. '
                    'Ainda não há registros de cidadãos; ela é substituída pelos dados reais conforme eles chegam.'
              : 'Minutos de espera por hora, pela média de $totalDeRegistros registros de cidadãos dos últimos 60 dias.'
                    '${algumaEstimada ? ' As horas sem registro usam a estimativa do modelo.' : ''}',
          style: tema.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _DestaqueDeHorario extends StatelessWidget {
  const _DestaqueDeHorario({
    required this.rotulo,
    required this.hora,
    required this.minutos,
    required this.nivel,
  });

  final String rotulo;
  final int hora;
  final int minutos;
  final NivelEspera nivel;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = nivel.corSobreSuperficie(tema.brightness);
    return Semantics(
      label: '$rotulo: $hora horas, com cerca de ${formatarEspera(minutos)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Espaco.m),
        decoration: BoxDecoration(
          color: nivel.fundoSuave(tema.brightness),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rotulo, style: tema.textTheme.labelMedium),
            Text(
              '${hora}h',
              style: tema.textTheme.headlineSmall?.copyWith(color: cor),
            ),
            Text(
              'cerca de ${formatarEspera(minutos)}',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Horarios extends StatelessWidget {
  const _Horarios({required this.horarios});

  final List<HorarioFuncionamento> horarios;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    if (horarios.isEmpty) return const Text('Horário não informado.');
    if (horarios.length == 7 && horarios.every((h) => h.dia24Horas)) {
      return const Text('Aberta 24 horas, todos os dias.');
    }
    final porDia = {for (final h in horarios) h.diaSemana: h};
    final hoje = DateTime.now().weekday % 7;
    return Column(
      children: [
        for (var dia = 0; dia < 7; dia++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontWeight: dia == hoje ? FontWeight.w800 : FontWeight.w400,
              ),
              child: Row(
                children: [
                  SizedBox(width: 56, child: Text(diasDaSemana[dia])),
                  Expanded(
                    child: Text(
                      porDia[dia] == null
                          ? 'Fechada'
                          : '${porDia[dia]!.abre} às ${porDia[dia]!.fecha}',
                      style: porDia[dia] == null
                          ? TextStyle(color: tema.colorScheme.onSurfaceVariant)
                          : null,
                    ),
                  ),
                  if (dia == hoje)
                    Text('hoje', style: tema.textTheme.labelSmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AvaliacaoItem extends StatelessWidget {
  const _AvaliacaoItem({
    required this.avaliacao,
    required this.proprio,
    required this.aoDenunciar,
  });

  final Avaliacao avaliacao;
  final bool proprio;
  final VoidCallback aoDenunciar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: tema.colorScheme.primary.withValues(alpha: 0.12),
            foregroundColor: tema.colorScheme.primary,
            child: Text(
              iniciaisDe(avaliacao.autor),
              style: tema.textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: Espaco.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'Nota ${avaliacao.nota} de 5',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        Icon(
                          i <= avaliacao.nota
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 18,
                          color: const Color(0xFFF2B01E),
                        ),
                    ],
                  ),
                ),
                if (avaliacao.oculta)
                  Text(
                    'Comentário removido após denúncias de outras pessoas.',
                    style: tema.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (avaliacao.comentario != null)
                  Text(avaliacao.comentario!),
                Text(
                  '${avaliacao.autor} · ${formatarHaQuantoTempo(avaliacao.criadoEm)}',
                  style: tema.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!proprio && avaliacao.id != null && !avaliacao.oculta)
            IconButton(
              tooltip: 'Denunciar esta avaliação',
              icon: const Icon(Icons.flag_outlined),
              onPressed: aoDenunciar,
            ),
        ],
      ),
    );
  }
}

class _EscolherTamanho extends StatelessWidget {
  const _EscolherTamanho({required this.estouNaFila});

  final bool estouNaFila;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            estouNaFila
                ? 'Como está a fila na sua chegada?'
                : 'Como está a fila agora?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Um toque e pronto. Sua resposta ajuda quem ainda vai sair de casa.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final tamanho in TamanhoFila.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _nivelDoTamanho(tamanho).cor,
                    child: Icon(
                      _nivelDoTamanho(tamanho).icone,
                      color: _nivelDoTamanho(tamanho).corDoTexto,
                    ),
                  ),
                  title: Text(tamanho.rotulo),
                  subtitle: Text(tamanho.descricao),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(tamanho),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  NivelEspera _nivelDoTamanho(TamanhoFila tamanho) => switch (tamanho) {
    TamanhoFila.semFila || TamanhoFila.curta => NivelEspera.baixa,
    TamanhoFila.media => NivelEspera.moderada,
    TamanhoFila.longa => NivelEspera.alta,
    TamanhoFila.lotada => NivelEspera.critica,
  };
}

class _NovoRelato extends StatefulWidget {
  const _NovoRelato();

  @override
  State<_NovoRelato> createState() => _NovoRelatoState();
}

class _NovoRelatoState extends State<_NovoRelato> {
  final _descricao = TextEditingController();
  String _tipo = 'sem_medico';

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'O que está acontecendo?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entrada in Relato.rotulos.entries)
                ChoiceChip(
                  label: Text(entrada.value),
                  selected: _tipo == entrada.key,
                  onSelected: (_) => setState(() => _tipo = entrada.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descricao,
            maxLength: 140,
            decoration: const InputDecoration(labelText: 'Detalhes (opcional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop((_tipo, _descricao.text)),
            child: const Text('Publicar aviso'),
          ),
        ],
      ),
    ),
  );
}

/// Devolve o limite em minutos, ou -1 para remover o alerta.
class _ConfigurarAlerta extends StatefulWidget {
  const _ConfigurarAlerta({required this.limiteAtual});

  final int? limiteAtual;

  @override
  State<_ConfigurarAlerta> createState() => _ConfigurarAlertaState();
}

class _ConfigurarAlertaState extends State<_ConfigurarAlerta> {
  late double _limite = (widget.limiteAtual ?? 20).toDouble();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Alerta de fila baixa',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Avisar quando a espera ficar em até ${_limite.round()} minutos.',
          ),
          const SizedBox(height: 28),
          Slider(
            value: _limite,
            min: 5,
            max: 120,
            divisions: 23,
            label: '${_limite.round()} min',
            onChanged: (v) => setState(() => _limite = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_limite.round()),
            child: const Text('Salvar alerta'),
          ),
          if (widget.limiteAtual != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(-1),
              child: const Text('Remover alerta'),
            ),
        ],
      ),
    ),
  );
}

/// Selo "Bom momento para ir", "Horário de pico" ou "Dentro do normal", com ícone e cor (nunca só cor).
class _SeloDoMomento extends StatelessWidget {
  const _SeloDoMomento({required this.analise});

  final AnaliseDoMomento analise;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final (icone, cor) = switch (analise.momento) {
      Momento.bom => (Icons.thumb_up_alt_rounded, const Color(0xFF16803C)),
      Momento.pico => (Icons.trending_up_rounded, const Color(0xFFB54708)),
      Momento.normal => (
        Icons.horizontal_rule_rounded,
        tema.colorScheme.onSurfaceVariant,
      ),
    };
    return Semantics(
      label: analise.texto,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Espaco.m,
          vertical: Espaco.p,
        ),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icone, size: 20, color: cor),
            const SizedBox(width: Espaco.p),
            Expanded(
              child: Text(
                analise.texto,
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: cor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DadosDaSugestao {
  const _DadosDaSugestao(this.campo, this.descricao, this.usarMinhaPosicao);

  final String campo;
  final String descricao;
  final bool usarMinhaPosicao;
}

/// Formulário "Sugerir correção": o que está errado, detalhes e, se for a localização, usar a posição atual.
class _NovaSugestao extends StatefulWidget {
  const _NovaSugestao({required this.podeUsarMinhaPosicao});

  final bool podeUsarMinhaPosicao;

  @override
  State<_NovaSugestao> createState() => _NovaSugestaoState();
}

class _NovaSugestaoState extends State<_NovaSugestao> {
  static const _campos = {
    'localizacao': 'O pino está no lugar errado',
    'telefone': 'Telefone errado',
    'endereco': 'Endereço errado',
    'nome': 'Nome errado',
    'fechada': 'A unidade fechou',
    'horario': 'Horário de funcionamento errado',
    'outro': 'Outro problema',
  };
  static const _dicas = {
    'localizacao': 'Onde fica de verdade? (ex.: a 2 quarteirões, na outra rua)',
    'telefone': 'Digite o telefone correto, com DDD',
    'endereco': 'Digite o endereço correto, com número e bairro',
    'nome': 'Digite o nome correto da unidade',
    'fechada': 'Conte o que viu (ex.: fechou em outubro, mudou de endereço)',
    'horario': 'Qual o horário correto? (ex.: seg a sex, 7h às 17h)',
    'outro': 'Conte o que está errado',
  };

  final _descricao = TextEditingController();
  String _campo = 'localizacao';
  bool _usarPosicao = false;
  String? _erro;

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  void _enviar() {
    if (_descricao.text.trim().length < 5) {
      setState(() => _erro = 'Escreva pelo menos 5 letras.');
      return;
    }
    Navigator.of(context).pop(
      _DadosDaSugestao(
        _campo,
        _descricao.text,
        _campo == 'localizacao' && _usarPosicao,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'O que está errado?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entrada in _campos.entries)
                ChoiceChip(
                  label: Text(entrada.value),
                  selected: _campo == entrada.key,
                  onSelected: (_) => setState(() => _campo = entrada.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descricao,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _dicas[_campo],
              errorText: _erro,
            ),
            onChanged: (_) => setState(() => _erro = null),
          ),
          if (_campo == 'localizacao' && widget.podeUsarMinhaPosicao)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _usarPosicao,
              onChanged: (v) => setState(() => _usarPosicao = v ?? false),
              title: const Text('Estou na unidade: usar minha posição atual'),
              subtitle: const Text(
                'A análise usa esse ponto para corrigir o mapa.',
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _enviar,
            child: const Text('Enviar sugestão'),
          ),
          const SizedBox(height: 4),
          Text(
            'Sua sugestão é analisada antes de mudar o mapa. Quem ajuda ganha pontos quando ela é aceita.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

/// Mapa de calor da semana: cada célula é uma hora de um dia; a cor é o nível da espera típica.
/// Responde "qual o melhor dia e hora para ir?" de uma olhada. A melhor janela leva uma estrela.
class _MapaDeCalor extends StatelessWidget {
  const _MapaDeCalor({required this.slots});

  final List<SlotSemanal> slots;

  @override
  Widget build(BuildContext context) {
    final resumo = melhorEPiorJanela(slots);
    if (resumo == null) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final porCelula = {for (final s in slots) (s.dia, s.hora): s};
    final primeira = slots.map((s) => s.hora).reduce((a, b) => a < b ? a : b);
    final ultima = slots.map((s) => s.hora).reduce((a, b) => a > b ? a : b);
    final agora = DateTime.now();
    final hoje = agora.weekday % 7;
    final totalDeRegistros = slots.fold<int>(0, (soma, s) => soma + s.amostras);

    Widget celula(int dia, int hora) {
      final slot = porCelula[(dia, hora)];
      if (slot == null) {
        return Expanded(
          child: Container(
            height: 20,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: tema.colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }
      final nivel = NivelEspera.porMinutos(slot.mediaMin);
      final ehMelhor =
          slot.dia == resumo.melhor.dia && slot.hora == resumo.melhor.hora;
      final ehAgora = dia == hoje && hora == agora.hour;
      return Expanded(
        child: Container(
          height: 20,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: nivel.cor.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(4),
            border: ehAgora
                ? Border.all(color: tema.colorScheme.onSurface, width: 2)
                : null,
          ),
          alignment: Alignment.center,
          child: ehMelhor
              ? const Icon(Icons.star_rounded, size: 13, color: Colors.white)
              : null,
        ),
      );
    }

    return Semantics(
      label:
          'Mapa de calor da semana. Melhor janela: ${resumo.melhor.descricao}. '
          'Pior janela: ${resumo.pior.descricao}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A semana inteira', style: tema.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            'Melhor janela: ${resumo.melhor.descricao}.  Pior: ${resumo.pior.descricao}.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: Espaco.m),
          for (var dia = 0; dia < 7; dia++)
            Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    diasDaSemana[dia],
                    style: tema.textTheme.labelSmall?.copyWith(
                      fontWeight: dia == hoje
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
                for (var hora = primeira; hora <= ultima; hora++)
                  celula(dia, hora),
              ],
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 34),
              for (var hora = primeira; hora <= ultima; hora++)
                Expanded(
                  child: Text(
                    (hora - primeira) % 3 == 0 ? '${hora}h' : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: tema.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Espaco.p),
          Wrap(
            spacing: Espaco.m,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final n in [
                NivelEspera.baixa,
                NivelEspera.moderada,
                NivelEspera.alta,
                NivelEspera.critica,
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: n.cor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      n.rotulo.replaceFirst('Fila ', ''),
                      style: tema.textTheme.labelSmall,
                    ),
                  ],
                ),
              const Icon(Icons.star_rounded, size: 14),
              Text('melhor', style: tema.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            totalDeRegistros == 0
                ? 'Estimativa do modelo para este tipo de unidade, até haver registros de cidadãos. Contorno: agora.'
                : 'Média de $totalDeRegistros registros de cidadãos; horas sem registro usam o modelo. Contorno: agora.',
            style: tema.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// Hoje ou amanhã é feriado: o horário da unidade pode mudar.
class _AvisoDeFeriado extends StatelessWidget {
  const _AvisoDeFeriado({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    const cor = Color(0xFFB54708);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Espaco.m),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_busy_rounded, color: cor),
            const SizedBox(width: Espaco.m),
            Expanded(
              child: Text(
                texto,
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: cor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esta unidade comparada às do mesmo tipo por perto.
class _Comparacao extends StatelessWidget {
  const _Comparacao({
    required this.unidade,
    required this.comparacao,
    required this.aoAbrirMelhor,
  });

  final Unidade unidade;
  final ComparacaoComVizinhas comparacao;
  final VoidCallback aoAbrirMelhor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final diferenca = comparacao.diferencaPct;
    final (texto, cor) = diferenca >= 20
        ? ('$diferenca% mais cheia que a média', tema.colorScheme.error)
        : diferenca <= -20
        ? (
            '${-diferenca}% mais vazia que a média',
            NivelEspera.baixa.corSobreSuperficie(tema.brightness),
          )
        : ('Na média das vizinhas', tema.colorScheme.onSurfaceVariant);
    final estimativa = unidade.estimada || comparacao.melhor.estimada;
    final melhorEMelhor = comparacao.melhor.esperaMin! < unidade.esperaMin!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(texto, style: tema.textTheme.titleMedium?.copyWith(color: cor)),
        const SizedBox(height: 2),
        Text(
          'Média de ${comparacao.vizinhas} ${unidade.tipo} abertas num raio de ${comparacao.raioKm.round()} km: '
          '~${formatarEspera(comparacao.mediaMin)}.${estimativa ? ' Valores estimados pelo modelo.' : ''}',
          style: tema.textTheme.bodySmall,
        ),
        if (melhorEMelhor) ...[
          const SizedBox(height: Espaco.m),
          OutlinedButton.icon(
            onPressed: aoAbrirMelhor,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(
              'Mais rápida: ${comparacao.melhor.nome} (~${formatarEspera(comparacao.melhor.esperaMin)})',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// "Tenho horário marcado": mostra o plano salvo desta unidade ou o botão para criar.
class _PlanoDeIda extends StatelessWidget {
  const _PlanoDeIda({required this.unidadeId, required this.aoPlanejar});

  final int unidadeId;
  final VoidCallback aoPlanejar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final plano = context.watch<PlanoControlador>().plano;
    final daqui = plano != null && plano.unidadeId == unidadeId ? plano : null;
    final localizacoes = MaterialLocalizations.of(context);
    String quando(DateTime d) =>
        '${localizacoes.formatShortDate(d)} às ${localizacoes.formatTimeOfDay(TimeOfDay.fromDateTime(d), alwaysUse24HourFormat: true)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (daqui != null) ...[
          Text(
            'Atendimento: ${quando(daqui.horario)}',
            style: tema.textTheme.titleSmall,
          ),
          Text(
            'Saia de casa até ${quando(daqui.saida)} (${daqui.deslocamentoMin} min de caminho + ${PlanoDeIda.folgaMin} min de folga).',
          ),
          const SizedBox(height: Espaco.m),
          Row(
            children: [
              OutlinedButton(
                onPressed: aoPlanejar,
                child: const Text('Mudar horário'),
              ),
              const SizedBox(width: Espaco.p),
              TextButton(
                onPressed: () => context.read<PlanoControlador>().limpar(),
                child: const Text('Remover plano'),
              ),
            ],
          ),
        ] else ...[
          Text(
            'Tem horário marcado? Diga o dia e a hora: o app calcula quando sair de casa, '
            'já contando o caminho e uma folga de ${PlanoDeIda.folgaMin} minutos.',
            style: tema.textTheme.bodyMedium,
          ),
          const SizedBox(height: Espaco.m),
          OutlinedButton.icon(
            onPressed: aoPlanejar,
            icon: const Icon(Icons.edit_calendar_rounded),
            label: const Text('Planejar minha ida'),
          ),
        ],
      ],
    );
  }
}

/// Lista do que levar, com caixinhas para marcar o que já está separado (só nesta tela, nada é enviado).
class _OQueLevar extends StatefulWidget {
  const _OQueLevar({required this.tipo});

  final String tipo;

  @override
  State<_OQueLevar> createState() => _OQueLevarState();
}

class _OQueLevarState extends State<_OQueLevar> {
  final _separados = <String>{};

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final itens = oQueLevar(widget.tipo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in itens)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _separados.contains(item),
            title: Text(item),
            onChanged: (marcou) => setState(
              () => marcou == true
                  ? _separados.add(item)
                  : _separados.remove(item),
            ),
          ),
        const SizedBox(height: Espaco.p),
        Text(
          _separados.length == itens.length ? 'Tudo separado. Boa ida!' : aviso,
          style: tema.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Recursos de acessibilidade confirmados por outras pessoas e o direito a atendimento prioritário.
class _Acessibilidade extends StatelessWidget {
  const _Acessibilidade({
    required this.contagens,
    required this.meusVotos,
    required this.aoVotar,
  });

  final List<ContagemDeRecurso> contagens;
  final Map<RecursoDeAcessibilidade, bool> meusVotos;
  final void Function(RecursoDeAcessibilidade recurso, bool existe) aoVotar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final porRecurso = {for (final c in contagens) c.recurso: c};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Espaco.m),
          decoration: BoxDecoration(
            color: tema.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Você pode ter direito a atendimento prioritário: pessoas com 60 anos ou mais (80 anos ou mais têm preferência '
            'especial), gestantes, lactantes, pessoas com crianças de colo, pessoas com deficiência e pessoas com '
            'mobilidade reduzida (Leis 10.048/2000 e 13.146/2015). Peça na entrada.',
            style: tema.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: Espaco.m),
        Text('Confirmado por quem já foi', style: tema.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Já esteve aqui? Diga o que existe. Ajuda quem tem dificuldade de locomoção.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: Espaco.p),
        for (final recurso in RecursoDeAcessibilidade.values)
          _LinhaDeRecurso(
            recurso: recurso,
            contagem: porRecurso[recurso],
            meuVoto: meusVotos[recurso],
            aoVotar: (existe) => aoVotar(recurso, existe),
          ),
      ],
    );
  }
}

class _LinhaDeRecurso extends StatelessWidget {
  const _LinhaDeRecurso({
    required this.recurso,
    required this.contagem,
    required this.meuVoto,
    required this.aoVotar,
  });

  final RecursoDeAcessibilidade recurso;
  final ContagemDeRecurso? contagem;
  final bool? meuVoto;
  final void Function(bool existe) aoVotar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final c = contagem ?? ContagemDeRecurso(recurso: recurso, sim: 0, nao: 0);
    final cor = c.existe
        ? NivelEspera.baixa.corSobreSuperficie(tema.brightness)
        : c.inexiste
        ? tema.colorScheme.error
        : tema.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            c.existe
                ? Icons.check_circle_rounded
                : c.inexiste
                ? Icons.cancel_rounded
                : Icons.help_outline_rounded,
            color: cor,
            size: 22,
          ),
          const SizedBox(width: Espaco.m),
          Expanded(
            child: Semantics(
              label: '${recurso.rotulo}: ${c.resumo}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recurso.rotulo, style: tema.textTheme.bodyMedium),
                  Text(
                    c.resumo,
                    style: tema.textTheme.bodySmall?.copyWith(color: cor),
                  ),
                ],
              ),
            ),
          ),
          ToggleButtons(
            isSelected: [meuVoto == true, meuVoto == false],
            constraints: const BoxConstraints(minWidth: 52, minHeight: 40),
            borderRadius: BorderRadius.circular(10),
            onPressed: (i) => aoVotar(i == 0),
            children: [
              Semantics(
                label: 'Tem ${recurso.rotulo}',
                excludeSemantics: true,
                child: const Text('Tem'),
              ),
              Semantics(
                label: 'Não tem ${recurso.rotulo}',
                excludeSemantics: true,
                child: const Text('Não'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Abas da ficha: a tela ficou longa, então as seções foram agrupadas pelo que a pessoa quer saber em cada momento.
/// Agora (situação e avisos), Ir (planejar e o que levar), Sobre (serviços, horários, acessibilidade), Opiniões.
class _AbasDaFicha extends StatelessWidget {
  const _AbasDaFicha({required this.aba, required this.aoTrocar});

  final int aba;
  final ValueChanged<int> aoTrocar;

  static const _abas = [
    (Icons.bolt_rounded, 'Agora'),
    (Icons.directions_walk_rounded, 'Ir'),
    (Icons.info_outline_rounded, 'Sobre'),
    (Icons.star_outline_rounded, 'Opiniões'),
  ];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Seções da unidade',
      child: Row(
        children: [
          for (var i = 0; i < _abas.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == _abas.length - 1 ? 0 : Espaco.p,
                ),
                child: Semantics(
                  button: true,
                  selected: aba == i,
                  label: '${_abas[i].$2}${aba == i ? ', selecionada' : ''}',
                  excludeSemantics: true,
                  child: Material(
                    color: aba == i
                        ? tema.colorScheme.primary
                        : tema.cardTheme.color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        IdentidadeVisual.de(context).raioBotao.clamp(8, 18),
                      ),
                      side: BorderSide(
                        color: aba == i
                            ? tema.colorScheme.primary
                            : tema.dividerColor,
                      ),
                    ),
                    child: InkWell(
                      customBorder: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          IdentidadeVisual.de(context).raioBotao.clamp(8, 18),
                        ),
                      ),
                      onTap: () => aoTrocar(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _abas[i].$1,
                              size: 22,
                              color: aba == i
                                  ? tema.colorScheme.onPrimary
                                  : tema.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _abas[i].$2,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: tema.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: aba == i
                                    ? tema.colorScheme.onPrimary
                                    : tema.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cabeçalho fixo (pinned) que guarda as abas da ficha.
class _AbasFixas extends SliverPersistentHeaderDelegate {
  const _AbasFixas({
    required this.aba,
    required this.aoTrocar,
    required this.fundo,
  });

  final int aba;
  final ValueChanged<int> aoTrocar;
  final Color fundo;

  static const _altura = 68.0;

  @override
  double get minExtent => _altura;

  @override
  double get maxExtent => _altura;

  @override
  Widget build(BuildContext context, double deslocamento, bool sobrepoe) =>
      Material(
        color: fundo,
        elevation: sobrepoe ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Espaco.g,
            vertical: 6,
          ),
          child: LarguraMaxima(
            child: _AbasDaFicha(aba: aba, aoTrocar: aoTrocar),
          ),
        ),
      );

  @override
  bool shouldRebuild(covariant _AbasFixas antigo) =>
      antigo.aba != aba || antigo.fundo != fundo;
}
