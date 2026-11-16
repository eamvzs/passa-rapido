import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formatos.dart';
import '../../core/tema.dart';
import '../../data/repositorios.dart';
import '../../models/colaboracao.dart';
import '../componentes/comuns.dart';

/// Visão para a gestão pública: bairros e tipos de unidade com mais espera, horário de pico e quantas
/// unidades têm fila real. Números agregados; nenhum dado pessoal.
class GestaoTela extends StatefulWidget {
  const GestaoTela({super.key});

  @override
  State<GestaoTela> createState() => _GestaoTelaState();
}

class _GestaoTelaState extends State<GestaoTela> {
  late Future<List<RegiaoDaGestao>> _dados = context.read<UnidadeRepositorio>().regioes();
  String? _tipo;
  String _busca = '';

  void _recarregar() => setState(() => _dados = context.read<UnidadeRepositorio>().regioes());

  Future<void> _copiar(List<RegiaoDaGestao> linhas) async {
    await Clipboard.setData(ClipboardData(text: regioesParaCsv(linhas)));
    if (mounted) mostrarMensagem(context, 'Tabela copiada (${linhas.length} linhas). Cole em uma planilha.');
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Visão da gestão')),
      body: FutureBuilder<List<RegiaoDaGestao>>(
        future: _dados,
        builder: (context, resultado) {
          if (resultado.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(Espaco.g), child: Esqueleto(linhas: 6));
          }
          if (resultado.hasError) {
            return EstadoDeErro(mensagem: traduzirErro(resultado.error!).mensagem, aoTentarDeNovo: _recarregar);
          }
          final todas = resultado.data ?? const [];
          final tipos = {for (final r in todas) r.tipo}.toList()..sort();
          final termo = _busca.trim().toLowerCase();
          final linhas = todas
              .where((r) =>
                  (_tipo == null || r.tipo == _tipo) &&
                  (termo.isEmpty || r.bairro.toLowerCase().contains(termo)))
              .toList()
            ..sort((a, b) => (b.esperaMediaMin ?? -1).compareTo(a.esperaMediaMin ?? -1));
          final apenasEstimativa = linhas.isNotEmpty && linhas.every((r) => r.somenteEstimativa);

          return ListView(
            padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
            children: [
              LarguraMaxima(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Onde a espera é maior, por bairro e tipo de unidade. Dados agregados, sem identificar pessoas.',
                      style: tema.textTheme.bodyMedium,
                    ),
                    if (apenasEstimativa)
                      Padding(
                        padding: const EdgeInsets.only(top: Espaco.m),
                        child: Text(
                          'Atenção: nenhuma destas unidades tem fila informada agora. Os números são estimativas do '
                          'modelo (média histórica do dia e da hora), não medições.',
                          style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: Espaco.m),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar bairro',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setState(() => _busca = v),
                    ),
                    const SizedBox(height: Espaco.m),
                    Wrap(
                      spacing: Espaco.p,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _tipo == null,
                          onSelected: (_) => setState(() => _tipo = null),
                        ),
                        for (final t in tipos)
                          ChoiceChip(
                            label: Text(t),
                            selected: _tipo == t,
                            onSelected: (_) => setState(() => _tipo = _tipo == t ? null : t),
                          ),
                      ],
                    ),
                    const SizedBox(height: Espaco.m),
                    Row(
                      children: [
                        Expanded(child: Text('${linhas.length} regiões', style: tema.textTheme.titleSmall)),
                        OutlinedButton.icon(
                          onPressed: linhas.isEmpty ? null : () => _copiar(linhas),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copiar tabela'),
                        ),
                      ],
                    ),
                    const SizedBox(height: Espaco.p),
                    if (linhas.isEmpty)
                      const EstadoVazio(icone: Icons.search_off_rounded, texto: 'Nenhuma região com esse filtro.')
                    else
                      for (final r in linhas.take(80)) _LinhaDeRegiao(regiao: r),
                    if (linhas.length > 80)
                      Padding(
                        padding: const EdgeInsets.only(top: Espaco.m),
                        child: Text('Mostrando 80 de ${linhas.length}. Use a busca ou copie a tabela completa.',
                            style: tema.textTheme.bodySmall),
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

class _LinhaDeRegiao extends StatelessWidget {
  const _LinhaDeRegiao({required this.regiao});

  final RegiaoDaGestao regiao;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final r = regiao;
    return Card(
      margin: const EdgeInsets.only(bottom: Espaco.p),
      child: Padding(
        padding: const EdgeInsets.all(Espaco.m),
        child: Semantics(
          label: '${r.bairro}, ${r.tipo}. ${r.unidades} unidades, ${r.abertasAgora} abertas. '
              '${r.esperaMediaMin == null ? 'Sem espera conhecida' : 'Espera média ${r.esperaMediaMin} minutos'}'
              '${r.somenteEstimativa ? ', estimativa do modelo' : ''}.',
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.bairro} · ${r.tipo}', style: tema.textTheme.titleSmall),
                    Text(
                      '${r.unidades} ${r.unidades == 1 ? 'unidade' : 'unidades'} · ${r.abertasAgora} abertas agora'
                      '${r.horaPico == null ? '' : ' · pico às ${r.horaPico}h (~${formatarEspera(r.esperaPicoMin)})'}',
                      style: tema.textTheme.bodySmall,
                    ),
                    if (r.unidadesComFilaReal > 0)
                      Text('${r.unidadesComFilaReal} com fila informada · ${r.registros7Dias} registros em 7 dias',
                          style: tema.textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    r.esperaMediaMin == null ? '—' : '${r.somenteEstimativa ? '~' : ''}${formatarEspera(r.esperaMediaMin)}',
                    style: tema.textTheme.titleMedium,
                  ),
                  Text(r.somenteEstimativa ? 'estimativa' : 'média agora', style: tema.textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
