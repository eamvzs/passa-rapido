// Importador de unidades reais do OpenStreetMap para o Passa Rápido.
//
// Baixa (ou lê de arquivo) as unidades de atendimento do município de São Paulo
// e gera o SQL `database/08_unidades_reais.sql`, para colar no SQL Editor do Supabase.
//
// Script Dart puro (só dart:io, dart:convert e dart:math), sem dependências.
//
//   dart run tool/importar_osm.dart                       baixa do Overpass e gera o SQL
//   dart run tool/importar_osm.dart --entrada resp.json   usa um JSON já baixado (pode repetir a opção)
//   dart run tool/importar_osm.dart --url http://localhost:8765/api/interpreter
//   dart run tool/importar_osm.dart --saida caminho.sql --pausa 8 --tentativas 3
//
// Identificador estável (coluna unidade.osm_id, bigint, única):
//   node     -> id do OSM
//   way      -> id do OSM + 1.000.000.000.000.000 (1e15)
//   relation -> id do OSM + 2.000.000.000.000.000 (2e15)
// Os ids reais do OSM ficam abaixo de 1e15, então não há colisão entre os três tipos.
//
// Dados © Colaboradores do OpenStreetMap, licença ODbL 1.0 (openstreetmap.org/copyright).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _versao = '1.0';
const _userAgent = 'PassaRapido-Importador/$_versao (projeto academico FIAP)';
const _espacoWay = 1000000000000000;
const _espacoRelation = 2000000000000000;
const _distanciaDuplicadoMetros = 60.0;
const _linhasPorInsert = 100;
const _enderecoVazio = 'Endereço não informado no OpenStreetMap';

/// Caixa de segurança em volta do município de São Paulo: descarta o que vier de fora.
const _latMin = -24.10, _latMax = -23.30, _lonMin = -47.00, _lonMax = -46.20;

/// Ordem de prioridade para resolver ambiguidade (o primeiro que casar vence).
const _tipos = ['Poupatempo', 'INSS', 'CRAS', 'UPA', 'Pronto-socorro', 'UBS'];

/// Ordem em que os tipos aparecem no SQL e no resumo.
const _ordemSaida = ['UPA', 'Pronto-socorro', 'UBS', 'Poupatempo', 'INSS', 'CRAS'];

const _letra = r'A-Za-zÀ-ÿ';

final _reUba = RegExp('^(UBS(?![$_letra])|Unidade B[aá]sica|Centro de Sa[uú]de)', caseSensitive: false);
final _reAma = RegExp('^AMA(?![$_letra])');
final _reUpa = RegExp('^(UPA(?![$_letra])|Unidade de Pronto Atendimento)', caseSensitive: false);
final _reProntoSocorro = RegExp(r'Pronto[- ]?Socorro', caseSensitive: false);
final _rePoupatempo = RegExp('Poupatempo', caseSensitive: false);
final _reInss = RegExp('(?<![$_letra])INSS(?![$_letra])|Previd[eê]ncia Social', caseSensitive: false);
final _reCras = RegExp(
  '(?<![$_letra])CRAS(?![$_letra])|Centro de Refer[eê]ncia de Assist[eê]ncia Social',
  caseSensitive: false,
);

/// Trecho das consultas Overpass (uma por tipo, para não estourar o tempo limite).
/// O filtro do servidor é propositalmente um pouco mais largo; a classificação final é no cliente.
const _consultas = <String, String>{
  'UPA': r'''nwr["name"~"^(UPA|Unidade de Pronto Atendimento)",i](area.sp);''',
  'Pronto-socorro': r'''nwr["name"~"Pronto[- ]?Socorro",i](area.sp);
  nwr["amenity"="hospital"]["emergency"="yes"]["operator:type"~"^(public|government)$"](area.sp);''',
  'UBS': r'''nwr["name"~"^(UBS|Unidade B[aá]sica|Centro de Sa[uú]de)",i](area.sp);
  nwr["name"~"^AMA([^A-Za-z]|$)"](area.sp);''',
  'Poupatempo': r'''nwr["name"~"Poupatempo",i](area.sp);''',
  'INSS': r'''nwr["name"~"INSS|Previd[eê]ncia Social",i](area.sp);''',
  'CRAS': r'''nwr["name"~"CRAS|Centro de Refer[eê]ncia de Assist[eê]ncia Social",i](area.sp);''',
};

