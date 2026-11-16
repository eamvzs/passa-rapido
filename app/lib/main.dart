import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'core/tema.dart';
import 'data/localizacao.dart';
import 'data/repositorios.dart';
import 'state/controladores.dart';
import 'ui/app_shell.dart';
import 'ui/telas/apresentacao_tela.dart';
import 'ui/telas/login_tela.dart';
import 'ui/telas/nova_senha_tela.dart';
import 'ui/telas/termos_tela.dart';
import 'ui/telas/unidade_detalhe_tela.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  runApp(PassaRapidoApp(prefs: prefs));
}

class PassaRapidoApp extends StatelessWidget {
  const PassaRapidoApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final unidades = UnidadeRepositorio(db, prefs);
    final fila = FilaRepositorio(db);
    final comunidade = ComunidadeRepositorio(db);

    return MultiProvider(
      providers: [
        Provider.value(value: unidades),
        Provider.value(value: fila),
        Provider.value(value: comunidade),
        ChangeNotifierProvider(create: (_) => PreferenciasControlador(prefs)),
        ChangeNotifierProvider(create: (_) => SessaoControlador(db, comunidade, fila)),
        ChangeNotifierProvider(
          create: (_) => MapaControlador(db, unidades, LocalizacaoServico())..iniciar(),
        ),
        ChangeNotifierProxyProvider<SessaoControlador, FilaControlador>(
          create: (_) => FilaControlador(fila),
          update: (_, sessao, controlador) => controlador!..sincronizarUsuario(sessao.usuarioId),
        ),
        ChangeNotifierProvider(create: (_) => NavegacaoControlador()),
        ChangeNotifierProvider(create: (_) => PlanoControlador(prefs)),
        ChangeNotifierProvider(
          create: (contexto) => PresencaControlador(
            contexto.read<MapaControlador>(),
            contexto.read<SessaoControlador>(),
            contexto.read<FilaControlador>(),
          ),
        ),
      ],
      child: Consumer<PreferenciasControlador>(
        builder: (context, preferencias, _) => MaterialApp(
          title: 'Passa Rápido',
          debugShowCheckedModeBanner: false,
          // Textos do sistema (voltar, fechar, copiar, colar) em português.
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: construirTema(brilho: Brightness.light, altoContraste: preferencias.altoContraste, estilo: preferencias.estilo),
          darkTheme: construirTema(brilho: Brightness.dark, altoContraste: preferencias.altoContraste, estilo: preferencias.estilo),
          themeMode: preferencias.modoDoTema,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(preferencias.escalaDoTexto * preferencias.estilo.paleta.escalaTexto),
            ),
            child: child!,
          ),
          initialRoute: '/',
          onGenerateInitialRoutes: _rotasIniciais,
          onGenerateRoute: _gerarRota,
          onUnknownRoute: (s) => _rota(s, const _Raiz()),
        ),
      ),
    );
  }
}

/// Primeira tela: apresentação na primeira abertura, depois o app.
class _Raiz extends StatelessWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context) =>
      context.select<PreferenciasControlador, bool>((p) => p.apresentacaoVista)
          ? const AppShell()
          : const ApresentacaoTela();
}

MaterialPageRoute<T> _rota<T>(RouteSettings configuracao, Widget tela, {bool dialogo = false}) =>
    MaterialPageRoute<T>(settings: configuracao, builder: (_) => tela, fullscreenDialog: dialogo);

/// Rotas do app. Na web, a URL acompanha a tela (`#/unidade/12`) e o botão voltar do navegador funciona.
Route<dynamic>? _gerarRota(RouteSettings configuracao) {
  final segmentos = Uri.parse(configuracao.name ?? '/').pathSegments;
  if (segmentos.isEmpty) return _rota(configuracao, const _Raiz());
  switch (segmentos.first) {
    case 'unidade':
      final id = segmentos.length == 2 ? int.tryParse(segmentos[1]) : null;
      return id == null ? null : _rota(configuracao, UnidadeDetalheTela(unidadeId: id));
    case 'entrar':
      return _rota(configuracao, const LoginTela(), dialogo: true);
    case 'termos':
      return _rota(configuracao, const TermosTela());
    case 'privacidade':
      return _rota(configuracao, const PrivacidadeTela());
    case 'nova-senha':
      return _rota(configuracao, const NovaSenhaTela(), dialogo: true);
  }
  return null;
}

/// Abrir um link direto para uma unidade deixa o mapa por baixo, para o voltar levar a ele.
List<Route<dynamic>> _rotasIniciais(String nome) {
  final raiz = _rota<void>(const RouteSettings(name: '/'), const _Raiz());
  if (nome == '/') return [raiz];
  final destino = _gerarRota(RouteSettings(name: nome));
  return [raiz, ?destino];
}
