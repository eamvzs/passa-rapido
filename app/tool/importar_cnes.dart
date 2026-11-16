// Importador de unidades de saúde do CNES (DATASUS) para o Passa Rápido.
//
// O CNES (Cadastro Nacional de Estabelecimentos de Saúde, Ministério da Saúde) é a base oficial:
// tem todas as UBS, UPAs e prontos-socorros cadastrados, bem mais completa que o OpenStreetMap.
// Este script baixa os estabelecimentos do município de São Paulo pela API de dados abertos
// e gera o SQL `10_unidades_cnes.sql`, para colar no SQL Editor do Supabase.
//
// Script Dart puro (só dart:io, dart:convert e dart:math), sem dependências.
//
//   dart run importar_cnes.dart                          baixa da API e gera o SQL
//   dart run importar_cnes.dart --entrada resp.json      usa um JSON já baixado (repita a opção)
//   dart run importar_cnes.dart --saida caminho.sql --pausa 300 --tentativas 4
//
// Tipos importados (campo codigo_tipo_unidade do CNES):
//   2  Centro de Saúde / Unidade Básica   -> UBS
//   73 Pronto Atendimento                 -> UPA
//   20 Pronto Socorro Geral               -> Pronto-socorro
//   21 Pronto Socorro Especializado       -> Pronto-socorro
// INSS, Poupatempo e CRAS não são estabelecimentos de saúde e continuam vindo do OpenStreetMap.
//
// Reclassificação pelo nome (o tipo 73 do CNES mistura UPA, AMA e pronto-atendimento municipal):
//   - nome começando com "UPA" ou "Unidade de Pronto Atendimento"  -> UPA
//   - nome começando com "AMA" (Assistência Médica Ambulatorial)    -> UBS (como no cadastro do OpenStreetMap)
//   - os demais do tipo 73 (por exemplo "PA Mun ...")               -> Pronto-socorro
//   - "AMA 24H" e "AMA 12H": o próprio nome informa o horário (24 h ou 7h às 19h, todos os dias).
//
// Regras de limpeza (cada descarte é contado no resumo):
//   - estabelecimento desabilitado (codigo_motivo_desabilitacao preenchido);
//   - sem nome; sem coordenada, coordenada zerada ou fora da região de São Paulo;
//   - privado e que não atende pelo SUS (natureza jurídica fora da administração pública e sem SUS);
//   - fora do escopo (presídio e centro de detenção, comando militar, atenção domiciliar, unidade socioeducativa);
//   - mesmo nome a menos de 60 m (cadastro repetido);
//   - mesmo código CNES repetido.
//
// Identificador estável: unidade.cnes_id (bigint, único) = codigo_cnes.
// O SQL gerado também desativa as unidades do OpenStreetMap que o CNES já cobre (mesmo tipo, até 150 m).
//
// Fonte: CNES/DATASUS, Ministério da Saúde (dados abertos), apidadosabertos.saude.gov.br.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _versao = '1.0';
const _userAgent = 'PassaRapido-Importador/$_versao (projeto academico FIAP)';
const _urlPadrao = 'https://apidadosabertos.saude.gov.br/cnes/estabelecimentos';
const _municipioSp = 355030; // código IBGE de 6 dígitos usado pelo CNES
const _distanciaDuplicadoMetros = 60.0;
const _linhasPorInsert = 100;
const _enderecoVazio = 'Endereço não informado no CNES';

// Mesma caixa do importador do OpenStreetMap: município de São Paulo com folga.
const _latMin = -24.10, _latMax = -23.30, _lonMin = -47.00, _lonMax = -46.20;

/// Código CNES do tipo de unidade -> nome do tipo no Passa Rápido.
const _tiposCnes = <int, String>{2: 'UBS', 73: 'UPA', 20: 'Pronto-socorro', 21: 'Pronto-socorro'};
const _ordemSaida = ['UPA', 'Pronto-socorro', 'UBS'];

class _Opcoes {
  final entradas = <String>[];
  String url = _urlPadrao;
  String? saida;
  int municipio = _municipioSp;
  int pagina = 20; // registros pedidos por requisição (a API pode devolver menos)
  int pausaMs = 300;
  int tentativas = 4;
  int maxPaginas = 3000; // trava de segurança por tipo
  int limiteKb = 400;
  int linhasPorInsert = _linhasPorInsert;
  bool ajuda = false;
}

class _Candidato {
  _Candidato({
    required this.cnesId,
    required this.tipo,
    required this.nome,
    required this.endereco,
    required this.bairro,
    required this.telefone,
    required this.latitude,
    required this.longitude,
    this.horas,
  });

