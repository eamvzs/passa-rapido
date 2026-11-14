import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatos.dart';
import '../../core/nivel_espera.dart';
import '../../data/repositorios.dart';
import '../../models/colaboracao.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';

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
  late final ComunidadeRepositorio _comunidade = context.read<ComunidadeRepositorio>();

  List<Servico> _servicos = const [];
  List<HorarioFuncionamento> _horarios = const [];
  List<Relato> _relatos = const [];
  List<Avaliacao> _avaliacoes = const [];
  List<PrevisaoHora> _previsao = const [];
  Favorito? _favorito;
  int _diaPrevisao = DateTime.now().weekday % 7;
  bool _carregando = true;

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

    final (servicos, horarios, relatos, avaliacoes, previsao, favoritos) = await (
      seguro(_unidades.listarServicos(id), _servicos),
      seguro(_unidades.listarHorarios(id), _horarios),
      seguro(_comunidade.listarRelatos(id), _relatos),
      seguro(_comunidade.listarAvaliacoes(id), _avaliacoes),
      seguro(_unidades.melhorHorario(id, _diaPrevisao), _previsao),
      seguro(autenticado ? _comunidade.listarFavoritos() : Future.value(<Favorito>[]), <Favorito>[]),
    ).wait;
    if (!mounted) return;
    setState(() {
      _servicos = servicos;
      _horarios = horarios;
      _relatos = relatos;
      _avaliacoes = avaliacoes;
      _previsao = previsao;
      _favorito = favoritos.where((f) => f.unidadeId == id).firstOrNull;
      _carregando = false;
    });
    if (houveFalha) mostrarMensagem(context, 'Parte das informações não carregou. Tente atualizar.');
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
      await context.read<FilaControlador>().registrar(
            unidadeId: widget.unidadeId,
            tamanho: tamanho,
            estouNaFila: estouNaFila,
          );
      if (!mounted) return;
      await context.read<SessaoControlador>().recarregarPerfil();
      if (!mounted) return;
      mostrarMensagem(
        context,
        estouNaFila
            ? 'Chegada registrada. Você ganhou 5 pontos. Avise quando for atendido.'
            : 'Obrigado! Você ganhou 3 pontos.',
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
      () => _comunidade.criarRelato(unidadeId: widget.unidadeId, tipo: dados.$1, descricao: dados.$2),
      'Aviso publicado. Você ganhou 3 pontos.',
    );
  }

  Future<void> _confirmarRelato(Relato relato) async {
    if (!await garantirLogin(context)) return;
    await _executar(() => _comunidade.confirmarRelato(relato.id), 'Confirmação registrada.');
  }

  Future<void> _avaliar() async {
    if (!await garantirLogin(context) || !mounted) return;
    final dados = await showModalBottomSheet<(int, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _NovaAvaliacao(),
    );
    if (dados == null) return;
    await _executar(
      () => _comunidade.avaliar(unidadeId: widget.unidadeId, nota: dados.$1, comentario: dados.$2),
      'Avaliação salva.',
    );
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
      await _executar(() => _comunidade.removerFavorito(widget.unidadeId), 'Alerta removido.');
    } else {
      await _executar(
        () => _comunidade.salvarFavorito(unidadeId: widget.unidadeId, limiteMin: resultado),
        'Você será avisado quando a espera ficar em até $resultado min.',
      );
    }
  }

  Future<void> _executar(Future<void> Function() acao, String sucesso) async {
    try {
      await acao();
      if (!mounted) return;
      mostrarMensagem(context, sucesso);
      await Future.wait([
        _carregarTudo(),
        context.read<SessaoControlador>().recarregarPerfil(),
      ]);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  Future<void> _ouvir(Unidade unidade) async {
    final melhor = _previsao.where((p) => p.melhor).firstOrNull;
    final texto = StringBuffer('${unidade.nome}. ${unidade.nivel.rotulo}. ')
      ..write(unidade.esperaMin == null
          ? 'Ainda não há informação de espera. '
          : 'Espera estimada de ${formatarEspera(unidade.esperaMin).replaceAll('h', 'horas').replaceAll('min', 'minutos')}. ')
      ..write(unidade.abertaAgora ? 'A unidade está aberta. ' : 'A unidade está fechada agora. ')
      ..write(_relatos.where((r) => !r.positivo).isEmpty
          ? ''
          : 'Avisos: ${_relatos.where((r) => !r.positivo).map((r) => r.rotulo).toSet().join(', ')}. ')
      ..write(melhor == null ? '' : 'O melhor horário costuma ser às ${melhor.hora} horas.');
    await _voz.setLanguage('pt-BR');
    await _voz.speak(texto.toString());
  }

  Future<void> _comoChegar(Unidade unidade) async {
    final destino = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${unidade.latitude},${unidade.longitude}',
    );
    if (!await launchUrl(destino, mode: LaunchMode.externalApplication) && mounted) {
      mostrarMensagem(context, 'Não foi possível abrir o mapa de rotas.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // A situação vem do controlador do mapa, então muda ao vivo com a tela aberta.
    final unidade = context.select<MapaControlador, Unidade?>((m) => m.porId(widget.unidadeId));
    final usuarioId = context.select<SessaoControlador, String?>((s) => s.usuarioId);
    final filaAtiva = context.select<FilaControlador, RegistroFila?>((f) => f.ativo);

    if (unidade == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(unidade.nome),
        actions: [
          IconButton(
            tooltip: 'Ouvir a situação da unidade',
            icon: const Icon(Icons.volume_up),
            onPressed: () => _ouvir(unidade),
          ),
          IconButton(
            tooltip: _favorito == null ? 'Criar alerta de fila baixa' : 'Editar alerta de fila baixa',
            icon: Icon(_favorito == null ? Icons.notifications_none : Icons.notifications_active),
            onPressed: _alternarFavorito,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _Situacao(unidade: unidade),
                const SizedBox(height: 12),
                if (filaAtiva == null) ...[
                  FilledButton.icon(
                    onPressed: () => _informarFila(estouNaFila: true),
                    icon: const Icon(Icons.how_to_reg),
                    label: const Text('Cheguei na fila'),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _informarFila(estouNaFila: false),
                        icon: const Icon(Icons.visibility),
                        label: const Text('Só informar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _comoChegar(unidade),
                        icon: const Icon(Icons.directions),
                        label: const Text('Como chegar'),
                      ),
                    ),
                  ],
                ),
                if (_favorito != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Alerta ativo: aviso quando a espera ficar em até ${_favorito!.limiteMin} min.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TituloDeSecao(
                  'Avisos da comunidade',
                  acao: TextButton.icon(
                    onPressed: _novoRelato,
                    icon: const Icon(Icons.add),
                    label: const Text('Avisar'),
                  ),
                ),
                if (_carregando)
                  const LinearProgressIndicator()
                else if (_relatos.isEmpty)
                  const EstadoVazio(icone: Icons.campaign_outlined, texto: 'Nenhum aviso nas últimas horas.')
                else
                  for (final relato in _relatos)
                    _RelatoItem(
                      relato: relato,
                      proprio: relato.usuarioId == usuarioId,
                      aoConfirmar: () => _confirmarRelato(relato),
                    ),
                const TituloDeSecao('Melhor horário'),
                _SeletorDeDia(dia: _diaPrevisao, aoTrocar: _trocarDia),
                const SizedBox(height: 8),
                _GraficoPrevisao(previsao: _previsao),
                const TituloDeSecao('Serviços e documentos'),
                if (_servicos.isEmpty && !_carregando)
                  const EstadoVazio(icone: Icons.list_alt, texto: 'Serviços não informados.')
                else
                  for (final servico in _servicos)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(servico.nome),
                      subtitle: servico.descricao == null ? null : Text(servico.descricao!),
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      expandedAlignment: Alignment.centerLeft,
                      children: [Text('Leve: ${servico.documentos ?? 'documento com foto'}')],
                    ),
                const TituloDeSecao('Horário de funcionamento'),
                _Horarios(horarios: _horarios),
                TituloDeSecao(
                  'Avaliações',
                  acao: TextButton.icon(
                    onPressed: _avaliar,
                    icon: const Icon(Icons.star_border),
                    label: const Text('Avaliar'),
                  ),
                ),
                if (_avaliacoes.isEmpty && !_carregando)
                  const EstadoVazio(icone: Icons.reviews_outlined, texto: 'Ainda sem avaliações.')
                else
                  for (final avaliacao in _avaliacoes) _AvaliacaoItem(avaliacao: avaliacao),
                const SizedBox(height: 16),
                Text(
                  'Em caso de emergência, não espere: ligue 192 (SAMU). '
                  'Os tempos são estimativas feitas com informações de outros cidadãos.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const FaixaFilaAtiva(),
        ],
      ),
    );
  }
}

class _Situacao extends StatelessWidget {
  const _Situacao({required this.unidade});

  final Unidade unidade;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final origem = switch (unidade.fonte) {
      'tempo_real' =>
        'Informado por cidadãos · atualizado ${formatarHaQuantoTempo(unidade.atualizadoEm)}',
      'historico' => 'Estimativa pela média histórica deste dia e horário',
      _ => 'Ninguém informou a fila ainda',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SeloEspera(nivel: unidade.nivel, minutos: unidade.esperaMin, fechada: !unidade.abertaAgora, grande: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unidade.abertaAgora ? unidade.nivel.rotulo : 'Sem atendimento agora', style: tema.textTheme.titleMedium),
                      Text(
                        unidade.abertaAgora ? 'Aberta agora' : 'Fechada agora',
                        style: tema.textTheme.bodyMedium?.copyWith(
                          color: unidade.abertaAgora ? null : tema.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(origem, style: tema.textTheme.bodySmall),
            if (unidade.emTempoReal) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Confiança ${unidade.confianca}%', style: tema.textTheme.bodySmall),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: unidade.confianca / 100,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                unidade.pessoasAguardando == 1
                    ? '1 pessoa na fila usando o app'
                    : '${unidade.pessoasAguardando} pessoas na fila usando o app',
                style: tema.textTheme.bodySmall,
              ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                Icon(iconeDoTipo(unidade.tipo), size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text([unidade.tipo, if (unidade.bairro != null) unidade.bairro!, unidade.cidade].join(' · ')),
                ),
                if (unidade.notaMedia != null) ...[
                  const Icon(Icons.star, size: 18, color: Color(0xFFF9A825)),
                  Text(' ${unidade.notaMedia!.toStringAsFixed(1).replaceAll('.', ',')} (${unidade.qtdAvaliacoes})'),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(unidade.endereco, style: tema.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _RelatoItem extends StatelessWidget {
  const _RelatoItem({required this.relato, required this.proprio, required this.aoConfirmar});

  final Relato relato;
  final bool proprio;
  final VoidCallback aoConfirmar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        relato.positivo ? Icons.check_circle : Icons.campaign,
        color: relato.positivo ? const Color(0xFF2E7D32) : tema.colorScheme.error,
      ),
      title: Text(relato.rotulo),
      subtitle: Text([
        if (relato.descricao != null) relato.descricao!,
        '${relato.autor} · ${formatarHaQuantoTempo(relato.criadoEm)}'
            '${relato.confirmacoes > 0 ? ' · ${relato.confirmacoes} confirmaram' : ''}',
      ].join('\n')),
      isThreeLine: relato.descricao != null,
      trailing: proprio
          ? null
          : IconButton(
              tooltip: 'Confirmar este aviso',
              icon: const Icon(Icons.thumb_up_outlined),
              onPressed: aoConfirmar,
            ),
    );
  }
}

class _SeletorDeDia extends StatelessWidget {
  const _SeletorDeDia({required this.dia, required this.aoTrocar});

  final int dia;
  final ValueChanged<int> aoTrocar;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(diasDaSemana[i]),
                  selected: dia == i,
                  onSelected: (_) => aoTrocar(i),
                ),
              ),
          ],
        ),
      );
}

