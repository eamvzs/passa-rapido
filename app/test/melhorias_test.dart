import 'package:flutter_test/flutter_test.dart';
import 'package:passa_rapido/core/documentos.dart';
import 'package:passa_rapido/core/formatos.dart';
import 'package:passa_rapido/models/colaboracao.dart';
import 'package:passa_rapido/core/feriados.dart';
import 'package:passa_rapido/core/insights.dart';
import 'package:passa_rapido/core/nivel_espera.dart';
import 'package:passa_rapido/core/plano.dart';
import 'package:passa_rapido/core/presenca.dart';
import 'package:passa_rapido/core/triagem.dart';
import 'package:passa_rapido/models/unidade.dart';

Unidade unidade(int id, {int tipo = 1, double lat = -23.55, double lon = -46.63, int? espera, bool aberta = true}) => Unidade(
      id: id,
      nome: 'Unidade $id',
      endereco: 'x',
      bairro: 'Centro',
      cidade: 'São Paulo',
      latitude: lat,
      longitude: lon,
      telefone: null,
      tipoUnidadeId: tipo,
      tipo: 'UBS',
      esperaMin: espera,
      nivel: NivelEspera.porMinutos(espera),
      fonte: espera == null ? 'sem_dados' : 'historico',
      confianca: 0,
      pessoasAguardando: 0,
      atualizadoEm: null,
      abertaAgora: aberta,
      notaMedia: null,
      qtdAvaliacoes: 0,
      relatosAtivos: 0,
    );

