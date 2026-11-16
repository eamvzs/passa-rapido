import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../componentes/comuns.dart';

/// Documento de texto corrido com títulos de seção, usado nos termos e na política.
class _Documento extends StatelessWidget {
  const _Documento({required this.titulo, required this.secoes, required this.rodape});

  final String titulo;
  final List<(String, String)> secoes;
  final String rodape;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Espaco.g, Espaco.p, Espaco.g, Espaco.xg),
        children: [
          LarguraMaxima(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (cabecalho, texto) in secoes) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: Espaco.g, bottom: Espaco.pp),
                    child: Semantics(header: true, child: Text(cabecalho, style: tema.textTheme.titleMedium)),
                  ),
                  Text(texto, style: tema.textTheme.bodyMedium),
                ],
                const SizedBox(height: Espaco.gg),
                Text(rodape, style: tema.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _rodape = 'Projeto acadêmico (FIAP, Global Solution 2026). Estes textos descrevem como o aplicativo funciona '
    'e devem ser revisados por um profissional jurídico antes de qualquer uso comercial.';

class TermosTela extends StatelessWidget {
  const TermosTela({super.key});

  @override
  Widget build(BuildContext context) => const _Documento(
        titulo: 'Termos de uso',
        rodape: _rodape,
        secoes: [
          (
            'O que é o Passa Rápido',
            'Um aplicativo que mostra, em tempo real, a espera estimada em serviços públicos presenciais '
                '(UPAs, postos de saúde, Poupatempo, INSS e CRAS), a partir de informações enviadas pelos próprios cidadãos.',
          ),
          (
            'Os tempos são estimativas',
            'As esperas são calculadas com o que outras pessoas informam e podem estar erradas ou desatualizadas. '
                'O app não substitui a orientação da própria unidade. Em caso de emergência, ligue 192 (SAMU) e não espere por informação do aplicativo.',
          ),
          (
            'O que você se compromete a fazer',
            'Informar apenas o que viu, sem inventar filas, avisos ou avaliações; não usar o app para prejudicar pessoas ou serviços; '
                'não tentar burlar os limites de uso nem criar contas para inflar pontos. Registros suspeitos podem ser removidos.',
          ),
          (
            'Pontos e reputação',
            'Os pontos e o nível servem para dar mais peso a quem colabora com informações consistentes. '
                'Não têm valor financeiro e podem ser ajustados para combater abusos.',
          ),
          (
            'Sua conta',
            'Você pode excluir a conta a qualquer momento em Perfil > Excluir minha conta. A exclusão apaga seus dados pessoais.',
          ),
        ],
      );
}

class PrivacidadeTela extends StatelessWidget {
  const PrivacidadeTela({super.key});

  @override
  Widget build(BuildContext context) => const _Documento(
        titulo: 'Política de privacidade',
        rodape: _rodape,
        secoes: [
          (
            'Que dados coletamos',
            'Nome e e-mail do cadastro; as filas, avisos, avaliações, confirmações de acessibilidade, denúncias e sugestões de correção '
                'que você envia; sua localização no momento em que você informa uma fila (somente com a sua permissão); '
                'e, no próprio aparelho, as preferências de tela, o plano de ida e a última lista de unidades.',
          ),
          (
            'Para que usamos',
            'Para calcular a espera de cada unidade, ordenar as unidades por distância, validar que o registro foi feito perto da unidade '
                'e dar pontos a quem colabora. Não usamos seus dados para publicidade e não os vendemos.',
          ),
          (
            'Sua localização',
            'Com a sua permissão, o app lê a posição do aparelho enquanto está aberto para mostrar a distância, sugerir o registro de '
                'chegada e, se você ficar alguns minutos dentro de uma unidade, perguntar como está a fila. Essa leitura acontece no aparelho. '
                'A coordenada só é enviada junto com o registro de fila que você decidir fazer. O ponto que você escolhe no mapa para buscar '
                'a partir de outro lugar não é enviado a ninguém.',
          ),
          (
            'No seu aparelho',
            'Ficam guardados no aparelho: suas preferências, o plano de ida (hora do atendimento e unidade), e a última lista de unidades '
                'baixada, para o app funcionar sem internet. Nada disso é enviado. Limpar os dados do navegador ou do app apaga tudo.',
          ),
          (
            'O que outras pessoas veem',
            'Apenas seu primeiro nome com a inicial do sobrenome (por exemplo, "Ana S.") nos avisos, avaliações e no ranking. '
                'Seu e-mail, seu nome completo e sua localização exata nunca aparecem para outros usuários, e o identificador interno '
                'da sua conta não é divulgado nos avisos e avaliações. Denúncias e sugestões que você envia ficam visíveis só para a moderação.',
          ),
          (
            'Moderação',
            'Pessoas designadas como moderadoras analisam sugestões de correção e conteúdo denunciado. Elas veem o texto, a unidade e o '
                'primeiro nome com inicial do autor, nunca o e-mail. Conteúdo denunciado por várias pessoas pode ser ocultado.',
          ),
          (
            'Com quem compartilhamos',
            'Os dados ficam armazenados no Supabase (banco de dados e autenticação). O mapa é carregado do OpenStreetMap, '
                'que recebe o endereço de IP do seu aparelho ao baixar os mapas, como em qualquer site de mapas.',
          ),
          (
            'Por quanto tempo guardamos',
            'Enquanto a sua conta existir. Os registros de fila antigos são reunidos em médias por horário e deixam de ser ligados a você quando a conta é excluída.',
          ),
          (
            'Seus direitos (LGPD)',
            'Você pode acessar os dados do seu perfil na aba Perfil, corrigir o nome ao falar com o responsável pelo projeto e excluir a conta '
                'e todos os dados pessoais, a qualquer momento, em Perfil > Excluir minha conta.',
          ),
          (
            'Dados das unidades',
            'Nome, endereço e localização das unidades de saúde vêm do CNES/DATASUS (Ministério da Saúde, dados abertos); '
                'os demais serviços e os mapas vêm do OpenStreetMap (© colaboradores do OpenStreetMap, licença ODbL, openstreetmap.org/copyright). '
                'Os cadastros podem estar desatualizados. Os horários mostrados são os padrões de cada tipo de unidade, salvo quando a unidade informar o contrário.',
          ),
        ],
      );
}
