import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'core/tema.dart';
import 'data/localizacao.dart';
import 'data/repositorios.dart';
import 'state/controladores.dart';
import 'ui/app_shell.dart';

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
    final unidades = UnidadeRepositorio(db);
    final fila = FilaRepositorio(db);
    final comunidade = ComunidadeRepositorio(db);

    return MultiProvider(
      providers: [
        Provider.value(value: unidades),
        Provider.value(value: comunidade),
        ChangeNotifierProvider(create: (_) => PreferenciasControlador(prefs)),
        ChangeNotifierProvider(create: (_) => SessaoControlador(db, comunidade)),
        ChangeNotifierProvider(
          create: (_) => MapaControlador(db, unidades, LocalizacaoServico())..iniciar(),
        ),
        ChangeNotifierProxyProvider<SessaoControlador, FilaControlador>(
          create: (_) => FilaControlador(fila),
          update: (_, sessao, controlador) => controlador!..sincronizarUsuario(sessao.usuarioId),
        ),
      ],
      child: Consumer<PreferenciasControlador>(
        builder: (context, preferencias, _) => MaterialApp(
          title: 'Passa Rápido',
          debugShowCheckedModeBanner: false,
          theme: construirTema(altoContraste: preferencias.altoContraste),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(preferencias.escalaDoTexto),
            ),
            child: child!,
          ),
          home: const AppShell(),
        ),
      ),
    );
  }
}