  /// Horário que o nome informa: '24h' (todos os dias, 24 horas) ou '12h' (todos os dias, 7h às 19h).
  final String? horas;
  final int cnesId;
  final String tipo;
  final String nome;
  final String endereco;
  final String? bairro;
  final String? telefone;
  final double latitude;
  final double longitude;
  late final String nomeNormalizado = _normalizar(nome);
}

class _Relatorio {
  final importados = <String, int>{for (final t in _ordemSaida) t: 0};
  final duplicadoProximo = <String, int>{for (final t in _ordemSaida) t: 0};
  int recebidos = 0;
  int tipoIgnorado = 0;
  int outroMunicipio = 0;
  int desabilitado = 0;
  int privadoSemSus = 0;
  int foraDoEscopo = 0;
  int semNome = 0;
  int semCoordenadas = 0;
  int foraDoMunicipio = 0;
  int duplicadoId = 0;
}

Future<void> main(List<String> args) async {
  final opcoes = _lerArgumentos(args);
  if (opcoes.ajuda) {
    stdout.writeln(_textoAjuda);
    return;
  }

  final saida = opcoes.saida ?? '10_unidades_cnes.sql';
  final registros = <Map<String, dynamic>>[];

  if (opcoes.entradas.isNotEmpty) {
    for (final caminho in opcoes.entradas) {
      final arquivo = File(caminho);
      if (!arquivo.existsSync()) {
        stderr.writeln('Arquivo de entrada não encontrado: $caminho');
        exit(1);
      }
      stdout.writeln('Lendo $caminho ...');
      registros.addAll(_extrairRegistros(await arquivo.readAsString(), caminho));
    }
  } else {
    var primeiro = true;
    for (final codigo in _tiposCnes.keys) {
      if (!primeiro && opcoes.pausaMs > 0) await Future<void>.delayed(Duration(milliseconds: opcoes.pausaMs));
      primeiro = false;
      stdout.writeln('Baixando tipo $codigo (${_tiposCnes[codigo]}) ...');
      final lista = await _baixarTipo(codigo, opcoes);
      stdout.writeln('  ${lista.length} estabelecimentos recebidos');
      registros.addAll(lista);
    }
  }

  if (registros.isEmpty) {
    stderr.writeln('\nNenhum estabelecimento recebido: o SQL não foi gerado.');
    exit(2);
  }

  final relatorio = _Relatorio();
  final unidades = _processar(registros, relatorio, opcoes.municipio);
  if (unidades.isEmpty) {
    stderr.writeln('\nNenhuma unidade válida após a limpeza: o SQL não foi gerado.');
    _imprimirResumo(relatorio);
    exit(2);
  }

  final arquivos = _gerarSql(unidades, relatorio, saida, opcoes.limiteKb, opcoes.linhasPorInsert);
  _imprimirResumo(relatorio);
  stdout.writeln('\nArquivos gerados:');
  for (final a in arquivos) {
    stdout.writeln('  ${a.path}  (${(a.lengthSync() / 1024).toStringAsFixed(1)} KB)');
  }
  if (arquivos.length > 1) {
    stdout.writeln('\nO SQL passou do limite de ${opcoes.limiteKb} KB e foi dividido: cole as partes em ordem.');
  }
}

// ---------------------------------------------------------------------------------------------
// Argumentos

_Opcoes _lerArgumentos(List<String> args) {
  final o = _Opcoes();
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String valor() {
      if (i + 1 >= args.length) {
        stderr.writeln('A opção $a precisa de um valor.');
        exit(64);
      }
      return args[++i];
    }

    switch (a) {
      case '--entrada':
        o.entradas.add(valor());
      case '--url':
        o.url = valor();
      case '--saida':
        o.saida = valor();
      case '--municipio':
        o.municipio = int.parse(valor());
      case '--pagina':
        o.pagina = int.parse(valor());
      case '--pausa':
        o.pausaMs = int.parse(valor());
      case '--tentativas':
        o.tentativas = int.parse(valor());
      case '--max-paginas':
        o.maxPaginas = int.parse(valor());
      case '--limite-kb':
        o.limiteKb = int.parse(valor());
      case '--linhas-por-insert':
        o.linhasPorInsert = int.parse(valor());
      case '--ajuda' || '-h' || '--help':
        o.ajuda = true;
      default:
        stderr.writeln('Opção desconhecida: $a (use --ajuda)');
        exit(64);
    }
  }
  return o;
}

