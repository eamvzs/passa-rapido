import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../core/nivel_espera.dart';
import '../../core/tema.dart';
import '../../data/repositorios.dart';
import '../../models/unidade.dart';
import '../../state/controladores.dart';

IconData iconeDoTipo(String tipo) => switch (tipo) {
      'UPA' => Icons.emergency_rounded,
      'Pronto-socorro' => Icons.local_hospital_rounded,
      'UBS' => Icons.medical_services_rounded,
      'Poupatempo' => Icons.badge_rounded,
      'INSS' => Icons.account_balance_rounded,
      'CRAS' => Icons.diversity_3_rounded,
      _ => Icons.place_rounded,
    };

/// Símbolo do app: pino de localização (a unidade) com o avanço rápido (passa rápido) sobre o azul da marca.
/// Desenhado em vetor, com as mesmas coordenadas de `docs/marca/logo-icone.svg`.
class LogoPassaRapido extends StatelessWidget {
  const LogoPassaRapido({super.key, this.tamanho = 56});

  final double tamanho;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Passa Rápido',
        image: true,
        excludeSemantics: true,
        child: SizedBox(
          width: tamanho,
          height: tamanho,
          child: CustomPaint(
            painter: _PintorDaLogo(
              IdentidadeVisual.de(context).heroInicio,
              IdentidadeVisual.de(context).heroFim,
            ),
          ),
        ),
      );
}

class _PintorDaLogo extends CustomPainter {
  const _PintorDaLogo(this.inicio, this.fim);

  final Color inicio;
  final Color fim;

  /// O disco do pino fica entre as duas pontas do degradê, para a logo acompanhar o estilo escolhido.
  Color get disco => Color.lerp(inicio, fim, 0.3)!;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    const caixa = Rect.fromLTWH(0, 0, 100, 100);
    final fundo = RRect.fromRectAndRadius(caixa, const Radius.circular(24));
    canvas.drawRRect(
      fundo,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(inicio, Colors.white, 0.18)!, fim],
        ).createShader(caixa),
    );
    canvas.save();
    canvas.clipRRect(fundo);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 50),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 50)),
    );
    canvas.restore();

    final linhas = Paint()
      ..color = const Color(0x73FFFFFF)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(9, 38), const Offset(19, 38), linhas);
    canvas.drawLine(const Offset(6, 48), const Offset(17, 48), linhas);
    canvas.drawLine(const Offset(10, 58), const Offset(20, 58), linhas);

    final pino = Path()
      ..moveTo(54, 88)
      ..cubicTo(54, 88, 28, 64, 28, 45)
      ..arcToPoint(const Offset(80, 45), radius: const Radius.circular(26))
      ..cubicTo(80, 64, 54, 88, 54, 88)
      ..close();
    canvas.drawPath(pino, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(54, 45), 17.5, Paint()..color = disco);

    final avanco = Path()
      ..moveTo(46, 35)
      ..lineTo(55.5, 45)
      ..lineTo(46, 55)
      ..moveTo(56.5, 35)
      ..lineTo(66, 45)
      ..lineTo(56.5, 55);
    canvas.drawPath(
      avanco,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PintorDaLogo antigo) => antigo.inicio != inicio || antigo.fim != fim;
}

void mostrarMensagem(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Confirmação de uma ação bem-sucedida, com os pontos ganhos em destaque.
void mostrarSucesso(BuildContext context, String texto, {int? pontos}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80)),
            const SizedBox(width: Espaco.m),
            Expanded(child: Text(texto)),
            if (pontos != null)
              Container(
                margin: const EdgeInsets.only(left: Espaco.p),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4ADE80),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '+$pontos pts',
                  style: const TextStyle(color: Color(0xFF052E16), fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
}

void mostrarErro(BuildContext context, Object erro) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8A80)),
            const SizedBox(width: Espaco.m),
            Expanded(child: Text(traduzirErro(erro).mensagem)),
          ],
        ),
      ),
    );
}

/// Abre a ficha de uma unidade por rota nomeada: a URL muda e o botão voltar do navegador funciona.
void abrirUnidade(BuildContext context, int unidadeId) =>
    Navigator.of(context).pushNamed('/unidade/$unidadeId');

