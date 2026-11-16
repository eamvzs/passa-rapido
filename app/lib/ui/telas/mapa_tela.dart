import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../core/formatos.dart';
import '../../core/nivel_espera.dart';
import '../../core/tema.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';

enum _Ordem { proximidade, espera }

/// Tela inicial: mapa vivo em tela cheia, com busca, filtros e a lista de unidades em uma folha deslizante.
/// A lista traz a mesma informação do mapa, para quem usa leitor de tela.
class MapaTela extends StatefulWidget {
  const MapaTela({super.key});

  @override
  State<MapaTela> createState() => _MapaTelaState();
}

class _MapaTelaState extends State<MapaTela> with SingleTickerProviderStateMixin {
  final _mapa = MapController();
  final _folha = DraggableScrollableController();
  final _rolagemDoPainel = ScrollController();
  late final AnimationController _camera = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  VoidCallback? _ouvinteDaCamera;

  /// Unidade realçada no mapa: a do cartão sob o mouse ou, se não houver, a selecionada (tela larga).
  final _destaque = ValueNotifier<int?>(null);
  Unidade? _selecionada;
  final _campoDeBusca = TextEditingController();
  double _zoom = 11.5;
  LatLngBounds? _vista;
  _Ordem? _ordemEscolhida;
  bool _centralizouNoUsuario = false;

  @override
  void dispose() {
    _camera.dispose();
    _destaque.dispose();
    _rolagemDoPainel.dispose();
    _mapa.dispose();
    _folha.dispose();
    _campoDeBusca.dispose();
    super.dispose();
  }

  void _abrirDetalhe(Unidade unidade) => abrirUnidade(context, unidade.id);

  /// Move a câmera do mapa com animação suave (sem animação se o sistema pede "reduzir movimento").
  void _voarPara(LatLng destino, double zoom) {
    if (!mounted) return;
    if (_ouvinteDaCamera != null) _camera.removeListener(_ouvinteDaCamera!);
    if (MediaQuery.disableAnimationsOf(context)) {
      try {
        _mapa.move(destino, zoom);
      } catch (_) {
        // Sem mapa na tela (modo econômico).
      }
      return;
    }
    final MapCamera atual;
    try {
      atual = _mapa.camera;
    } catch (_) {
      try {
        _mapa.move(destino, zoom);
      } catch (_) {
        // Sem mapa na tela (modo econômico): não há para onde mover.
      }
      return;
    }
    final origem = atual.center;
    final zoomInicial = atual.zoom;
    final curva = CurvedAnimation(parent: _camera, curve: Curves.easeInOutCubic);
    _ouvinteDaCamera = () {
      final t = curva.value;
      _mapa.move(
        LatLng(
          origem.latitude + (destino.latitude - origem.latitude) * t,
          origem.longitude + (destino.longitude - origem.longitude) * t,
        ),
        zoomInicial + (zoom - zoomInicial) * t,
      );
    };
    _camera.addListener(_ouvinteDaCamera!);
    _camera.forward(from: 0);
  }

  /// Tela larga: seleciona a unidade, voa até ela e mostra a ficha rápida sobre o mapa.
  void _selecionar(Unidade unidade) {
    setState(() => _selecionada = unidade);
    _destaque.value = unidade.id;
    _voarPara(LatLng(unidade.latitude, unidade.longitude), math.max(_zoom, 15.5));
  }

  void _limparSelecao() {
    setState(() => _selecionada = null);
    _destaque.value = null;
  }

  /// Toque na alça: abre a lista até quase a tela toda ou volta ao tamanho normal.
  void _alternarFolha() {
    if (!_folha.isAttached) return;
    final alto = MediaQuery.sizeOf(context).height >= 520;
    final normal = alto ? 0.36 : 0.55;
    _folha.animateTo(
      _folha.size > 0.6 ? normal : 0.9,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Ao buscar, enquadra no mapa as unidades encontradas (com folga para a folha de baixo).
  void _ajustarMapaAosResultados() {
    final controlador = context.read<MapaControlador>();
    if (controlador.busca.trim().isEmpty) return;
    final lista = controlador.unidades;
    if (lista.isEmpty || lista.length > 300) return;
    final pontos = [for (final u in lista) LatLng(u.latitude, u.longitude)];
    if (pontos.length == 1) {
      _voarPara(pontos.first, 15);
      return;
    }
    final larga = MediaQuery.sizeOf(context).width >= 940;
    final altura = MediaQuery.sizeOf(context).height;
    try {
      final alvo = CameraFit.coordinates(
        coordinates: pontos,
        padding: larga ? const EdgeInsets.fromLTRB(60, 60, 60, 60) : EdgeInsets.fromLTRB(40, 190, 40, altura * 0.42),
        maxZoom: 16,
      ).fit(_mapa.camera);
      _voarPara(alvo.center, alvo.zoom);
    } catch (_) {
      // Mapa ainda não montado: ignora o enquadramento.
    }
  }

  void _mostrarResumo(Unidade unidade) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ResumoUnidade(unidadeId: unidade.id, aoAbrir: _abrirDetalhe),
      );

  void _mostrarLegenda() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _Legenda(),
      );