const _espelhos = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

String _montarConsulta(String corpo) => '''[out:json][timeout:180];
area["name"="São Paulo"]["boundary"="administrative"]["admin_level"="8"]->.sp;
(
  $corpo
);
out center tags;''';

class _Opcoes {
  final entradas = <String>[];
  String? url;
  String? saida;
  int pausa = 8;
  int tentativas = 3;
  int limiteKb = 400;
  int linhasPorInsert = _linhasPorInsert;
  bool ajuda = false;
}

class _Candidato {
  _Candidato({
    required this.osmId,
    required this.tipo,
    required this.nome,
    required this.endereco,
    required this.bairro,
    required this.telefone,
    required this.latitude,
    required this.longitude,
    required this.pontos,
  });

  final int osmId;
  final String tipo;
  final String nome;
  final String endereco;
  final String? bairro;
  final String? telefone;
  final double latitude;
  final double longitude;
  final int pontos;
  late final String nomeNormalizado = _normalizar(nome);
}

class _Relatorio {
  final importados = <String, int>{for (final t in _ordemSaida) t: 0};
  final duplicadoProximo = <String, int>{for (final t in _ordemSaida) t: 0};
  int recebidos = 0;
  int semNome = 0;
  int semCoordenadas = 0;
  int foraDoMunicipio = 0;
  int naoClassificado = 0;
  int duplicadoId = 0;
}

