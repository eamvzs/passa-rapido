import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/controladores.dart';
import 'telas/mapa_tela.dart';
import 'telas/painel_tela.dart';
import 'telas/perfil_tela.dart';
import 'telas/recomendacao_tela.dart';

/// Estrutura principal com as quatro abas do app.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _aba = 0;

  @override
  Widget build(BuildContext context) {
    final naoLidas = context.select<SessaoControlador, int>((s) => s.naoLidas);

    return Scaffold(
      // IndexedStack mantém o estado das abas sem reconstruir o mapa a cada troca.
      body: IndexedStack(
        index: _aba,
        children: const [MapaTela(), RecomendacaoTela(), PainelTela(), PerfilTela()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (i) => setState(() => _aba = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Mapa'),
          const NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'Mais rápido'),
          const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Painel'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: naoLidas > 0,
              label: Text('$naoLidas'),
              child: const Icon(Icons.person_outline),
            ),
            selectedIcon: const Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