  /// As melhores opções da região visível: abertas, com menor espera (empate: mais perto do centro da tela).
  /// Só no zoom afastado, onde mostrar todos os marcadores com etiqueta deixaria o mapa ilegível.
  ///
  /// [topo] e [base] são frações da altura da tela que ficam cobertas (busca e filtros em cima, folha da lista
  /// embaixo): uma melhor opção escondida debaixo delas não ajudaria ninguém.
  Set<int> _melhoresNaVista(List<Unidade> unidades, {required double topo, required double base}) {
    if (_zoom >= 14) return const {};
    final vista = _vista;
    bool naAreaLivre(Unidade u) {
      if (vista == null) return true;
      final altura = vista.north - vista.south;
      final largura = vista.east - vista.west;
      return u.latitude <= vista.north - altura * topo &&
          u.latitude >= vista.south + altura * base &&
          u.longitude >= vista.west + largura * 0.06 &&
          u.longitude <= vista.east - largura * 0.06;
    }

    final candidatas = unidades.where((u) => u.abertaAgora && u.esperaMin != null && naAreaLivre(u)).toList();
    final centro = vista?.center;
    double distancia(Unidade u) => centro == null
        ? 0
        : math.pow(u.latitude - centro.latitude, 2).toDouble() + math.pow(u.longitude - centro.longitude, 2).toDouble();
    candidatas.sort((a, b) {
      final porEspera = a.esperaMin!.compareTo(b.esperaMin!);
      return porEspera != 0 ? porEspera : distancia(a).compareTo(distancia(b));
    });
    return {for (final u in candidatas.take(6)) u.id};
  }

