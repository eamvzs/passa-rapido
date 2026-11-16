import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';

/// Apresentação exibida na primeira abertura do app.
class ApresentacaoTela extends StatefulWidget {
  const ApresentacaoTela({super.key});

  @override
  State<ApresentacaoTela> createState() => _ApresentacaoTelaState();
}

class _ApresentacaoTelaState extends State<ApresentacaoTela> {
  static const _paginas = [
    (
      Icons.map_rounded,
      'Veja a fila antes de sair de casa',
      'O mapa mostra, em tempo real, quanto tempo de espera há em UPAs, postos de saúde, Poupatempo, INSS e CRAS.',
    ),
    (
      Icons.bolt_rounded,
      'Vá aonde é mais rápido',
      'O app soma o deslocamento e a fila e indica a melhor unidade e o melhor horário para você.',
    ),
    (
      Icons.volunteer_activism_rounded,
      'Ajude quem vem depois',
      'Com um toque você informa como está a fila. Cada colaboração vale pontos e melhora a estimativa para todos.',
    ),
  ];

  final _controle = PageController();
  int _pagina = 0;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  void _avancar() {
    if (_pagina == _paginas.length - 1) {
      context.read<PreferenciasControlador>().concluirApresentacao();
    } else {
      _controle.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ultima = _pagina == _paginas.length - 1;

    return Scaffold(
      body: SafeArea(
        child: LarguraMaxima(
          child: Padding(
            padding: const EdgeInsets.all(Espaco.gg),
            child: Column(
              children: [
                Row(
                  children: [
                    const LogoPassaRapido(tamanho: 40),
                    const SizedBox(width: Espaco.m),
                    Text('Passa Rápido', style: tema.textTheme.titleLarge),
                    const Spacer(),
                    if (!ultima)
                      TextButton(
                        onPressed: context.read<PreferenciasControlador>().concluirApresentacao,
                        child: const Text('Pular'),
                      ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controle,
                    itemCount: _paginas.length,
                    onPageChanged: (i) => setState(() => _pagina = i),
                    itemBuilder: (_, i) {
                      final (icone, titulo, texto) = _paginas[i];
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 168,
                            height: 168,
                            decoration: BoxDecoration(
                              color: tema.colorScheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icone, size: 84, color: tema.colorScheme.primary),
                          ),
                          const SizedBox(height: Espaco.xg),
                          Text(titulo, style: tema.textTheme.headlineMedium, textAlign: TextAlign.center),
                          const SizedBox(height: Espaco.m),
                          Text(texto, style: tema.textTheme.bodyLarge, textAlign: TextAlign.center),
                        ],
                      );
                    },
                  ),
                ),
                Semantics(
                  label: 'Página ${_pagina + 1} de ${_paginas.length}',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _paginas.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _pagina ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _pagina ? tema.colorScheme.primary : tema.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Espaco.gg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _avancar,
                    child: Text(ultima ? 'Começar' : 'Continuar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