const _textoAjuda = '''
Importador de unidades de saúde (CNES/DATASUS) do Passa Rápido.

  dart run importar_cnes.dart [opções]

  --entrada ARQ     usa um JSON já baixado (repita a opção para vários arquivos)
  --url URL         endereço da API (padrão: $_urlPadrao)
  --saida ARQ       arquivo SQL de saída (padrão: 10_unidades_cnes.sql)
  --municipio N     código do município com 6 dígitos (padrão: $_municipioSp, São Paulo)
  --pagina N        registros por requisição (padrão: 20)
  --pausa MS        pausa entre requisições, em milissegundos (padrão: 300)
  --tentativas N    tentativas por requisição (padrão: 4)
  --max-paginas N   trava de segurança de páginas por tipo (padrão: 3000)
  --limite-kb N     divide o SQL em partes acima deste tamanho (padrão: 400)
  --linhas-por-insert N  unidades por comando insert (padrão: $_linhasPorInsert)
''';

// ---------------------------------------------------------------------------------------------
// Rede

/// Baixa todas as páginas de um tipo de unidade. Falha (saída 2) se a API ignorar o filtro de tipo,
/// para não varrer o cadastro inteiro por engano.
///
/// O parâmetro `offset` da API pode contar REGISTROS (pula N registros) ou PÁGINAS (a página número N).
/// O importador descobre qual é comparando as páginas 0 e 1: se a página 1 repete registros da 0, o offset
/// conta registros; se traz (quase) só registros novos, conta páginas.
Future<List<Map<String, dynamic>>> _baixarTipo(int codigo, _Opcoes opcoes) async {
  Future<List<Map<String, dynamic>>> pedir(int offset) async {
    final uri = Uri.parse(opcoes.url).replace(queryParameters: {
      'codigo_municipio': '${opcoes.municipio}',
      'codigo_tipo_unidade': '$codigo',
      'limit': '${opcoes.pagina}',
      'offset': '$offset',
    });
    final lista = _extrairRegistros(await _baixar(uri, opcoes), uri.toString());
    if (lista.any((e) => _inteiro(e['codigo_tipo_unidade']) != codigo)) {
      stderr.writeln('\nA API ignorou o filtro codigo_tipo_unidade=$codigo (devolveu outros tipos).');
      stderr.writeln('Para não baixar o cadastro inteiro, o importador parou. Me envie esta mensagem.');
      exit(2);
    }
    if (opcoes.pausaMs > 0) await Future<void>.delayed(Duration(milliseconds: opcoes.pausaMs));
    return lista;
  }

  Set<Object?> ids(List<Map<String, dynamic>> l) => {for (final e in l) e['codigo_cnes']};

  final primeira = await pedir(0);
  if (primeira.isEmpty) return [];
  final segunda = await pedir(1);
  if (segunda.isEmpty) return primeira; // só uma página (se o offset contasse registros, a segunda viria com dados)

  final idsDaPrimeira = ids(primeira);
  final repetidos = ids(segunda).where(idsDaPrimeira.contains).length;
  // Se o offset contasse registros, a página 1 repetiria quase tudo da página 0 (todos menos um).
  // Um código repetido por acaso no cadastro não pode enganar a detecção: exige-se a metade ou mais.
  final menor = math.min(primeira.length, segunda.length);
  final porPagina = repetidos * 2 < menor;
  stdout.writeln('  paginação da API: offset conta ${porPagina ? 'páginas' : 'registros'}');

  final todos = <Map<String, dynamic>>[...primeira];
  var anterior = primeira;
  var offset = 0;
  if (porPagina) {
    todos.addAll(segunda);
    anterior = segunda;
    offset = 1;
  } else {
    offset = primeira.length;
  }

  for (var n = 2; n <= opcoes.maxPaginas; n++) {
    offset = porPagina ? offset + 1 : offset;
    final lista = await pedir(offset);
    if (lista.isEmpty) return todos;
    if (lista.first['codigo_cnes'] != null && lista.first['codigo_cnes'] == anterior.first['codigo_cnes']) {
      stderr.writeln('\nA API repetiu a mesma página (o parâmetro offset pode ser ignorado). Parando este tipo.');
      return todos;
    }
    todos.addAll(lista);
    anterior = lista;
    if (!porPagina) offset += lista.length;
    if (n % 20 == 0) stdout.writeln('  ... ${todos.length}');
  }
  stderr.writeln('  AVISO: chegou ao limite de ${opcoes.maxPaginas} páginas para o tipo $codigo; pode estar incompleto.');
  return todos;
}

