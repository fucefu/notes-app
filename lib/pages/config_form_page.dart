import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../services/wifi_service.dart';
import '../theme.dart';

/// 配置表单：首次启动的引导页与后续的设置页共用同一套字段。
class ConfigFormPage extends StatefulWidget {
  const ConfigFormPage({
    super.key,
    required this.title,
    required this.submitLabel,
    this.initial,
    this.showCancel = false,
    this.wifiService,
    this.onSubmit,
  });

  final String title;
  final String submitLabel;
  final AppConfig? initial;
  final bool showCancel;
  final WifiService? wifiService;

  /// 提供时直接回调（用于首次引导这种没有上层可 pop 的场景）。
  final Future<void> Function(AppConfig config)? onSubmit;

  @override
  State<ConfigFormPage> createState() => _ConfigFormPageState();
}

class _ConfigFormPageState extends State<ConfigFormPage> {
  late final WifiService _wifi = widget.wifiService ?? WifiService();
  late final TextEditingController _internalCtrl;
  late final TextEditingController _publicCtrl;
  late final TextEditingController _ssidCtrl;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _saving = false;
  bool _readingSsid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _internalCtrl = TextEditingController(text: initial?.internalUrl ?? '');
    _publicCtrl = TextEditingController(text: initial?.publicUrl ?? '');
    _ssidCtrl = TextEditingController(text: initial?.ssid ?? '');
  }

  @override
  void dispose() {
    _internalCtrl.dispose();
    _publicCtrl.dispose();
    _ssidCtrl.dispose();
    super.dispose();
  }

  Future<void> _fillCurrentSsid() async {
    setState(() => _readingSsid = true);
    try {
      final granted = await _wifi.ensurePermission();
      if (!granted) {
        if (mounted) {
          setState(() => _error = '未获得定位权限，无法读取 WiFi 名称。请在系统设置里授予定位权限后重试。');
        }
        return;
      }
      final ssid = await _wifi.currentSsid();
      if (!mounted) return;
      if (ssid == null) {
        setState(() => _error = '当前没有连接到 WiFi，或系统拒绝提供名称。请手动填写。');
        return;
      }
      _ssidCtrl.text = ssid;
      setState(() => _error = null);
    } finally {
      if (mounted) setState(() => _readingSsid = false);
    }
  }

  String? _validateUrl(String? raw, String field) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '请填写$field';
    final normalized = normalizeUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '$field格式不正确';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = AppConfig(
        internalUrl: normalizeUrl(_internalCtrl.text),
        publicUrl: normalizeUrl(_publicCtrl.text),
        ssid: _ssidCtrl.text.trim(),
        preferInternal: widget.initial?.preferInternal ?? true,
      );
      if (widget.onSubmit != null) {
        await widget.onSubmit!(config);
      } else if (mounted) {
        Navigator.of(context).pop(config);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnboarding = !widget.showCancel;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        automaticallyImplyLeading: widget.showCancel,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (isOnboarding) ...[
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppPalette.accent.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.sticky_note_2_outlined,
                      color: AppPalette.accent,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '连接到你的便签',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '在家连上指定 WiFi 自动走内网地址，出门自动走公网域名。\n两个地址都会保存，随时可以在设置里修改。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppPalette.inkSoft,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              _label('内网地址'),
              TextFormField(
                controller: _internalCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'http://192.0.2.10:18080',
                  prefixIcon: Icon(Icons.lan_outlined, size: 20),
                ),
                validator: (v) => _validateUrl(v, '内网地址'),
              ),
              const SizedBox(height: 18),
              _label('公网地址'),
              TextFormField(
                controller: _publicCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'https://notes.example.com',
                  prefixIcon: Icon(Icons.public, size: 20),
                ),
                validator: (v) => _validateUrl(v, '公网地址'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _label('内网 WiFi 名称'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _readingSsid ? null : _fillCurrentSsid,
                    icon: _readingSsid
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find, size: 18),
                    label: const Text('读取当前'),
                  ),
                ],
              ),
              TextFormField(
                controller: _ssidCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: '例如 HomeWiFi',
                  prefixIcon: Icon(Icons.wifi, size: 20),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? '请填写内网 WiFi 名称' : null,
              ),
              const SizedBox(height: 12),
              const Text(
                '提示：读取 WiFi 名称需要定位权限（系统限制）。iOS 还需要在系统设置里允许「精确定位」。',
                style: TextStyle(fontSize: 12, height: 1.5, color: AppPalette.inkSoft),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppPalette.danger.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: AppPalette.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: AppPalette.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.submitLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppPalette.ink,
      ),
    ),
  );
}
