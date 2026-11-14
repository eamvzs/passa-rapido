import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../core/nivel_espera.dart';
import '../../data/repositorios.dart';
import '../../models/colaboracao.dart';
import '../componentes/comuns.dart';
import 'unidade_detalhe_tela.dart';

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

  Future<void> _atualizar() async {
    final novo = _carregar();
    setState(() => _dados = novo);
    await novo.catchError((_) => (geral: _vazio, indicadores: <IndicadorUnidade>[], ranking: <PosicaoRanking>[]));
  }

  static const _vazio = PainelGeral(
    unidadesMonitoradas: 0,
    unidadesComDados: 0,
    registrosHoje: 0,
    esperaMediaMin: null,
    colaboradores7Dias: 0,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Painel'),
          actions: [IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _atualizar)],
        ),
        body: FutureBuilder<_DadosDoPainel>(
          future: _dados,
          builder: (context, resultado) {
            if (resultado.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (resultado.hasError) {
              return EstadoDeErro(
                mensagem: traduzirErro(resultado.error!).mensagem,
                aoTentarDeNovo: _atualizar,
              );
            }
            final dados = resultado.data!;
            return RefreshIndicator(
              onRefresh: _atualizar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _Resumo(geral: dados.geral),
                  const TituloDeSecao('Maiores esperas da semana'),
                  for (final indicador in dados.indicadores) _IndicadorItem(indicador: indicador),
                  const TituloDeSecao('Quem mais colabora'),
                  for (final posicao in dados.ranking) _RankingItem(posicao: posicao),
                ],
              ),
            );
          },
        ),
      );
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.geral});

  final PainelGeral geral;

  @override
  Widget build(BuildContext context) {
    final itens = [
      (Icons.timer, formatarEspera(geral.esperaMediaMin), 'Espera média agora'),
      (Icons.sensors, '${geral.unidadesComDados} de ${geral.unidadesMonitoradas}', 'Unidades com dados ao vivo'),
      (Icons.how_to_reg, '${geral.registrosHoje}', 'Registros hoje'),
      (Icons.groups, '${geral.colaboradores7Dias}', 'Colaboradores em 7 dias'),
    ];
    return LayoutBuilder(
      builder: (context, limites) {
        final largura = (limites.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in itens)
              SizedBox(
                width: largura,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.$1, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 8),
                        Text(item.$2, style: Theme.of(context).textTheme.headlineSmall),
                        Text(item.$3, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IndicadorItem extends StatelessWidget {
  const _IndicadorItem({required this.indicador});

  final IndicadorUnidade indicador;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(iconeDoTipo(indicador.tipo)),
        title: Text(indicador.nome),
        subtitle: Text(
          '${indicador.registros7Dias} registros'
          '${indicador.horaPico == null ? '' : ' · pico às ${indicador.horaPico}h'}',
        ),
        trailing: SeloEspera(
          nivel: NivelEspera.porMinutos(indicador.esperaMediaMin),
          minutos: indicador.esperaMediaMin,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => UnidadeDetalheTela(unidadeId: indicador.unidadeId)),
        ),
      );
}

class _RankingItem extends StatelessWidget {
  const _RankingItem({required this.posicao});

  final PosicaoRanking posicao;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(child: Text('${posicao.posicao}')),
        title: Text(posicao.nome),
        subtitle: Text(Perfil.rotulosNivel[posicao.nivel] ?? posicao.nivel),
        trailing: Text('${posicao.pontos} pts', style: Theme.of(context).textTheme.titleMedium),
      );
}
