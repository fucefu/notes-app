import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_config.dart';
import 'package:notes_app/theme.dart';

/// iOS 左缘返回手势的判定参数（与 home_page.dart 内保持一致）：
/// 手势区宽度 24 逻辑像素，向右拖动超过 60 逻辑像素才算一次返回。
const double kEdgeZoneWidth = 24;
const double kBackDragThreshold = 60;

Widget _wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

/// 一个最小可用的手势宿主，复刻 home_page 里左缘手势区的行为，
/// 便于在不依赖 WebView 的情况下验证判定逻辑。
class EdgeBackProbe extends StatefulWidget {
  const EdgeBackProbe({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<EdgeBackProbe> createState() => _EdgeBackProbeState();
}

class _EdgeBackProbeState extends State<EdgeBackProbe> {
  bool _active = false;
  double _distance = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.white, child: const SizedBox.expand()),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: kEdgeZoneWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _active = true,
              onHorizontalDragUpdate: (d) {
                if (!_active) return;
                _distance += d.delta.dx;
              },
              onHorizontalDragEnd: (_) {
                final dragged = _distance;
                _active = false;
                _distance = 0;
                if (dragged > kBackDragThreshold) widget.onBack();
              },
              onHorizontalDragCancel: () {
                _active = false;
                _distance = 0;
              },
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  group('iOS 左缘返回手势判定', () {
    testWidgets('向右滑足够远触发返回', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _wrap(EdgeBackProbe(onBack: () => fired++)),
      );

      // 从屏幕最左侧开始向右拖 100 像素（超过 60 阈值）
      final gesture = await tester.startGesture(const Offset(2, 400));
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fired, 1);
    });

    testWidgets('滑得太短不触发返回', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _wrap(EdgeBackProbe(onBack: () => fired++)),
      );

      // 只拖 30 像素，未达阈值
      final gesture = await tester.startGesture(const Offset(2, 400));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fired, 0);
    });

    testWidgets('从屏幕中间拖动不触发返回（不抢占网页交互）', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _wrap(EdgeBackProbe(onBack: () => fired++)),
      );

      // 起点在屏幕中央，不在左缘 24px 手势区
      final gesture = await tester.startGesture(const Offset(300, 400));
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fired, 0);
    });
  });

  group('包名相关：配置模型不依赖包名', () {
    test('AppConfig 序列化正常', () {
      final c = AppConfig(
        internalUrl: 'http://192.0.2.10:18080',
        publicUrl: '',
        ssid: '',
      );
      final restored = AppConfig.fromJson(c.toJson());
      expect(restored, isNotNull);
      expect(restored!.internalUrl, c.internalUrl);
      expect(restored.hasPublic, isFalse);
    });
  });
}
