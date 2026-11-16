import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../core/tema.dart';
import '../../models/colaboracao.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';
import '../../data/repositorios.dart';
import 'ajuda_tela.dart';
import 'login_tela.dart';
import 'moderacao_tela.dart';

/// Conta do usuário: pontos, alertas recebidos, unidades acompanhadas e preferências.
class PerfilTela extends StatelessWidget {
  const PerfilTela({super.key});

  @override
  Widget build(BuildContext context) {
    final sessao = context.watch<SessaoControlador>();

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
        children: [
          LarguraMaxima(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!sessao.autenticado)
                  const Card(
                    child: Padding(padding: EdgeInsets.all(Espaco.gg), child: FormularioDeAcesso()),
                  )
                else ...[
                  if (sessao.perfil == null)
                    const Card(child: Padding(padding: EdgeInsets.all(Espaco.g), child: Esqueleto()))
                  else
                    _Pontuacao(perfil: sessao.perfil!),
                  if (sessao.perfil != null) _ImpactoSemanal(pontos: sessao.perfil!.pontos),
                  const _PlanoSalvo(),
                  const _AcessoDaModeracao(),
                  Secao(
                    icone: Icons.notifications_rounded,
                    titulo: 'Alertas recebidos',
                    acao: sessao.naoLidas > 0
                        ? TextButton(onPressed: sessao.marcarNotificacoesLidas, child: const Text('Marcar como lidos'))
                        : null,
                    child: sessao.notificacoes.isEmpty
                        ? const EstadoVazio(
                            icone: Icons.notifications_none_rounded,
                            texto: 'Crie um alerta na ficha de uma unidade para saber quando a fila baixar.',
                          )
                        : Column(
                            children: [
                              for (final n in sessao.notificacoes.take(5)) _NotificacaoItem(notificacao: n),
                            ],
                          ),
                  ),
                  const Secao(
                    icone: Icons.bookmark_rounded,
                    titulo: 'Unidades que você acompanha',
                    child: _Favoritos(),
                  ),
                  const Secao(
                    icone: Icons.history_rounded,
                    titulo: 'Suas últimas colaborações',
                    child: _Historico(),
                  ),
                ],
                Secao(
                  icone: Icons.help_outline_rounded,
                  titulo: 'Ajuda e direitos',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.menu_book_rounded),
                    title: const Text('Como usar, siglas e atendimento prioritário'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AjudaTela())),
                  ),
                ),
                const Secao(
                  icone: Icons.tune_rounded,
                  titulo: 'Aparência e acessibilidade',
                  child: _Preferencias(),
                ),
                Secao(
                  icone: Icons.shield_outlined,
                  titulo: 'Privacidade e dados',
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Termos de uso'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pushNamed('/termos'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Política de privacidade'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pushNamed('/privacidade'),
                      ),
                      if (sessao.autenticado)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                          title: Text(
                            'Excluir minha conta',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                          subtitle: const Text('Apaga seus dados pessoais de forma definitiva'),
                          onTap: () => _confirmarExclusao(context),
                        ),
                    ],
                  ),
                ),
                Secao(
                  icone: Icons.info_rounded,
                  titulo: 'Sobre o Passa Rápido',
                  child: Text(
                    'O Passa Rápido mostra a espera em serviços públicos com informações enviadas por cidadãos. '
                    'Quando ninguém informou a fila, o app mostra uma estimativa do modelo, sempre identificada como estimativa. '
                    'Em caso de emergência, ligue 192.\n\n'
                    'Cadastro das unidades de saúde: CNES/DATASUS, Ministério da Saúde. '
                    'Mapas e demais unidades: © colaboradores do OpenStreetMap (licença ODbL).',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (sessao.autenticado) ...[
                  const SizedBox(height: Espaco.g),
                  OutlinedButton.icon(
                    onPressed: sessao.sair,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sair da conta'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmação em duas etapas: a exclusão não tem volta.
Future<void> _confirmarExclusao(BuildContext context) async {
  final sessao = context.read<SessaoControlador>();
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Excluir a conta?'),
      content: const Text(
        'Seu perfil, pontos, registros, avisos, avaliações e alertas serão apagados de forma definitiva. '
        'Esta ação não pode ser desfeita.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogo).pop(false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogo).colorScheme.error),
          onPressed: () => Navigator.of(dialogo).pop(true),
          child: const Text('Excluir tudo'),
        ),
      ],
    ),
  );
  if (confirmou != true || !context.mounted) return;
  try {
    await sessao.excluirConta();
    if (context.mounted) mostrarMensagem(context, 'Conta excluída. Seus dados foram apagados.');
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
  }
}

class _Pontuacao extends StatelessWidget {
  const _Pontuacao({required this.perfil});

  final Perfil perfil;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final faltam = perfil.pontosParaProximoNivel;
    const claro = Colors.white;
    final suave = claro.withValues(alpha: 0.82);

    return Container(
      padding: const EdgeInsets.all(Espaco.gg),
      decoration: BoxDecoration(
        gradient: IdentidadeVisual.de(context).gradiente,
        borderRadius: BorderRadius.circular(IdentidadeVisual.de(context).raioCartao),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: claro.withValues(alpha: 0.2),
                foregroundColor: claro,
                child: Text(iniciaisDe(perfil.nome), style: tema.textTheme.titleLarge?.copyWith(color: claro)),
              ),
              const SizedBox(width: Espaco.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(perfil.nome, style: tema.textTheme.titleLarge?.copyWith(color: claro)),
                    Row(
                      children: [
                        Icon(Icons.military_tech_rounded, size: 18, color: IdentidadeVisual.de(context).destaque),
                        const SizedBox(width: 4),
                        Text('Nível ${perfil.rotuloNivel}', style: tema.textTheme.bodyMedium?.copyWith(color: suave)),
                      ],
                    ),
                  ],
                ),
              ),
              Semantics(
                label: '${perfil.pontos} pontos',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${perfil.pontos}', style: tema.textTheme.headlineMedium?.copyWith(color: claro, height: 1)),
                    Text('pontos', style: tema.textTheme.labelMedium?.copyWith(color: suave)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaco.g),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: perfil.progressoNoNivel,
              minHeight: 10,
              color: IdentidadeVisual.de(context).destaque,
              backgroundColor: claro.withValues(alpha: 0.22),
            ),
          ),
          const SizedBox(height: Espaco.p),
          Text(
            faltam == null
                ? 'Nível máximo: suas informações têm o maior peso no cálculo das filas.'
                : 'Faltam $faltam pontos para o próximo nível. Quanto maior o nível, mais suas informações pesam.',
            style: tema.textTheme.bodySmall?.copyWith(color: suave),
          ),
          const SizedBox(height: Espaco.m),
          Semantics(
            label: 'Confiabilidade ${perfil.confiabilidade} por cento',
            excludeSemantics: true,
            child: Row(
              children: [
                Icon(Icons.verified_rounded, size: 18, color: IdentidadeVisual.de(context).destaque2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Confiabilidade ${perfil.confiabilidade}%: sobe quando a fila que você informa bate com a espera que você mede.',
                    style: tema.textTheme.bodySmall?.copyWith(color: suave),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaco.m),
          Wrap(
            spacing: Espaco.p,
            runSpacing: Espaco.p,
            children: [
              for (final (texto, pontos) in const [
                ('Chegar na fila', 5),
                ('Confirmar atendimento', 10),
                ('Informar ou avisar', 3),
                ('Avaliar', 2),
              ])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: claro.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$texto +$pontos', style: tema.textTheme.labelMedium?.copyWith(color: claro)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificacaoItem extends StatelessWidget {
  const _NotificacaoItem({required this.notificacao});

  final Notificacao notificacao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: notificacao.unidadeId == null
          ? null
          : () => abrirUnidade(context, notificacao.unidadeId!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Espaco.p),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              notificacao.lida ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
              color: notificacao.lida ? tema.colorScheme.onSurfaceVariant : tema.colorScheme.primary,
            ),
            const SizedBox(width: Espaco.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notificacao.titulo,
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: notificacao.lida ? FontWeight.w500 : FontWeight.w800,
                    ),
                  ),
                  Text(notificacao.mensagem),
                  Text(formatarHaQuantoTempo(notificacao.criadoEm), style: tema.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Favoritos extends StatelessWidget {
  const _Favoritos();

  @override
  Widget build(BuildContext context) {
    final sessao = context.watch<SessaoControlador>();
    if (!sessao.dadosCarregados) return const Esqueleto(linhas: 2);
    if (sessao.favoritos.isEmpty) {
      return const EstadoVazio(
        icone: Icons.bookmark_border_rounded,
        texto: 'Você ainda não acompanha nenhuma unidade.',
      );
    }
    return Column(
      children: [
        for (final favorito in sessao.favoritos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_active_rounded),
            title: Text(favorito.nomeUnidade),
            subtitle: Text('Avisar com espera de até ${favorito.limiteMin} min'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => abrirUnidade(context, favorito.unidadeId),
          ),
      ],
    );
  }
}

class _Historico extends StatelessWidget {
  const _Historico();

  static const _rotulos = {
    'aguardando': 'Na fila',
    'atendido': 'Atendido',
    'concluido': 'Concluído',
    'desistiu': 'Desistiu',
    'expirado': 'Expirado',
  };

  @override
  Widget build(BuildContext context) {
    final sessao = context.watch<SessaoControlador>();
    if (!sessao.dadosCarregados) return const Esqueleto(linhas: 2);
    final registros = sessao.historico.take(5).toList();
    if (registros.isEmpty) {
      return const EstadoVazio(
        icone: Icons.how_to_reg_rounded,
        texto: 'Quando você informar uma fila, ela aparece aqui.',
      );
    }
    final tema = Theme.of(context);
    return Column(
      children: [
        for (final registro in registros)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  registro.tipo == 'checkin' ? Icons.how_to_reg_rounded : Icons.visibility_rounded,
                  color: tema.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: Espaco.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(registro.nomeUnidade ?? 'Unidade', style: tema.textTheme.titleSmall),
                      Text(
                        [
                          registro.tipo == 'checkin'
                              ? (_rotulos[registro.status] ?? registro.status)
                              : 'Você informou: ${registro.tamanho.rotulo.toLowerCase()}',
                          if (registro.esperaRealMin != null) 'esperou ${formatarEspera(registro.esperaRealMin)}',
                          formatarHaQuantoTempo(registro.chegadaEm),
                        ].join(' · '),
                        style: tema.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Preferencias extends StatelessWidget {
  const _Preferencias();

  @override
  Widget build(BuildContext context) {
    final preferencias = context.watch<PreferenciasControlador>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
              ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Escuro')),
            ],
            selected: {preferencias.modoDoTema},
            onSelectionChanged: (s) => preferencias.definirModoDoTema(s.first),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Letras maiores'),
          subtitle: const Text('Aumenta todos os textos do app'),
          value: preferencias.fonteGrande,
          onChanged: preferencias.definirFonteGrande,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Modo econômico'),
          subtitle: const Text('Sem mapa: lista de lugares por distância, para gastar menos dados'),
          value: preferencias.modoLeve,
          onChanged: preferencias.definirModoLeve,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alto contraste'),
          subtitle: const Text('Cores mais fortes e bordas visíveis'),
          value: preferencias.altoContraste,
          onChanged: preferencias.definirAltoContraste,
        ),
      ],
    );
  }
}


/// O que a pessoa fez nos últimos 7 dias, só com números dela (sem ranking, sem comparação).
class _ImpactoSemanal extends StatefulWidget {
  const _ImpactoSemanal({required this.pontos});

  /// Muda a cada contribuição; serve para buscar de novo.
  final int pontos;

  @override
  State<_ImpactoSemanal> createState() => _ImpactoSemanalState();
}

class _ImpactoSemanalState extends State<_ImpactoSemanal> {
  late Future<ImpactoSemanal> _impacto = context.read<ComunidadeRepositorio>().meuImpacto();

  @override
  void didUpdateWidget(covariant _ImpactoSemanal antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.pontos != widget.pontos) _impacto = context.read<ComunidadeRepositorio>().meuImpacto();
  }

  @override
  Widget build(BuildContext context) => Secao(
        icone: Icons.volunteer_activism_rounded,
        titulo: 'Sua semana',
        child: FutureBuilder<ImpactoSemanal>(
          future: _impacto,
          builder: (context, r) {
            if (r.connectionState != ConnectionState.done) return const Esqueleto(linhas: 2);
            if (r.hasError || r.data == null) {
              return const Text('Não foi possível carregar agora.');
            }
            final i = r.data!;
            if (i.contribuicoes == 0) {
              return const EstadoVazio(
                icone: Icons.favorite_border_rounded,
                texto: 'Nenhuma contribuição nos últimos 7 dias. Informe uma fila e ajude a próxima pessoa.',
              );
            }
            final partes = [
              if (i.registros > 0) '${i.registros} ${i.registros == 1 ? 'registro de fila' : 'registros de fila'} em ${i.unidades} ${i.unidades == 1 ? 'unidade' : 'unidades'}',
              if (i.avisos > 0) '${i.avisos} ${i.avisos == 1 ? 'aviso' : 'avisos'}',
              if (i.avaliacoes > 0) '${i.avaliacoes} ${i.avaliacoes == 1 ? 'avaliação' : 'avaliações'}',
              if (i.sugestoesAceitas > 0) '${i.sugestoesAceitas} ${i.sugestoesAceitas == 1 ? 'correção aceita' : 'correções aceitas'}',
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nos últimos 7 dias você enviou ${partes.join(', ')}.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text('+${i.pontos} pontos na semana. Obrigado por ajudar quem vem depois de você.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            );
          },
        ),
      );
}

/// Compromisso salvo no aparelho: hora de sair de casa.
class _PlanoSalvo extends StatelessWidget {
  const _PlanoSalvo();

  @override
  Widget build(BuildContext context) {
    final plano = context.watch<PlanoControlador>().plano;
    if (plano == null) return const SizedBox.shrink();
    final l = MaterialLocalizations.of(context);
    String quando(DateTime d) =>
        '${l.formatShortDate(d)} às ${l.formatTimeOfDay(TimeOfDay.fromDateTime(d), alwaysUse24HourFormat: true)}';
    return Secao(
      icone: Icons.event_available_rounded,
      titulo: 'Sua próxima ida',
      acao: TextButton(onPressed: () => context.read<PlanoControlador>().limpar(), child: const Text('Remover')),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(plano.nomeUnidade),
        subtitle: Text('Atendimento ${quando(plano.horario)}. Saia de casa até ${quando(plano.saida)}.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => abrirUnidade(context, plano.unidadeId),
      ),
    );
  }
}

/// A entrada da moderação só aparece para moderadores (o banco confere de novo em cada chamada).
class _AcessoDaModeracao extends StatefulWidget {
  const _AcessoDaModeracao();

  @override
  State<_AcessoDaModeracao> createState() => _AcessoDaModeracaoState();
}

class _AcessoDaModeracaoState extends State<_AcessoDaModeracao> {
  late final Future<bool> _moderador =
      context.read<ComunidadeRepositorio>().souModerador().catchError((_) => false);

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _moderador,
        builder: (context, r) {
          if (r.data != true) return const SizedBox.shrink();
          return Secao(
            icone: Icons.admin_panel_settings_rounded,
            titulo: 'Moderação',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.rule_rounded),
              title: const Text('Sugestões e denúncias pendentes'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModeracaoTela())),
            ),
          );
        },
      );
}
