import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../data/repositorios.dart';
import '../../models/colaboracao.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';
import 'login_tela.dart';
import 'unidade_detalhe_tela.dart';

/// Conta do usuário: pontos, alertas recebidos, unidades acompanhadas e acessibilidade.
class PerfilTela extends StatelessWidget {
  const PerfilTela({super.key});

  @override
  Widget build(BuildContext context) {
    final sessao = context.watch<SessaoControlador>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          if (sessao.autenticado)
            IconButton(tooltip: 'Sair da conta', icon: const Icon(Icons.logout), onPressed: sessao.sair),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!sessao.autenticado)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: FormularioDeAcesso()))
          else ...[
            if (sessao.perfil != null) _Pontuacao(perfil: sessao.perfil!),
            TituloDeSecao(
              'Alertas recebidos',
              acao: sessao.naoLidas > 0
                  ? TextButton(onPressed: sessao.marcarNotificacoesLidas, child: const Text('Marcar como lidos'))
                  : null,
            ),
            if (sessao.notificacoes.isEmpty)
              const EstadoVazio(
                icone: Icons.notifications_none,
                texto: 'Crie um alerta na ficha de uma unidade para saber quando a fila baixar.',
              )
            else
              for (final n in sessao.notificacoes.take(5)) _NotificacaoItem(notificacao: n),
            const TituloDeSecao('Unidades que você acompanha'),
            const _Favoritos(),
          ],
          const TituloDeSecao('Acessibilidade'),
          const _Acessibilidade(),
          const TituloDeSecao('Sobre'),
          const Text(
            'O Passa Rápido mostra a espera em serviços públicos com informações enviadas por cidadãos. '
            'Nesta versão, as unidades têm localização aproximada e parte das filas é simulada para demonstração. '
            'Em caso de emergência, ligue 192.',
          ),
        ],
      ),
    );
  }
}

class _Pontuacao extends StatelessWidget {
  const _Pontuacao({required this.perfil});

  final Perfil perfil;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final faltam = perfil.pontosParaProximoNivel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(perfil.nome, style: tema.textTheme.titleLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.military_tech, color: tema.colorScheme.primary),
                const SizedBox(width: 4),
                Text('${perfil.rotuloNivel} · ${perfil.pontos} pontos', style: tema.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: perfil.progressoNoNivel,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(
              faltam == null
                  ? 'Nível máximo: suas informações têm o maior peso no cálculo das filas.'
                  : 'Faltam $faltam pontos para o próximo nível. Quanto maior o nível, mais suas informações pesam.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificacaoItem extends StatelessWidget {
  const _NotificacaoItem({required this.notificacao});

  final Notificacao notificacao;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(notificacao.lida ? Icons.notifications_none : Icons.notifications_active),
        title: Text(
          notificacao.titulo,
          style: TextStyle(fontWeight: notificacao.lida ? FontWeight.normal : FontWeight.bold),
        ),
        subtitle: Text('${notificacao.mensagem}\n${formatarHaQuantoTempo(notificacao.criadoEm)}'),
        isThreeLine: true,
        onTap: notificacao.unidadeId == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => UnidadeDetalheTela(unidadeId: notificacao.unidadeId!),
                  ),
                ),
      );
}

class _Favoritos extends StatefulWidget {
  const _Favoritos();

  @override
  State<_Favoritos> createState() => _FavoritosState();
}

class _FavoritosState extends State<_Favoritos> {
  late Future<List<Favorito>> _favoritos = context.read<ComunidadeRepositorio>().listarFavoritos();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Favorito>>(
        future: _favoritos,
        builder: (context, resultado) {
          if (resultado.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          final favoritos = resultado.data ?? const [];
          return Column(
            children: [
              if (favoritos.isEmpty)
                const EstadoVazio(icone: Icons.bookmark_border, texto: 'Você ainda não acompanha nenhuma unidade.'),
              for (final favorito in favoritos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active),
                  title: Text(favorito.nomeUnidade),
                  subtitle: Text('Avisar com espera de até ${favorito.limiteMin} min'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => UnidadeDetalheTela(unidadeId: favorito.unidadeId),
                      ),
                    );
                    if (!context.mounted) return;
                    setState(() {
                      _favoritos = context.read<ComunidadeRepositorio>().listarFavoritos();
                    });
                  },
                ),
            ],
          );
        },
      );
}

class _Acessibilidade extends StatelessWidget {
  const _Acessibilidade();

  @override
  Widget build(BuildContext context) {
    final preferencias = context.watch<PreferenciasControlador>();
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Letras maiores'),
          value: preferencias.fonteGrande,
          onChanged: preferencias.definirFonteGrande,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alto contraste'),
          value: preferencias.altoContraste,
          onChanged: preferencias.definirAltoContraste,
        ),
      ],
    );
  }
}
