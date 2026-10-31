import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon_raw/main.dart';

void main() {
  testWidgets('SemiDarktable Studio smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PhotonRawApp());
    await tester.pumpAndSettle();

    expect(find.text('SemiDarktable'), findsOneWidget);
    expect(find.text('사진 열기'), findsOneWidget);
  });
}
