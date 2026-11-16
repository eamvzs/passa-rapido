/// Lista do que levar a cada tipo de unidade. É orientação geral: o serviço específico pode pedir mais
/// (a ficha mostra os documentos de cada serviço), e as regras mudam; por isso o aviso final.
library;

const _documentoComFoto = 'Documento oficial com foto (RG, CNH ou outro)';

const aviso = 'Confirme no site oficial ou por telefone: as exigências mudam de serviço para serviço.';

List<String> oQueLevar(String tipo) => switch (tipo) {
      'UBS' => const [
          _documentoComFoto,
          'Cartão Nacional de Saúde (cartão SUS), se tiver',
          'CPF',
          'Comprovante de endereço (no primeiro cadastro)',
          'Cartão de vacinação, exames e receitas anteriores, se tiver',
        ],
      'UPA' || 'Pronto-socorro' => const [
          _documentoComFoto,
          'Cartão Nacional de Saúde (cartão SUS), se tiver',
          'Lista dos remédios que usa e das alergias',
          'Exames e receitas recentes, se tiver',
          'Criança: documento dela e a presença de um responsável',
        ],
      'Poupatempo' => const [
          _documentoComFoto,
          'CPF',
          'Comprovante de agendamento, se agendou',
          'Comprovante de residência, quando o serviço pedir',
        ],
      'INSS' => const [
          _documentoComFoto,
          'CPF',
          'Número do requerimento ou do protocolo do Meu INSS',
          'Documentos do benefício (carteira de trabalho, laudos, comprovantes)',
        ],
      'CRAS' => const [
          _documentoComFoto,
          'CPF',
          'Comprovante de residência',
          'NIS ou número do CadÚnico, se tiver',
          'Documentos das pessoas da família que serão cadastradas',
        ],
      _ => const [_documentoComFoto, 'CPF'],
    };