Future<void> main(List<String> args) async {
  final opcoes = _lerArgumentos(args);
  if (opcoes.ajuda) {
    stdout.writeln(_textoAjuda);
    return;
  }

  final saida = opcoes.saida ?? _saidaPadrao();
  final falhas = <String>[];
  final elementos = <Map<String, dynamic>>[];

  if (opcoes.entradas.isNotEmpty) {
    for (final caminho in opcoes.entradas) {
      final arquivo = File(caminho);
      if (!arquivo.existsSync()) {
        stderr.writeln('Arquivo de entrada não encontrado: $caminho');
        exit(1);
      }
      stdout.writeln('Lendo $caminho ...');
      elementos.addAll(_extrairElementos(await arquivo.readAsString(), caminho));
    }
  } else {
    final endpoints = opcoes.url != null ? [opcoes.url!] : _espelhos;
    var primeira = true;
    for (final entrada in _consultas.entries) {
      if (!primeira && opcoes.pausa > 0) await Future<void>.delayed(Duration(seconds: opcoes.pausa));
      primeira = false;
      stdout.writeln('Consultando ${entrada.key} ...');
      try {
        final corpo = await _baixar(_montarConsulta(entrada.value), endpoints, opcoes);
        final lista = _extrairElementos(corpo, entrada.key);
        stdout.writeln('  ${lista.length} elementos recebidos');
        elementos.addAll(lista);
      } catch (e) {
        falhas.add(entrada.key);
        stderr.writeln('  FALHOU: $e');
      }
    }
  }

  if (elementos.isEmpty) {
    stderr.writeln('\nNenhum elemento recebido: o SQL não foi gerado. Tente de novo mais tarde ou use --entrada.');
    exit(2);
  }

  final relatorio = _Relatorio();
  final unidades = _processar(elementos, relatorio);
  if (unidades.isEmpty) {
    stderr.writeln('\nNenhuma unidade válida após a limpeza: o SQL não foi gerado.');
    _imprimirResumo(relatorio, falhas);
    exit(2);
  }

  final arquivos = _gerarSql(unidades, relatorio, saida, opcoes.limiteKb, opcoes.linhasPorInsert);
  _imprimirResumo(relatorio, falhas);
  stdout.writeln('\nArquivos gerados:');
  for (final a in arquivos) {
    stdout.writeln('  ${a.path}  (${(a.lengthSync() / 1024).toStringAsFixed(1)} KB)');
  }
  if (arquivos.length > 1) {
    stdout.writeln('\nO SQL passou do limite de ${opcoes.limiteKb} KB e foi dividido: cole as partes em ordem.');
  }
  if (falhas.isNotEmpty) {
    stderr.writeln('\nATENÇÃO: as consultas de ${falhas.join(', ')} falharam; o SQL está incompleto. Rode de novo.');
    exit(3);
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
      case '--pausa':
        o.pausa = int.parse(valor());
      case '--tentativas':
        o.tentativas = int.parse(valor());
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

String _saidaPadrao() {
  // app/tool/importar_osm.dart -> app/../database/08_unidades_reais.sql
  final script = File.fromUri(Platform.script);
  final app = script.parent.parent;
  return '${app.parent.path}${Platform.pathSeparator}database${Platform.pathSeparator}08_unidades_reais.sql';
}

const _textoAjuda = '''
Importador de unidades reais (OpenStreetMap) do Passa Rápido.

  dart run tool/importar_osm.dart [opções]

  --entrada ARQ     usa um JSON do Overpass já baixado (repita a opção para vários arquivos)
  --url URL         endereço de um Overpass específico (padrão: overpass-api.de e overpass.kumi.systems)
  --saida ARQ       arquivo SQL de saída (padrão: database/08_unidades_reais.sql)
  --pausa SEG       pausa entre consultas e base da espera entre tentativas (padrão: 8)
  --tentativas N    tentativas por endereço (padrão: 3)
  --limite-kb N     divide o SQL em partes acima deste tamanho (padrão: 400)
  --linhas-por-insert N  unidades por comando insert (padrão: 100)
''';

// ---------------------------------------------------------------------------------------------
// Rede

Future<String> _baixar(String consulta, List<String> endpoints, _Opcoes opcoes) async {
  Object? ultimoErro;
  for (final endpoint in endpoints) {
    for (var tentativa = 1; tentativa <= opcoes.tentativas; tentativa++) {
      final cliente = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..userAgent = _userAgent;
      try {
        final req = await cliente.postUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 30));
        req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        req.write('data=${Uri.encodeQueryComponent(consulta)}');
        final resp = await req.close().timeout(const Duration(minutes: 5));
        final corpo = await resp.transform(utf8.decoder).join().timeout(const Duration(minutes: 5));

        if (resp.statusCode == 200) {
          final json = jsonDecode(corpo);
          final aviso = json is Map ? (json['remark'] as String?) : null;
          if (aviso != null && aviso.toLowerCase().contains('runtime error')) {
            throw StateError('o servidor respondeu com erro de execução: $aviso');
          }
          return corpo;
        }
        throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(endpoint));
      } catch (e) {
        ultimoErro = e;
        stderr.writeln('  tentativa $tentativa/${opcoes.tentativas} em $endpoint: $e');
        if (tentativa < opcoes.tentativas && opcoes.pausa > 0) {
          await Future<void>.delayed(Duration(seconds: opcoes.pausa * tentativa));
        }
      } finally {
        cliente.close(force: true);
      }
    }
  }
  throw StateError('todos os endereços falharam (último erro: $ultimoErro)');
}

List<Map<String, dynamic>> _extrairElementos(String corpo, String origem) {
  final Object? json;
  try {
    json = jsonDecode(corpo);
  } on FormatException catch (e) {
    throw FormatException('JSON inválido em $origem: ${e.message}');
  }
  if (json is! Map || json['elements'] is! List) {
    throw FormatException('$origem não tem a lista "elements" do Overpass');
  }
  return [
    for (final e in json['elements'] as List)
      if (e is Map<String, dynamic>) e,
  ];
}

// ---------------------------------------------------------------------------------------------
// Limpeza e classificação

String? _classificar(String nome, Map<String, dynamic> tags) {
  for (final tipo in _tipos) {
    final casou = switch (tipo) {
      'Poupatempo' => _rePoupatempo.hasMatch(nome),
      'INSS' => _reInss.hasMatch(nome),
      'CRAS' => _reCras.hasMatch(nome),
      'UPA' => _reUpa.hasMatch(nome),
      'Pronto-socorro' => _reProntoSocorro.hasMatch(nome) || _hospitalPublicoComEmergencia(tags),
      _ => _reUba.hasMatch(nome) || _reAma.hasMatch(nome),
    };
    if (casou) return tipo;
  }
  return null;
}

bool _hospitalPublicoComEmergencia(Map<String, dynamic> tags) {
  final operador = _texto(tags['operator:type'])?.toLowerCase();
  return _texto(tags['amenity']) == 'hospital' &&
      _texto(tags['emergency']) == 'yes' &&
      (operador == 'public' || operador == 'government');
}

