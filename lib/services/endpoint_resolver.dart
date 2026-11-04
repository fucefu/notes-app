import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_config.dart';

/// 依据「当前 SSID + 用户偏好 + 连通性探测」选出本次要打开的地址。
///
/// 支持三种配置：
/// - 只填内网地址（仅内网模式）：始终走内网，没有公网可回退
/// - 内网 + 公网 + SSID：连上指定 WiFi 走内网，否则走公网
/// - 内网 + 公网但 SSID 留空：只要内网可达就走内网，否则走公网
class EndpointResolver {
  const EndpointResolver();

  Future<EndpointPlan> resolve(
    AppConfig config, {
    required String? ssid,
    required bool preferInternal,
  }) async {
    final target = config.ssid.trim();
    final current = ssid?.trim();
    final ssidConfigured = target.isNotEmpty;
    final onTargetWifi = ssidConfigured &&
        current != null &&
        current.isNotEmpty &&
        current.toLowerCase() == target.toLowerCase();

    // --- 仅内网模式：没填公网地址，唯一选择就是内网 ---
    if (!config.hasPublic) {
      return EndpointPlan(
        primaryKind: EndpointKind.internal,
        primaryUrl: config.internalUrl,
        fallbackKind: EndpointKind.internal,
        fallbackUrl: config.internalUrl,
        reason: ssidConfigured
            ? (onTargetWifi ? '已连接 $target' : _offWifiReason(current))
            : '仅内网模式',
        hasFallback: false,
      );
    }

    // --- 双地址模式 ---
    // SSID 留空时不按 WiFi 判断，直接以内网可达性为准。
    final internalFirst = ssidConfigured
        ? (onTargetWifi && preferInternal)
        : preferInternal;

    if (!internalFirst) {
      return EndpointPlan(
        primaryKind: EndpointKind.publicUrl,
        primaryUrl: config.publicUrl,
        fallbackKind: EndpointKind.internal,
        fallbackUrl: config.internalUrl,
        reason: ssidConfigured
            ? (onTargetWifi
                ? '已连接 $target（手动选择公网）'
                : _offWifiReason(current))
            : '手动选择公网',
        hasFallback: true,
      );
    }

    // 在内网 WiFi 上（或 SSID 未配置）：先探一下内网地址，避免白屏再回退。
    final reachable = await probe(config.internalUrl);
    if (reachable) {
      return EndpointPlan(
        primaryKind: EndpointKind.internal,
        primaryUrl: config.internalUrl,
        fallbackKind: EndpointKind.publicUrl,
        fallbackUrl: config.publicUrl,
        reason: ssidConfigured ? '已连接 $target' : '内网地址可达',
        hasFallback: true,
      );
    }
    return EndpointPlan(
      primaryKind: EndpointKind.publicUrl,
      primaryUrl: config.publicUrl,
      fallbackKind: EndpointKind.internal,
      fallbackUrl: config.internalUrl,
      reason: ssidConfigured
          ? '已连接 $target，但内网地址不可达'
          : '内网地址不可达',
      hasFallback: true,
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