Future<String> _baixar(Uri uri, _Opcoes opcoes) async {
  Object? ultimoErro;
  for (var tentativa = 1; tentativa <= opcoes.tentativas; tentativa++) {
    final cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent = _userAgent;
    try {
      final req = await cliente.getUrl(uri).timeout(const Duration(seconds: 30));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(const Duration(minutes: 2));
      final corpo = await resp.transform(utf8.decoder).join().timeout(const Duration(minutes: 2));
      if (resp.statusCode == 200) return corpo;
      throw HttpException('HTTP ${resp.statusCode}', uri: uri);
    } catch (e) {
      ultimoErro = e;
      stderr.writeln('  tentativa $tentativa/${opcoes.tentativas}: $e');
      if (tentativa < opcoes.tentativas) await Future<void>.delayed(Duration(seconds: 2 * tentativa));
    } finally {
      cliente.close(force: true);
    }
  }
  stderr.writeln('\nA API do CNES não respondeu (último erro: $ultimoErro). Tente de novo mais tarde.');
  exit(2);
}

/// A resposta é {"estabelecimentos": [...]}; aceita também uma lista pura.
List<Map<String, dynamic>> _extrairRegistros(String corpo, String origem) {
  final Object? json;
  try {
    json = jsonDecode(corpo);
  } on FormatException catch (e) {
    stderr.writeln('Resposta de $origem não é JSON válido: ${e.message}');
    exit(1);
  }
  final lista = json is Map ? json['estabelecimentos'] : json;
  if (lista is! List) {
    stderr.writeln('Resposta de $origem sem a lista "estabelecimentos".');
    exit(1);
  }
  return lista.whereType<Map<String, dynamic>>().toList();
}

// ---------------------------------------------------------------------------------------------
// Limpeza

List<_Candidato> _processar(List<Map<String, dynamic>> registros, _Relatorio r, int municipio) {
  r.recebidos = registros.length;
  final vistos = <int>{};
  final porTipo = <String, List<_Candidato>>{for (final t in _ordemSaida) t: []};

  for (final e in registros) {
    final codigoTipo = _inteiro(e['codigo_tipo_unidade']);
    final tipoPadrao = _tiposCnes[codigoTipo];
    if (tipoPadrao == null) {
      r.tipoIgnorado++;
      continue;
    }
    final cnesId = _inteiro(e['codigo_cnes']);
    if (cnesId == null) continue;
    final cod = _inteiro(e['codigo_municipio']);
    if (cod != null && cod != municipio) {
      r.outroMunicipio++;
      continue;
    }
    if (!vistos.add(cnesId)) {
      r.duplicadoId++;
      continue;
    }
    if (_desabilitado(e['codigo_motivo_desabilitacao_estabelecimento'])) {
      r.desabilitado++;
      continue;
    }
    if (!_atendePublico(e)) {
      r.privadoSemSus++;
      continue;
    }
    final nomeBruto = _texto(e['nome_fantasia']) ?? _texto(e['nome_razao_social']);
    final nome = _nomeProprio(_expandirAbreviacao(nomeBruto));
    if (nome == null) {
      r.semNome++;
      continue;
    }
    if (_foraDoEscopo(nome)) {
      r.foraDoEscopo++;
      continue;
    }
    final tipo = codigoTipo == 73 ? _tipoDoProntoAtendimento(nome) : tipoPadrao;
    final horas = _horasDoNome(nome);
    final lat = _decimal(e['latitude_estabelecimento_decimo_grau']);
    final lon = _decimal(e['longitude_estabelecimento_decimo_grau']);
    if (lat == null || lon == null || (lat == 0 && lon == 0)) {
      r.semCoordenadas++;
      continue;
    }
    if (lat < _latMin || lat > _latMax || lon < _lonMin || lon > _lonMax) {
      r.foraDoMunicipio++;
      continue;
    }

    final candidato = _Candidato(
      cnesId: cnesId,
      tipo: tipo,
      nome: nome,
      endereco: _montarEndereco(e),
      bairro: _nomeProprio(_texto(e['bairro_estabelecimento'])),
      telefone: _telefone(_texto(e['numero_telefone_estabelecimento'])),
      latitude: lat,
      longitude: lon,
      horas: tipo == 'UBS' ? horas : null,
    );
    final grupo = porTipo[tipo]!;
    final repetido = grupo.any((o) =>
        o.nomeNormalizado == candidato.nomeNormalizado &&
        _distanciaMetros(o.latitude, o.longitude, lat, lon) < _distanciaDuplicadoMetros);
    if (repetido) {
      r.duplicadoProximo[tipo] = r.duplicadoProximo[tipo]! + 1;
      continue;
    }
    grupo.add(candidato);
  }

  final saida = <_Candidato>[];
  for (final t in _ordemSaida) {
    final grupo = porTipo[t]!..sort((a, b) => a.nome.compareTo(b.nome));
    r.importados[t] = grupo.length;
    saida.addAll(grupo);
  }
  return saida;
}

