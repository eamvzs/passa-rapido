import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../componentes/comuns.dart';

/// Ajuda em linguagem simples: como usar, o que significam as siglas, como ler as cores e os direitos de quem procura atendimento.
class AjudaTela extends StatelessWidget {
  const AjudaTela({super.key});

  static const _passos = [
    ('1', 'Veja o mapa', 'Cada ponto é um lugar de atendimento. A cor mostra quanto tempo se espera: verde é pouco, vermelho é muito.'),
    ('2', 'Escolha o melhor', 'Na aba "Rápido" o app soma o caminho e a fila e diz qual lugar chega mais cedo.'),
    ('3', 'Ajude os outros', 'Chegou? Toque em "Cheguei na fila". Foi atendido? Avise. Cada aviso ajuda a próxima pessoa.'),
  ];

  static const _siglas = [
    ('UBS', 'Unidade Básica de Saúde, o "posto de saúde". Consultas, vacinas, receitas e acompanhamento.'),
    ('UPA', 'Unidade de Pronto Atendimento. Casos urgentes, 24 horas, que não são de morrer agora.'),
    ('Pronto-socorro', 'Hospital com atendimento de urgência e emergência.'),
    ('SAMU 192', 'Ambulância. Ligue de graça, de qualquer telefone, em emergência.'),
    ('CRAS', 'Centro de Referência de Assistência Social. Ajuda com benefícios e cadastro de famílias.'),
    ('INSS', 'Instituto Nacional do Seguro Social. Aposentadoria, auxílios e benefícios.'),
    ('Poupatempo', 'Central de serviços do governo de São Paulo: RG, CNH e outros documentos.'),
    ('CadÚnico / NIS', 'Cadastro das famílias de baixa renda e o número de identificação social.'),
    ('Cartão SUS', 'Cartão Nacional de Saúde. Facilita o atendimento, mas pode ser feito no próprio local.'),
  ];

  static const _cores = [
    ('Número com "~"', 'É uma estimativa do modelo, a partir do que costuma acontecer neste dia e hora. Ninguém informou a fila ainda.'),
    ('"Informado por cidadãos"', 'Pessoas que estão no local contaram como está a fila. Quanto mais gente, mais confiável.'),
    ('"Dado oficial"', 'O próprio órgão responsável enviou a espera.'),
    ('Fechada', 'Fora do horário padrão do tipo de unidade. Confirme por telefone, pode haver exceção.'),
  ];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajuda')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
        children: [
          LarguraMaxima(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Secao(
                  icone: Icons.touch_app_rounded,
                  titulo: 'Como usar em 3 passos',
                  child: Column(
                    children: [
                      for (final (numero, titulo, texto) in _passos)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: tema.colorScheme.primary.withValues(alpha: 0.12),
                            foregroundColor: tema.colorScheme.primary,
                            child: Text(numero),
                          ),
                          title: Text(titulo, style: tema.textTheme.titleSmall),
                          subtitle: Text(texto),
                        ),
                    ],
                  ),
                ),
                Secao(
                  icone: Icons.palette_outlined,
                  titulo: 'Como ler os números',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (titulo, texto) in _cores)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Espaco.m),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(titulo, style: tema.textTheme.titleSmall),
                              Text(texto),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Secao(
                  icone: Icons.abc_rounded,
                  titulo: 'O que significam as siglas',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (sigla, texto) in _siglas)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Espaco.m),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sigla, style: tema.textTheme.titleSmall),
                              Text(texto),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Secao(
                  icone: Icons.balance_rounded,
                  titulo: 'Seus direitos',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Atendimento prioritário: pessoas com 60 anos ou mais, gestantes, lactantes, pessoas com '
                        'crianças de colo e pessoas com deficiência ou mobilidade reduzida têm direito a ser '
                        'atendidas antes, sem fila comum. Quem tem 80 anos ou mais tem preferência especial entre os idosos '
                        '(Leis 10.048/2000, 10.741/2003, 13.146/2015 e 13.466/2017).',
                      ),
                      const SizedBox(height: Espaco.m),
                      const Text(
                        'Urgência não espera: em emergência, ligue 192. O atendimento de urgência no SUS não pode ser negado.',
                      ),
                      const SizedBox(height: Espaco.m),
                      Text(
                        'Este resumo é informativo. Em caso de dúvida, procure a ouvidoria do SUS (136) ou a Defensoria Pública.',
                        style: tema.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Secao(
                  icone: Icons.data_saver_on_rounded,
                  titulo: 'Internet fraca ou plano limitado?',
                  child: Text(
                    'Em Perfil, ligue o "Modo econômico": o app mostra só a lista de lugares por distância, sem baixar o '
                    'mapa. Se a internet cair, o app mostra os últimos dados salvos e avisa a hora deles.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
