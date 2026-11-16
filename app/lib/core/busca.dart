/// Busca de unidades por texto: cada palavra digitada precisa aparecer no nome, no bairro, no endereço
/// ou no tipo. Assim "ubs itaquera" acha "Unidade Básica de Saúde Itaquera" (tipo UBS, bairro/nome Itaquera)
/// e "itaquera ubs" dá o mesmo resultado, em qualquer ordem e sem depender de acentos ou maiúsculas.
library;

/// Texto sem acentos, em minúsculas e com espaços simples, para comparar.
String normalizarParaBusca(String texto) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final saida = StringBuffer();
  for (final letra in texto.toLowerCase().trim().split('')) {
    final i = de.indexOf(letra);
    saida.write(i == -1 ? letra : para[i]);
  }
  return saida.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Palavras da busca, já normalizadas. Lista vazia quando não há o que filtrar.
List<String> palavrasDaBusca(String busca) =>
    normalizarParaBusca(busca).split(' ').where((p) => p.isNotEmpty).toList(growable: false);

/// Verdadeiro quando todas as [palavras] aparecem no [textoDaUnidade] (já normalizado).
bool combinaComBusca(String textoDaUnidade, List<String> palavras) => palavras.every(textoDaUnidade.contains);

/// Texto pesquisável de uma unidade, normalizado uma vez.
String textoPesquisavel({required String nome, String? bairro, required String tipo, String? endereco}) =>
    normalizarParaBusca('$nome ${bairro ?? ''} $tipo ${endereco ?? ''}');
