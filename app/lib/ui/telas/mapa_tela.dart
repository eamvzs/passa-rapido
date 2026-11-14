import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/formatos.dart';
import '../../core/nivel_espera.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';
import 'unidade_detalhe_tela.dart';

/// Mapa vivo: unidades coloridas pela espera estimada, atualizadas em tempo real.
/// A mesma informação está disponível em lista, para quem usa leitor de tela.
class MapaTela extends StatefulWidget {
  const MapaTela({super.key});

  @override
  State<MapaTela> createState() => _MapaTelaState();
}

class _MapaTelaState extends State<MapaTela> {
  final _mapa = MapController();
  bool _emLista = false;

  @override
  void dispose() {
    _mapa.dispose();
    super.dispose();
  }

  void _abrirDetalhe(Unidade unidade) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => UnidadeDetalheTela(unidadeId: unidade.id)),
      );

  void _mostrarResumo(Unidade unidade) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ResumoUnidade(unidadeId: unidade.id, aoAbrir: _abrirDetalhe),
      );

  @override
  Widget build(BuildContext context) {
    final controlador = context.watch<MapaControlador>();
    final unidades = controlador.unidades;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passa Rápido'),
        actions: [
          IconButton(
            tooltip: _emLista ? 'Ver mapa' : 'Ver lista',
            icon: Icon(_emLista ? Icons.map : Icons.view_list),
            onPressed: () => setState(() => _emLista = !_emLista),
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: controlador.carregar,
          ),
        ],
      ),
      body: Column(
        children: [
          _FiltroDeTipos(controlador: controlador),
          Expanded(
            child: controlador.erro != null
                ? EstadoDeErro(mensagem: controlador.erro!, aoTentarDeNovo: controlador.carregar)
                : controlador.carregando && unidades.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _emLista
                        ? _Lista(unidades: unidades, aoTocar: _abrirDetalhe)
                        : _Mapa(
                            mapa: _mapa,
                            unidades: unidades,
                            localizacao: controlador.localizacao?.ponto,
                            localizacaoReal: controlador.localizacao?.real ?? false,
                            aoTocar: _mostrarResumo,
                          ),
          ),
          const FaixaFilaAtiva(),
        ],
      ),
    );
  }
}

class _FiltroDeTipos extends StatelessWidget {
  const _FiltroDeTipos({required this.controlador});

  final MapaControlador controlador;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('Todos'),
                selected: controlador.filtroTipoId == null,
                onSelected: (_) => controlador.filtrarPorTipo(null),
              ),
            ),
            for (final tipo in controlador.tipos)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(iconeDoTipo(tipo.nome), size: 18),
                  label: Text(tipo.nome),
                  selected: controlador.filtroTipoId == tipo.id,
                  onSelected: (_) => controlador.filtrarPorTipo(tipo.id),
                ),
              ),
          ],
        ),
      );
}

class _Mapa extends StatelessWidget {
  const _Mapa({
    required this.mapa,
    required this.unidades,
    required this.localizacao,
    required this.localizacaoReal,
    required this.aoTocar,
  });

  final MapController mapa;
  final List<Unidade> unidades;
  final LatLng? localizacao;
  final bool localizacaoReal;
  final ValueChanged<Unidade> aoTocar;