/// Abre a tela de login quando a ação exige conta. Devolve verdadeiro se há sessão ao final.
Future<bool> garantirLogin(BuildContext context) async {
  final sessao = context.read<SessaoControlador>();
  if (sessao.autenticado) return true;
  await Navigator.of(context).pushNamed('/entrar');
  return sessao.autenticado;
}

/// Erro mostrado junto do formulário, anunciado pelo leitor de tela e sem sumir sozinho.
class CaixaDeErro extends StatelessWidget {
  const CaixaDeErro({super.key, required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: Espaco.m),
        padding: const EdgeInsets.all(Espaco.m),
        decoration: BoxDecoration(
          color: tema.colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tema.colorScheme.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: tema.colorScheme.error),
            const SizedBox(width: Espaco.m),
            Expanded(child: Text(mensagem, style: tema.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// Abre a folha de avaliação e grava a nota. Devolve verdadeiro se a pessoa avaliou.
Future<bool> pedirAvaliacao(BuildContext context, {required int unidadeId, String? nomeUnidade}) async {
  final dados = await showModalBottomSheet<(int, String)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FolhaDeAvaliacao(nomeUnidade: nomeUnidade),
  );
  if (dados == null || !context.mounted) return false;
  try {
    await context.read<ComunidadeRepositorio>().avaliar(unidadeId: unidadeId, nota: dados.$1, comentario: dados.$2);
    if (!context.mounted) return false;
    mostrarSucesso(context, 'Obrigado pela avaliação!');
    await context.read<SessaoControlador>().recarregarPerfil();
    return true;
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
    return false;
  }
}

class FolhaDeAvaliacao extends StatefulWidget {
  const FolhaDeAvaliacao({super.key, this.nomeUnidade});

  final String? nomeUnidade;

  @override
  State<FolhaDeAvaliacao> createState() => _FolhaDeAvaliacaoState();
}

class _FolhaDeAvaliacaoState extends State<FolhaDeAvaliacao> {
  final _comentario = TextEditingController();
  int _nota = 5;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Como foi o atendimento?', style: Theme.of(context).textTheme.titleLarge),
              if (widget.nomeUnidade != null) Text(widget.nomeUnidade!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: 'Nota $i',
                      iconSize: 40,
                      icon: Icon(i <= _nota ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF2B01E)),
                      onPressed: () => setState(() => _nota = i),
                    ),
                ],
              ),
              TextField(
                controller: _comentario,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Comentário (opcional)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((_nota, _comentario.text)),
                child: const Text('Salvar avaliação'),
              ),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Agora não')),
            ],
          ),
        ),
      );
}

/// Centraliza e limita a largura do conteúdo em telas largas.
class LarguraMaxima extends StatelessWidget {
  const LarguraMaxima({super.key, required this.child, this.ajustarAltura = false});

  final Widget child;

  /// Verdadeiro quando o pai dá altura livre (barras de rodapé): ocupa só a altura do conteúdo.
  final bool ajustarAltura;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: ajustarAltura ? 1 : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: larguraMaximaDoConteudo),
          child: child,
        ),
      );
}

/// Etiqueta colorida com o tempo de espera. O texto acompanha a cor para não depender só dela.
class SeloEspera extends StatelessWidget {
  const SeloEspera({
    super.key,
    required NivelEspera nivel,
    required int? minutos,
    this.fechada = false,
  })  : nivel = fechada ? NivelEspera.semDados : nivel,
        minutos = fechada ? null : minutos;

  final NivelEspera nivel;
  final int? minutos;

  /// Unidade fora do horário de funcionamento: mostra "Fechada" no lugar da espera.
  final bool fechada;

  @override
  Widget build(BuildContext context) => Semantics(
        label: fechada ? 'Fechada agora' : '${nivel.rotulo}, espera de ${formatarEspera(minutos)}',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: nivel.cor, borderRadius: BorderRadius.circular(24)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fechada ? Icons.lock_clock_rounded : nivel.icone, size: 16, color: nivel.corDoTexto),
              const SizedBox(width: 6),
              Text(
                fechada ? 'Fechada' : formatarEspera(minutos),
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: nivel.corDoTexto, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
}

/// Bloco compacto de espera para listas: número grande e unidade embaixo.
class BlocoEspera extends StatelessWidget {
  const BlocoEspera({super.key, required this.unidade});

