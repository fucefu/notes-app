import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_config.dart';
import 'package:notes_app/services/wifi_service.dart';

void main() {
  group('normalizeUrl', () {
    test('补全缺失的 scheme', () {
      expect(normalizeUrl('192.0.2.10:18080'), 'http://192.0.2.10:18080');
    });

    test('保留已有的 https', () {
      expect(
        normalizeUrl('https://notes.example.com'),
        'https://notes.example.com',
      );
    });

    test('去掉尾部斜杠与空白', () {
      expect(
        normalizeUrl('  https://notes.example.com/  '),
        'https://notes.example.com',
      );
    });

    test('空串保持为空', () {
      expect(normalizeUrl('   '), '');
    });
  });

  group('normalizeSsid', () {
    test('去掉 iOS 返回的引号', () {
      expect(WifiService.normalizeSsid('"HomeWiFi"'), 'HomeWiFi');
    });

    test('普通名称原样返回', () {
      expect(WifiService.normalizeSsid(' HomeWiFi '), 'HomeWiFi');
    });

    test('空值返回 null', () {
      expect(WifiService.normalizeSsid(null), isNull);
      expect(WifiService.normalizeSsid('""'), isNull);
      expect(WifiService.normalizeSsid('   '), isNull);
    });
  });

  group('AppConfig', () {
    final config = AppConfig(
      internalUrl: 'http://192.0.2.10:18080',
      publicUrl: 'https://notes.example.com',
      ssid: 'HomeWiFi',
    );

    test('JSON 往返一致', () {
      final restored = AppConfig.fromJson(config.toJson());
      expect(restored, isNotNull);
      expect(restored!.internalUrl, config.internalUrl);
      expect(restored.publicUrl, config.publicUrl);
      expect(restored.ssid, config.ssid);
      expect(restored.preferInternal, isTrue);
    });

    test('字段缺失时视为无效配置', () {
      expect(AppConfig.fromJson({'internalUrl': 'http://a'}), isNull);
      expect(AppConfig.fromJson(null), isNull);
    });

    test('copyWith 只改指定字段', () {
      final updated = config.copyWith(preferInternal: false);
      expect(updated.preferInternal, isFalse);
      expect(updated.ssid, config.ssid);
    });
  });
}
