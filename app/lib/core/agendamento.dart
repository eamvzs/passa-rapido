/// Canal oficial para agendar ou resolver à distância antes de ir à unidade.
class Agendamento {
  const Agendamento({required this.rotulo, required this.url, required this.nota});

  final String rotulo;
  final String url;
  final String nota;
}

/// Atalho para o canal oficial de agendamento do tipo de unidade, quando existe. UPA e pronto-socorro atendem sem
/// agendamento; CRAS não tem um canal único, então ficam sem atalho.
Agendamento? agendamentoDoTipo(String tipo) => switch (tipo) {
      'Poupatempo' => const Agendamento(
          rotulo: 'Agendar no Poupatempo',
          url: 'https://www.poupatempo.sp.gov.br/',
          nota: 'O agendamento é gratuito e evita a fila de quem chega sem horário marcado.',
        ),
      'INSS' => const Agendamento(
          rotulo: 'Agendar pelo Meu INSS',
          url: 'https://meu.inss.gov.br/',
          nota: 'Muitos serviços do INSS podem ser resolvidos online, sem ir à agência.',
        ),
      'UBS' => const Agendamento(
          rotulo: 'Ver o Meu SUS Digital',
          url: 'https://www.gov.br/pt-br/apps/conecte-sus',
          nota: 'Em cidades que usam o sistema, a consulta na UBS pode ser marcada pelo aplicativo (conta gov.br).',
        ),
      _ => null,
    };