  final Unidade unidade;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final fechada = !unidade.abertaAgora;
    final nivel = fechada ? NivelEspera.semDados : unidade.nivel;
    final cor = nivel.corSobreSuperficie(tema.brightness);
    final minutos = unidade.esperaMin;

    final estimada = unidade.estimada && !fechada && minutos != null;
    final (String principal, String secundario) = fechada
        ? ('Fechada', 'agora')
        : minutos == null
            ? ('—', 'sem dados')
            : minutos < 60
                ? ('${estimada ? '~' : ''}$minutos', estimada ? 'min · est.' : 'min')
                : (
                    '${estimada ? '~' : ''}${(minutos / 60).toStringAsFixed(1).replaceAll('.', ',')}',
                    estimada ? 'h · est.' : 'horas',
                  );

    return Semantics(
      label: fechada
          ? 'Fechada agora'
          : estimada
              ? 'Estimativa: ${nivel.rotulo.toLowerCase()}, espera típica de ${formatarEspera(minutos)}'
              : '${nivel.rotulo}, espera de ${formatarEspera(minutos)}',
      excludeSemantics: true,
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: nivel.fundoSuave(tema.brightness),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                principal,
                style: (fechada ? tema.textTheme.labelLarge : tema.textTheme.headlineSmall)
                    ?.copyWith(color: cor, fontWeight: FontWeight.w800, height: 1.1),
              ),
            ),
            Text(secundario, style: tema.textTheme.labelSmall?.copyWith(color: cor)),
          ],
        ),
      ),
    );
  }
}

/// Cartão de lista com os dados principais da unidade.
class UnidadeCartao extends StatelessWidget {
  const UnidadeCartao({super.key, required this.unidade, required this.aoTocar, this.distanciaKm});

  final Unidade unidade;
  final VoidCallback aoTocar;
  final double? distanciaKm;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final detalhes = [
      unidade.tipo,
      ?unidade.bairro,
      if (distanciaKm != null) formatarDistancia(distanciaKm),
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.all(Espaco.m),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tema.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconeDoTipo(unidade.tipo), color: tema.colorScheme.primary),
              ),
              const SizedBox(width: Espaco.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unidade.nome, style: tema.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(detalhes, style: tema.textTheme.bodySmall),
                    if (unidade.relatosAtivos > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.campaign_rounded, size: 16, color: tema.colorScheme.error),
                            const SizedBox(width: 4),
                            Text(
                              unidade.relatosAtivos == 1 ? '1 aviso ativo' : '${unidade.relatosAtivos} avisos ativos',
                              style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Espaco.p),
              BlocoEspera(unidade: unidade),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de seção com ícone, título e ação opcional no cabeçalho.
class Secao extends StatelessWidget {
  const Secao({super.key, required this.icone, required this.titulo, required this.child, this.acao});

  final IconData icone;
  final String titulo;
  final Widget child;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Espaco.g),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.m, Espaco.g, Espaco.g),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Icon(icone, size: 22, color: tema.colorScheme.primary),
                    const SizedBox(width: Espaco.p),
                    Expanded(
                      child: Semantics(header: true, child: Text(titulo, style: tema.textTheme.titleMedium)),
                    ),
                    ?acao,
                  ],
                ),
              ),
              const SizedBox(height: Espaco.pp),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class EstadoVazio extends StatelessWidget {
  const EstadoVazio({super.key, required this.icone, required this.texto, this.titulo});

  final IconData icone;
  final String texto;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaco.p),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tema.colorScheme.onSurface.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icone, size: 20, color: tema.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: Espaco.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titulo != null) Text(titulo!, style: tema.textTheme.titleSmall),
                Text(texto, style: tema.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EstadoDeErro extends StatelessWidget {
  const EstadoDeErro({super.key, required this.mensagem, required this.aoTentarDeNovo});

  final String mensagem;
  final VoidCallback aoTentarDeNovo;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Espaco.gg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: Espaco.m),
              Text('Não deu para carregar', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Espaco.pp),
              Text(mensagem, textAlign: TextAlign.center),
              const SizedBox(height: Espaco.g),
              FilledButton.icon(
                onPressed: aoTentarDeNovo,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
}

/// Blocos cinza no lugar do conteúdo enquanto os dados chegam.
class Esqueleto extends StatelessWidget {
  const Esqueleto({super.key, this.linhas = 3});

  final int linhas;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07);
    return ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < linhas; i++)
            Container(
              height: 18,
              margin: EdgeInsets.only(bottom: Espaco.m, right: i.isOdd ? 80 : 0),
              decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(6)),
            ),
        ],
      ),
    );
  }
}