final _reForaDoEscopo = RegExp(
  r'detencao|penitenciaria|progressao penitenciaria|distrito naval|uaisa|servico de atencao domiciliar|^sad ',
);

/// Presídios, centros de detenção, comando militar, unidades socioeducativas e atenção domiciliar
/// não atendem o público em fila: não entram.
bool _foraDoEscopo(String nome) => _reForaDoEscopo.hasMatch(_normalizar(nome));

/// O tipo 73 do CNES ("Pronto Atendimento") mistura UPA, AMA e pronto-atendimento municipal.
String _tipoDoProntoAtendimento(String nome) {
  final n = _normalizar(nome);
  if (n.startsWith('upa ') || n == 'upa' || n.startsWith('unidade de pronto atendimento')) return 'UPA';
  if (n.startsWith('ama ') || n == 'ama') return 'UBS';
  return 'Pronto-socorro';
}

/// "AMA 24H ..." funciona 24 horas; "AMA 12H ..." funciona 12 horas (7h às 19h). Outros: sem informação.
String? _horasDoNome(String nome) {
  final n = _normalizar(nome);
  if (RegExp(r'^ama (24h|24 h)\b').hasMatch(n)) return '24h';
  if (RegExp(r'^ama (12h|12 h)\b').hasMatch(n)) return '12h';
  return null;
}

/// Abreviações do cadastro oficial no começo do nome.
String? _expandirAbreviacao(String? nome) {
  if (nome == null) return null;
  const trocas = {
    r'^PS MUN\b': 'Pronto Socorro Municipal',
    r'^PA MUN\b': 'Pronto Atendimento Municipal',
    r'^CSE\b': 'Centro de Saúde Escola',
    r'^CS ESCOLA\b': 'Centro de Saúde Escola',
    r'^CS\b': 'Centro de Saúde',
  };
  for (final e in trocas.entries) {
    final re = RegExp(e.key, caseSensitive: false);
    if (re.hasMatch(nome)) return nome.replaceFirst(re, e.value);
  }
  return nome;
}

/// Motivo de desabilitação preenchido (e diferente de zero) = estabelecimento fora de operação.
bool _desabilitado(Object? motivo) {
  final t = _texto(motivo);
  return t != null && t.replaceAll('0', '').isNotEmpty;
}

/// Público: natureza jurídica da administração pública (grupo 1), empresa pública ou economia mista,
/// ou qualquer unidade que atenda pelo SUS. Privada que não atende pelo SUS fica de fora.
bool _atendePublico(Map<String, dynamic> e) {
  final natureza = _texto(e['descricao_natureza_juridica_estabelecimento'])?.replaceAll(RegExp(r'\D'), '') ?? '';
  final publica = natureza.startsWith('1') || natureza == '2011' || natureza == '2038';
  final sus = (_texto(e['estabelecimento_faz_atendimento_ambulatorial_sus']) ?? '').toUpperCase().startsWith('S');
  return publica || sus;
}

String _montarEndereco(Map<String, dynamic> e) {
  final rua = _nomeProprio(_texto(e['endereco_estabelecimento']));
  if (rua == null) return _enderecoVazio;
  final numero = _texto(e['numero_estabelecimento']);
  final semNumero = numero == null || RegExp(r'^(s/?n|sn|0+)$', caseSensitive: false).hasMatch(numero);
  final bairro = _nomeProprio(_texto(e['bairro_estabelecimento']));
  return '$rua${semNumero ? '' : ', $numero'}${bairro == null ? '' : ' - $bairro'}';
}

/// "11983295551" -> "(11) 98329-5551"; "1122048083" -> "(11) 2204-8083"; outro formato: nulo.
String? _telefone(String? bruto) {
  if (bruto == null) return null;
  var d = bruto.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('55') && d.length > 11) d = d.substring(2);
  if (d.startsWith('0') && d.length > 10) d = d.substring(1);
  if (d.length == 11) return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  if (d.length == 10) return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  return null;
}

