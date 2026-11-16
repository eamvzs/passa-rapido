/// Endereço e chave pública do backend. Podem ser trocados na compilação com
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...`.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ccjkejxcvisauiplflvb.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_cjYYw_9jMllnckCVdcszkg_61Iib5cs',
  );

  /// Endereço dos blocos do mapa. O servidor público do OpenStreetMap serve para desenvolvimento e uso leve;
  /// em produção, troque por um provedor contratado na compilação:
  /// `--dart-define=TILE_URL=https://seu-provedor/{z}/{x}/{y}.png`.
  static const tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Centro de São Paulo, usado quando a localização não está disponível.
  static const latitudePadrao = -23.5505;
  static const longitudePadrao = -46.6333;
}
