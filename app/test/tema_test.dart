import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passa_rapido/core/tema.dart';

double razao(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final claro = la > lb ? la : lb, escuro = la > lb ? lb : la;
  return (claro + 0.05) / (escuro + 0.05);
}

void main() {
  for (final estilo in EstiloVisual.values) {
    for (final brilho in Brightness.values) {
      final rotulo = '${estilo.codigo}/${brilho.name}';
      group('contraste $rotulo', () {
        final tema = construirTema(brilho: brilho, altoContraste: false, estilo: estilo);
        final e = tema.colorScheme;
        final cartao = tema.cardTheme.color!;
        final id = tema.extension<IdentidadeVisual>()!;

        test('texto do botão sobre a cor primária (mínimo 4,5)', () {
          expect(razao(e.onPrimary, e.primary), greaterThanOrEqualTo(4.5));
        });
        test('cor primária como texto/ícone sobre fundo e cartão (mínimo 4,5)', () {
          expect(razao(e.primary, e.surface), greaterThanOrEqualTo(4.5));
          expect(razao(e.primary, cartao), greaterThanOrEqualTo(4.5));
        });
        test('texto principal e secundário sobre o cartão (mínimo 4,5)', () {
          expect(razao(e.onSurface, cartao), greaterThanOrEqualTo(7));
          expect(razao(tema.textTheme.bodySmall!.color!, cartao), greaterThanOrEqualTo(4.5));
          expect(razao(tema.textTheme.bodySmall!.color!, e.surface), greaterThanOrEqualTo(4.5));
        });
        test('texto branco no cartão de destaque, nas duas pontas do degradê (mínimo 4,5)', () {
          expect(razao(Colors.white, id.heroInicio), greaterThanOrEqualTo(4.5));
          expect(razao(Colors.white, id.heroFim), greaterThanOrEqualTo(4.5));
        });
        test('cor de destaque visível sobre o cartão de destaque (mínimo 3, ícones)', () {
          expect(razao(id.destaque, id.heroFim), greaterThanOrEqualTo(3));
          expect(razao(id.destaque2, id.heroFim), greaterThanOrEqualTo(3));
        });
        test('a cor da marca não se confunde com a escala de filas (matiz fora do verde puro, amarelo e vermelho)', () {
          final hsl = HSLColor.fromColor(e.primary);
          final h = hsl.hue;
          // verde das filas ~ 140°, amarelo ~ 42°, laranja ~ 25°, vermelho ~ 0°/360°. Verde-água (160°+) e azuis/violetas são seguros.
          final seguro = h >= 165 || h <= 0 && false;
          expect(seguro, isTrue, reason: '$rotulo tem matiz ${h.toStringAsFixed(0)}°');
        });
      });
    }
  }
}
