// Servidor FALSO da API do CNES para testar tool/importar_cnes.dart sem internet.
// Imita GET /cnes/estabelecimentos?codigo_municipio=&codigo_tipo_unidade=&limit=&offset=
// com o formato real da resposta ({"estabelecimentos": [...]}), incluindo os campos
// que o importador usa e casos difíceis de limpeza.
//
//   dart run tool/teste_importador/servidor_falso_cnes.dart PORTA [opções]
//
//   --max-limite N     o servidor devolve no máximo N registros por página (imita um teto da API)
//   --ignorar-filtro   ignora codigo_tipo_unidade (para testar a trava do importador)
//   --offset-por-pagina  o offset conta PÁGINAS (a página número N), como a API real do CNES parece fazer
//   --repetir-pagina   ignora offset e devolve sempre a primeira página (para testar a trava de loop)
//   --falhar-primeira  a primeira requisição recebe HTTP 503 (para testar a repetição)
//
// GET /tudo.json devolve todos os registros juntos, inclusive os de outro município (para --entrada).

import 'dart:convert';
import 'dart:io';

Map<String, dynamic> reg(
  int cnes,
  int tipo,
  String? fantasia, {
  String? razao,
  String natureza = '1015',
  String sus = 'SIM',
  String? motivo,
  double? lat = -23.55,
  double? lon = -46.63,
  String? rua = 'RUA DAS FLORES',
  String? numero = '100',
  String? bairro = 'CENTRO',
  String? fone = '11 22048083',
  int municipio = 355030,
}) =>
    {
      'codigo_cnes': cnes,
      'nome_razao_social': razao ?? (fantasia == null ? null : 'RAZAO $fantasia'),
      'nome_fantasia': fantasia,
      'codigo_tipo_unidade': tipo,
      'endereco_estabelecimento': rua,
      'numero_estabelecimento': numero,
      'bairro_estabelecimento': bairro,
      'numero_telefone_estabelecimento': fone,
      'latitude_estabelecimento_decimo_grau': lat,
      'longitude_estabelecimento_decimo_grau': lon,
      'descricao_natureza_juridica_estabelecimento': natureza,
      'estabelecimento_faz_atendimento_ambulatorial_sus': sus,
      'codigo_motivo_desabilitacao_estabelecimento': motivo,
      'codigo_municipio': municipio,
    };

