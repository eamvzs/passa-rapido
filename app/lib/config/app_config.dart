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

  /// Centro de São Paulo, usado quando a localização não está disponível.
  static const latitudePadrao = -23.5505;
  static const longitudePadrao = -46.6333;
}
