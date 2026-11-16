import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nivel_espera.dart';
import '../models/colaboracao.dart';
import '../state/controladores.dart';
import 'telas/mapa_tela.dart';
import 'telas/painel_tela.dart';
import 'telas/perfil_tela.dart';
import 'telas/recomendacao_tela.dart';
import 'componentes/comuns.dart';

/// Estrutura principal com as quatro abas do app.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _perguntando = false;

  /// Mostra na hora o alerta de fila baixa que chegou pelo canal de tempo real.
  void _mostrarAlerta(Notificacao alerta) {
    final sessao = context.read<SessaoControlador>()..consumirAlerta();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: Color(0xFF4ADE80)),
              const SizedBox(width: 12),
              Expanded(child: Text('${alerta.titulo}\n${alerta.mensagem}')),
            ],
          ),
          action: alerta.unidadeId == null
              ? null
              : SnackBarAction(
                  label: 'Ver',
                  onPressed: () {
                    sessao.marcarNotificacoesLidas();
                    abrirUnidade(context, alerta.unidadeId!);
                  },
                ),
        ),
      );
  }

  /// "Como está a fila?": aparece quando a pessoa está há alguns minutos dentro de uma unidade.
  Future<void> _perguntarDaFila(int unidadeId) async {
    if (_perguntando) return;
    _perguntando = true;
    final presenca = context.read<PresencaControlador>();
    final unidade = context.read<MapaControlador>().porId(unidadeId);
    if (unidade == null) {
      presenca.encerrar();
      _perguntando = false;
      return;
    }
    final tamanho = await showModalBottomSheet<TamanhoFila>(
      context: context,
      showDragHandle: true,
      builder: (contexto) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Você está em ${unidade.nome}', style: Theme.of(contexto).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Como está a fila agora? Sua resposta ajuda quem está a caminho.'),
              const SizedBox(height: 12),
              for (final t in TamanhoFila.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(contexto).pop(t),
                    child: Text('${t.rotulo} · ${t.descricao}'),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(contexto).pop(),
                child: const Text('Agora não'),
              ),
            ],
          ),
        ),
      ),
    );
    presenca.encerrar();
    _perguntando = false;
    if (tamanho == null || !mounted) return;
    try {
      final localizacao = context.read<MapaControlador>().localizacao;
      await context.read<FilaControlador>().registrar(
            unidadeId: unidadeId,
            tamanho: tamanho,
            estouNaFila: false,
            latitude: localizacao != null && localizacao.real ? localizacao.ponto.latitude : null,
            longitude: localizacao != null && localizacao.real ? localizacao.ponto.longitude : null,
          );
      if (!mounted) return;
      await context.read<SessaoControlador>().recarregarPerfil();
      if (mounted) mostrarSucesso(context, 'Obrigado por informar!', pontos: 3);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aba = context.select<NavegacaoControlador, int>((n) => n.aba);
    final pergunta = context.select<PresencaControlador, int?>((p) => p.pendente);
    if (pergunta != null && !_perguntando) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _perguntarDaFila(pergunta);
      });
    }
    final naoLidas = context.select<SessaoControlador, int>((s) => s.naoLidas);
    final alerta = context.select<SessaoControlador, Notificacao?>((s) => s.alertaPendente);
    final recuperacao = context.select<SessaoControlador, bool>((s) => s.recuperacaoPendente);
    if (alerta != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mostrarAlerta(alerta);
      });
    }
    if (recuperacao) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SessaoControlador>().recuperacaoPendente = false;
        Navigator.of(context).pushNamed('/nova-senha');
      });
    }

    // IndexedStack mantém o estado das abas sem reconstruir o mapa a cada troca.
    final conteudo = IndexedStack(
      index: aba,
      children: const [MapaTela(), RecomendacaoTela(), PainelTela(), PerfilTela()],
    );

    final icones = [
      (Icons.map_outlined, Icons.map_rounded, 'Mapa'),
      (Icons.bolt_outlined, Icons.bolt_rounded, 'Rápido'),
      (Icons.insights_outlined, Icons.insights_rounded, 'Painel'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
    ];
    Widget icone(int i, {required bool selecionado}) {
      final (normal, cheio, _) = icones[i];
      final base = Icon(selecionado ? cheio : normal);
      return i == 3
          ? Badge(isLabelVisible: naoLidas > 0, label: Text('$naoLidas'), child: base)
          : base;
    }

    // Em telas largas (tablet, computador e celular na horizontal) o menu vai para a lateral
    // e libera a altura da tela para o conteúdo.
    final larguraDaTela = MediaQuery.sizeOf(context).width;
    if (larguraDaTela >= 700) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: aba,
              onDestinationSelected: context.read<NavegacaoControlador>().irPara,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (var i = 0; i < icones.length; i++)
                  NavigationRailDestination(
                    icon: icone(i, selecionado: false),
                    selectedIcon: icone(i, selecionado: true),
                    label: Text(icones[i].$3),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
            Expanded(child: conteudo),
          ],
        ),
      );
    }

    return Scaffold(
      body: conteudo,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
        child: NavigationBar(
          selectedIndex: aba,
          onDestinationSelected: context.read<NavegacaoControlador>().irPara,
          destinations: [
            for (var i = 0; i < icones.length; i++)
              NavigationDestination(
                icon: icone(i, selecionado: false),
                selectedIcon: icone(i, selecionado: true),
                label: icones[i].$3,
                tooltip: i == 1 ? 'Mais rápido agora' : icones[i].$3,
              ),
          ],
        ),
      ),
    );
  }
}