  @override
  Widget build(BuildContext context) {
    final controlador = context.watch<MapaControlador>();
    final tema = Theme.of(context);
    final unidades = controlador.unidades;
    final modoLeve = context.select<PreferenciasControlador, bool>((p) => p.modoLeve);
    final ponto = controlador.localizacao?.ponto;
    final centro = ponto ?? const LatLng(AppConfig.latitudePadrao, AppConfig.longitudePadrao);
    final referencia = controlador.pontoDeReferencia;
    final ordem = (controlador.localizacaoParaBusca?.real ?? false)
        ? (_ordemEscolhida ?? _Ordem.proximidade)
        : _Ordem.espera;

    // Quando a localização real chega, leva o mapa até o usuário uma única vez.
    if (controlador.localizacaoReal && !_centralizouNoUsuario && !modoLeve) {
      _centralizouNoUsuario = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _voarPara(centro, 13);
      });
    }

    // Zoom afastado: um ponto colorido por unidade e etiquetas só nas melhores opções da vista.
    // Zoom próximo (14 ou mais): todas as unidades viram etiqueta com o tempo.
    final larguraDaTela = MediaQuery.sizeOf(context).width;
    final telaLarga = larguraDaTela >= 940; // painel lateral: a folha de baixo não existe
    final destaques = _melhoresNaVista(unidades, topo: telaLarga ? 0.06 : 0.2, base: telaLarga ? 0.06 : 0.42);
    final comEtiqueta = [
      for (final u in unidades)
        if (_zoom >= 14 || destaques.contains(u.id) || u.id == _selecionada?.id) u,
    ]..sort((a, b) => _prioridade(a).compareTo(_prioridade(b)));
    final soPontos = _zoom >= 14
        ? const <Unidade>[]
        : ([
            for (final u in unidades)
              if (!destaques.contains(u.id) && u.id != _selecionada?.id) u,
          ]..sort((a, b) => _prioridade(a).compareTo(_prioridade(b))));

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, limites) {
          // Tela larga (computador, tablet deitado): painel lateral com a lista e mapa ao lado.
          final larga = limites.maxWidth >= 860;
          const larguraDoPainel = 420.0;
          final recuo = larga ? larguraDoPainel : 0.0;

          void aoTocarNaUnidade(Unidade u) => larga ? _selecionar(u) : _mostrarResumo(u);

          final barraDeBusca = _BarraDeBusca(
            campo: _campoDeBusca,
            aoMudar: (texto) {
              controlador.buscar(texto);
              _ajustarMapaAosResultados();
            },
            aoAtualizar: controlador.carregar,
            servicoAtivo: controlador.filtroServico != null,
            aoFiltrarServico: controlador.servicos.isEmpty ? null : () => _escolherServico(context, controlador),
          );

          Widget lista(ScrollController rolagem, {required bool painel}) => _FolhaDeUnidades(
                rolagem: rolagem,
                controlador: controlador,
                unidades: unidades,
                ordem: ordem,
                painel: painel,
                aoTrocarOrdem: (o) => setState(() => _ordemEscolhida = o),
                aoAlternarFolha: _alternarFolha,
                aoDestacar: (id) => _destaque.value = id ?? _selecionada?.id,
                aoTocar: larga ? _selecionar : _abrirDetalhe,
                aoLimparBusca: () {
                  _campoDeBusca.clear();
                  controlador
                    ..buscar('')
                    ..filtrarPorTipo(null)
                    ..filtrarPorServico(null)
                    ..definirSomenteAbertas(false);
                },
              );

          // Modo econômico: só a lista por distância, sem baixar o mapa.
          if (modoLeve) {
            return SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.m, Espaco.m, Espaco.p),
                    child: barraDeBusca,
                  ),
                  _FiltroDeTipos(controlador: controlador, quebrar: larga),
                  _AvisoDoModoLeve(
                    aoMostrarMapa: () => context.read<PreferenciasControlador>().definirModoLeve(false),
                  ),
                  Expanded(child: lista(_rolagemDoPainel, painel: true)),
                ],
              ),
            );
          }

          final botoesDoMapa = Positioned(
            right: Espaco.m,
            top: larga ? Espaco.m : MediaQuery.paddingOf(context).top + 168,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'centralizar',
                  tooltip: 'Centralizar em mim',
                  onPressed: () => _voarPara(centro, 13),
                  child: const Icon(Icons.my_location_rounded),
                ),
                const SizedBox(height: Espaco.p),
                FloatingActionButton.small(
                  heroTag: 'partida',
                  tooltip: referencia == null
                      ? 'Buscar a partir de outro ponto'
                      : 'Voltar a buscar a partir da minha localização',
                  onPressed: () {
                    if (referencia != null) {
                      controlador.definirPontoDeReferencia(null);
                    } else {
                      mostrarMensagem(
                        context,
                        'Para buscar a partir de outro lugar, segure o dedo (ou o clique) em um ponto do mapa.',
                      );
                    }
                  },
                  child: Icon(referencia == null ? Icons.pin_drop_outlined : Icons.pin_drop_rounded),
                ),
                const SizedBox(height: Espaco.p),
                FloatingActionButton.small(
                  heroTag: 'legenda',
                  tooltip: 'Legenda das cores',
                  onPressed: _mostrarLegenda,
                  child: const Icon(Icons.palette_outlined),
                ),
              ],
            ),
          );

          return Stack(
            children: [
              Positioned.fill(
                left: recuo,
                child: FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: 11.5,
                    minZoom: 9,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onMapReady: () => setState(() => _vista = _mapa.camera.visibleBounds),
                    onPositionChanged: (camera, _) {
                      final zoom = (camera.zoom * 2).round() / 2;
                      final nova = camera.visibleBounds;
                      final antiga = _vista;
                      // Reavalia as melhores opções só quando o zoom muda ou a tela andou mais de 12%.
                      final andou = antiga == null ||
                          (nova.center.latitude - antiga.center.latitude).abs() > (nova.north - nova.south) * 0.12 ||
                          (nova.center.longitude - antiga.center.longitude).abs() > (nova.east - nova.west) * 0.12;
                      if (zoom != _zoom || andou) {
                        setState(() {
                          _zoom = zoom;
                          _vista = nova;
                        });
                      }
                    },
                    onTap: (_, _) {
                      if (_selecionada != null) _limparSelecao();
                    },
                    onLongPress: (_, escolhido) {
                      controlador.definirPontoDeReferencia(escolhido);
                      mostrarMensagem(
                        context,
                        'Buscando a partir do ponto escolhido. Use o botão de alfinete para voltar à sua localização.',
                      );
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: AppConfig.tileUrl,
                      userAgentPackageName: 'br.com.passarapido.passa_rapido',
                      maxNativeZoom: 19,
                      tileBuilder: tema.brightness == Brightness.dark ? darkModeTileBuilder : null,
                    ),
                    if (ponto != null && controlador.localizacaoReal)
                      MarkerLayer(
                        markers: [
                          Marker(point: ponto, width: 26, height: 26, child: const _PontoDoUsuario()),
                        ],
                      ),
                    if (referencia != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: referencia,
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: Icon(Icons.location_on_rounded, size: 44, color: tema.colorScheme.tertiary),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final u in soPontos)
                          Marker(
                            key: ValueKey('ponto-${u.id}'),
                            point: LatLng(u.latitude, u.longitude),
                            width: 40,
                            height: 40,
                            child: _PontoDaUnidade(
                              unidade: u,
                              destaque: _destaque,
                              aoTocar: () => aoTocarNaUnidade(u),
                            ),
                          ),
                        for (final u in comEtiqueta)
                          Marker(
                            key: ValueKey(u.id),
                            point: LatLng(u.latitude, u.longitude),
                            width: 84,
                            height: 40,
                            child: _Marcador(
                              unidade: u,
                              destaque: _destaque,
                              aoTocar: () => aoTocarNaUnidade(u),
                            ),
                          ),
                      ],
                    ),
                    Align(
                      alignment: larga ? Alignment.bottomRight : Alignment.topRight,
                      child: SafeArea(
                        child: Padding(
                          padding: EdgeInsets.only(top: larga ? 0 : 124, right: 4),
                          child: const SimpleAttributionWidget(source: Text('OpenStreetMap')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!larga) ...[
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.m, Espaco.m, Espaco.p),
                        child: barraDeBusca,
                      ),
                      _FiltroDeTipos(controlador: controlador),
                    ],
                  ),
                ),
                botoesDoMapa,
                DraggableScrollableSheet(
                  controller: _folha,
                  initialChildSize: MediaQuery.sizeOf(context).height < 520 ? 0.55 : 0.36,
                  minChildSize: 0.13,
                  maxChildSize: 0.9,
                  snap: true,
                  snapSizes: [MediaQuery.sizeOf(context).height < 520 ? 0.55 : 0.36],
                  builder: (context, rolagem) => lista(rolagem, painel: false),
                ),
              ] else ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: larguraDoPainel,
                  child: Material(
                    color: tema.cardTheme.color,
                    elevation: 10,
                    shadowColor: Colors.black,
                    child: SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.m, Espaco.m, Espaco.p),
                            child: barraDeBusca,
                          ),
                          _FiltroDeTipos(controlador: controlador, quebrar: true),
                          Expanded(child: lista(_rolagemDoPainel, painel: true)),
                        ],
                      ),
                    ),
                  ),
                ),
                botoesDoMapa,
                if (_selecionada != null)
                  Positioned(
                    left: larguraDoPainel + Espaco.m,
                    bottom: Espaco.m,
                    width: 440,
                    child: _FichaFlutuante(
                      key: ValueKey(_selecionada!.id),
                      unidadeId: _selecionada!.id,
                      aoAbrir: _abrirDetalhe,
                      aoFechar: _limparSelecao,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Filas mais altas são desenhadas por último, para ficarem por cima.
  static int _prioridade(Unidade u) => (u.abertaAgora && u.esperaMin != null) ? u.nivel.index : -1;
}

class _BarraDeBusca extends StatelessWidget {
  const _BarraDeBusca({
    required this.campo,
    required this.aoMudar,
    required this.aoAtualizar,
    required this.servicoAtivo,
    required this.aoFiltrarServico,
  });

  final TextEditingController campo;
  final ValueChanged<String> aoMudar;
  final VoidCallback aoAtualizar;
  final bool servicoAtivo;
  final VoidCallback? aoFiltrarServico;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      elevation: 4,
      shadowColor: Colors.black38,
      color: tema.cardTheme.color,
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: Espaco.p),
            const LogoPassaRapido(tamanho: 40),
            const SizedBox(width: Espaco.pp),
            Expanded(
              child: TextField(
                controller: campo,
                onChanged: aoMudar,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Buscar unidade ou bairro',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: Espaco.p),
                ),
              ),
            ),
            if (aoFiltrarServico != null)
              IconButton(
                tooltip: 'Filtrar por serviço',
                icon: Badge(
                  isLabelVisible: servicoAtivo,
                  smallSize: 9,
                  child: const Icon(Icons.tune_rounded),
                ),
                onPressed: aoFiltrarServico,
              ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: campo,
              builder: (_, valor, _) => valor.text.isEmpty
                  ? IconButton(
                      tooltip: 'Atualizar',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: aoAtualizar,
                    )
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        campo.clear();
                        aoMudar('');
                      },
                    ),
            ),
            const SizedBox(width: Espaco.pp),
          ],
        ),
      ),
    );
  }
}

