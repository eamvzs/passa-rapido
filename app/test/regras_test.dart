import 'package:flutter_test/flutter_test.dart';
import 'package:passa_rapido/core/agendamento.dart';
import 'package:passa_rapido/core/busca.dart';
import 'package:passa_rapido/core/formatos.dart';
import 'package:passa_rapido/core/insights.dart';
import 'package:passa_rapido/core/nivel_espera.dart';
import 'package:passa_rapido/core/previsao.dart';
import 'package:passa_rapido/data/repositorios.dart';
import 'package:passa_rapido/models/colaboracao.dart';
import 'package:passa_rapido/models/unidade.dart';

void main() {
  testesDeCamposNovos();
  group('insights da semana e por tipo', () {
    SlotSemanal slot(int dia, int hora, int media) => SlotSemanal(dia: dia, hora: hora, mediaMin: media, amostras: 0);

    test('melhor e pior janela da semana, com descrição legível', () {
      final r = melhorEPiorJanela([slot(1, 9, 50), slot(2, 14, 12), slot(3, 10, 80), slot(4, 8, 12)])!;
      expect(r.melhor.dia, 2); // empate em 12 min: vale o primeiro da semana
      expect(r.melhor.descricao, 'terça-feira às 14h (~12 min)');
      expect(r.pior.descricao, 'quarta-feira às 10h (~80 min)');
      expect(melhorEPiorJanela(const []), isNull);
    });

    Unidade u(String tipo, {int? espera, bool aberta = true, String fonte = 'historico'}) => Unidade(
          id: tipo.hashCode ^ (espera ?? 0) ^ fonte.hashCode,
          nome: tipo,
          endereco: 'x',
          bairro: null,
          cidade: 'São Paulo',
          latitude: -23.5,
          longitude: -46.6,
          telefone: null,
          tipoUnidadeId: 1,
          tipo: tipo,
          esperaMin: espera,
          nivel: NivelEspera.porMinutos(espera),
          fonte: fonte,
          confianca: 0,
          pessoasAguardando: 0,
          atualizadoEm: null,
          abertaAgora: aberta,
          notaMedia: null,
          qtdAvaliacoes: 0,
          relatosAtivos: 0,
          origem: 'cnes',
        );

    test('resumo por tipo: média só das abertas com dado, ordenado do mais vazio ao mais cheio', () {
      final r = resumirPorTipo([
        u('UPA', espera: 60),
        u('UPA', espera: 40),
        u('UPA', espera: 500, aberta: false), // fechada não entra na média
        u('UBS', espera: 20),
        u('INSS', aberta: false),
      ]);
      expect(r.map((x) => x.tipo), ['UBS', 'UPA', 'INSS']);
      expect(r[1].esperaMediaMin, 50);
      expect(r[1].abertas, 2);
      expect(r[1].total, 3);
      expect(r[2].esperaMediaMin, isNull);
      expect(r[0].somenteEstimativa, isTrue);
    });

    test('com fila informada por cidadãos, deixa de ser só estimativa', () {
      final r = resumirPorTipo([u('UPA', espera: 30, fonte: 'tempo_real'), u('UPA', espera: 50)]);
      expect(r.single.somenteEstimativa, isFalse);
    });
  });

  group('analisarMomento (ao vivo x típico)', () {
    PrevisaoHora h(int hora, int media) => PrevisaoHora(hora: hora, mediaMin: media, amostras: 0, melhor: false);
    final curva = [h(8, 20), h(9, 40), h(10, 60), h(11, 50), h(12, 30), h(13, 22)];

    test('ao vivo bem abaixo do típico: mais vazia', () {
      final a = analisarMomento(curva, 10, esperaAoVivo: 30)!;
      expect(a.momento, Momento.bom);
      expect(a.texto, startsWith('50% mais vazia'));
    });
    test('ao vivo bem acima do típico: mais cheia', () {
      final a = analisarMomento(curva, 9, esperaAoVivo: 60)!;
      expect(a.momento, Momento.pico);
      expect(a.texto, startsWith('50% mais cheia'));
    });
    test('ao vivo parecido com o típico: dentro do normal', () {
      expect(analisarMomento(curva, 10, esperaAoVivo: 62)!.momento, Momento.normal);
    });
    test('sem fila informada: hora vazia vira "bom momento", hora cheia vira pico', () {
      expect(analisarMomento(curva, 8)!.momento, Momento.bom);
      expect(analisarMomento(curva, 10)!.momento, Momento.pico);
    });
    test('hora intermediária, curva plana ou sem previsão: nada a dizer', () {
      expect(analisarMomento(curva, 11), isNull);
      expect(analisarMomento([h(8, 30), h(9, 32), h(10, 31)], 9), isNull);
      expect(analisarMomento(curva, 22), isNull);
      expect(analisarMomento(const [], 9), isNull);
    });
  });

  group('agendamentoDoTipo', () {
    test('Poupatempo, INSS e UBS têm atalho; UPA, pronto-socorro e CRAS não', () {
      expect(agendamentoDoTipo('Poupatempo')!.url, startsWith('https://'));
      expect(agendamentoDoTipo('INSS')!.rotulo, contains('INSS'));
      expect(agendamentoDoTipo('UBS')!.url, contains('gov.br'));
      expect(agendamentoDoTipo('UPA'), isNull);
      expect(agendamentoDoTipo('Pronto-socorro'), isNull);
      expect(agendamentoDoTipo('CRAS'), isNull);
    });
  });

  group('proximaAbertura', () {
    final semana = [
      for (var d = 1; d <= 5; d++) HorarioFuncionamento(diaSemana: d, abre: '08:00', fecha: '17:00'),
    ];
    test('de madrugada num dia útil: abre hoje', () {
      expect(proximaAbertura(semana, DateTime(2026, 11, 16, 3, 0)), 'Abre hoje às 08:00'); // segunda
    });
    test('depois do expediente: amanhã, ou segunda na sexta', () {
      expect(proximaAbertura(semana, DateTime(2026, 11, 17, 18, 0)), 'Abre amanhã às 08:00'); // terça
      expect(proximaAbertura(semana, DateTime(2026, 11, 20, 18, 0)), 'Abre segunda-feira às 08:00'); // sexta
    });
    test('no domingo: abre amanhã (segunda)', () {
      expect(proximaAbertura(semana, DateTime(2026, 11, 15, 10, 0)), 'Abre amanhã às 08:00');
    });
    test('sem horário cadastrado: nulo', () {
      expect(proximaAbertura(<HorarioFuncionamento>[], DateTime(2026, 11, 15)), isNull);
    });
  });

  group('busca por palavras', () {
    final itaquera = textoPesquisavel(
      nome: 'Unidade Básica de Saúde Itaquera',
      bairro: 'Itaquera',
      tipo: 'UBS',
      endereco: 'Rua Américo Salvador Novelli, 265 - Itaquera',
    );
    final lapa = textoPesquisavel(nome: 'UPA Lapa', bairro: 'Alto da Lapa', tipo: 'UPA', endereco: 'Avenida Queiroz Filho, 313');

    bool acha(String texto, String busca) => combinaComBusca(texto, palavrasDaBusca(busca));

    test('"ubs itaquera" acha "Unidade Básica de Saúde Itaquera"', () {
      expect(acha(itaquera, 'ubs itaquera'), isTrue);
      expect(acha(itaquera, 'itaquera ubs'), isTrue);
      expect(acha(lapa, 'ubs itaquera'), isFalse);
    });

    test('ignora acento, maiúsculas e espaços repetidos', () {
      expect(acha(itaquera, '  UNIDADE   básica  de saude '), isTrue);
      expect(acha(itaquera, 'AMÉRICO novelli'), isTrue);
    });

    test('todas as palavras precisam aparecer', () {
      expect(acha(itaquera, 'ubs lapa'), isFalse);
      expect(acha(lapa, 'upa alto lapa'), isTrue);
    });

    test('busca vazia não filtra nada', () {
      expect(palavrasDaBusca('   '), isEmpty);
      expect(acha(lapa, ''), isTrue);
    });

    test('procura também no endereço', () {
      expect(acha(lapa, 'queiroz filho'), isTrue);
    });
  });

  group('crédito do cadastro por fonte', () {
    Unidade comOrigem(String origem) => Unidade(
          id: 1,
          nome: 'X',
          endereco: 'Y',
          bairro: null,
          cidade: 'São Paulo',
          latitude: -23.5,
          longitude: -46.6,
          telefone: null,
          tipoUnidadeId: 1,
          tipo: 'UBS',
          esperaMin: null,
          nivel: NivelEspera.semDados,
          fonte: 'sem_dados',
          confianca: 0,
          pessoasAguardando: 0,
          atualizadoEm: null,
          abertaAgora: true,
          notaMedia: null,
          qtdAvaliacoes: 0,
          relatosAtivos: 0,
          origem: origem,
        );

    test('CNES, OpenStreetMap e demonstração', () {
      expect(comOrigem('cnes').creditoDoCadastro, contains('CNES/DATASUS'));
      expect(comOrigem('cnes').dadosReais, isTrue);
      expect(comOrigem('openstreetmap').creditoDoCadastro, contains('OpenStreetMap'));
      expect(comOrigem('openstreetmap').dadosReais, isTrue);
      expect(comOrigem('demonstracao').creditoDoCadastro, isNull);
      expect(comOrigem('demonstracao').dadosReais, isFalse);
    });
  });

  group('NivelEspera', () {
    test('classifica os minutos nas mesmas faixas do banco', () {
      expect(NivelEspera.porMinutos(null), NivelEspera.semDados);
      expect(NivelEspera.porMinutos(0), NivelEspera.baixa);
      expect(NivelEspera.porMinutos(15), NivelEspera.baixa);
      expect(NivelEspera.porMinutos(16), NivelEspera.moderada);
      expect(NivelEspera.porMinutos(45), NivelEspera.moderada);
      expect(NivelEspera.porMinutos(46), NivelEspera.alta);
      expect(NivelEspera.porMinutos(90), NivelEspera.alta);
      expect(NivelEspera.porMinutos(91), NivelEspera.critica);
    });

    test('converte o código vindo do banco e tolera valor desconhecido', () {
      expect(NivelEspera.porCodigo('critica'), NivelEspera.critica);
      expect(NivelEspera.porCodigo('qualquer'), NivelEspera.semDados);
      expect(NivelEspera.porCodigo(null), NivelEspera.semDados);
    });

    test('o texto sempre contrasta com a cor de fundo', () {
      for (final nivel in NivelEspera.values) {
        final fundo = nivel.cor.computeLuminance();
        final texto = nivel.corDoTexto.computeLuminance();
        final razao = (fundo > texto ? fundo + 0.05 : texto + 0.05) / (fundo > texto ? texto + 0.05 : fundo + 0.05);
        expect(razao, greaterThanOrEqualTo(4.5), reason: '${nivel.codigo} tem contraste ${razao.toStringAsFixed(2)}');
      }
    });
  });

  group('formatos', () {
    test('formatarEspera', () {
      expect(formatarEspera(null), 'Sem dados');
      expect(formatarEspera(0), '0 min');
      expect(formatarEspera(59), '59 min');
      expect(formatarEspera(60), '1 h');
      expect(formatarEspera(84), '1 h 24 min');
    });

    test('formatarEsperaCurta', () {
      expect(formatarEsperaCurta(null), '?');
      expect(formatarEsperaCurta(45), "45'");
      expect(formatarEsperaCurta(90), '1,5h');
    });

    test('formatarDistancia', () {
      expect(formatarDistancia(null), '');
      expect(formatarDistancia(0.35), '350 m');
      expect(formatarDistancia(2.43), '2,4 km');
      expect(formatarDistancia(14.6), '15 km');
    });

    test('iniciaisDe', () {
      expect(iniciaisDe('Ana Souza'), 'AS');
      expect(iniciaisDe('  maria  da silva '), 'MS');
      expect(iniciaisDe('Edu'), 'E');
      expect(iniciaisDe(''), '?');
    });

    test('formatarHaQuantoTempo', () {
      expect(formatarHaQuantoTempo(null), '');
      expect(formatarHaQuantoTempo(DateTime.now()), 'agora');
      expect(formatarHaQuantoTempo(DateTime.now().subtract(const Duration(minutes: 12))), 'há 12 min');
      expect(formatarHaQuantoTempo(DateTime.now().subtract(const Duration(hours: 3, minutes: 5))), 'há 3 h');
    });
  });

  group('modelos', () {
    test('Unidade.deMapa lê a linha da view do mapa', () {
      final unidade = Unidade.deMapa({
        'id': 7,
        'nome': 'UPA Teste',
        'endereco': 'Rua A',
        'bairro': null,
        'cidade': 'São Paulo',
        'latitude': -23.5,
        'longitude': -46.6,
        'telefone': null,
        'tipo_unidade_id': 1,
        'tipo': 'UPA',
        'espera_estimada_min': 38,
        'nivel': 'moderada',
        'fonte': 'tempo_real',
        'confianca': 70,
        'pessoas_aguardando': 3,
        'atualizado_em': '2026-11-14T20:00:00+00:00',
        'aberta_agora': true,
        'nota_media': 4.5,
        'qtd_avaliacoes': 2,
        'relatos_ativos': 1,
      });
      expect(unidade.nivel, NivelEspera.moderada);
      expect(unidade.emTempoReal, isTrue);
      expect(unidade.bairro, isNull);
      expect(unidade.notaMedia, 4.5);
    });

    test('Unidade.comSituacao aplica só a atualização de tempo real', () {
      final base = Unidade.deMapa({
        'id': 1, 'nome': 'X', 'endereco': 'E', 'cidade': 'C', 'latitude': 0, 'longitude': 0,
        'tipo_unidade_id': 1, 'tipo': 'UPA', 'espera_estimada_min': 10, 'nivel': 'baixa',
        'fonte': 'tempo_real', 'aberta_agora': true,
      });
      final nova = base.comSituacao({'espera_estimada_min': 95, 'nivel': 'critica', 'fonte': 'tempo_real', 'confianca': 40});
      expect(nova.esperaMin, 95);
      expect(nova.nivel, NivelEspera.critica);
      expect(nova.nome, 'X');
      expect(nova.abertaAgora, isTrue);
    });

    test('Perfil calcula pontos que faltam e progresso nos mesmos níveis do banco', () {
      const iniciante = Perfil(id: 'a', nome: 'A', pontos: 20, nivel: 'iniciante');
      expect(iniciante.pontosParaProximoNivel, 30);
      expect(iniciante.progressoNoNivel, closeTo(0.4, 0.001));

      const colaborador = Perfil(id: 'a', nome: 'A', pontos: 125, nivel: 'colaborador');
      expect(colaborador.pontosParaProximoNivel, 75);
      expect(colaborador.progressoNoNivel, closeTo(0.5, 0.001));

      const confiavel = Perfil(id: 'a', nome: 'A', pontos: 250, nivel: 'confiavel');
      expect(confiavel.pontosParaProximoNivel, isNull);
      expect(confiavel.progressoNoNivel, 1);
    });

    test('Relato diferencia aviso positivo e traduz o tipo', () {
      final relato = Relato.deMapa({
        'id': 1, 'unidade_id': 2, 'usuario_id': 'u', 'tipo': 'atendimento_normal',
        'confirmacoes': 0, 'criado_em': '2026-11-14T20:00:00+00:00',
      });
      expect(relato.positivo, isTrue);
      expect(relato.rotulo, 'Atendimento normal');
      expect(relato.autor, 'Cidadão');
    });

    test('TamanhoFila usa "média" quando o código é desconhecido', () {
      expect(TamanhoFila.porCodigo('lotada'), TamanhoFila.lotada);
      expect(TamanhoFila.porCodigo('xyz'), TamanhoFila.media);
    });
  });

  group('traduzirErro', () {
    test('mantém a mensagem das regras do banco (códigos PR)', () {
      const regra = ErroDeNegocio('Você já registrou esta unidade há menos de 10 minutos');
      expect(traduzirErro(regra).mensagem, contains('10 minutos'));
    });

    test('erro desconhecido vira mensagem de conexão', () {
      expect(traduzirErro(Exception('falha')).mensagem, contains('Sem conexão'));
    });
  });
}