  @override
  Widget build(BuildContext context) {
    final centro = localizacao ?? const LatLng(AppConfig.latitudePadrao, AppConfig.longitudePadrao);
    // Desenha por último as filas mais altas, para ficarem por cima quando há sobreposição.
    final emOrdem = [...unidades]..sort((a, b) => _prioridade(a).compareTo(_prioridade(b)));

    return Stack(
      children: [
        FlutterMap(
          mapController: mapa,
          options: MapOptions(
            initialCenter: centro,
            initialZoom: 11.5,
            minZoom: 9,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'br.com.passarapido.passa_rapido',
              maxNativeZoom: 19,
            ),
            if (localizacao != null && localizacaoReal)
              MarkerLayer(
                markers: [
                  Marker(
                    point: localizacao!,
                    width: 22,
                    height: 22,
                    child: Semantics(
                      label: 'Sua localização',
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final unidade in emOrdem)
                  Marker(
                    key: ValueKey(unidade.id),
                    point: LatLng(unidade.latitude, unidade.longitude),
                    width: 76,
                    height: 40,
                    child: _Marcador(unidade: unidade, aoTocar: () => aoTocar(unidade)),
                  ),
              ],
            ),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
        const Positioned(top: 8, left: 8, right: 8, child: _Legenda()),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'centralizar',
            tooltip: 'Centralizar em mim',
            onPressed: () => mapa.move(centro, 13),
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  static int _prioridade(Unidade u) => u.abertaAgora ? u.nivel.index : -1;
}

/// Marcador com a espera em minutos. A cor muda sozinha quando chega atualização do banco.
class _Marcador extends StatelessWidget {
  const _Marcador({required this.unidade, required this.aoTocar});

  final Unidade unidade;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final fechada = !unidade.abertaAgora;
    final nivel = fechada ? NivelEspera.semDados : unidade.nivel;
    return Semantics(
      button: true,
      label: fechada
          ? '${unidade.nome}, fechada agora'
          : '${unidade.nome}, ${nivel.rotulo}, espera de ${formatarEspera(unidade.esperaMin)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: aoTocar,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            color: nivel.cor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconeDoTipo(unidade.tipo), size: 16, color: nivel.corDoTexto),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  fechada ? 'fech.' : formatarEsperaCurta(unidade.esperaMin),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(color: nivel.corDoTexto, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final nivel in const [
                  (NivelEspera.baixa, 'até 15 min'),
                  (NivelEspera.moderada, 'até 45'),
                  (NivelEspera.alta, 'até 90'),
                  (NivelEspera.critica, 'mais de 90'),
                  (NivelEspera.semDados, 'sem dados ou fechada'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: nivel.$1.cor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      Text(nivel.$2, style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
}

class _Lista extends StatelessWidget {
  const _Lista({required this.unidades, required this.aoTocar});

  final List<Unidade> unidades;
  final ValueChanged<Unidade> aoTocar;

  @override
  Widget build(BuildContext context) {
    if (unidades.isEmpty) {
      return const Center(child: Text('Nenhuma unidade deste tipo.'));
    }
    // Menor espera primeiro; unidades sem dados ficam no fim.
    int chave(Unidade u) => !u.abertaAgora ? 1 << 31 : (u.esperaMin ?? 1 << 30);
    final ordenadas = [...unidades]..sort((a, b) => chave(a).compareTo(chave(b)));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: ordenadas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => UnidadeCartao(unidade: ordenadas[i], aoTocar: () => aoTocar(ordenadas[i])),
    );
  }
}

class _ResumoUnidade extends StatelessWidget {
  const _ResumoUnidade({required this.unidadeId, required this.aoAbrir});

  final int unidadeId;
  final ValueChanged<Unidade> aoAbrir;

  @override
  Widget build(BuildContext context) {
    // Observa o controlador para o resumo aberto também refletir o tempo real.
    final unidade = context.watch<MapaControlador>().porId(unidadeId);
    if (unidade == null) return const SizedBox.shrink();
    final tema = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(unidade.nome, style: tema.textTheme.titleLarge)),
                SeloEspera(nivel: unidade.nivel, minutos: unidade.esperaMin, fechada: !unidade.abertaAgora),
              ],
            ),
            const SizedBox(height: 4),
            Text([
              unidade.tipo,
              if (unidade.bairro != null) unidade.bairro!,
              unidade.abertaAgora ? 'Aberta agora' : 'Fechada agora',
            ].join(' · ')),
            const SizedBox(height: 4),
            Text(
              switch (unidade.fonte) {
                'tempo_real' =>
                  '${unidade.pessoasAguardando} na fila pelo app · atualizado ${formatarHaQuantoTempo(unidade.atualizadoEm)}',
                'historico' => 'Estimativa pela média histórica deste horário',
                _ => 'Ninguém informou a fila ainda. Seja o primeiro.',
              },
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  aoAbrir(unidade);
                },
                child: const Text('Ver detalhes e informar a fila'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
