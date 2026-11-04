import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// 读取当前 WiFi 状态。
///
/// - Android：依赖 `ACCESS_FINE_LOCATION` 运行时权限（系统限制，读 SSID 必须有定位权限）。
/// - iOS：依赖定位权限，iOS 14+ 还要求用户在设置里开启「精确定位」；部分系统版本会
///   返回 null。此时上层按「非内网」处理，由地址回退逻辑兜底。
class WifiService {
  final NetworkInfo _info = NetworkInfo();

  /// 申请读取 SSID 所需的定位权限，返回最终是否已授予。
  Future<bool> ensurePermission() async {
    if (kIsWeb) return false;
    if (Platform.isIOS) {
      final status = await Permission.locationWhenInUse.status;
      if (status.isGranted) return true;
      final result = await Permission.locationWhenInUse.request();
      return result.isGranted;
    }
    if (Platform.isAndroid) {
      // Android 12 及以上读 SSID 仍以定位权限为准。
      var status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        status = await Permission.locationWhenInUse.request();
      }
      return status.isGranted;
    }
    return false;
  }

  /// 当前连接的 WiFi 名称；未连接 WiFi 或权限不足时为 null。
  Future<String?> currentSsid() async {
    if (kIsWeb) return null;
    try {
      final raw = await _info.getWifiName();
      return normalizeSsid(raw);
    } on Exception catch (error) {
      debugPrint('读取 SSID 失败：$error');
      return null;
    }
  }

  /// 当前是否处在 WiFi 网络下（用于 UI 提示）。
  Future<bool> isOnWifi() async {
    if (kIsWeb) return false;
    try {
      final ip = await _info.getWifiIP();
      return ip != null && ip.isNotEmpty;
    } on Exception catch (error) {
      debugPrint('读取 WiFi IP 失败：$error');
      return false;
    }
  }

  /// 系统返回的 SSID 可能带英文双引号（iOS 常见），去掉再比较。
  static String? normalizeSsid(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.isEmpty) return null;
    return value;
  }
}