void testesDeCamposNovos() {
  group('campos novos do banco', () {
    test('Unidade lê origem e horário padrão, com padrões seguros', () {
      final base = {
        'id': 1, 'nome': 'X', 'endereco': 'E', 'cidade': 'C', 'latitude': 0, 'longitude': 0,
        'tipo_unidade_id': 1, 'tipo': 'UPA', 'aberta_agora': true,
      };
      expect(Unidade.deMapa(base).dadosReais, isFalse);
      expect(Unidade.deMapa(base).horarioPadrao, isTrue);
      final real = Unidade.deMapa({...base, 'origem': 'openstreetmap', 'horario_padrao': false});
      expect(real.dadosReais, isTrue);
      expect(real.horarioPadrao, isFalse);
    });

    test('Perfil lê a confiabilidade e usa 50 quando o banco ainda não envia', () {
      expect(Perfil.deMapa({'id': 'a', 'nome': 'A', 'pontos': 0, 'nivel': 'iniciante'}).confiabilidade, 50);
      expect(Perfil.deMapa({'id': 'a', 'nome': 'A', 'pontos': 0, 'nivel': 'iniciante', 'confiabilidade': 87}).confiabilidade, 87);
    });

    test('Relato e Avaliacao usam o nome público gravado pelo banco', () {
      final relato = Relato.deMapa({
        'id': 1, 'unidade_id': 2, 'usuario_id': 'u', 'tipo': 'outro', 'autor': 'Ana S.',
        'confirmacoes': 0, 'criado_em': '2026-11-14T20:00:00+00:00',
      });
      expect(relato.autor, 'Ana S.');
      final avaliacao = Avaliacao.deMapa({'usuario_id': 'u', 'nota': 5, 'autor': 'Beto', 'criado_em': '2026-11-14T20:00:00+00:00'});
      expect(avaliacao.autor, 'Beto');
    });

    test('erros das regras novas do banco chegam ao usuário sem alteração', () {
      const mensagem = 'Você precisa estar perto da unidade para informar a fila (a menos de 500 m).';
      expect(traduzirErro(const ErroDeNegocio(mensagem)).mensagem, mensagem);
    });
  });
}
