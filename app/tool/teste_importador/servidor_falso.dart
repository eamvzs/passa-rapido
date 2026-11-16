// Servidor Overpass FALSO para testar tool/importar_osm.dart sem internet.
// Responde POST /api/interpreter com JSON sintético no formato real do Overpass
// (`out center tags;`: node com lat/lon; way e relation com "center").
// GET /tudo.json devolve todos os elementos juntos (para testar --entrada).
//
//   dart run tool/teste_importador/servidor_falso.dart PORTA [--falhar-primeira]
//
// --falhar-primeira: a primeira requisição POST recebe HTTP 504, para testar a repetição.

import 'dart:convert';
import 'dart:io';

Map<String, dynamic> node(int id, double lat, double lon, Map<String, String> tags) =>
    {'type': 'node', 'id': id, 'lat': lat, 'lon': lon, 'tags': tags};

Map<String, dynamic> via(String tipo, int id, double lat, double lon, Map<String, String> tags) =>
    {'type': tipo, 'id': id, 'center': {'lat': lat, 'lon': lon}, 'tags': tags};

final conjuntos = <String, List<Map<String, dynamic>>>{
  'UPA': [
    node(1001, -23.5893, -46.6350, {
      'name': 'UPA Vila Mariana', 'addr:street': 'Rua Domingos de Morais', 'addr:housenumber': '2564',
      'addr:suburb': 'Vila Mariana', 'phone': '+55 11 3333-0001; +55 11 3333-0002', 'amenity': 'clinic',
    }),
    via('way', 2001, -23.6536, -46.7106, {'name': 'UPA Santo Amaro', 'amenity': 'hospital'}),
    node(1002, -23.5400, -46.5766, {
      'name': "upa são josé d'Água", 'addr:street': "Rua do 'Quinze' \"Novembro\" \\ Teste",
      'addr:housenumber': '15', 'contact:phone': '1133330003',
    }),
    node(1003, -23.4870, -46.7260, {'amenity': 'clinic'}), // sem nome
    {'type': 'node', 'id': 1004, 'tags': {'name': 'UPA Sem Coordenada'}}, // sem coordenadas
    node(1005, -23.58932, -46.63502, {'name': 'UPA Vila Mariana', 'addr:street': 'Rua Sem Número'}), // ~3 m do 1001
    node(1001, -23.5893, -46.6350, {'name': 'UPA Vila Mariana'}), // mesmo id repetido
    node(1006, -23.5000, -46.6000, {'name': 'UPAMENTO Falso'}), // não é UPA
    node(1007, -22.9000, -47.0600, {'name': 'UPA Campinas'}), // fora de São Paulo
  ],
  'Pronto-socorro': [
    via('way', 3001, -23.5270, -46.7030, {'name': 'Pronto-Socorro Lapa', 'addr:street': 'Rua Guaicurus'}),
    node(3002, -23.5020, -46.6250, {
      'name': 'Hospital Municipal Santana', 'amenity': 'hospital', 'emergency': 'yes', 'operator:type': 'public',
    }),
    node(3003, -23.5500, -46.6500, {
      'name': 'Hospital Privado Exemplo', 'amenity': 'hospital', 'emergency': 'yes', 'operator:type': 'private',
    }),
    node(3004, -23.5600, -46.5990, {'name': 'UPA Pronto-Socorro Mooca', 'addr:suburb': 'Mooca'}), // prioridade: UPA
  ],
  'UBS': [
    node(4001, -23.5480, -46.6340, {'name': 'UBS Sé', 'addr:suburb': 'Sé'}),
    node(4002, -23.5360, -46.4560, {'name': 'AMA/UBS Integrada Itaquera'}),
    via('way', 4003, -23.5630, -46.6900, {'name': 'Unidade Básica de Saúde Pinheiros'}),
    node(4004, -23.5710, -46.7080, {'name': 'Centro de Saúde Escola Butantã'}),
    node(4005, -23.5900, -46.6000, {'name': 'Amara Clínica'}), // AMA seguido de letra: não é AMA
    node(4006, -23.5600, -46.6100, {'name': 'UBS Mooca', 'contact:phone': '1133330006'}),
  ],
  'Poupatempo': [
    node(5001, -23.5499, -46.6310, {'name': 'Poupatempo Sé', 'addr:street': 'Praça do Carmo', 'addr:housenumber': '1'}),
    via('way', 5002, -23.6510, -46.7080, {'name': 'Poupatempo Santo Amaro'}),
    // mesmo número de id do node 5001, mas é outro elemento (way): precisa importar os dois
    via('way', 5001, -23.5200, -46.7010, {'name': 'Poupatempo Lapa'}),
    // o mesmo Poupatempo Sé mapeado como relação a ~30 m do ponto: duplicado próximo
    via('relation', 7001, -23.54985, -46.63075, {'name': 'poupatempo sé'}),
  ],
  'INSS': [
    node(6001, -23.5440, -46.6390, {'name': 'Agência da Previdência Social Centro'}),
    node(6002, -23.5010, -46.6280, {'name': 'INSS Santana', 'phone': '135'}),
  ],
  'CRAS': [
    node(7001, -23.5465, -46.6365, {'name': 'CRAS Sé'}),
    node(7002, -23.4690, -46.6900, {'name': 'Centro de Referência de Assistência Social Brasilândia'}),
    node(7003, -23.5470, -46.6370, {'name': 'CREAS Sé'}), // CREAS não é CRAS
  ],
};

String chaveDaConsulta(String consulta) {
  if (consulta.contains('Poupatempo')) return 'Poupatempo';
  if (consulta.contains('Pronto[- ]?Socorro')) return 'Pronto-socorro';
  if (consulta.contains('UBS')) return 'UBS';
  if (consulta.contains('INSS')) return 'INSS';
  if (consulta.contains('CRAS')) return 'CRAS';
  return 'UPA';
}

Future<void> main(List<String> args) async {
  final porta = int.parse(args.first);
  var falharPrimeira = args.contains('--falhar-primeira');
  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, porta);
  stdout.writeln('Servidor falso na porta ${servidor.port}');

  await for (final req in servidor) {
    if (req.method == 'GET' && req.uri.path == '/tudo.json') {
      final todos = [for (final l in conjuntos.values) ...l];
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'version': 0.6, 'generator': 'servidor falso', 'elements': todos}));
      await req.response.close();
      continue;
    }
    if (req.method == 'GET' && req.uri.path == '/ping') {
      req.response.write('ok');
      await req.response.close();
      continue;
    }
    if (req.method != 'POST' || req.uri.path != '/api/interpreter') {
      req.response.statusCode = 404;
      await req.response.close();
      continue;
    }
    final corpo = await utf8.decoder.bind(req).join();
    final consulta = Uri.splitQueryString(corpo)['data'] ?? '';
    if (falharPrimeira) {
      falharPrimeira = false;
      req.response.statusCode = 504;
      req.response.write('Gateway Timeout');
      await req.response.close();
      stdout.writeln('POST -> 504 (falha injetada)');
      continue;
    }
    final chave = chaveDaConsulta(consulta);
    stdout.writeln('POST $chave (${consulta.length} bytes)');
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'version': 0.6, 'generator': 'servidor falso', 'elements': conjuntos[chave]}));
    await req.response.close();
  }
}
