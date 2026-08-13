import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:muebles_andres/app.dart';

void main() {
  testWidgets('App arranca y muestra la puerta de autenticación',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MueblesAndresApp()),
    );
    await tester.pump();

    // No debe lanzar excepciones al construir el árbol inicial.
    expect(tester.takeException(), isNull);
  });
}
