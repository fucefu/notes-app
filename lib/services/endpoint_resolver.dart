import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_config.dart';

/// 依据「当前 SSID + 用户偏好 + 连通性探测」选出本次要打开的地址。
class EndpointResolver {
  const EndpointResolver();

  /// 判定主地址。
  ///
  /// - 连着目标 WiFi 且偏好内网 → 主内网、备公网（探测不通时直接换公网）
  /// - 连着目标 WiFi 但偏好公网 → 主公网、备内网
  /// - 不是目标 WiFi → 主公网、备内网（不在内网就没必要等内网超时）
  Future<EndpointPlan> resolve(
    AppConfig config, {
    required String? ssid,
    required bool preferInternal,
  }) async {
    final target = config.ssid.trim();
    final current = ssid?.trim();
    final onTargetWifi =
        current != null &&
        current.isNotEmpty &&
        current.toLowerCase() == target.toLowerCase();

    final internalFirst = onTargetWifi && preferInternal;

    if (!internalFirst) {
      return EndpointPlan(
        primaryKind: EndpointKind.publicUrl,
        primaryUrl: config.publicUrl,
        fallbackKind: EndpointKind.internal,
        fallbackUrl: config.internalUrl,
        reason: onTargetWifi ? '已连接 $target（手动选择公网）' : _offWifiReason(current),
      );
    }

    // 在内网 WiFi 上：先探一下内网地址，避免打开后白屏再回退。
    final reachable = await probe(config.internalUrl);
    if (reachable) {
      return EndpointPlan(
        primaryKind: EndpointKind.internal,
        primaryUrl: config.internalUrl,
        fallbackKind: EndpointKind.publicUrl,
        fallbackUrl: config.publicUrl,
        reason: '已连接 $target',
      );
    }
    return EndpointPlan(
      primaryKind: EndpointKind.publicUrl,
      primaryUrl: config.publicUrl,
      fallbackKind: EndpointKind.internal,
      fallbackUrl: config.internalUrl,
      reason: '已连接 $target，但内网地址不可达',
    );
  }

  String _offWifiReason(String? current) {
    if (current == null || current.isEmpty) return '未连接 WiFi 或无法读取 SSID';
    return '当前 WiFi：$current';
  }

  /// 轻量连通性探测：能建立连接并返回 < 500 即视为可达。
  ///
  /// 401/403 也算可达——反向代理要求登录时也应先把页面打开。
  Future<bool> probe(
    String url, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (url.trim().isEmpty) return false;
    final client = HttpClient()..connectionTimeout = timeout;
    client.badCertificateCallback = (_, _, _) => false;
    try {
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'notes-app-probe/1.0');
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      return response.statusCode < 500;
    } on Exception catch (error) {
      debugPrint('探测 $url 失败：$error');
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