class _FiltroDeTipos extends StatelessWidget {
  const _FiltroDeTipos({required this.controlador, this.quebrar = false});

  final MapaControlador controlador;

  /// Painel lateral: os filtros quebram em linhas, para todos ficarem visíveis sem rolar para o lado.
  final bool quebrar;

  @override
  Widget build(BuildContext context) {
    final todas = controlador.todasAsUnidades;
    final abertas = todas.where((u) => u.abertaAgora).length;
    int porTipo(int id) => todas.where((u) => u.tipoUnidadeId == id).length;
    final chips = <Widget>[
            _Filtro(
              rotulo: todas.isEmpty ? 'Todos' : 'Todos · ${todas.length}',
              icone: Icons.apps_rounded,
              selecionado: controlador.filtroTipoId == null && controlador.filtroServico == null,
              aoTocar: () => controlador
                ..filtrarPorTipo(null)
                ..filtrarPorServico(null)
                ..definirSomenteAbertas(false),
            ),
            if (controlador.filtroServico != null)
              _Filtro(
                rotulo: 'Serviço: ${controlador.filtroServico!.nome}',
                icone: Icons.close_rounded,
                selecionado: true,
                aoTocar: () => controlador.filtrarPorServico(null),
              ),
            _Filtro(
              rotulo: todas.isEmpty ? 'Abertas agora' : 'Abertas agora · $abertas',
              icone: Icons.schedule_rounded,
              selecionado: controlador.somenteAbertas,
              aoTocar: controlador.alternarSomenteAbertas,
            ),
            for (final tipo in controlador.tipos)
              _Filtro(
                rotulo: todas.isEmpty ? tipo.nome : '${tipo.nome} · ${porTipo(tipo.id)}',
                icone: iconeDoTipo(tipo.nome),
                selecionado: controlador.filtroTipoId == tipo.id,
                aoTocar: () => controlador.filtrarPorTipo(tipo.id),
              ),
    ];
    if (quebrar) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espaco.m),
        child: Align(alignment: Alignment.centerLeft, child: Wrap(children: chips)),
      );
    }
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Espaco.m),
        children: chips,
      ),
    );
  }
}

