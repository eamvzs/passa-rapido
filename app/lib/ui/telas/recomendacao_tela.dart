import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/formatos.dart';
import '../../core/tema.dart';
import '../../data/repositorios.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';
import 'triagem_tela.dart';
import 'mapa_tela.dart' show abrirRota;

/// Recomenda a unidade mais rápida somando deslocamento e espera.
class RecomendacaoTela extends StatefulWidget {
  const RecomendacaoTela({super.key});

  @override
  State<RecomendacaoTela> createState() => _RecomendacaoTelaState();
}

class _RecomendacaoTelaState extends State<RecomendacaoTela> {
  int? _tipoId;
  Future<List<Recomendacao>>? _busca;
  LatLng? _pontoDaBusca;
  bool _buscaComLocalizacaoReal = false;
  bool _atualizacaoAgendada = false;

  Future<void> _buscar() {
    final localizacao = context.read<MapaControlador>().localizacaoParaBusca;
    final ponto = localizacao?.ponto;
    _pontoDaBusca = ponto;
    _buscaComLocalizacaoReal = localizacao?.real ?? false;
    final busca = context.read<UnidadeRepositorio>().recomendar(
          latitude: ponto?.latitude ?? AppConfig.latitudePadrao,
          longitude: ponto?.longitude ?? AppConfig.longitudePadrao,
          tipoUnidadeId: _tipoId,
        );
    setState(() => _busca = busca);
    return busca.then((_) {}, onError: (_) {});
  }

  void _abrir(int unidadeId) => abrirUnidade(context, unidadeId);

