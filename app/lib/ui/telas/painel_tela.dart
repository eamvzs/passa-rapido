import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../core/insights.dart';
import 'gestao_tela.dart';
import '../../core/nivel_espera.dart';
import '../../core/tema.dart';
import '../../data/repositorios.dart';
import '../../models/colaboracao.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';

typedef _DadosDoPainel = ({PainelGeral geral, List<IndicadorUnidade> indicadores, List<PosicaoRanking> ranking});

/// Indicadores gerados pelas rotinas do banco: visão geral, unidades mais cheias e ranking.
class PainelTela extends StatefulWidget {
  const PainelTela({super.key});

  @override
  State<PainelTela> createState() => _PainelTelaState();
}

class _PainelTelaState extends State<PainelTela> {
  late Future<_DadosDoPainel> _dados = _carregar();

  Future<_DadosDoPainel> _carregar() async {
    final repositorio = context.read<UnidadeRepositorio>();
    final (geral, indicadores, ranking) = await (
      repositorio.painelGeral(),
      repositorio.indicadores(),
      repositorio.ranking(),
    ).wait;
    return (geral: geral, indicadores: indicadores, ranking: ranking);
  }

  Future<void> _atualizar() {
    final novo = _carregar();
    setState(() => _dados = novo);
    return novo.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final usuarioId = context.select<SessaoControlador, String?>((s) => s.usuarioId);
    return Scaffold(
      appBar: AppBar(title: const Text('Painel da cidade')),
      body: FutureBuilder<_DadosDoPainel>(
        future: _dados,
        builder: (context, resultado) {
          if (resultado.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(Espaco.g), child: Esqueleto(linhas: 8));
          }
          if (resultado.hasError) {
            return EstadoDeErro(
              mensagem: traduzirErro(resultado.error!).mensagem,
              aoTentarDeNovo: _atualizar,
            );
          }
          final dados = resultado.data!;
          final maiorEspera = dados.indicadores
              .map((i) => i.esperaMediaMin ?? 0)
              .fold<int>(1, (a, b) => a > b ? a : b);
          return RefreshIndicator(
            onRefresh: _atualizar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
              children: [
                LarguraMaxima(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroDoPainel(unidades: context.watch<MapaControlador>().todasAsUnidades),
                      const SizedBox(height: Espaco.m),
                      _Resumo(geral: dados.geral, unidades: context.watch<MapaControlador>().todasAsUnidades),
                      _InsightsAgora(unidades: context.watch<MapaControlador>().todasAsUnidades),
                      Secao(
                        icone: Icons.domain_rounded,
                        titulo: 'Para a gestão pública',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.table_chart_rounded),
                          title: const Text('Visão por bairro e tipo de unidade'),
                          subtitle: const Text('Onde a espera é maior, horário de pico e tabela para planilha'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GestaoTela())),
                        ),
                      ),
                      Secao(
                        icone: Icons.trending_up_rounded,
                        titulo: 'Maiores esperas da semana',
                        acao: dados.indicadores.isEmpty
                            ? null
                            : TextButton.icon(
                                onPressed: () => _copiarRelatorio(context, dados.indicadores),
                                icon: const Icon(Icons.content_copy_rounded),
                                label: const Text('Copiar CSV'),
                              ),
                        child: dados.indicadores.isEmpty
                            ? const EstadoVazio(icone: Icons.bar_chart_rounded, texto: 'Sem registros nos últimos 7 dias.')
                            : Column(
                                children: [
                                  for (final indicador in dados.indicadores)
                                    _IndicadorItem(indicador: indicador, maiorEspera: maiorEspera),
                                ],
                              ),
                      ),
                      Secao(
                        icone: Icons.emoji_events_rounded,
                        titulo: 'Quem mais colabora',
                        child: dados.ranking.isEmpty
                            ? const EstadoVazio(icone: Icons.groups_rounded, texto: 'Seja a primeira pessoa a colaborar.')
                            : Column(
                                children: [
                                  for (final posicao in dados.ranking)
                                    _RankingItem(posicao: posicao, souEu: posicao.usuarioId == usuarioId),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Copia o relatório da semana em CSV (separador ponto e vírgula, abre direto no Excel em português).
Future<void> _copiarRelatorio(BuildContext context, List<IndicadorUnidade> indicadores) async {
  final linhas = [
    'unidade;tipo;registros_7_dias;espera_media_min;hora_pico',
    for (final i in indicadores)
      [campoCsv(i.nome), campoCsv(i.tipo), i.registros7Dias, i.esperaMediaMin ?? '', i.horaPico ?? ''].join(';'),
  ];
  await Clipboard.setData(ClipboardData(text: linhas.join('\n')));
  if (context.mounted) mostrarMensagem(context, 'Relatório copiado. Cole em uma planilha.');
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.geral, required this.unidades});

  final PainelGeral geral;
  final List<Unidade> unidades;

  @override
  Widget build(BuildContext context) {
    // Só conta fila informada por cidadãos agora: a estimativa do modelo não entra nos totais.
    final informadas = unidades.where((u) => u.emTempoReal && u.abertaAgora && u.esperaMin != null).toList();
    final media = informadas.isEmpty
        ? null
        : (informadas.map((u) => u.esperaMin!).reduce((a, b) => a + b) / informadas.length).round();
    final itens = [
      (
        Icons.timer_rounded,
        const Color(0xFFE2680A),
        media == null ? '—' : formatarEspera(media),
        'Espera média nas filas informadas',
      ),
      (
        Icons.sensors_rounded,
        const Color(0xFF16803C),
        '${informadas.length} de ${unidades.length}',
        'Unidades com fila informada agora',
      ),
      (Icons.how_to_reg_rounded, Theme.of(context).colorScheme.primary, '${geral.registrosHoje}', 'Registros hoje'),
      (Icons.groups_rounded, const Color(0xFF7C3AED), '${geral.colaboradores7Dias}', 'Colaboradores em 7 dias'),
    ];
    return LayoutBuilder(
      builder: (context, limites) {
        final largura = (limites.maxWidth - Espaco.m) / 2;
        final tema = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        Wrap(
          spacing: Espaco.m,
          runSpacing: Espaco.m,
          children: [
            for (final (icone, cor, valor, rotulo) in itens)
              SizedBox(
                width: largura,
                child: Semantics(
                  label: '$rotulo: $valor',
                  excludeSemantics: true,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Espaco.g),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: cor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icone, color: cor, size: 22),
                          ),
                          const SizedBox(height: Espaco.m),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(valor, style: tema.textTheme.headlineSmall),
                          ),
                          Text(rotulo, style: tema.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
            if (informadas.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Espaco.m),
                child: Text(
                  'Ainda ninguém informou fila. Os tempos do mapa são estimativas do modelo e dão lugar '
                  'aos registros dos cidadãos conforme eles chegam.',
                  style: tema.textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Linha do ranking de esperas, com barra proporcional à maior espera da lista.
class _IndicadorItem extends StatelessWidget {
  const _IndicadorItem({required this.indicador, required this.maiorEspera});

  final IndicadorUnidade indicador;
  final int maiorEspera;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nivel = NivelEspera.porMinutos(indicador.esperaMediaMin);
    final fracao = ((indicador.esperaMediaMin ?? 0) / maiorEspera).clamp(0.04, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => abrirUnidade(context, indicador.unidadeId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Espaco.p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconeDoTipo(indicador.tipo), size: 18, color: tema.colorScheme.onSurfaceVariant),
                const SizedBox(width: Espaco.p),
                Expanded(child: Text(indicador.nome, style: tema.textTheme.titleSmall)),
                Text(
                  formatarEspera(indicador.esperaMediaMin),
                  style: tema.textTheme.titleSmall?.copyWith(color: nivel.corSobreSuperficie(tema.brightness)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fracao,
                  minHeight: 8,
                  color: nivel.cor,
                  backgroundColor: tema.colorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${indicador.registros7Dias} registros'
              '${indicador.horaPico == null ? '' : ' · pico às ${indicador.horaPico}h'}',
              style: tema.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingItem extends StatelessWidget {
  const _RankingItem({required this.posicao, required this.souEu});

  final PosicaoRanking posicao;
  final bool souEu;

  static const _medalhas = [Color(0xFFE5A50A), Color(0xFF98A2B3), Color(0xFFB7723A)];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final noPodio = posicao.posicao <= 3;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: Espaco.p, vertical: Espaco.p),
      decoration: BoxDecoration(
        color: souEu ? tema.colorScheme.primary.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: noPodio
                ? Icon(Icons.workspace_premium_rounded, color: _medalhas[posicao.posicao - 1], size: 28)
                : Text('${posicao.posicao}º', style: tema.textTheme.titleSmall, textAlign: TextAlign.center),
          ),
          const SizedBox(width: Espaco.p),
          CircleAvatar(
            radius: 18,
            backgroundColor: tema.colorScheme.primary.withValues(alpha: 0.12),
            foregroundColor: tema.colorScheme.primary,
            child: Text(iniciaisDe(posicao.nome), style: tema.textTheme.labelMedium),
          ),
          const SizedBox(width: Espaco.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(souEu ? '${posicao.nome} (você)' : posicao.nome, style: tema.textTheme.titleSmall),
                Text(Perfil.rotulosNivel[posicao.nivel] ?? posicao.nivel, style: tema.textTheme.bodySmall),
              ],
            ),
          ),
          Text('${posicao.pontos} pts', style: tema.textTheme.titleSmall),
        ],
      ),
    );
  }
}


/// Insights do momento: qual tipo de unidade está mais vazio agora e quantas estão abertas.
/// Usa as unidades já carregadas no mapa (sem nova consulta); deixa claro quando é só estimativa do modelo.
class _InsightsAgora extends StatelessWidget {
  const _InsightsAgora({required this.unidades});

  final List<Unidade> unidades;

  @override
  Widget build(BuildContext context) {
    if (unidades.isEmpty) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final resumos = resumirPorTipo(unidades);
    final comDado = resumos.where((r) => r.esperaMediaMin != null).toList();
    final maior = comDado.isEmpty ? 1 : comDado.map((r) => r.esperaMediaMin!).reduce((a, b) => a > b ? a : b);
    final abertas = unidades.where((u) => u.abertaAgora).length;
    final melhor = comDado.isEmpty ? null : comDado.first;

    return Secao(
      icone: Icons.insights_rounded,
      titulo: 'Insights agora',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (melhor != null)
            Text(
              'Neste horário, ${melhor.tipo} tem a menor espera média: ~${melhor.esperaMediaMin} min'
              '${melhor.somenteEstimativa ? ' (estimativa do modelo)' : ''}.',
              style: tema.textTheme.titleSmall,
            )
          else
            Text('Neste horário a maioria das unidades está fechada.', style: tema.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            '$abertas de ${unidades.length} unidades abertas agora (${(abertas * 100 / unidades.length).round()}%).',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: Espaco.m),
          for (final r in resumos)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaco.m),
              child: Semantics(
                label: '${r.tipo}: ${r.abertas} de ${r.total} abertas, '
                    '${r.esperaMediaMin == null ? 'sem dado de espera' : 'espera média de ${r.esperaMediaMin} minutos'}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Icon(iconeDoTipo(r.tipo), size: 20, color: tema.colorScheme.primary),
                    const SizedBox(width: Espaco.p),
                    SizedBox(
                      width: 124,
                      child: Text(r.tipo, style: tema.textTheme.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: r.esperaMediaMin == null ? 0 : (r.esperaMediaMin! / maior).clamp(0.04, 1.0),
                          backgroundColor: tema.colorScheme.onSurface.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(NivelEspera.porMinutos(r.esperaMediaMin).cor),
                        ),
                      ),
                    ),
                    const SizedBox(width: Espaco.p),
                    SizedBox(
                      width: 64,
                      child: Text(
                        r.esperaMediaMin == null ? '—' : '~${r.esperaMediaMin} min',
                        textAlign: TextAlign.right,
                        style: tema.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            'Abertas agora: ${resumos.map((r) => '${r.tipo} ${r.abertas}/${r.total}').join(' · ')}.',
            style: tema.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}


/// Destaque do topo do Painel: o tipo de unidade mais rápido neste horário e quantas estão abertas.
class _HeroDoPainel extends StatelessWidget {
  const _HeroDoPainel({required this.unidades});

  final List<Unidade> unidades;

  @override
  Widget build(BuildContext context) {
    if (unidades.isEmpty) return const SizedBox.shrink();
    final id = IdentidadeVisual.de(context);
    final tema = Theme.of(context);
    final resumos = resumirPorTipo(unidades).where((r) => r.esperaMediaMin != null).toList();
    final melhor = resumos.firstOrNull;
    final abertas = unidades.where((u) => u.abertaAgora).length;
    final branco = Colors.white;
    return Semantics(
      container: true,
      label: melhor == null
          ? 'Neste horário a maioria das unidades está fechada. $abertas de ${unidades.length} abertas.'
          : 'Neste horário, ${melhor.tipo} é o tipo mais rápido, com espera média de ${melhor.esperaMediaMin} minutos'
              '${melhor.somenteEstimativa ? ', estimativa do modelo' : ''}. $abertas de ${unidades.length} unidades abertas.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Espaco.gg),
        decoration: BoxDecoration(gradient: id.gradiente, borderRadius: BorderRadius.circular(id.raioCartao)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, color: id.destaque, size: 20),
                const SizedBox(width: 6),
                Text('Neste horário', style: tema.textTheme.labelLarge?.copyWith(color: branco.withValues(alpha: 0.85))),
              ],
            ),
            const SizedBox(height: Espaco.p),
            Text(
              melhor == null ? 'A maioria está fechada' : '${melhor.tipo} é o mais rápido',
              style: tema.textTheme.headlineSmall?.copyWith(color: branco),
            ),
            const SizedBox(height: 2),
            Text(
              melhor == null
                  ? 'Veja o melhor horário na ficha de cada unidade.'
                  : 'Espera média de ~${melhor.esperaMediaMin} min${melhor.somenteEstimativa ? ' (estimativa do modelo)' : ''}',
              style: tema.textTheme.bodyMedium?.copyWith(color: branco.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: Espaco.m),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: unidades.isEmpty ? 0 : abertas / unidades.length,
                backgroundColor: branco.withValues(alpha: 0.22),
                valueColor: AlwaysStoppedAnimation(id.destaque),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$abertas de ${unidades.length} unidades abertas agora',
              style: tema.textTheme.bodySmall?.copyWith(color: branco.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}
