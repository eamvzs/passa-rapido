import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/formatos.dart';
import '../../data/repositorios.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';
import 'unidade_detalhe_tela.dart';

/// Recomenda a unidade mais rápida somando deslocamento e espera.
class RecomendacaoTela extends StatefulWidget {
  const RecomendacaoTela({super.key});

  @override
  State<RecomendacaoTela> createState() => _RecomendacaoTelaState();
}

class _RecomendacaoTelaState extends State<RecomendacaoTela> {
  int? _tipoId;
  Future<List<Recomendacao>>? _busca;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tipos = context.read<MapaControlador>().tipos;
    if (_tipoId == null && tipos.isNotEmpty) {
      _tipoId = tipos.first.id;
      _buscar();
    }
  }

  void _buscar() {
    final ponto = context.read<MapaControlador>().localizacao?.ponto;
    setState(() {
      _busca = context.read<UnidadeRepositorio>().recomendar(
            latitude: ponto?.latitude ?? AppConfig.latitudePadrao,
            longitude: ponto?.longitude ?? AppConfig.longitudePadrao,
            tipoUnidadeId: _tipoId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mapa = context.watch<MapaControlador>();
    // Os tipos chegam depois da primeira construção; dispara a busca inicial quando chegarem.
    if (_tipoId == null && mapa.tipos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tipoId == null) {
          _tipoId = mapa.tipos.first.id;
          _buscar();
        }
      });
    }
    final localizacaoReal = mapa.localizacao?.real ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mais rápido agora'),
        actions: [IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _buscar)],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('Do que você precisa?', style: Theme.of(context).textTheme.titleMedium),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final tipo in mapa.tipos)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(iconeDoTipo(tipo.nome), size: 18),
                      label: Text(tipo.nome),
                      selected: _tipoId == tipo.id,
                      onSelected: (_) {
                        _tipoId = tipo.id;
                        _buscar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (!localizacaoReal)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Sem acesso à sua localização: distâncias calculadas a partir do centro de São Paulo.'),
            ),
          Expanded(
            child: FutureBuilder<List<Recomendacao>>(
              future: _busca,
              builder: (context, resultado) {
                if (resultado.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (resultado.hasError) {
                  return EstadoDeErro(
                    mensagem: traduzirErro(resultado.error!).mensagem,
                    aoTentarDeNovo: _buscar,
                  );
                }
                final opcoes = resultado.data ?? const [];
                if (opcoes.isEmpty) {
                  return const Center(child: Text('Nenhuma unidade deste tipo em um raio de 15 km.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: opcoes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _OpcaoCartao(
                    opcao: opcoes[i],
                    melhor: i == 0 && opcoes[i].tempoTotalMin != null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OpcaoCartao extends StatelessWidget {
  const _OpcaoCartao({required this.opcao, required this.melhor});

  final Recomendacao opcao;
  final bool melhor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      color: melhor ? tema.colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => UnidadeDetalheTela(unidadeId: opcao.unidadeId)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (melhor)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, size: 18, color: tema.colorScheme.primary),
                      Text('Melhor opção agora', style: tema.textTheme.labelLarge),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(child: Text(opcao.nome, style: tema.textTheme.titleMedium)),
                  SeloEspera(nivel: opcao.nivel, minutos: opcao.esperaMin),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                opcao.tempoTotalMin == null
                    ? 'A ${opcao.distanciaKm.toStringAsFixed(1).replaceAll('.', ',')} km · sem informação de fila'
                    : 'Tempo total estimado: ${formatarEspera(opcao.tempoTotalMin)}',
                style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (opcao.tempoTotalMin != null)
                Text(
                  '${formatarEspera(opcao.deslocamentoMin)} de deslocamento '
                  '(${opcao.distanciaKm.toStringAsFixed(1).replaceAll('.', ',')} km) '
                  '+ ${formatarEspera(opcao.esperaMin)} de fila',
                  style: tema.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