  @override
  Widget build(BuildContext context) {
    final mapa = context.watch<MapaControlador>();
    final tema = Theme.of(context);
    // A localização costuma chegar depois dos tipos: refaz a busca quando ela chega ou quando a pessoa
    // se afasta mais de 200 m do ponto usado antes (senão a recomendação ficaria presa ao centro da cidade).
    final atual = mapa.localizacaoParaBusca;
    if (_tipoId != null && atual != null && atual.real) {
      final mudou = !_buscaComLocalizacaoReal ||
          _pontoDaBusca == null ||
          const Distance().as(LengthUnit.Meter, _pontoDaBusca!, atual.ponto) > 200;
      if (mudou && !_atualizacaoAgendada) {
        _atualizacaoAgendada = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _atualizacaoAgendada = false;
          if (mounted) _buscar();
        });
      }
    }
    // Os tipos chegam depois da primeira construção; dispara a busca inicial quando chegarem.
    if (_tipoId == null && mapa.tipos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tipoId == null) {
          _tipoId = mapa.tipos.first.id;
          _buscar();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mais rápido agora')),
      body: RefreshIndicator(
        onRefresh: _buscar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
          children: [
            LarguraMaxima(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.health_and_safety_rounded, color: tema.colorScheme.primary),
                      title: const Text('Não sabe qual unidade procurar?'),
                      subtitle: const Text('Responda a perguntas rápidas e veja se é caso de UBS, UPA ou 192.'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const TriagemTela()),
                      ),
                    ),
                  ),
                  const SizedBox(height: Espaco.g),
                  Text('Do que você precisa?', style: tema.textTheme.titleMedium),
                  const SizedBox(height: Espaco.m),
                  _GradeDeTipos(
                    tipos: mapa.tipos,
                    selecionado: _tipoId,
                    aoEscolher: (id) {
                      _tipoId = id;
                      _buscar();
                    },
                  ),
                  if (mapa.pontoDeReferencia != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Espaco.m),
                      child: Row(
                        children: [
                          Icon(Icons.pin_drop_rounded, size: 18, color: tema.colorScheme.tertiary),
                          const SizedBox(width: Espaco.p),
                          Expanded(
                            child: Text(
                              'Buscando a partir do ponto que você escolheu no mapa.',
                              style: tema.textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => mapa.definirPontoDeReferencia(null),
                            child: const Text('Voltar à minha localização'),
                          ),
                        ],
                      ),
                    )
                  else if (!mapa.localizacaoReal)
                    Padding(
                      padding: const EdgeInsets.only(top: Espaco.m),
                      child: Row(
                        children: [
                          Icon(Icons.location_off_outlined, size: 18, color: tema.colorScheme.onSurfaceVariant),
                          const SizedBox(width: Espaco.p),
                          Expanded(
                            child: Text(
                              'Sem acesso à sua localização: distâncias calculadas a partir do centro de São Paulo.',
                              style: tema.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: Espaco.g),
                  FutureBuilder<List<Recomendacao>>(
                    future: _busca,
                    builder: (context, resultado) {
                      if (_busca == null || resultado.connectionState != ConnectionState.done) {
                        return const Card(
                          child: Padding(padding: EdgeInsets.all(Espaco.g), child: Esqueleto(linhas: 5)),
                        );
                      }
                      if (resultado.hasError) {
                        return EstadoDeErro(
                          mensagem: traduzirErro(resultado.error!).mensagem,
                          aoTentarDeNovo: _buscar,
                        );
                      }
                      final opcoes = resultado.data ?? const [];
                      if (opcoes.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(Espaco.g),
                            child: EstadoVazio(
                              icone: Icons.lock_clock_rounded,
                              titulo: 'Nenhuma unidade aberta agora',
                              texto: 'Não há unidades deste tipo abertas em um raio de 15 km. '
                                  'Abra uma unidade no mapa para ver o melhor horário.',
                            ),
                          ),
                        );
                      }
                      final comTempo = opcoes.first.tempoTotalMin != null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (comTempo)
                            _MelhorOpcao(
                              opcao: opcoes.first,
                              aoAbrir: () => _abrir(opcoes.first.unidadeId),
                              aoIr: () {
                                final unidade = mapa.porId(opcoes.first.unidadeId);
                                if (unidade != null) abrirRota(context, unidade);
                              },
                            ),
                          if (opcoes.length > (comTempo ? 1 : 0)) ...[
                            const SizedBox(height: Espaco.gg),
                            Text(comTempo ? 'Outras opções' : 'Unidades abertas', style: tema.textTheme.titleMedium),
                            const SizedBox(height: Espaco.p),
                            for (var i = comTempo ? 1 : 0; i < opcoes.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: Espaco.p),
                                child: _OutraOpcao(
                                  posicao: i + 1,
                                  opcao: opcoes[i],
                                  aoAbrir: () => _abrir(opcoes[i].unidadeId),
                                ),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeDeTipos extends StatelessWidget {
  const _GradeDeTipos({required this.tipos, required this.selecionado, required this.aoEscolher});

  final List<TipoUnidade> tipos;
  final int? selecionado;
  final ValueChanged<int> aoEscolher;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return LayoutBuilder(
      builder: (context, limites) {
        final largura = (limites.maxWidth - 2 * Espaco.p) / 3;
        return Wrap(
          spacing: Espaco.p,
          runSpacing: Espaco.p,
          children: [
            for (final tipo in tipos)
              SizedBox(
                width: largura,
                child: Semantics(
                  button: true,
                  selected: selecionado == tipo.id,
                  label: tipo.nome,
                  excludeSemantics: true,
                  child: Material(
                    color: selecionado == tipo.id ? tema.colorScheme.primary : tema.cardTheme.color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: selecionado == tipo.id ? tema.colorScheme.primary : tema.dividerColor,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => aoEscolher(tipo.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Espaco.m, horizontal: Espaco.pp),
                        child: Column(
                          children: [
                            Icon(
                              iconeDoTipo(tipo.nome),
                              color: selecionado == tipo.id ? tema.colorScheme.onPrimary : tema.colorScheme.primary,
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                tipo.nome,
                                style: tema.textTheme.labelLarge?.copyWith(
                                  color: selecionado == tipo.id ? tema.colorScheme.onPrimary : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

/// Destaque da unidade com o menor tempo total, com a divisão entre caminho e fila.
class _MelhorOpcao extends StatelessWidget {
  const _MelhorOpcao({required this.opcao, required this.aoAbrir, required this.aoIr});

  final Recomendacao opcao;
  final VoidCallback aoAbrir;
  final VoidCallback aoIr;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    const claro = Colors.white;
    final suave = claro.withValues(alpha: 0.82);
    final espera = opcao.esperaMin ?? 0;
    final total = (opcao.deslocamentoMin + espera).clamp(1, 1 << 30);

    return Container(
      padding: const EdgeInsets.all(Espaco.gg),
      decoration: BoxDecoration(
        gradient: IdentidadeVisual.de(context).gradiente,
        borderRadius: BorderRadius.circular(IdentidadeVisual.de(context).raioCartao),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: IdentidadeVisual.de(context).destaque, size: 20),
              const SizedBox(width: 4),
              Text('Melhor opção agora', style: tema.textTheme.labelLarge?.copyWith(color: suave)),
            ],
          ),
          const SizedBox(height: Espaco.p),
          Text(opcao.nome, style: tema.textTheme.titleLarge?.copyWith(color: claro)),
          const SizedBox(height: Espaco.m),
          Semantics(
            label: 'Tempo total estimado: ${formatarEspera(opcao.tempoTotalMin)}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatarEspera(opcao.tempoTotalMin),
                  style: tema.textTheme.displaySmall?.copyWith(color: claro, height: 1),
                ),
                const SizedBox(width: Espaco.p),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('no total', style: tema.textTheme.bodyMedium?.copyWith(color: suave)),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaco.g),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    Expanded(
                      flex: (opcao.deslocamentoMin * 100 ~/ total).clamp(4, 96),
                      child: ColoredBox(color: IdentidadeVisual.de(context).destaque2),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      flex: (espera * 100 ~/ total).clamp(4, 96),
                      child: ColoredBox(color: IdentidadeVisual.de(context).destaque),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Espaco.p),
          Row(
            children: [
              Expanded(
                child: _Parcela(
                  cor: IdentidadeVisual.de(context).destaque2,
                  icone: Icons.directions_walk_rounded,
                  valor: formatarEspera(opcao.deslocamentoMin),
                  rotulo: 'de caminho (${formatarDistancia(opcao.distanciaKm)})',
                ),
              ),
              Expanded(
                child: _Parcela(
                  cor: IdentidadeVisual.de(context).destaque,
                  icone: Icons.hourglass_top_rounded,
                  valor: formatarEspera(opcao.esperaMin),
                  rotulo: 'de fila',
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaco.g),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: claro,
                    foregroundColor: IdentidadeVisual.de(context).heroFim,
                    minimumSize: const Size(48, 50),
                  ),
                  onPressed: aoIr,
                  icon: const Icon(Icons.directions_rounded),
                  label: const Text('Ir agora'),
                ),
              ),
              const SizedBox(width: Espaco.p),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: claro,
                    side: BorderSide(color: suave),
                    minimumSize: const Size(48, 50),
                  ),
                  onPressed: aoAbrir,
                  child: const Text('Ver unidade'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Parcela extends StatelessWidget {
  const _Parcela({required this.cor, required this.icone, required this.valor, required this.rotulo});

  final Color cor;
  final IconData icone;
  final String valor;
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      children: [
        Icon(icone, size: 18, color: cor),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor, style: tema.textTheme.titleSmall?.copyWith(color: Colors.white)),
              Text(rotulo, style: tema.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.82))),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutraOpcao extends StatelessWidget {
  const _OutraOpcao({required this.posicao, required this.opcao, required this.aoAbrir});

  final int posicao;
  final Recomendacao opcao;
  final VoidCallback aoAbrir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoAbrir,
        child: Padding(
          padding: const EdgeInsets.all(Espaco.m),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tema.colorScheme.onSurface.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: Text('$posicaoº', style: tema.textTheme.labelLarge),
              ),
              const SizedBox(width: Espaco.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(opcao.nome, style: tema.textTheme.titleSmall),
                    Text(
                      opcao.tempoTotalMin == null
                          ? '${formatarDistancia(opcao.distanciaKm)} · sem informação de fila'
                          : '${formatarEspera(opcao.deslocamentoMin)} de caminho + ${formatarEspera(opcao.esperaMin)} de fila',
                      style: tema.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Espaco.p),
              if (opcao.tempoTotalMin != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatarEspera(opcao.tempoTotalMin),
                      style: tema.textTheme.titleMedium?.copyWith(
                        color: opcao.nivel.corSobreSuperficie(tema.brightness),
                      ),
                    ),
                    Text('no total', style: tema.textTheme.labelSmall),
                  ],
                )
              else
                Icon(Icons.chevron_right_rounded, color: tema.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
