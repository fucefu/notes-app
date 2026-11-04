/// App 的运行配置：内网地址、公网地址、内网 WiFi 的 SSID。
///
/// 判断逻辑与 Home Assistant Companion 一致：
/// 当前连接的 WiFi 名字等于 [ssid] 时优先走 [internalUrl]，否则优先走 [publicUrl]。
class AppConfig {
  const AppConfig({
    required this.internalUrl,
    required this.publicUrl,
    required this.ssid,
    this.preferInternal = true,
  });

  /// 内网地址，形如 `http://192.0.2.10:18080`
  final String internalUrl;

  /// 公网地址，形如 `https://notes.example.com`
  final String publicUrl;

  /// 内网 WiFi 的 SSID（区分大小写，比较时忽略首尾空白）
  final String ssid;

  /// 用户在手动切换里设定的偏好，true 表示下次仍优先内网
  final bool preferInternal;

  /// 内网地址必填；公网地址可选——只在局域网使用的人可以不填。
  /// SSID 也可留空，此时只要内网地址可用就走内网（等同「仅内网模式」）。
  bool get isComplete => internalUrl.trim().isNotEmpty;

  /// 是否只配了内网地址（仅内网模式）。
  bool get internalOnly => internalUrl.trim().isNotEmpty && publicUrl.trim().isEmpty;

  /// 是否配了公网地址，可用于回退。
  bool get hasPublic => publicUrl.trim().isNotEmpty;

  AppConfig copyWith({
    String? internalUrl,
    String? publicUrl,
    String? ssid,
    bool? preferInternal,
  }) {
    return AppConfig(
      internalUrl: internalUrl ?? this.internalUrl,
      publicUrl: publicUrl ?? this.publicUrl,
      ssid: ssid ?? this.ssid,
      preferInternal: preferInternal ?? this.preferInternal,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'internalUrl': internalUrl,
    'publicUrl': publicUrl,
    'ssid': ssid,
    'preferInternal': preferInternal,
  };

  static AppConfig? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final internalUrl = (json['internalUrl'] as String?)?.trim() ?? '';
    final publicUrl = (json['publicUrl'] as String?)?.trim() ?? '';
    final ssid = (json['ssid'] as String?)?.trim() ?? '';
    // 只有内网地址是必需的：允许只填内网、公网留空。
    if (internalUrl.isEmpty) return null;
    return AppConfig(
      internalUrl: internalUrl,
      publicUrl: publicUrl,
      ssid: ssid,
      preferInternal: (json['preferInternal'] as bool?) ?? true,
    );
  }
}

/// 本次实际使用的地址来源。
enum EndpointKind {
  internal,
  publicUrl;

  String get label => this == EndpointKind.internal ? '内网' : '公网';
}

/// 解析结果：主地址 + 备用地址。
class EndpointPlan {
  const EndpointPlan({
    required this.primaryKind,
    required this.primaryUrl,
    required this.fallbackKind,
    required this.fallbackUrl,
    required this.reason,
    this.hasFallback = true,
  });

  final EndpointKind primaryKind;
  final String primaryUrl;
  final EndpointKind fallbackKind;
  final String fallbackUrl;

  /// 供 UI 展示的判定理由，例如「已连接 家庭WiFi」/「当前网络非内网 WiFi」
  final String reason;

  /// 是否有备用地址可切。仅内网模式（未填公网）时为 false。
  final bool hasFallback;
}

/// 规范化用户输入的地址：补 scheme、去尾部斜杠。
String normalizeUrl(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return value;
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'http://$value';
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
