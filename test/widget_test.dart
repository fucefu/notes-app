import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/pages/config_form_page.dart';
import 'package:notes_app/theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

/// 表单比默认测试画布(800x600)长，放大画布避免底部按钮被 ListView 裁掉。
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('引导页展示三个必填项', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _wrap(
        ConfigFormPage(
          title: '欢迎使用',
          submitLabel: '保存并连接',
          onSubmit: (_) async {},
        ),
      ),
    );

    expect(find.text('连接到你的便签'), findsOneWidget);
    expect(find.text('内网地址'), findsOneWidget);
    expect(find.text('公网地址（可选）'), findsOneWidget);
    expect(find.text('内网 WiFi 名称（可选）'), findsOneWidget);
    expect(find.text('保存并连接'), findsOneWidget);
  });

  testWidgets('只填内网地址也能提交（仅内网模式）', (tester) async {
    _useTallSurface(tester);
    String? publicUrl;
    await tester.pumpWidget(
      _wrap(
        ConfigFormPage(
          title: '欢迎使用',
          submitLabel: '保存并连接',
          onSubmit: (config) async {
            publicUrl = config.publicUrl;
          },
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '192.0.2.10:18080');
    await tester.tap(find.text('保存并连接'));
    await tester.pumpAndSettle();

    // 公网与 SSID 留空也应通过校验，公网地址为空串
    expect(publicUrl, '');
  });

  testWidgets('空表单提交只提示内网地址必填', (tester) async {
    _useTallSurface(tester);
    var submitted = false;
    await tester.pumpWidget(
      _wrap(
        ConfigFormPage(
          title: '欢迎使用',
          submitLabel: '保存并连接',
          onSubmit: (_) async {
            submitted = true;
          },
        ),
      ),
    );

    await tester.tap(find.text('保存并连接'));
    await tester.pumpAndSettle();

    expect(submitted, isFalse);
    expect(find.text('请填写内网地址'), findsOneWidget);
    // 公网地址与 SSID 为可选，不应再提示必填
    expect(find.text('请填写公网地址'), findsNothing);
    expect(find.text('请填写内网 WiFi 名称'), findsNothing);
  });

  testWidgets('填写完整后提交配置', (tester) async {
    _useTallSurface(tester);
    String? internalUrl;
    await tester.pumpWidget(
      _wrap(
        ConfigFormPage(
          title: '欢迎使用',
          submitLabel: '保存并连接',
          onSubmit: (config) async {
            internalUrl = config.internalUrl;
          },
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '192.0.2.10:18080');
    await tester.enterText(fields.at(1), 'https://notes.example.com');
    await tester.enterText(fields.at(2), 'HomeWiFi');
    await tester.tap(find.text('保存并连接'));
    await tester.pumpAndSettle();

    expect(internalUrl, 'http://192.0.2.10:18080');
  });
}
