/// Formata minutos como "45 min" ou "1 h 20 min".
String formatarEspera(int? minutos) {
  if (minutos == null) return 'Sem dados';
  if (minutos < 60) return '$minutos min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  return resto == 0 ? '$horas h' : '$horas h $resto min';
}

/// Texto curto para o marcador do mapa.
String formatarEsperaCurta(int? minutos) {
  if (minutos == null) return '?';
  if (minutos < 60) return "$minutos'";
  final horas = minutos / 60;
  return '${horas.toStringAsFixed(horas >= 10 ? 0 : 1).replaceAll('.', ',')}h';
}

/// Tempo decorrido em linguagem natural: "agora", "há 12 min", "há 3 h".
String formatarHaQuantoTempo(DateTime? momento) {
  if (momento == null) return '';
  final diferenca = DateTime.now().difference(momento);
  if (diferenca.inMinutes < 1) return 'agora';
  if (diferenca.inMinutes < 60) return 'há ${diferenca.inMinutes} min';
  if (diferenca.inHours < 24) return 'há ${diferenca.inHours} h';
  return 'há ${diferenca.inDays} d';
}

const diasDaSemana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