final todos = <Map<String, dynamic>>[
  // --- UBS (tipo 2) ---
  reg(3001, 2, 'UBS JARDIM ICARAI',
      rua: 'RUA DO ICARAI', numero: '123', bairro: 'JARDIM ICARAI', lat: -23.5500000, lon: -46.6300000),
  reg(3002, 2, "UBS DONA ANA D'AVILA",
      rua: "RUA D'AGUA DO 'QUINZE'", numero: '45', bairro: 'VILA D ESTE', fone: '(11) 98329-5551',
      lat: -23.5700000, lon: -46.6500000),
  reg(3003, 2, 'UBS DESABILITADA', motivo: '10', lat: -23.5710000),
  reg(3004, 2, 'CLINICA PRIVADA LTDA', natureza: '2062', sus: 'NAO', lat: -23.5720000),
  reg(3005, 2, 'UBS FILANTROPICA SANTA MARIA', natureza: '3999', sus: 'SIM', lat: -23.5730000, lon: -46.6600000),
  reg(3006, 2, 'UBS SEM COORDENADA', lat: null, lon: null),
  reg(3007, 2, 'UBS COORDENADA ZERO', lat: 0, lon: 0),
  reg(3008, 2, 'UBS EM CAMPINAS', lat: -22.9000, lon: -47.0600),
  reg(3009, 2, 'UBS JARDIM ICARAI', rua: 'RUA DO ICARAI', numero: '123', lat: -23.5500500, lon: -46.6300000), // ~5 m
  reg(3001, 2, 'UBS JARDIM ICARAI REPETIDA', lat: -23.5600000), // mesmo código CNES
  reg(3011, 2, null, razao: null, lat: -23.5740000),
  reg(3012, 2, 'AMA/UBS INTEGRADA VILA ROSA II',
      rua: 'AVENIDA DR ARNALDO', numero: 'S/N', bairro: 'VILA ROSA', fone: '5511987654321',
      lat: -23.5750000, lon: -46.6700000),
  reg(3013, 2, 'UBS SEM TELEFONE VALIDO', fone: '123', lat: -23.5760000, lon: -46.6710000),
  reg(3014, 2, 'UBS SEM ENDERECO', rua: null, numero: null, bairro: null, lat: -23.5770000, lon: -46.6720000),
  // Fora do escopo (não atendem o público em fila) e abreviação do cadastro
  reg(3020, 2, 'CENTRO DE DETENCAO PROVISORIA DE PINHEIROS', lat: -23.5610, lon: -46.7010),
  reg(3021, 2, 'SAD SERVICO DE ATENCAO DOMICILIAR SANTO AMARO', lat: -23.6500, lon: -46.7100),
  reg(3022, 2, 'PENITENCIARIA DA CAPITAL', lat: -23.5120, lon: -46.6180),
  reg(3023, 2, 'CS ESCOLA SAMUEL B PESSOA', lat: -23.5680, lon: -46.7160),
  for (var i = 0; i < 12; i++)
    reg(3100 + i, 2, 'UBS TESTE ${i + 1}',
        rua: 'RUA TESTE', numero: '${i + 1}', lat: -23.6000 - i * 0.01, lon: -46.7000 + i * 0.005),
  // --- UPA / Pronto Atendimento (tipo 73) ---
  reg(4001, 73, 'UPA 24H VILA MARIANA', rua: 'RUA DOMINGOS DE MORAES', numero: '2564', bairro: 'VILA MARIANA',
      lat: -23.5893, lon: -46.6350),
  reg(4002, 73, 'PRONTO ATENDIMENTO PRIVADO', natureza: '2062', sus: 'NAO', lat: -23.5900),
  reg(4003, 73, 'UPA PARELHEIROS', lat: -23.8159, lon: -46.7355),
  // Tipo 73 que não é UPA: AMA (vira UBS; o nome informa o horário) e pronto-atendimento municipal
  reg(4004, 73, 'AMA 24H JOSE BONIFACIO ITAQUERA', lat: -23.5400, lon: -46.4500),
  reg(4005, 73, 'AMA 12H JARDIM PERI PERI', lat: -23.4700, lon: -46.6900),
  reg(4006, 73, 'PA MUN J MACEDONIA', lat: -23.5100, lon: -46.7700),
  // --- Pronto-socorro (tipo 20 e 21) ---
  reg(5001, 20, 'HOSPITAL MUNICIPAL SANTANA PRONTO SOCORRO', lat: -23.5020, lon: -46.6250),
  reg(5101, 21, 'PRONTO SOCORRO INFANTIL SABARA', natureza: '1031', lat: -23.5300, lon: -46.6600),
  // --- Registros que só aparecem em /tudo.json (testam o filtro do importador com --entrada) ---
];

final soNoArquivo = <Map<String, dynamic>>[
  reg(9001, 2, 'UBS DE OUTRO MUNICIPIO', municipio: 355100, lat: -23.4),
  reg(9002, 99, 'FARMACIA QUALQUER', lat: -23.5),
];

Future<void> main(List<String> args) async {
  final porta = int.parse(args.first);
  var maxLimite = 1000000;
  final ignorarFiltro = args.contains('--ignorar-filtro');
  final repetirPagina = args.contains('--repetir-pagina');
  final offsetPorPagina = args.contains('--offset-por-pagina');
  var falhar = args.contains('--falhar-primeira');
  final i = args.indexOf('--max-limite');
  if (i != -1) maxLimite = int.parse(args[i + 1]);

  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, porta);
  stdout.writeln('CNES falso em http://127.0.0.1:$porta');
  await for (final req in servidor) {
    final caminho = req.uri.path;
    if (caminho == '/ping') {
      req.response.write('ok');
    } else if (caminho == '/tudo.json') {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'estabelecimentos': [...todos, ...soNoArquivo]}));
    } else if (caminho == '/cnes/estabelecimentos') {
      if (falhar) {
        falhar = false;
        req.response.statusCode = 503;
        req.response.write('indisponivel');
        await req.response.close();
        continue;
      }
      final q = req.uri.queryParameters;
      final tipo = int.tryParse(q['codigo_tipo_unidade'] ?? '');
      final municipio = int.tryParse(q['codigo_municipio'] ?? '');
      var lista = todos.where((e) =>
          (municipio == null || e['codigo_municipio'] == municipio) &&
          (ignorarFiltro || tipo == null || e['codigo_tipo_unidade'] == tipo));
      var limit = int.tryParse(q['limit'] ?? '') ?? 20;
      if (limit > maxLimite) limit = maxLimite;
      final deslocamento = int.tryParse(q['offset'] ?? '') ?? 0;
      final offset = repetirPagina ? 0 : (offsetPorPagina ? deslocamento * limit : deslocamento);
      final pagina = lista.skip(offset).take(limit).toList();
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'estabelecimentos': pagina}));
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  }
}