List<_Candidato> _processar(List<Map<String, dynamic>> elementos, _Relatorio r) {
  final porId = <int, _Candidato>{};

  for (final e in elementos) {
    r.recebidos++;
    final tipoElemento = e['type'];
    final id = e['id'];
    if (id is! int || (tipoElemento != 'node' && tipoElemento != 'way' && tipoElemento != 'relation')) continue;
    final tags = e['tags'] is Map ? (e['tags'] as Map).cast<String, dynamic>() : <String, dynamic>{};

    final nome = _texto(tags['name']);
    if (nome == null) {
      r.semNome++;
      continue;
    }

    final coordenadas = _coordenadas(e);
    if (coordenadas == null) {
      r.semCoordenadas++;
      continue;
    }
    final (lat, lon) = coordenadas;
    if (lat < _latMin || lat > _latMax || lon < _lonMin || lon > _lonMax) {
      r.foraDoMunicipio++;
      continue;
    }

    final tipo = _classificar(nome, tags);
    if (tipo == null) {
      r.naoClassificado++;
      continue;
    }

    final osmId = switch (tipoElemento) {
      'way' => id + _espacoWay,
      'relation' => id + _espacoRelation,
      _ => id,
    };
    if (porId.containsKey(osmId)) {
      r.duplicadoId++;
      continue;
    }

    final rua = _texto(tags['addr:street']);
    final numero = _texto(tags['addr:housenumber']);
    final bairro = _texto(tags['addr:suburb']) ?? _texto(tags['addr:neighbourhood']);
    final telefone = _primeiroTelefone(_texto(tags['phone']) ?? _texto(tags['contact:phone']));

    final endereco = rua == null
        ? _enderecoVazio
        : '$rua${numero != null ? ', $numero' : ''}${bairro != null ? ' - $bairro' : ''}';

    porId[osmId] = _Candidato(
      osmId: osmId,
      tipo: tipo,
      nome: nome,
      endereco: endereco,
      bairro: bairro,
      telefone: telefone,
      latitude: lat,
      longitude: lon,
      pontos: (rua != null ? 2 : 0) + (numero != null ? 1 : 0) + (bairro != null ? 1 : 0) + (telefone != null ? 1 : 0),
    );
  }

  // Duplicados próximos: o mesmo lugar mapeado como ponto e como área, por exemplo.
  // Fica o registro mais completo (empate: menor id), para o resultado ser reprodutível.
  final ordenados = porId.values.toList()
    ..sort((a, b) {
      final porPontos = b.pontos.compareTo(a.pontos);
      return porPontos != 0 ? porPontos : a.osmId.compareTo(b.osmId);
    });
  final mantidos = <_Candidato>[];
  for (final c in ordenados) {
    final repetido = mantidos.any((m) =>
        m.tipo == c.tipo &&
        m.nomeNormalizado == c.nomeNormalizado &&
        _distanciaMetros(m.latitude, m.longitude, c.latitude, c.longitude) < _distanciaDuplicadoMetros);
    if (repetido) {
      r.duplicadoProximo[c.tipo] = r.duplicadoProximo[c.tipo]! + 1;
    } else {
      mantidos.add(c);
      r.importados[c.tipo] = r.importados[c.tipo]! + 1;
    }
  }

  mantidos.sort((a, b) {
    final porTipo = _ordemSaida.indexOf(a.tipo).compareTo(_ordemSaida.indexOf(b.tipo));
    if (porTipo != 0) return porTipo;
    final porNome = a.nomeNormalizado.compareTo(b.nomeNormalizado);
    return porNome != 0 ? porNome : a.osmId.compareTo(b.osmId);
  });
  return mantidos;
}

(double, double)? _coordenadas(Map<String, dynamic> e) {
  final lat = e['lat'], lon = e['lon'];
  if (lat is num && lon is num) return (lat.toDouble(), lon.toDouble());
  final centro = e['center'];
  if (centro is Map && centro['lat'] is num && centro['lon'] is num) {
    return ((centro['lat'] as num).toDouble(), (centro['lon'] as num).toDouble());
  }
  return null;
}