/// Lista de serviços para filtrar as unidades que o oferecem (por exemplo, "Pediatria" ou "CNH").
Future<void> _escolherServico(BuildContext context, MapaControlador controlador) async {
  final escolha = await showModalBottomSheet<Servico?>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Espaco.m, 0, Espaco.m, Espaco.g),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espaco.p, 0, Espaco.p, Espaco.p),
              child: Text('Do que você precisa?', style: Theme.of(sheetContext).textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: const Text('Qualquer serviço'),
              selected: controlador.filtroServico == null,
              onTap: () => Navigator.of(sheetContext).pop(null),
            ),
            for (final servico in controlador.servicos)
              ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: Text(servico.nome),
                subtitle: servico.descricao == null ? null : Text(servico.descricao!),
                selected: controlador.filtroServico?.id == servico.id,
                onTap: () => Navigator.of(sheetContext).pop(servico),
              ),
          ],
        ),
      ),
    ),
  );
  // Fechar a folha sem escolher devolve nulo, igual a "Qualquer serviço"; só reage se mudou.
  if (escolha?.id != controlador.filtroServico?.id) await controlador.filtrarPorServico(escolha);
}

class _Filtro extends StatelessWidget {
  const _Filtro({required this.rotulo, required this.icone, required this.selecionado, required this.aoTocar});

  final String rotulo;
  final IconData icone;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final frente = selecionado ? tema.colorScheme.onPrimary : tema.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: Espaco.p, bottom: 6),
      child: Semantics(
        button: true,
        selected: selecionado,
        label: 'Filtrar por $rotulo',
        excludeSemantics: true,
        child: Material(
          elevation: 2,
          shadowColor: Colors.black26,
          color: selecionado ? tema.colorScheme.primary : tema.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: aoTocar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 38),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icone, size: 18, color: frente),
                    const SizedBox(width: 6),
                    Text(rotulo, style: tema.textTheme.labelLarge?.copyWith(color: frente)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PontoDoUsuario extends StatelessWidget {
  const _PontoDoUsuario();

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Sua localização',
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
          ),
        ),
      );
}

/// Marcador de uma unidade. Com dados ao vivo, mostra a espera em destaque;
/// fechada ou sem dados, vira um ponto discreto para não poluir o mapa.
class _Marcador extends StatelessWidget {
  const _Marcador({required this.unidade, required this.aoTocar, this.destaque});

  final Unidade unidade;
  final VoidCallback aoTocar;

  /// Id da unidade realçada (cartão sob o mouse ou selecionada); o marcador correspondente cresce.
  final ValueListenable<int?>? destaque;