void main() {
  group('feriados', () {
    test('Páscoa de 2026 e 2027 e as datas que dependem dela', () {
      expect(domingoDePascoa(2026), DateTime(2026, 4, 5));
      expect(domingoDePascoa(2027), DateTime(2027, 3, 28));
      final dias = feriadosDoAno(2026);
      DateTime de(String nome) => dias.firstWhere((f) => f.nome == nome).data;
      expect(de('Sexta-feira Santa'), DateTime(2026, 4, 3));
      expect(de('Corpus Christi'), DateTime(2026, 6, 4));
      expect(dias.where((f) => f.nome == 'Carnaval').map((f) => f.data), [DateTime(2026, 2, 16), DateTime(2026, 2, 17)]);
    });

    test('datas fixas, tipo e feriado municipal só em São Paulo', () {
      expect(feriadoDe(DateTime(2026, 11, 15))?.nome, 'Proclamação da República');
      expect(feriadoDe(DateTime(2026, 11, 20))?.nome, 'Dia da Consciência Negra');
      expect(feriadoDe(DateTime(2026, 7, 9))?.tipo, TipoDeFeriado.feriado);
      expect(feriadoDe(DateTime(2026, 2, 17))?.tipo, TipoDeFeriado.pontoFacultativo);
      expect(feriadoDe(DateTime(2026, 1, 25), cidade: 'São Paulo')?.nome, contains('São Paulo'));
      expect(feriadoDe(DateTime(2026, 1, 25), cidade: 'Campinas'), isNull);
      expect(feriadoDe(DateTime(2026, 11, 16)), isNull);
    });

    test('aviso para hoje, para amanhã e nenhum nos dias comuns', () {
      expect(avisoDeFeriado(DateTime(2026, 11, 15, 10)), contains('Hoje é feriado (Proclamação da República)'));
      expect(avisoDeFeriado(DateTime(2026, 11, 14, 10)), contains('Amanhã é feriado'));
      expect(avisoDeFeriado(DateTime(2026, 11, 17, 10)), isNull);
      expect(avisoDeFeriado(DateTime(2026, 12, 31, 10)), contains('Amanhã'), reason: 'passa de ano sem erro');
    });
  });

  group('o que levar', () {
    test('cada tipo tem lista, todas pedem documento com foto, e o tipo desconhecido não fica vazio', () {
      for (final tipo in ['UBS', 'UPA', 'Pronto-socorro', 'Poupatempo', 'INSS', 'CRAS', 'Outro']) {
        final lista = oQueLevar(tipo);
        expect(lista, isNotEmpty, reason: tipo);
        expect(lista.first, contains('Documento oficial com foto'), reason: tipo);
      }
      expect(oQueLevar('UPA'), oQueLevar('Pronto-socorro'));
      expect(oQueLevar('INSS').any((i) => i.contains('Meu INSS')), isTrue);
    });
  });

  group('triagem informativa', () {
    test('nenhum sinal: UBS', () {
      final r = avaliarTriagem({});
      expect(r.orientacao, Orientacao.ubs);
      expect(r.tiposDeUnidade, ['UBS']);
    });

    test('sinal de urgência: UPA ou pronto-socorro', () {
      final r = avaliarTriagem({'febre_alta'});
      expect(r.orientacao, Orientacao.upaOuProntoSocorro);
      expect(r.tiposDeUnidade, ['UPA', 'Pronto-socorro']);
    });

    test('qualquer sinal de emergência vence os outros e manda ligar 192', () {
      final r = avaliarTriagem({'febre_alta', 'dor_peito', 'chiado'});
      expect(r.orientacao, Orientacao.samu);
      expect(r.titulo, contains('192'));
      expect(r.tiposDeUnidade, isEmpty);
    });

    test('ids desconhecidos são ignorados e todos os sinais têm gravidade e texto', () {
      expect(avaliarTriagem({'nao_existe'}).orientacao, Orientacao.ubs);
      expect(sinaisDeAlerta.map((s) => s.id).toSet().length, sinaisDeAlerta.length, reason: 'ids únicos');
      expect(sinaisDeAlerta.every((s) => s.texto.length > 5), isTrue);
      for (final s in sinaisDeAlerta.where((s) => s.gravidade == GravidadeDoSinal.emergencia)) {
        expect(avaliarTriagem({s.id}).orientacao, Orientacao.samu, reason: s.id);
      }
      for (final s in sinaisDeAlerta.where((s) => s.gravidade == GravidadeDoSinal.urgencia)) {
        expect(avaliarTriagem({s.id}).orientacao, Orientacao.upaOuProntoSocorro, reason: s.id);
      }
    });
  });

  group('comparação com unidades vizinhas', () {
    test('compara com a média das vizinhas do mesmo tipo e indica a melhor', () {
      final alvo = unidade(1, espera: 60);
      final r = compararComVizinhas(alvo, [
        alvo,
        unidade(2, espera: 20, lat: -23.551),
        unidade(3, espera: 40, lat: -23.552),
        unidade(4, espera: 5, tipo: 2), // outro tipo: fora
        unidade(5, espera: 5, lat: -23.9), // longe (mais de 5 km): fora
        unidade(6, espera: 5, aberta: false), // fechada: fora
        unidade(7, lat: -23.553), // sem espera: fora
      ])!;
      expect(r.vizinhas, 2);
      expect(r.mediaMin, 30);
      expect(r.diferencaPct, 100);
      expect(r.melhor.id, 2);
    });

    test('sem comparação quando falta dado', () {
      final alvo = unidade(1, espera: 60);
      expect(compararComVizinhas(alvo, [alvo, unidade(2, espera: 20)]), isNull, reason: 'só uma vizinha');
      expect(compararComVizinhas(unidade(1, espera: null), [unidade(2, espera: 20), unidade(3, espera: 30)]), isNull);
      expect(compararComVizinhas(unidade(1, espera: 10, aberta: false), [unidade(2, espera: 20), unidade(3, espera: 30)]), isNull);
    });

    test('unidade mais vazia que a média dá porcentagem negativa', () {
      final alvo = unidade(1, espera: 15);
      final r = compararComVizinhas(alvo, [unidade(2, espera: 30), unidade(3, espera: 30)])!;
      expect(r.diferencaPct, -50);
    });
  });

  group('CSV seguro', () {
    test('texto que começa como fórmula ganha apóstrofo e aspas internas são dobradas', () {
      expect(campoCsv('UBS Centro'), '"UBS Centro"');
      expect(campoCsv('=HYPERLINK("http://x")'), '"\'=HYPERLINK(""http://x"")"');
      expect(campoCsv('+55 11'), '"\'+55 11"');
      expect(campoCsv('-cmd'), '"\'-cmd"');
      expect(campoCsv('@soma'), '"\'@soma"');
      expect(campoCsv('A=B'), '"A=B"', reason: 'só vale no começo do campo');
    });

    test('a tabela por região leva cabeçalho, uma linha por região e protege os textos', () {
      const r = RegiaoDaGestao(
        cidade: 'São Paulo',
        bairro: '=1+1',
        tipo: 'UBS',
        unidades: 3,
        abertasAgora: 2,
        esperaMediaMin: 25,
        unidadesComFilaReal: 0,
        registros7Dias: 0,
        horaPico: 10,
        esperaPicoMin: 60,
      );
      final linhas = regioesParaCsv([r]).split('\n');
      expect(linhas, hasLength(2));
      expect(linhas.first, startsWith('cidade;bairro;tipo;'));
      expect(linhas.last, '"São Paulo";"\'=1+1";"UBS";3;2;25;0;0;10;60;sim');
    });
  });

  group('acessibilidade e fonte oficial', () {
    test('resumo da confirmação por pessoas', () {
      ContagemDeRecurso c(int sim, int nao) =>
          ContagemDeRecurso(recurso: RecursoDeAcessibilidade.rampa, sim: sim, nao: nao);
      expect(c(0, 0).resumo, 'Sem confirmação ainda');
      expect(c(1, 0).resumo, 'Confirmado por 1 pessoa');
      expect(c(4, 1).resumo, 'Confirmado por 4 pessoas');
      expect(c(4, 1).existe, isTrue);
      expect(c(1, 3).resumo, '3 pessoas dizem que não tem');
      expect(c(1, 3).inexiste, isTrue);
      expect(c(2, 2).resumo, 'Opiniões divididas');
      expect(c(2, 2).existe, isFalse);
      expect(RecursoDeAcessibilidade.porCodigo('banheiro_adaptado'), RecursoDeAcessibilidade.banheiroAdaptado);
      expect(RecursoDeAcessibilidade.porCodigo('xyz'), isNull);
      expect(ContagemDeRecurso.deMapa({'recurso': 'xyz', 'sim': 1, 'nao': 0}), isNull);
    });

    test('fonte oficial conta como dado real, não como estimativa', () {
      final base = unidade(1, espera: 20);
      final oficial = base.comSituacao({'espera_estimada_min': 15, 'nivel': 'baixa', 'fonte': 'oficial'});
      expect(oficial.oficial, isTrue);
      expect(oficial.emTempoReal, isTrue);
      expect(oficial.estimada, isFalse);
      expect(base.oficial, isFalse);
      expect(base.estimada, isTrue);
    });

    test('impacto semanal soma as contribuições', () {
      final i = ImpactoSemanal.deMapa({
        'registros_7d': 3, 'unidades_7d': 2, 'pontos_7d': 14, 'avisos_7d': 1, 'avaliacoes_7d': 0, 'sugestoes_aceitas': 1,
      });
      expect(i.contribuicoes, 5);
      expect(i.pontos, 14);
    });
  });

  group('plano de ida', () {
    test('a saída é o horário menos o deslocamento menos a folga', () {
      final p = PlanoDeIda.calcular(
          unidadeId: 7, nomeUnidade: 'UBS X', horario: DateTime(2026, 11, 16, 14), deslocamentoMin: 30);
      expect(p.saida, DateTime(2026, 11, 16, 13, 15));
      expect(PlanoDeIda.deslocamentoPorDistancia(5), 15);
      expect(PlanoDeIda.deslocamentoPorDistancia(0.01), 1);
    });

    test('grava e lê; texto corrompido vira nulo; vence 1 hora depois', () {
      final p = PlanoDeIda.calcular(
          unidadeId: 7, nomeUnidade: 'UBS X', horario: DateTime(2026, 11, 16, 14), deslocamentoMin: 30);
      final lido = PlanoDeIda.deJson(p.toJson())!;
      expect(lido.unidadeId, 7);
      expect(lido.saida, p.saida);
      expect(PlanoDeIda.deJson('{lixo'), isNull);
      expect(PlanoDeIda.deJson(null), isNull);
      expect(PlanoDeIda.deJson('{"unidade_id": "x"}'), isNull);
      expect(p.venceu(DateTime(2026, 11, 16, 14, 59)), isFalse);
      expect(p.venceu(DateTime(2026, 11, 16, 15, 1)), isTrue);
    });
  });

  group('detector de presença', () {
    final base = DateTime(2026, 11, 16, 9);
    final u = unidade(1, lat: -23.55, lon: -46.63);

    test('pergunta só depois de 10 minutos perto da unidade, e uma vez', () {
      final d = DetectorDePresenca();
      const aqui = (-23.55, -46.63);
      expect(d.atualizar(posicao: aqui, unidades: [u], agora: base), isNull, reason: 'acabou de chegar');
      expect(d.atualizar(posicao: aqui, unidades: [u], agora: base.add(const Duration(minutes: 9))), isNull);
      expect(d.atualizar(posicao: aqui, unidades: [u], agora: base.add(const Duration(minutes: 10))), 1);
      expect(d.atualizar(posicao: aqui, unidades: [u], agora: base.add(const Duration(minutes: 20))), isNull,
          reason: 'já perguntou');
      expect(d.atualizar(posicao: aqui, unidades: [u], agora: base.add(const Duration(hours: 3, minutes: 11))), 1,
          reason: 'depois do silêncio pergunta de novo');
    });

    test('sair do raio zera a contagem; unidade fechada nunca gera pergunta', () {
      final d = DetectorDePresenca();
      const aqui = (-23.55, -46.63);
      d.atualizar(posicao: aqui, unidades: [u], agora: base);
      expect(d.atualizar(posicao: (-23.56, -46.63), unidades: [u], agora: base.add(const Duration(minutes: 5))), isNull);
      d.atualizar(posicao: aqui, unidades: [u], agora: base.add(const Duration(minutes: 6)));
      expect(d.atualizar(posicao: aqui, unidades: [u], agora: base.add(const Duration(minutes: 12))), isNull,
          reason: 'recomeçou aos 6 min');
      final fechada = unidade(1, aberta: false);
      final d2 = DetectorDePresenca();
      d2.atualizar(posicao: aqui, unidades: [fechada], agora: base);
      expect(d2.atualizar(posicao: aqui, unidades: [fechada], agora: base.add(const Duration(minutes: 30))), isNull);
    });

    test('silenciar (pessoa dispensou) impede a pergunta', () {
      final d = DetectorDePresenca();
      const aqui = (-23.55, -46.63);
      d.atualizar(posicao: aqui, unidades: [u], agora: base);
      d.silenciar(1, base);
      expect(d.atualizar(posicao: aqui, unidades: [u], agora: base.add(const Duration(minutes: 15))), isNull);
    });

    test('com duas unidades, vale a mais próxima', () {
      final d = DetectorDePresenca();
      final perto = unidade(2, lat: -23.5501, lon: -46.63);
      final longe = unidade(3, lat: -23.5508, lon: -46.63);
      d.atualizar(posicao: (-23.55, -46.63), unidades: [longe, perto], agora: base);
      expect(d.atualizar(posicao: (-23.55, -46.63), unidades: [longe, perto], agora: base.add(const Duration(minutes: 11))), 2);
    });
  });
}