/// Texto limpo (sem caracteres de controle nem espaços repetidos); nulo se ficar vazio.
String? _texto(Object? valor) {
  if (valor is! String) return null;
  final limpo = valor.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return limpo.isEmpty ? null : limpo;
}

String? _primeiroTelefone(String? telefone) {
  if (telefone == null) return null;
  final primeiro = telefone.split(';').first.trim();
  if (primeiro.isEmpty) return null;
  return primeiro.length > 40 ? primeiro.substring(0, 40) : primeiro;
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
    '${c.latitude.toStringAsFixed(7)}, ${c.longitude.toStringAsFixed(7)}, ${_sql(c.telefone)}, ${c.osmId})';

String _insert(List<_Candidato> lote) => '''
insert into unidade (tipo_unidade_id, nome, endereco, bairro, cidade, uf, latitude, longitude, telefone, origem, osm_id, horario_padrao)
select t.id, v.nome, v.endereco, v.bairro, 'São Paulo', 'SP',
       v.latitude::double precision, v.longitude::double precision, v.telefone,
       'openstreetmap', v.osm_id::bigint, true
  from (values
${lote.map(_linhaDeValores).join(',\n')}
  ) as v (tipo, nome, endereco, bairro, latitude, longitude, telefone, osm_id)
  join tipo_unidade t on t.nome = v.tipo
on conflict (osm_id) where osm_id is not null
do update set nome = excluded.nome,
              endereco = excluded.endereco,
              bairro = excluded.bairro,
              latitude = excluded.latitude,
              longitude = excluded.longitude,
              telefone = excluded.telefone;
''';

List<File> _gerarSql(List<_Candidato> unidades, _Relatorio r, String caminho, int limiteKb, int linhasPorInsert) {
  final inserts = <String>[
    for (var i = 0; i < unidades.length; i += linhasPorInsert)
      _insert(unidades.sublist(i, math.min(i + linhasPorInsert, unidades.length))),
  ];
  const fecho = '''
-- Completa serviços, horários padrão e histórico estimado; desativa as unidades de demonstração.
call prc_completar_unidades_reais();

-- Conferência: unidades por tipo e origem.
select * from fn_resumo_dados_reais();
''';

  // Agrupa os inserts em partes que respeitam o limite de tamanho.
  final cabecalhoBase = _cabecalho(unidades, r, 1, 1);
  final limiteBytes = limiteKb * 1024;
  final partes = <List<String>>[[]];
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
-- Passa Rápido: unidades reais de São Paulo (importadas do OpenStreetMap).
-- © Colaboradores do OpenStreetMap (ODbL 1.0), openstreetmap.org/copyright
-- Gerado em ${DateTime.now().toUtc().toIso8601String()} por tool/importar_osm.dart $_versao.
-- Unidades: ${unidades.length} ($contagem).${partes > 1 ? '\n-- Parte $parte de $partes: execute as partes em ordem.' : ''}
-- Idempotente: pode ser executado mais de uma vez. Requer 07_estrutura_dados_reais.sql
-- e 08_dados_reais_base.sql já aplicados. Nomes e endereços podem estar desatualizados.

''';
}

void _imprimirResumo(_Relatorio r, List<String> falhas) {
  stdout.writeln('\nResumo');
  stdout.writeln('  elementos recebidos: ${r.recebidos}');
  stdout.writeln('  importados por tipo:');
  for (final t in _ordemSaida) {
    stdout.writeln('    ${t.padRight(15)} ${r.importados[t]}   (duplicados próximos descartados: ${r.duplicadoProximo[t]})');
  }
  stdout.writeln('  total importado: ${r.importados.values.fold<int>(0, (a, b) => a + b)}');
  stdout.writeln('  descartados:');
  stdout.writeln('    sem nome:                          ${r.semNome}');
  stdout.writeln('    sem coordenadas:                   ${r.semCoordenadas}');
  stdout.writeln('    fora do município (caixa):         ${r.foraDoMunicipio}');
  stdout.writeln('    nome não corresponde a nenhum tipo: ${r.naoClassificado}');
  stdout.writeln('    repetidos pelo mesmo id:           ${r.duplicadoId}');
  if (falhas.isNotEmpty) stdout.writeln('  consultas que falharam: ${falhas.join(', ')}');
}