  @override
  Widget build(BuildContext context) {
    final fechada = !unidade.abertaAgora;
    final comDados = !fechada && unidade.esperaMin != null;
    final nivel = comDados ? unidade.nivel : NivelEspera.semDados;

    final estimada = comDados && unidade.estimada;
    final Widget conteudo;
    if (estimada) {
      // Estimativa do modelo: marcador vazado (contorno na cor do nível) com "~", para não parecer fila informada.
      final corDoNivel = nivel.corSobreSuperficie(Brightness.light);
      conteudo = Container(
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: nivel.cor, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconeDoTipo(unidade.tipo), size: 15, color: corDoNivel),
            const SizedBox(width: 4),
            Text(
              '~${formatarEsperaCurta(unidade.esperaMin)}',
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: TextStyle(color: corDoNivel, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
          ],
        ),
      );
    } else if (comDados) {
      conteudo = AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        height: 34,
        decoration: BoxDecoration(
          color: nivel.cor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5, offset: Offset(0, 2))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconeDoTipo(unidade.tipo), size: 15, color: nivel.corDoTexto),
            const SizedBox(width: 4),
            Text(
              formatarEsperaCurta(unidade.esperaMin),
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: TextStyle(color: nivel.corDoTexto, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ],
        ),
      );
    } else {
      conteudo = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF98A2B3), width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Icon(
          fechada ? Icons.lock_clock_rounded : iconeDoTipo(unidade.tipo),
          size: 15,
          color: const Color(0xFF667085),
        ),
      );
    }

    // container + onTap: cada marcador vira um botão próprio para o leitor de tela.
    return Semantics(
      container: true,
      button: true,
      onTap: aoTocar,
      label: fechada
          ? '${unidade.nome}, fechada agora'
          : estimada
              ? '${unidade.nome}, estimativa: ${nivel.rotulo.toLowerCase()}, espera típica de ${formatarEspera(unidade.esperaMin)}'
              : '${unidade.nome}, ${nivel.rotulo}, espera de ${formatarEspera(unidade.esperaMin)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: aoTocar,
        child: Center(
          child: destaque == null
              ? conteudo
              : ValueListenableBuilder<int?>(
                  valueListenable: destaque!,
                  child: conteudo,
                  builder: (context, id, filho) => AnimatedScale(
                    scale: id == unidade.id ? 1.35 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: filho,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Ponto colorido de uma unidade no zoom afastado: a cor é o nível da espera (estimada ou informada);
/// cinza é fechada ou sem dado. Não carrega número: o tempo aparece nas etiquetas das melhores opções.
class _PontoDaUnidade extends StatelessWidget {
  const _PontoDaUnidade({required this.unidade, required this.aoTocar, this.destaque});

  final Unidade unidade;
  final VoidCallback aoTocar;
  final ValueListenable<int?>? destaque;

  @override
  Widget build(BuildContext context) {
    final fechada = !unidade.abertaAgora;
    final comDados = !fechada && unidade.esperaMin != null;
    final nivel = comDados ? unidade.nivel : NivelEspera.semDados;
    final ponto = Container(
      width: comDados ? 17 : 13,
      height: comDados ? 17 : 13,
      decoration: BoxDecoration(
        color: comDados ? nivel.cor : const Color(0xFFB4BCC8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: comDados ? 2.5 : 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1))],
      ),
    );
    return Semantics(
      container: true,
      button: true,
      onTap: aoTocar,
      label: fechada
          ? '${unidade.nome}, fechada agora'
          : unidade.estimada
              ? '${unidade.nome}, estimativa: ${nivel.rotulo.toLowerCase()}, espera típica de ${formatarEspera(unidade.esperaMin)}'
              : '${unidade.nome}, ${nivel.rotulo}, espera de ${formatarEspera(unidade.esperaMin)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: aoTocar,
        child: Center(
          child: destaque == null
              ? ponto
              : ValueListenableBuilder<int?>(
                  valueListenable: destaque!,
                  child: ponto,
                  builder: (context, id, filho) => AnimatedScale(
                    scale: id == unidade.id ? 1.9 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: filho,
                  ),
                ),
        ),
      ),
    );
  }
}

class _FolhaDeUnidades extends StatelessWidget {
  const _FolhaDeUnidades({
    required this.rolagem,
    required this.controlador,
    required this.unidades,
    required this.ordem,
    required this.aoTrocarOrdem,
    required this.aoAlternarFolha,
    required this.aoTocar,
    required this.aoLimparBusca,
    this.painel = false,
    this.aoDestacar,
  });

  final ScrollController rolagem;
  final MapaControlador controlador;
  final List<Unidade> unidades;
  final _Ordem ordem;
  final ValueChanged<_Ordem> aoTrocarOrdem;
  final VoidCallback aoAlternarFolha;

  /// Verdadeiro na tela larga: a lista vira um painel lateral fixo (sem alça nem cantos arredondados).
  final bool painel;

  /// Chamado com o id do cartão sob o mouse (ou nulo ao sair), para realçar o marcador no mapa.
  final ValueChanged<int?>? aoDestacar;
  final ValueChanged<Unidade> aoTocar;
  final VoidCallback aoLimparBusca;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    int chaveDeEspera(Unidade u) => !u.abertaAgora ? 1 << 31 : (u.esperaMin ?? 1 << 30);
    final ordenadas = [...unidades];
    if (ordem == _Ordem.proximidade) {
      ordenadas.sort((a, b) => (controlador.distanciaKm(a) ?? 0).compareTo(controlador.distanciaKm(b) ?? 0));
    } else {
      ordenadas.sort((a, b) => chaveDeEspera(a).compareTo(chaveDeEspera(b)));
    }

    final filtrando = controlador.busca.isNotEmpty ||
        controlador.filtroTipoId != null ||
        controlador.filtroServico != null ||
        controlador.somenteAbertas;
    final proxima = context.watch<FilaControlador>().ativo == null ? controlador.unidadeProxima : null;
    final informadas = unidades.where((u) => u.emTempoReal && u.abertaAgora).length;
    final titulo = controlador.busca.isNotEmpty
        ? 'Resultados'
        : (controlador.pontoDeReferencia != null
            ? 'Perto do ponto escolhido'
            : (controlador.localizacaoReal ? 'Perto de você' : 'Unidades'));

    return Material(
      color: tema.cardTheme.color,
      elevation: painel ? 0 : 16,
      shadowColor: Colors.black,
      borderRadius: painel ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: _Envoltorio(
        painel: painel,
        child: CustomScrollView(
          controller: rolagem,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (painel) const SizedBox(height: Espaco.p) else Semantics(
                    button: true,
                    label: 'Expandir ou recolher a lista de unidades',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: aoAlternarFolha,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Espaco.p),
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: tema.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.m, Espaco.g, Espaco.p),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(header: true, child: Text(titulo, style: tema.textTheme.titleLarge)),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: informadas > 0 ? const Color(0xFF22C55E) : const Color(0xFF98A2B3),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${unidades.length} ${unidades.length == 1 ? 'unidade' : 'unidades'} · '
                                      '${informadas == 0 ? 'tempos estimados' : '$informadas com fila informada agora'}',
                                      style: tema.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (controlador.localizacaoReal)
                          SegmentedButton<_Ordem>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(value: _Ordem.proximidade, label: Text('Perto')),
                              ButtonSegment(value: _Ordem.espera, label: Text('Rápido')),
                            ],
                            selected: {ordem},
                            onSelectionChanged: (s) => aoTrocarOrdem(s.first),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (controlador.carregando && unidades.isNotEmpty)
              const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 3)),
            if (controlador.avisoDeConexao != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.p, Espaco.m, Espaco.p),
                  child: Container(
                    padding: const EdgeInsets.all(Espaco.m),
                    decoration: BoxDecoration(
                      color: tema.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.cloud_off_rounded, color: tema.colorScheme.error),
                            const SizedBox(width: Espaco.m),
                            Expanded(
                              child: Text(
                                '${controlador.avisoDeConexao} Os tempos abaixo podem estar desatualizados.',
                                style: tema.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: controlador.carregar, child: const Text('Tentar de novo')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (proxima != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Espaco.m, 0, Espaco.m, Espaco.m),
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(Espaco.m),
                      decoration: BoxDecoration(
                        color: tema.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tema.colorScheme.primary.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.near_me_rounded, color: tema.colorScheme.primary),
                              const SizedBox(width: Espaco.p),
                              Expanded(
                                child: Text('Você está perto de ${proxima.nome}', style: tema.textTheme.titleSmall),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Já chegou? Informe a fila para ajudar quem ainda vai sair de casa.',
                            style: tema.textTheme.bodySmall,
                          ),
                          const SizedBox(height: Espaco.m),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(minimumSize: const Size(48, 46)),
                                  onPressed: () => aoTocar(proxima),
                                  child: const Text('Informar a fila'),
                                ),
                              ),
                              const SizedBox(width: Espaco.p),
                              TextButton(
                                onPressed: () => controlador.dispensarProxima(proxima.id),
                                child: const Text('Agora não'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: FaixaFilaAtiva(margem: EdgeInsets.fromLTRB(Espaco.m, 0, Espaco.m, Espaco.m)),
            ),
            if (controlador.erro != null)
              SliverToBoxAdapter(
                child: EstadoDeErro(mensagem: controlador.erro!, aoTentarDeNovo: controlador.carregar),
              )
            else if (controlador.carregando && unidades.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(Espaco.g), child: Esqueleto(linhas: 6)),
              )
            else if (ordenadas.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Espaco.g),
                  child: Column(
                    children: [
                      const EstadoVazio(
                        icone: Icons.search_off_rounded,
                        titulo: 'Nenhuma unidade encontrada',
                        texto: 'Tente outro nome, outro bairro ou outro tipo de serviço.',
                      ),
                      if (filtrando)
                        TextButton(onPressed: aoLimparBusca, child: const Text('Limpar busca e filtros')),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Espaco.m, 0, Espaco.m, Espaco.gg),
                sliver: SliverList.separated(
                  itemCount: ordenadas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Espaco.p),
                  itemBuilder: (_, i) => EntradaSuave(
                    key: ValueKey(ordenadas[i].id),
                    indice: i,
                    child: MouseRegion(
                      onEnter: (_) => aoDestacar?.call(ordenadas[i].id),
                      onExit: (_) => aoDestacar?.call(null),
                      child: UnidadeCartao(
                        unidade: ordenadas[i],
                        distanciaKm: controlador.distanciaKm(ordenadas[i]),
                        aoTocar: () => aoTocar(ordenadas[i]),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espaco.gg, 0, Espaco.gg, Espaco.gg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Como ler o mapa', style: tema.textTheme.titleLarge),
            const SizedBox(height: Espaco.m),
            for (final (nivel, faixa) in const [
              (NivelEspera.baixa, 'Até 15 minutos de espera'),
              (NivelEspera.moderada, 'De 16 a 45 minutos'),
              (NivelEspera.alta, 'De 46 a 90 minutos'),
              (NivelEspera.critica, 'Mais de 90 minutos'),
              (NivelEspera.semDados, 'Fechada ou sem informação recente'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: nivel.cor, shape: BoxShape.circle),
                      child: Icon(nivel.icone, color: nivel.corDoTexto, size: 20),
                    ),
                    const SizedBox(width: Espaco.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nivel.rotulo, style: tema.textTheme.titleSmall),
                          Text(faixa, style: tema.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Espaco.p),
            Text(
              'Cada ponto é uma unidade, na cor da espera. Cinza: fechada ou sem dado. As etiquetas com tempo mostram as '
              'melhores opções da região que você está vendo; aproxime o mapa para ver o tempo de todas. '
              'Etiqueta cheia: fila informada por cidadãos. Etiqueta vazada com "~": estimativa do modelo, '
              'ainda sem registro para este horário.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoUnidade extends StatelessWidget {
  const _ResumoUnidade({required this.unidadeId, required this.aoAbrir, this.flutuante = false});

  final int unidadeId;
  final ValueChanged<Unidade> aoAbrir;

  /// Dentro da ficha flutuante (tela larga): não fecha uma folha ao abrir os detalhes.
  final bool flutuante;

  @override
  Widget build(BuildContext context) {
    // Observa o controlador para o resumo aberto também refletir o tempo real.
    final controlador = context.watch<MapaControlador>();
    final unidade = controlador.porId(unidadeId);
    if (unidade == null) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final distancia = controlador.distanciaKm(unidade);

    final temTelefone = (unidade.telefone ?? '').replaceAll(RegExp(r'\D'), '').length >= 8;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espaco.gg, 0, Espaco.gg, Espaco.gg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: flutuante ? Espaco.g : 0),
                        child: Text(unidade.nome, style: tema.textTheme.titleLarge),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          unidade.tipo,
                          ?unidade.bairro,
                          if (distancia != null) formatarDistancia(distancia),
                        ].join(' · '),
                        style: tema.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Espaco.m),
                BlocoEspera(unidade: unidade),
              ],
            ),
            const SizedBox(height: Espaco.m),
            Text(
              !unidade.abertaAgora
                  ? 'Fechada agora. Veja o melhor horário nos detalhes.'
                  : switch (unidade.fonte) {
                      'tempo_real' || 'oficial' =>
                        '${unidade.nivel.rotulo}${unidade.oficial ? ' · dado oficial' : ''} · atualizado ${formatarHaQuantoTempo(unidade.atualizadoEm)}',
                      'historico' => 'Estimativa inicial para este horário, ainda sem informações de cidadãos',
                      _ => 'Ninguém informou a fila ainda. Seja o primeiro.',
                    },
              style: tema.textTheme.bodyMedium,
            ),
            const SizedBox(height: Espaco.g),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                    onPressed: () => abrirRota(context, unidade),
                    icon: const Icon(Icons.directions_rounded),
                    label: const Text('Rota', maxLines: 1, softWrap: false),
                  ),
                ),
                if (temTelefone) ...[
                  const SizedBox(width: Espaco.p),
                  IconButton.outlined(
                    tooltip: 'Ligar para a unidade',
                    onPressed: () => ligarPara(context, unidade),
                    icon: const Icon(Icons.call_rounded),
                  ),
                ],
                const SizedBox(width: Espaco.p),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      if (!flutuante) Navigator.of(context).pop();
                      aoAbrir(unidade);
                    },
                    child: const Text('Ver detalhes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Liga para a unidade (abre o discador do aparelho). Aceita "(11) 5237-9331", "+55 11 5239 4110" etc.
Future<void> ligarPara(BuildContext context, Unidade unidade) async {
  final digitos = (unidade.telefone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digitos.length < 8) return;
  final completo = digitos.startsWith('55') && digitos.length >= 12 ? digitos : '55$digitos';
  final abriu = await launchUrl(Uri.parse('tel:+$completo'));
  if (!abriu && context.mounted) mostrarMensagem(context, 'Não foi possível abrir o discador.');
}

/// Abre o aplicativo de mapas do aparelho com a rota até a unidade.
Future<void> abrirRota(BuildContext context, Unidade unidade) async {
  final modo = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (contexto) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Espaco.g, 0, Espaco.g, Espaco.p),
            child: Text('Como você vai?', style: Theme.of(contexto).textTheme.titleMedium),
          ),
          for (final (codigo, rotulo, icone) in const [
            ('transit', 'Transporte público (ônibus, metrô, trem)', Icons.directions_bus_rounded),
            ('walking', 'A pé', Icons.directions_walk_rounded),
            ('driving', 'Carro, moto ou aplicativo', Icons.directions_car_rounded),
            ('bicycling', 'Bicicleta', Icons.pedal_bike_rounded),
          ])
            ListTile(
              leading: Icon(icone),
              title: Text(rotulo),
              onTap: () => Navigator.of(contexto).pop(codigo),
            ),
        ],
      ),
    ),
  );
  if (modo == null || !context.mounted) return;
  final destino = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${unidade.latitude},${unidade.longitude}&travelmode=$modo',
  );
  final abriu = await launchUrl(destino, mode: LaunchMode.externalApplication);
  if (!abriu && context.mounted) mostrarMensagem(context, 'Não foi possível abrir o mapa de rotas.');
}

