import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_namer/main.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MyApp(cameras: <CameraDescription>[]),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
