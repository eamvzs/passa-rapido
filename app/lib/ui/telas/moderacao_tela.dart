import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../core/tema.dart';
import '../../data/repositorios.dart';
import '../../models/colaboracao.dart';
import '../componentes/comuns.dart';

/// Fila da moderação: sugestões de correção e conteúdo denunciado. Só moderadores chegam aqui
/// (o banco recusa qualquer outra pessoa, mesmo que alguém abra a tela por outro caminho).
class ModeracaoTela extends StatefulWidget {
  const ModeracaoTela({super.key});

  @override
  State<ModeracaoTela> createState() => _ModeracaoTelaState();
}

class _ModeracaoTelaState extends State<ModeracaoTela> {
  late final ComunidadeRepositorio _comunidade = context.read<ComunidadeRepositorio>();
  late Future<(List<SugestaoPendente>, List<DenunciaPendente>)> _fila = _carregar();

  Future<(List<SugestaoPendente>, List<DenunciaPendente>)> _carregar() =>
      (_comunidade.listarSugestoesPendentes(), _comunidade.listarDenunciasPendentes()).wait;

  void _recarregar() => setState(() => _fila = _carregar());

  Future<void> _executar(Future<void> Function() acao, String sucesso) async {
    try {
      await acao();
      if (!mounted) return;
      mostrarMensagem(context, sucesso);
      _recarregar();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderação'),
        actions: [IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh_rounded), onPressed: _recarregar)],
      ),
      body: FutureBuilder<(List<SugestaoPendente>, List<DenunciaPendente>)>(
        future: _fila,
        builder: (context, resultado) {
          if (resultado.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(Espaco.g), child: Esqueleto(linhas: 5));
          }
          if (resultado.hasError) {
            return EstadoDeErro(mensagem: traduzirErro(resultado.error!).mensagem, aoTentarDeNovo: _recarregar);
          }
          final (sugestoes, denuncias) = resultado.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
            children: [
              LarguraMaxima(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Secao(
                      icone: Icons.edit_location_alt_rounded,
                      titulo: 'Sugestões de correção (${sugestoes.length})',
                      child: sugestoes.isEmpty
                          ? const EstadoVazio(icone: Icons.check_circle_outline_rounded, texto: 'Nenhuma sugestão pendente.')
                          : Column(
                              children: [
                                for (final s in sugestoes)
                                  _CartaoDeSugestao(
                                    sugestao: s,
                                    aoDecidir: (aceitar) => _executar(
                                      () => _comunidade.analisarSugestao(s.id, aceitar: aceitar),
                                      aceitar ? 'Sugestão aceita e aplicada.' : 'Sugestão recusada.',
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    Secao(
                      icone: Icons.flag_rounded,
                      titulo: 'Conteúdo denunciado (${denuncias.length})',
                      child: denuncias.isEmpty
                          ? const EstadoVazio(icone: Icons.check_circle_outline_rounded, texto: 'Nenhuma denúncia pendente.')
                          : Column(
                              children: [
                                for (final d in denuncias)
                                  Card(
                                    margin: const EdgeInsets.only(bottom: Espaco.p),
                                    child: Padding(
                                      padding: const EdgeInsets.all(Espaco.m),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${d.rotuloDoAlvo}${d.unidadeNome == null ? '' : ' em ${d.unidadeNome}'}',
                                            style: tema.textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(d.texto),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${d.denuncias} ${d.denuncias == 1 ? 'denúncia' : 'denúncias'} (${d.motivos})'
                                            '${d.oculto ? ' · já oculto do público' : ' · ainda visível'}',
                                            style: tema.textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: Espaco.p),
                                          Wrap(
                                            spacing: Espaco.p,
                                            children: [
                                              OutlinedButton(
                                                onPressed: () => _executar(
                                                  () => _comunidade.resolverDenuncia(d.alvo, d.alvoId, restaurar: false),
                                                  'Mantido oculto.',
                                                ),
                                                child: const Text('Manter oculto'),
                                              ),
                                              OutlinedButton(
                                                onPressed: () => _executar(
                                                  () => _comunidade.resolverDenuncia(d.alvo, d.alvoId, restaurar: true),
                                                  'Conteúdo restaurado.',
                                                ),
                                                child: const Text('Restaurar'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CartaoDeSugestao extends StatelessWidget {
  const _CartaoDeSugestao({required this.sugestao, required this.aoDecidir});

  final SugestaoPendente sugestao;
  final void Function(bool aceitar) aoDecidir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final s = sugestao;
    return Card(
      margin: const EdgeInsets.only(bottom: Espaco.p),
      child: Padding(
        padding: const EdgeInsets.all(Espaco.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.rotuloDoCampo} · ${s.unidadeNome}', style: tema.textTheme.titleSmall),
            Text(s.unidadeEndereco, style: tema.textTheme.bodySmall),
            const SizedBox(height: Espaco.p),
            Text(s.descricao),
            if (s.latitude != null && s.longitude != null)
              Text(
                'Ponto sugerido: ${s.latitude!.toStringAsFixed(5)}, ${s.longitude!.toStringAsFixed(5)}',
                style: tema.textTheme.bodySmall,
              ),
            Text(
              '${s.autor} · ${formatarHaQuantoTempo(s.criadoEm)}'
              '${s.apoios > 0 ? ' · ${s.apoios} ${s.apoios == 1 ? 'outra sugestão igual' : 'outras sugestões iguais'}' : ''}',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: Espaco.p),
            Wrap(
              spacing: Espaco.p,
              children: [
                FilledButton(onPressed: () => aoDecidir(true), child: const Text('Aceitar')),
                OutlinedButton(onPressed: () => aoDecidir(false), child: const Text('Recusar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