/// Barras de espera média por hora. A descrição em texto repete a conclusão do gráfico.
class _GraficoPrevisao extends StatelessWidget {
  const _GraficoPrevisao({required this.previsao});

  final List<PrevisaoHora> previsao;

  @override
  Widget build(BuildContext context) {
    if (previsao.isEmpty) {
      return const EstadoVazio(
        icone: Icons.bar_chart,
        texto: 'Sem histórico para este dia. A unidade pode estar fechada.',
      );
    }
    final tema = Theme.of(context);
    final melhor = previsao.firstWhere((p) => p.melhor, orElse: () => previsao.first);
    final pior = previsao.reduce((a, b) => a.mediaMin >= b.mediaMin ? a : b);
    final teto = (pior.mediaMin * 1.2).ceilToDouble().clamp(10, 1000).toDouble();
    final intervaloDeRotulos = previsao.length > 12 ? 3 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Melhor horário: ${melhor.hora}h, com cerca de ${formatarEspera(melhor.mediaMin)}. '
          'Pico às ${pior.hora}h, com ${formatarEspera(pior.mediaMin)}.',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ExcludeSemantics(
            child: BarChart(
              BarChartData(
                maxY: teto,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (grupo, _, barra, _) => BarTooltipItem(
                      '${grupo.x}h\n${formatarEspera(barra.toY.round())}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (valor, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text('${valor.round()}', style: tema.textTheme.labelSmall),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (valor, meta) => SideTitleWidget(
                        meta: meta,
                        child: valor.round() % intervaloDeRotulos == 0
                            ? Text('${valor.round()}h', style: tema.textTheme.labelSmall)
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
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          borderSide: p.melhor
                              ? BorderSide(color: tema.colorScheme.onSurface, width: 2)
                              : BorderSide.none,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Text('Minutos de espera por hora do dia', style: tema.textTheme.labelSmall),
      ],
    );
  }
}

class _Horarios extends StatelessWidget {
  const _Horarios({required this.horarios});

  final List<HorarioFuncionamento> horarios;

  @override
  Widget build(BuildContext context) {
    if (horarios.isEmpty) return const Text('Horário não informado.');
    if (horarios.length == 7 && horarios.every((h) => h.dia24Horas)) {
      return const Text('Aberta 24 horas, todos os dias.');
    }
    final porDia = {for (final h in horarios) h.diaSemana: h};
    return Column(
      children: [
        for (var dia = 0; dia < 7; dia++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 48, child: Text(diasDaSemana[dia])),
                Text(porDia[dia] == null ? 'Fechada' : '${porDia[dia]!.abre} às ${porDia[dia]!.fecha}'),
              ],
            ),
          ),
      ],
    );
  }
}

