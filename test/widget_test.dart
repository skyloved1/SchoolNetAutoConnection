import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_net2/main.dart';

void main() {
  testWidgets('shows campus network login form', (WidgetTester tester) async {
    await tester.pumpWidget(const CampusNetworkApp());
    await tester.pump();

    expect(find.text('济宁学院校园网'), findsOneWidget);
    expect(find.widgetWithText(TextField, '账号'), findsOneWidget);
    expect(find.widgetWithText(TextField, '密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('注销'), findsOneWidget);
  });
}
