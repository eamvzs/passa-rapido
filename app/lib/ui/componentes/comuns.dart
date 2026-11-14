import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../core/nivel_espera.dart';
import '../../data/repositorios.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';
import '../telas/login_tela.dart';

IconData iconeDoTipo(String tipo) => switch (tipo) {
      'UPA' => Icons.emergency,
      'Pronto-socorro' => Icons.local_hospital,
      'UBS' => Icons.medical_services,
      'Poupatempo' => Icons.badge,
      'INSS' => Icons.account_balance,
      'CRAS' => Icons.diversity_3,
      _ => Icons.place,
    };

void mostrarMensagem(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating));
}

void mostrarErro(BuildContext context, Object erro) =>
    mostrarMensagem(context, traduzirErro(erro).mensagem);

/// Abre a tela de login quando a ação exige conta. Devolve verdadeiro se há sessão ao final.
Future<bool> garantirLogin(BuildContext context) async {
  final sessao = context.read<SessaoControlador>();
  if (sessao.autenticado) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const LoginTela(), fullscreenDialog: true),
  );
  return sessao.autenticado;
}

/// Etiqueta colorida com o tempo de espera. O texto acompanha a cor para não depender só dela.
class SeloEspera extends StatelessWidget {
  const SeloEspera({
    super.key,
    required NivelEspera nivel,
    required int? minutos,
    this.fechada = false,
    this.grande = false,
  })  : nivel = fechada ? NivelEspera.semDados : nivel,
        minutos = fechada ? null : minutos;

  final NivelEspera nivel;
  final int? minutos;

  /// Unidade fora do horário de funcionamento: mostra "Fechada" no lugar da espera.
  final bool fechada;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final estilo = grande
        ? Theme.of(context).textTheme.headlineSmall
        : Theme.of(context).textTheme.titleSmall;
    return Semantics(
      label: fechada ? 'Fechada agora' : '${nivel.rotulo}, espera de ${formatarEspera(minutos)}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: grande ? 16 : 10, vertical: grande ? 10 : 6),
        decoration: BoxDecoration(color: nivel.cor, borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fechada ? Icons.lock_clock : nivel.icone, size: grande ? 24 : 16, color: nivel.corDoTexto),
            const SizedBox(width: 6),
            Text(
              fechada ? 'Fechada' : formatarEspera(minutos),
              style: estilo?.copyWith(color: nivel.corDoTexto, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha de lista com os dados principais da unidade.
class UnidadeCartao extends StatelessWidget {
  const UnidadeCartao({super.key, required this.unidade, required this.aoTocar, this.complemento});

  final Unidade unidade;
  final VoidCallback aoTocar;
  final String? complemento;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final detalhes = [
      unidade.tipo,
      if (unidade.bairro != null) unidade.bairro!,
      ?complemento,
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: tema.colorScheme.primaryContainer,
                foregroundColor: tema.colorScheme.onPrimaryContainer,
                child: Icon(iconeDoTipo(unidade.tipo)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unidade.nome, style: tema.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(detalhes, style: tema.textTheme.bodySmall),
                    if (unidade.relatosAtivos > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.campaign, size: 16, color: tema.colorScheme.error),
                            const SizedBox(width: 4),
                            Text(
                              unidade.relatosAtivos == 1 ? '1 aviso ativo' : '${unidade.relatosAtivos} avisos ativos',
                              style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SeloEspera(nivel: unidade.nivel, minutos: unidade.esperaMin, fechada: !unidade.abertaAgora),
            ],
          ),
        ),
      ),
    );
  }
}

class TituloDeSecao extends StatelessWidget {
  const TituloDeSecao(this.texto, {super.key, this.acao});

  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(texto, style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            ?acao,
          ],
        ),
      );
}

class EstadoVazio extends StatelessWidget {
  const EstadoVazio({super.key, required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icone, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(child: Text(texto)),
          ],
        ),
      );
}

class EstadoDeErro extends StatelessWidget {
  const EstadoDeErro({super.key, required this.mensagem, required this.aoTentarDeNovo});

  final String mensagem;
  final VoidCallback aoTentarDeNovo;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(mensagem, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: aoTentarDeNovo, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
}

/// Faixa fixa enquanto o usuário está em uma fila, com as ações do momento.
class FaixaFilaAtiva extends StatelessWidget {
  const FaixaFilaAtiva({super.key});

  @override
  Widget build(BuildContext context) {
    final fila = context.watch<FilaControlador>();
    final registro = fila.ativo;
    if (registro == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final sessao = context.read<SessaoControlador>();

    Future<void> executar(Future<void> Function() acao, String sucesso) async {
      try {
        await acao();
        await sessao.recarregarPerfil();
        if (context.mounted) mostrarMensagem(context, sucesso);
      } catch (e) {
        if (context.mounted) mostrarErro(context, e);
      }
    }

    return Material(
      color: tema.colorScheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                registro.aguardando
                    ? 'Você está na fila: ${registro.nomeUnidade ?? ''}'
                    : 'Em atendimento: ${registro.nomeUnidade ?? ''}',
                style: tema.textTheme.titleSmall,
              ),
              Text(
                registro.aguardando
                    ? 'Chegada ${formatarHaQuantoTempo(registro.chegadaEm)}'
                    : 'Você esperou ${formatarEspera(registro.esperaRealMin)}',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (registro.aguardando)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: fila.ocupado
                            ? null
                            : () => executar(
                                  () async {
                                    await fila.marcarAtendido();
                                  },
                                  'Atendimento registrado. Você ganhou 10 pontos.',
                                ),
                        icon: const Icon(Icons.check),
                        label: const Text('Fui atendido'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: fila.ocupado ? null : () => executar(fila.desistir, 'Saída registrada.'),
                      child: const Text('Desisti'),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: fila.ocupado ? null : () => executar(fila.marcarSaida, 'Obrigado por colaborar.'),
                    icon: const Icon(Icons.logout),
                    label: const Text('Saí da unidade'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
