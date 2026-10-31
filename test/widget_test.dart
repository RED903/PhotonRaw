import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon_raw/main.dart';

void main() {
  testWidgets('PhotonRaw Studio smoke test', (WidgetTester tester) async {
    // 데스크톱 / 대화면 뷰포트 크기 설정
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // 앱 빌드 및 첫 프레임 렌더링
    await tester.pumpWidget(const PhotonRawApp());
    await tester.pumpAndSettle();

    // 상단 타이틀 확인
    expect(find.text('PhotonRaw'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
    expect(find.text('프리셋:'), findsOneWidget);
  });
}