/// Aviso fixo do modo econômico, com a saída para voltar ao mapa.
class _AvisoDoModoLeve extends StatelessWidget {
  const _AvisoDoModoLeve({required this.aoMostrarMapa});

  final VoidCallback aoMostrarMapa;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.p, Espaco.m, Espaco.p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Espaco.m, vertical: Espaco.p),
        decoration: BoxDecoration(
          color: tema.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.data_saver_on_rounded, size: 20, color: tema.colorScheme.primary),
            const SizedBox(width: Espaco.p),
            Expanded(child: Text('Modo econômico: sem mapa, para gastar menos dados.', style: tema.textTheme.bodySmall)),
            TextButton(onPressed: aoMostrarMapa, child: const Text('Mostrar mapa')),
          ],
        ),
      ),
    );
  }
}


/// No painel lateral a lista ocupa toda a largura; na folha do celular, fica centralizada com largura máxima.
class _Envoltorio extends StatelessWidget {
  const _Envoltorio({required this.painel, required this.child});

  final bool painel;
  final Widget child;

  @override
  Widget build(BuildContext context) => painel ? child : LarguraMaxima(child: child);
}

/// Ficha rápida da unidade selecionada (tela larga): aparece sobre o mapa, com entrada animada.
class _FichaFlutuante extends StatelessWidget {
  const _FichaFlutuante({super.key, required this.unidadeId, required this.aoAbrir, required this.aoFechar});

  final int unidadeId;
  final ValueChanged<Unidade> aoAbrir;
  final VoidCallback aoFechar;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Espaco.m),
            child: _ResumoUnidade(unidadeId: unidadeId, aoAbrir: aoAbrir, flutuante: true),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Fechar',
              icon: const Icon(Icons.close_rounded),
              onPressed: aoFechar,
            ),
          ),
        ],
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, filho) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: filho),
      ),
      child: card,
    );
  }
}
