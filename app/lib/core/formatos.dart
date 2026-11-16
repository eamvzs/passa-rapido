/// Formata minutos como "45 min" ou "1 h 20 min".
String formatarEspera(int? minutos) {
  if (minutos == null) return 'Sem dados';
  if (minutos < 60) return '$minutos min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  return resto == 0 ? '$horas h' : '$horas h $resto min';
}

/// Campo de texto de CSV: entre aspas e, se começar como fórmula de planilha (=, +, -, @), com apóstrofo na frente
/// para a planilha não executá-la. Nomes de unidades vêm de bases abertas editáveis por qualquer pessoa.
String campoCsv(String texto) {
  var t = texto.replaceAll('"', '""');
  if (RegExp(r'^[=+\-@\t\r]').hasMatch(t)) t = "'$t";
  return '"$t"';
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

/// Distância em linguagem natural: "350 m" ou "2,4 km".
String formatarDistancia(double? km) {
  if (km == null) return '';
  if (km < 1) return '${(km * 1000 / 10).round() * 10} m';
  return '${km.toStringAsFixed(km < 10 ? 1 : 0).replaceAll('.', ',')} km';
}

/// Iniciais para o avatar: "Ana Souza" vira "AS".
String iniciaisDe(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
  return (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
}