// ---------------------------------------------------------------------------------------------
// Texto

const _particulas = {'de', 'da', 'do', 'das', 'dos', 'e', 'a', 'o', 'em', 'na', 'no', 'nas', 'nos', 'com', 'para'};
const _siglas = {
  'ubs', 'upa', 'ama', 'ame', 'cer', 'caps', 'inss', 'cras', 'sp', 'ps', 'ceu', 'cdhu', 'pa',
  'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x', 'xi', 'xii',
};

/// O CNES grava os nomes sem acento. Restaura só palavras comuns em nomes de ruas e bairros de São Paulo,
/// onde o acento é certo; o resto fica como está (a busca do app ignora acentos de qualquer forma).
const _acentos = {
  'sao': 'São', 'jose': 'José', 'joao': 'João', 'antonio': 'Antônio', 'americo': 'Américo', 'julio': 'Júlio',
  'lucia': 'Lúcia', 'luis': 'Luís', 'mario': 'Mário', 'candido': 'Cândido', 'emilio': 'Emílio', 'zelia': 'Zélia',
  'sonia': 'Sônia', 'silvia': 'Sílvia', 'gloria': 'Glória', 'conceicao': 'Conceição', 'agua': 'Água',
  'aguia': 'Águia', 'angela': 'Ângela', 'bras': 'Brás', 'capao': 'Capão', 'carrao': 'Carrão', 'cangaiba': 'Cangaíba',
  'grajau': 'Grajaú', 'icarai': 'Icaraí', 'imperio': 'Império', 'jacana': 'Jaçanã', 'jaguare': 'Jaguaré',
  'sacoma': 'Sacomã', 'tatuape': 'Tatuapé', 'tiete': 'Tietê', 'piaui': 'Piauí', 'brasilia': 'Brasília',
  'brasilandia': 'Brasilândia', 'paraisopolis': 'Paraisópolis', 'americanopolis': 'Americanópolis',
  'orquideas': 'Orquídeas', 'boracea': 'Boracéia', 'macedonia': 'Macedônia', 'balneario': 'Balneário',
  'nobrega': 'Nóbrega', 'oratorio': 'Oratório', 'missionaria': 'Missionária', 'elisio': 'Elísio', 'doria': 'Dória',
  'sitio': 'Sítio', 'saude': 'Saúde', 'basica': 'Básica', 'medica': 'Médica', 'clinica': 'Clínica',
  'ambulatorio': 'Ambulatório', 'pediatrica': 'Pediátrica', 'ortopedica': 'Ortopédica', 'republica': 'República',
  'bonifacio': 'Bonifácio', 'nazare': 'Nazaré', 'tres': 'Três', 'ines': 'Inês', 'jordanopolis': 'Jordanópolis',
  'armenia': 'Armênia', 'italia': 'Itália', 'galvao': 'Galvão', 'goncalves': 'Gonçalves', 'araujo': 'Araújo',
  'sebastiao': 'Sebastião', 'vitoria': 'Vitória', 'esperanca': 'Esperança',
};

/// Nome em maiúsculas do CNES -> "Nome Próprio" (preposições minúsculas, siglas e algarismos romanos mantidos).
String? _nomeProprio(String? texto) {
  if (texto == null) return null;
  final partes = RegExp(r'[^\s/\-().,]+|[\s/\-().,]+').allMatches(texto.toLowerCase()).map((m) => m[0]!).toList();
  final saida = StringBuffer();
  var primeira = true;
  for (final p in partes) {
    if (RegExp(r'^[\s/\-().,]+$').hasMatch(p)) {
      saida.write(p);
      continue;
    }
    final comAcento = _acentos[p];
    if (comAcento != null) {
      saida.write(comAcento);
    } else if (_siglas.contains(p)) {
      saida.write(p.toUpperCase());
    } else if (!primeira && _particulas.contains(p)) {
      saida.write(p);
    } else {
      // Maiúscula na primeira letra e depois de apóstrofo ou aspas: "d'agua" -> "D'Agua", "'quinze'" -> "'Quinze'".
      saida.write(p.replaceAllMapped(RegExp(r'(^|[^\p{L}])(\p{L})', unicode: true), (m) => '${m[1]}${m[2]!.toUpperCase()}'));
    }
    primeira = false;
  }
  return saida.toString();
}

String? _texto(Object? valor) {
  if (valor == null) return null;
  final limpo = '$valor'.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return limpo.isEmpty ? null : limpo;
}