class _AvaliacaoItem extends StatelessWidget {
  const _AvaliacaoItem({required this.avaliacao});

  final Avaliacao avaliacao;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Semantics(
          label: 'Nota ${avaliacao.nota} de 5',
          child: Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= avaliacao.nota ? Icons.star : Icons.star_border,
                  size: 18,
                  color: const Color(0xFFF9A825),
                ),
            ],
          ),
        ),
        subtitle: Text([
          if (avaliacao.comentario != null) avaliacao.comentario!,
          '${avaliacao.autor} · ${formatarHaQuantoTempo(avaliacao.criadoEm)}',
        ].join('\n')),
      );
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
                estouNaFila ? 'Como está a fila na sua chegada?' : 'Como está a fila agora?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final tamanho in TamanhoFila.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _nivelDoTamanho(tamanho).cor,
                        child: Icon(_nivelDoTamanho(tamanho).icone, color: _nivelDoTamanho(tamanho).corDoTexto),
                      ),
                      title: Text(tamanho.rotulo),
                      subtitle: Text(tamanho.descricao),
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
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('O que está acontecendo?', style: Theme.of(context).textTheme.titleLarge),
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
                onPressed: () => Navigator.of(context).pop((_tipo, _descricao.text)),
                child: const Text('Publicar aviso'),
              ),
            ],
          ),
        ),
      );
}

class _NovaAvaliacao extends StatefulWidget {
  const _NovaAvaliacao();

  @override
  State<_NovaAvaliacao> createState() => _NovaAvaliacaoState();
}

class _NovaAvaliacaoState extends State<_NovaAvaliacao> {
  final _comentario = TextEditingController();
  int _nota = 5;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Como foi o atendimento?', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: 'Nota $i',
                      iconSize: 40,
                      icon: Icon(i <= _nota ? Icons.star : Icons.star_border, color: const Color(0xFFF9A825)),
                      onPressed: () => setState(() => _nota = i),
                    ),
                ],
              ),
              TextField(
                controller: _comentario,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Comentário (opcional)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((_nota, _comentario.text)),
                child: const Text('Salvar avaliação'),
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
              Text('Alerta de fila baixa', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Avisar quando a espera ficar em até ${_limite.round()} minutos.'),
              Slider(
                value: _limite,
                min: 5,
                max: 120,
                divisions: 23,
                label: '${_limite.round()} min',
                onChanged: (v) => setState(() => _limite = v),
              ),
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
