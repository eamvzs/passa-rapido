import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

/// Resultado da tentativa de localizar o usuário.
class Localizacao {
  const Localizacao(this.ponto, {required this.real});

  final LatLng ponto;

  /// Falso quando caímos no ponto padrão por falta de permissão ou de sinal.
  final bool real;
}

class LocalizacaoServico {
  static const _padrao = Localizacao(
    LatLng(AppConfig.latitudePadrao, AppConfig.longitudePadrao),
    real: false,
  );

  /// Nunca lança erro: sem permissão ou sem GPS, devolve o centro de São Paulo.
  Future<Localizacao> obter() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _padrao;
      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      if (permissao == LocationPermission.denied || permissao == LocationPermission.deniedForever) {
        return _padrao;
      }
      final posicao = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return Localizacao(LatLng(posicao.latitude, posicao.longitude), real: true);
    } catch (_) {
      return _padrao;
    }
  }
}