int? _inteiro(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) return int.tryParse(valor.trim());
  return null;
}

double? _decimal(Object? valor) {
  if (valor is num) return valor.toDouble();
  if (valor is String) return double.tryParse(valor.trim().replaceAll(',', '.'));
  return null;
}

const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _semAcento = 'aaaaaeeeeiiiiooooouuuucn';

String _normalizar(String texto) {
  final baixo = texto.toLowerCase();
  final saida = StringBuffer();
  for (final letra in baixo.split('')) {
    final i = _comAcento.indexOf(letra);
    saida.write(i == -1 ? letra : _semAcento[i]);
  }
  return saida.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

double _distanciaMetros(double lat1, double lon1, double lat2, double lon2) {
  const raio = 6371000.0;
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return raio * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

// ---------------------------------------------------------------------------------------------
// Geração do SQL

String _sql(String? texto) => texto == null ? 'NULL' : "'${texto.replaceAll("'", "''")}'";

String _linhaDeValores(_Candidato c) =>
    '  (${_sql(c.tipo)}, ${_sql(c.nome)}, ${_sql(c.endereco)}, ${_sql(c.bairro)}, '
    '${c.latitude.toStringAsFixed(7)}, ${c.longitude.toStringAsFixed(7)}, ${_sql(c.telefone)}, ${c.cnesId})';

String _insert(List<_Candidato> lote) => '''
insert into unidade (tipo_unidade_id, nome, endereco, bairro, cidade, uf, latitude, longitude, telefone, origem, cnes_id, horario_padrao)
select t.id, v.nome, v.endereco, v.bairro, 'São Paulo', 'SP',
       v.latitude::double precision, v.longitude::double precision, v.telefone,
       'cnes', v.cnes_id::bigint, true
  from (values
${lote.map(_linhaDeValores).join(',\n')}
  ) as v (tipo, nome, endereco, bairro, latitude, longitude, telefone, cnes_id)
  join tipo_unidade t on t.nome = v.tipo
on conflict (cnes_id) where cnes_id is not null
do update set nome = excluded.nome,
              endereco = excluded.endereco,
              bairro = excluded.bairro,
              latitude = excluded.latitude,
              longitude = excluded.longitude,
              telefone = excluded.telefone,
              ativo = true;
''';

/// Horários que o próprio nome informa (AMA 24H / AMA 12H). Sobrescreve o padrão do tipo para essas unidades.
String _sqlDeHorarios(List<_Candidato> unidades) {
  String lista(String h) => unidades.where((u) => u.horas == h).map((u) => u.cnesId).join(', ');
  final h24 = lista('24h'), h12 = lista('12h');
  if (h24.isEmpty && h12.isEmpty) return '';
  final b = StringBuffer('-- Horários que o próprio nome da unidade informa (AMA 24H e AMA 12H).\n');
  for (final (ids, abre, fecha) in [(h24, '00:00', '23:59:59'), (h12, '07:00', '19:00')]) {
    if (ids.isEmpty) continue;
    b.write('''
insert into horario_funcionamento (unidade_id, dia_semana, abre, fecha)
select u.id, d.dia, time '$abre', time '$fecha'
  from unidade u
  cross join generate_series(0, 6) as d (dia)
 where u.origem = 'cnes' and u.cnes_id in ($ids)
on conflict (unidade_id, dia_semana) do update set abre = excluded.abre, fecha = excluded.fecha;
''');
  }
  return b.toString();
}

const _fecho = '''
-- O CNES é a fonte oficial: as unidades do OpenStreetMap do mesmo tipo a até 150 m de uma unidade do CNES
-- são o mesmo lugar e saem do mapa (ficam inativas, não são apagadas). As que o CNES não cobre continuam.
update unidade o
   set ativo = false
 where o.origem = 'openstreetmap'
   and o.ativo
   and exists (
        select 1
          from unidade c
         where c.origem = 'cnes'
           and c.ativo
           and c.tipo_unidade_id = o.tipo_unidade_id
           and abs(c.latitude - o.latitude) < 0.002
           and abs(c.longitude - o.longitude) < 0.002
           and 6371000 * 2 * asin(sqrt(
                 power(sin(radians(c.latitude - o.latitude) / 2), 2)
               + cos(radians(o.latitude)) * cos(radians(c.latitude))
                 * power(sin(radians(c.longitude - o.longitude) / 2), 2))) <= 150);

-- Completa serviços, horários padrão e histórico estimado; desativa as unidades de demonstração.
call prc_completar_unidades_reais();

-- Conferência: unidades por tipo e origem.
select * from fn_resumo_dados_reais();
''';

List<File> _gerarSql(List<_Candidato> unidades, _Relatorio r, String caminho, int limiteKb, int linhasPorInsert) {
  final inserts = <String>[
    for (var i = 0; i < unidades.length; i += linhasPorInsert)
      _insert(unidades.sublist(i, math.min(i + linhasPorInsert, unidades.length))),
  ];

  final cabecalhoBase = _cabecalho(unidades, r, 1, 1);
  final limiteBytes = limiteKb * 1024;
  final partes = <List<String>>[[]];
  final fecho = _sqlDeHorarios(unidades) + _fecho;
  var tamanho = utf8.encode(cabecalhoBase).length + utf8.encode(fecho).length;
  for (final insert in inserts) {
    final bytes = utf8.encode(insert).length;
    if (partes.last.isNotEmpty && tamanho + bytes > limiteBytes) {
      partes.add([]);
      tamanho = utf8.encode(cabecalhoBase).length;
    }
    partes.last.add(insert);
    tamanho += bytes;
  }

  final arquivos = <File>[];
  for (var i = 0; i < partes.length; i++) {
    final destino = partes.length == 1 ? caminho : _comSufixo(caminho, '_parte${i + 1}');
    final texto = StringBuffer(_cabecalho(unidades, r, i + 1, partes.length))
      ..writeln(partes[i].join('\n'))
      ..write(i == partes.length - 1 ? fecho : '-- Continua na próxima parte.\n');
    final arquivo = File(destino)..parent.createSync(recursive: true);
    arquivo.writeAsStringSync(texto.toString(), encoding: utf8);
    arquivos.add(arquivo);
  }
  return arquivos;
}

String _comSufixo(String caminho, String sufixo) {
  final ponto = caminho.lastIndexOf('.');
  return ponto <= caminho.lastIndexOf(Platform.pathSeparator)
      ? '$caminho$sufixo'
      : '${caminho.substring(0, ponto)}$sufixo${caminho.substring(ponto)}';
}

String _cabecalho(List<_Candidato> unidades, _Relatorio r, int parte, int partes) {
  final contagem = _ordemSaida.map((t) => '$t=${r.importados[t]}').join(', ');
  return '''
-- Passa Rápido: unidades de saúde de São Paulo (CNES/DATASUS, Ministério da Saúde, dados abertos).
-- Fonte: Cadastro Nacional de Estabelecimentos de Saúde, apidadosabertos.saude.gov.br.
-- Gerado em ${DateTime.now().toUtc().toIso8601String()} por tool/importar_cnes.dart $_versao.
-- Unidades: ${unidades.length} ($contagem).${partes > 1 ? '\n-- Parte $parte de $partes: execute as partes em ordem.' : ''}
-- Idempotente: pode ser executado mais de uma vez. Requer 07_estrutura_dados_reais.sql, 10_cnes.sql
-- e 08_dados_reais_base.sql já aplicados. Nomes e endereços seguem o cadastro oficial (sem acentos, quando o CNES não os tem).

''';
}

void _imprimirResumo(_Relatorio r) {
  stdout.writeln('\nResumo');
  stdout.writeln('  estabelecimentos recebidos: ${r.recebidos}');
  stdout.writeln('  importados por tipo:');
  for (final t in _ordemSaida) {
    stdout.writeln('    ${t.padRight(15)} ${r.importados[t]}   (repetidos próximos descartados: ${r.duplicadoProximo[t]})');
  }
  stdout.writeln('  total importado: ${r.importados.values.fold<int>(0, (a, b) => a + b)}');
  stdout.writeln('  descartados:');
  stdout.writeln('    tipo fora da lista:                ${r.tipoIgnorado}');
  stdout.writeln('    de outro município:                ${r.outroMunicipio}');
  stdout.writeln('    desabilitados:                     ${r.desabilitado}');
  stdout.writeln('    privados sem atendimento SUS:      ${r.privadoSemSus}');
  stdout.writeln('    fora do escopo (presídio, domiciliar...): ${r.foraDoEscopo}');
  stdout.writeln('    sem nome:                          ${r.semNome}');
  stdout.writeln('    sem coordenadas:                   ${r.semCoordenadas}');
  stdout.writeln('    fora de São Paulo (caixa):         ${r.foraDoMunicipio}');
  stdout.writeln('    repetidos pelo mesmo código CNES:  ${r.duplicadoId}');
}