/// Cartão fixo enquanto o usuário está em uma fila, com cronômetro e as ações do momento.
class FaixaFilaAtiva extends StatelessWidget {
  const FaixaFilaAtiva({super.key, this.margem = EdgeInsets.zero});

  final EdgeInsets margem;

  @override
  Widget build(BuildContext context) {
    final fila = context.watch<FilaControlador>();
    final registro = fila.ativo;
    if (registro == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final sessao = context.read<SessaoControlador>();

    Future<void> executar(Future<void> Function() acao, String sucesso, {int? pontos}) async {
      try {
        await acao();
        await sessao.recarregarPerfil();
        if (context.mounted) mostrarSucesso(context, sucesso, pontos: pontos);
      } catch (e) {
        if (context.mounted) mostrarErro(context, e);
      }
    }

    return Padding(
      padding: margem,
      child: Container(
        decoration: BoxDecoration(
          color: tema.colorScheme.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(Espaco.g),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  registro.aguardando ? Icons.hourglass_top_rounded : Icons.medical_information_rounded,
                  color: tema.colorScheme.onPrimary,
                ),
                const SizedBox(width: Espaco.p),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        registro.aguardando ? 'Você está na fila' : 'Você foi atendido',
                        style: tema.textTheme.labelMedium?.copyWith(
                          color: tema.colorScheme.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                      Text(
                        registro.nomeUnidade ?? '',
                        style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.onPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (registro.aguardando)
                  _Cronometro(desde: registro.chegadaEm, cor: tema.colorScheme.onPrimary)
                else
                  Text(
                    formatarEspera(registro.esperaRealMin),
                    style: tema.textTheme.titleLarge?.copyWith(color: tema.colorScheme.onPrimary),
                  ),
              ],
            ),
            const SizedBox(height: Espaco.m),
            if (registro.aguardando)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: tema.colorScheme.onPrimary,
                        foregroundColor: tema.colorScheme.primary,
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: fila.ocupado
                          ? null
                          : () => executar(
                                () async {
                                  await fila.marcarAtendido();
                                },
                                'Atendimento registrado. Obrigado!',
                                pontos: 10,
                              ),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Fui atendido'),
                    ),
                  ),
                  const SizedBox(width: Espaco.p),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: tema.colorScheme.onPrimary,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: fila.ocupado ? null : () => executar(fila.desistir, 'Saída registrada.'),
                    child: const Text('Desisti'),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: tema.colorScheme.onPrimary,
                    foregroundColor: tema.colorScheme.primary,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: fila.ocupado
                      ? null
                      : () async {
                          final unidadeId = registro.unidadeId;
                          final nome = registro.nomeUnidade;
                          await executar(fila.marcarSaida, 'Atendimento concluído.');
                          if (context.mounted) await pedirAvaliacao(context, unidadeId: unidadeId, nomeUnidade: nome);
                        },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Saí da unidade'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tempo decorrido desde a chegada, atualizado a cada 30 segundos.
class _Cronometro extends StatelessWidget {
  const _Cronometro({required this.desde, required this.cor});

  final DateTime desde;
  final Color cor;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: Stream.periodic(const Duration(seconds: 30), (i) => i),
        builder: (context, _) {
          final minutos = DateTime.now().difference(desde).inMinutes.clamp(0, 9999);
          return Semantics(
            label: 'Esperando há ${formatarEspera(minutos)}',
            excludeSemantics: true,
            child: Text(
              formatarEspera(minutos),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: cor),
            ),
          );
        },
      );
}


/// Entrada suave de um item de lista (esmaece e sobe 12 px). Respeita "reduzir movimento" do sistema
/// e só anima os primeiros itens, para a rolagem longa não ficar piscando.
class EntradaSuave extends StatelessWidget {
  const EntradaSuave({super.key, required this.indice, required this.child});

  final int indice;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (indice >= 10 || MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + indice * 45),
      curve: Curves.easeOutCubic,
      builder: (context, t, filho) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: filho),
      ),
      child: child,
    );
  }
}
