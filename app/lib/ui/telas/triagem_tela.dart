import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/tema.dart';
import '../../core/triagem.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';

/// "Qual unidade procurar?": a pessoa marca os sinais que sente e o app orienta (192, UPA ou UBS).
/// Orientação informativa, nunca diagnóstico.
class TriagemTela extends StatefulWidget {
  const TriagemTela({super.key});

  @override
  State<TriagemTela> createState() => _TriagemTelaState();
}

class _TriagemTelaState extends State<TriagemTela> {
  final _marcados = <String>{};

  Future<void> _ligar192() async {
    final abriu = await launchUrl(Uri.parse('tel:192'));
    if (!abriu && mounted) mostrarMensagem(context, 'Não foi possível abrir o telefone. Ligue 192.');
  }

  void _verNoMapa(ResultadoDaTriagem resultado) {
    final mapa = context.read<MapaControlador>();
    final alvo = resultado.tiposDeUnidade.first;
    final tipo = mapa.tipos.where((t) => t.nome == alvo).firstOrNull;
    mapa.filtrarPorTipo(tipo?.id);
    context.read<NavegacaoControlador>().irPara(NavegacaoControlador.mapa);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final resultado = avaliarTriagem(_marcados);
    final (cor, icone) = switch (resultado.orientacao) {
      Orientacao.samu => (tema.colorScheme.error, Icons.emergency_rounded),
      Orientacao.upaOuProntoSocorro => (const Color(0xFFB54708), Icons.local_hospital_rounded),
      Orientacao.ubs => (const Color(0xFF16803C), Icons.health_and_safety_rounded),
    };

    Widget grupo(String titulo, GravidadeDoSinal gravidade) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Espaco.g, bottom: Espaco.p),
              child: Semantics(header: true, child: Text(titulo, style: tema.textTheme.titleSmall)),
            ),
            for (final sinal in sinaisDeAlerta.where((s) => s.gravidade == gravidade))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(sinal.texto),
                value: _marcados.contains(sinal.id),
                onChanged: (marcou) =>
                    setState(() => marcou == true ? _marcados.add(sinal.id) : _marcados.remove(sinal.id)),
              ),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Qual unidade procurar?')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
        children: [
          LarguraMaxima(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(Espaco.g),
                    decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cor.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icone, color: cor, size: 32),
                            const SizedBox(width: Espaco.m),
                            Expanded(child: Text(resultado.titulo, style: tema.textTheme.titleLarge?.copyWith(color: cor))),
                          ],
                        ),
                        const SizedBox(height: Espaco.p),
                        Text(resultado.texto, style: tema.textTheme.bodyMedium),
                        const SizedBox(height: Espaco.m),
                        if (resultado.orientacao == Orientacao.samu)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: cor),
                            onPressed: _ligar192,
                            icon: const Icon(Icons.call_rounded),
                            label: const Text('Ligar 192 agora'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => _verNoMapa(resultado),
                            icon: const Icon(Icons.map_rounded),
                            label: Text('Ver ${resultado.tiposDeUnidade.join(' e ')} no mapa'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Espaco.m),
                Text(
                  'Marque o que está acontecendo agora. A orientação acima muda sozinha.',
                  style: tema.textTheme.bodyMedium,
                ),
                grupo('Ligue 192 se houver', GravidadeDoSinal.emergencia),
                grupo('Procure uma UPA ou pronto-socorro hoje se houver', GravidadeDoSinal.urgencia),
                const SizedBox(height: Espaco.g),
                Text(avisoDaTriagem, style: tema.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
