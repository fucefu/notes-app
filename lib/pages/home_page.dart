import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/app_config.dart';
import '../services/endpoint_resolver.dart';
import '../services/wifi_service.dart';
import '../theme.dart';
import 'config_form_page.dart';

/// 主页面：全屏 WebView 加载 notes 网页，自身只负责「选对地址」。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.config,
    required this.onConfigChanged,
    required this.onReset,
  });

  final AppConfig config;
  final ValueChanged<AppConfig> onConfigChanged;
  final VoidCallback onReset;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const EndpointResolver _resolver = EndpointResolver();
  static final WifiService _wifi = WifiService();

  WebViewController? _controller;
  EndpointPlan? _plan;
  EndpointKind _activeKind = EndpointKind.publicUrl;
  String _activeUrl = '';
  String? _ssid;

  bool _booting = true;
  bool _loading = false;
  bool _failed = false;
  bool _didFallback = false;
  DateTime? _lastBackAt;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _booting = true;
      _failed = false;
    });

    // 读 SSID 需要定位权限；已授权时这里不会弹窗。
    await _wifi.ensurePermission();
    final ssid = await _wifi.currentSsid();

    final plan = await _resolver.resolve(
      widget.config,
      ssid: ssid,
      preferInternal: widget.config.preferInternal,
    );

    if (!mounted) return;
    _ssid = ssid;
    _applyPlan(plan);
  }

  void _applyPlan(EndpointPlan plan) {
    setState(() {
      _plan = plan;
      _activeKind = plan.primaryKind;
      _activeUrl = plan.primaryUrl;
      _didFallback = false;
      _booting = false;
      _loading = true;
      _failed = false;
    });
    _loadUrl(plan.primaryUrl);
  }

  void _loadUrl(String url) {
    final controller = _controller ??= _createController();
    controller.loadRequest(Uri.parse(url));
  }

  WebViewController _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppPalette.paper)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _failed = false;
              _progress = 0;
            });
          },
          onProgress: (value) {
            if (!mounted) return;
            if (value != _progress) setState(() => _progress = value);
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _progress = 100;
            });
          },
          onWebResourceError: _onResourceError,
          onHttpError: (error) {
            // 4xx/5xx 资源错误不处理，避免把反代的 401 登录页误判成失败。
          },
        ),
      );

    // notes 是 SPA，设置弹层依赖 localStorage；webview_flutter 在
    // Android / iOS 上默认已启用 DOM Storage，无需额外开关。
    return controller;
  }

  void _onResourceError(WebResourceError error) {
    if (error.isForMainFrame != true) return;

    final plan = _plan;
    if (plan == null) return;

    // 仅内网模式没有备用地址：直接进错误页，不做无意义的回退。
    if (!plan.hasFallback) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    if (!_didFallback) {
      _didFallback = true;
      setState(() {
        _activeKind = plan.fallbackKind;
        _activeUrl = plan.fallbackUrl;
        _loading = true;
      });
      _toast('${plan.primaryKind.label}地址不可达，已自动切换到${plan.fallbackKind.label}');
      _loadUrl(plan.fallbackUrl);
      return;
    }

    setState(() {
      _loading = false;
      _failed = true;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _retryDetect() async {
    Navigator.of(context).pop();
    await _bootstrap();
  }

  Future<void> _switchManually() async {
    Navigator.of(context).pop();
    final plan = _plan;
    if (plan == null) return;
    final targetKind = _activeKind == EndpointKind.internal
        ? EndpointKind.publicUrl
        : EndpointKind.internal;
    final targetUrl = targetKind == EndpointKind.internal
        ? widget.config.internalUrl
        : widget.config.publicUrl;

    final updated = widget.config.copyWith(
      preferInternal: targetKind == EndpointKind.internal,
    );
    widget.onConfigChanged(updated);

    setState(() {
      _activeKind = targetKind;
      _activeUrl = targetUrl;
      _loading = true;
      _failed = false;
    });
    _loadUrl(targetUrl);
    _toast('已手动切换到${targetKind.label}地址');
  }

  Future<void> _openSettings() async {
    Navigator.of(context).pop();
    final result = await Navigator.of(context).push<AppConfig>(
      MaterialPageRoute<AppConfig>(
        builder: (_) => ConfigFormPage(
          title: '设置',
          submitLabel: '保存并重新连接',
          initial: widget.config,
          showCancel: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    widget.onConfigChanged(result);
    setState(() {
      _booting = true;
      _controller = null;
      _plan = null;
    });
    await _bootstrap();
  }

  Future<void> _resetApp() async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重新开始'),
        content: const Text('会清除已保存的地址配置，回到首次引导。要清除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onReset();
  }

  void _openMenu() {
    final plan = _plan;
    if (plan == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.inkSoft.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Icon(
                  _activeKind == EndpointKind.internal
                      ? Icons.lan_outlined
                      : Icons.public,
                  color: _kindColor(_activeKind),
                ),
                title: Text(
                  '正在使用${_activeKind.label}地址',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '$_activeUrl\n${plan.reason}',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
                isThreeLine: true,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('刷新页面'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _loadUrl(_activeUrl);
                },
              ),
              if (plan.hasFallback)
                ListTile(
                  leading: const Icon(Icons.sync_alt),
                  title: Text(
                      '切换到${_activeKind == EndpointKind.internal ? '公网' : '内网'}地址'),
                  onTap: _switchManually,
                ),
              ListTile(
                leading: const Icon(Icons.wifi_find),
                title: const Text('重新检测网络'),
                subtitle: _ssid == null
                    ? const Text('未读取到 WiFi 名称')
                    : Text('当前 WiFi：$_ssid'),
                onTap: _retryDetect,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                onTap: _openSettings,
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt, color: AppPalette.danger),
                title: const Text('重新开始（清除配置）',
                    style: TextStyle(color: AppPalette.danger)),
                onTap: _resetApp,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Color _kindColor(EndpointKind kind) =>
      kind == EndpointKind.internal ? AppPalette.internal : AppPalette.publicNet;

  /// 网页内部关闭弹层时不会产生导航事件，canGoBack 一直为 false。
  /// 这里用 JS 让页面自己处理一次「返回」：派发 Escape、点关闭按钮、
  /// 或调用 history.back()，任一生效就说明这次返回被网页消费了。
  Future<bool> _letWebHandleBack() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      final handled = await controller.runJavaScriptReturningResult('''
(function () {
  try {
    // 1) 找可见的关闭类元素（弹层右上角的 ×、关闭按钮）
    var sels = ['[aria-label*="关闭"]', '[aria-label*="close" i]',
                '.close', '.close-btn', '.modal-close', '[data-close]'];
    for (var i = 0; i < sels.length; i++) {
      var el = document.querySelector(sels[i]);
      if (el) { var r = el.getBoundingClientRect();
                if (r.width > 0 && r.height > 0) { el.click(); return "closed"; } }
    }
    // 2) 有弹层容器就先按 Escape
    if (document.querySelector('.modal,.dialog,[role="dialog"]')) {
      document.dispatchEvent(new KeyboardEvent('keydown',
        {key:'Escape', code:'Escape', keyCode:27, which:27, bubbles:true}));
      return "escaped";
    }
    // 3) 都不行就让浏览器后退
    history.back();
    return "backed";
  } catch (e) { return "none"; }
})()
''');
      final text = handled.toString().replaceAll('"', '').trim();
      debugPrint('网页处理返回：$text');
      // 只有真正点中关闭 / Escape 才算消费掉这次返回
      return text == 'closed' || text == 'escaped';
    } on Exception catch (error) {
      debugPrint('网页处理返回失败：$error');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 只要还在网页里，返回手势先交给网页处理；网页处理不了才退出。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final controller = _controller;
        if (controller == null) {
          if (mounted) Navigator.of(context).maybePop();
          return;
        }
        final navigator = Navigator.of(context);

        // 1) 网页有真实导航历史 → 后退
        if (await controller.canGoBack()) {
          await controller.goBack();
          return;
        }

        // 2) 没有导航历史，但页面可能有 SPA 弹层 → 让网页自己关
        if (await _letWebHandleBack()) {
          return;
        }

        // 3) 再按一次才真正退出，避免误触
        final now = DateTime.now();
        final doubleTap = _lastBackAt != null &&
            now.difference(_lastBackAt!) < const Duration(seconds: 2);
        if (!doubleTap) {
          _lastBackAt = now;
          _toast('再按一次返回退出');
          return;
        }
        _lastBackAt = null;
        navigator.maybePop();
      },
      child: Scaffold(
        // targetSdk 36 在 Android 15 上强制 edge-to-edge，WebView 内容会画到
        // 状态栏下面，导致网页自己的顶部标题栏（含关闭按钮）被系统栏盖住。
        // 用 SafeArea 让网页整体落在安全区内。
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 进度条固定 2px 高度，不覆盖网页内容
              SizedBox(
                height: 2,
                child: _loading && !_booting
                    ? LinearProgressIndicator(
                        value: _progress <= 0 ? null : _progress / 100,
                        backgroundColor: Colors.transparent,
                        color: AppPalette.accent.withValues(alpha: .6),
                      )
                    : null,
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
        // 浮窗已移除，改用右下角小按钮，不遮挡网页顶部区域
        floatingActionButton: _booting || _controller == null
            ? null
            : FloatingActionButton.small(
                heroTag: 'notes_menu',
                backgroundColor: _kindColor(_activeKind).withValues(alpha: .92),
                foregroundColor: Colors.white,
                tooltip: '菜单（当前${_activeKind.label}）',
                onPressed: _openMenu,
                child: Icon(
                  _activeKind == EndpointKind.internal
                      ? Icons.lan_outlined
                      : Icons.public,
                  size: 19,
                ),
              ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildBody() {
    if (_booting) {
      return const _BootView();
    }
    if (_failed) {
      return _ErrorView(
        url: _activeUrl,
        showSwitch: _plan?.hasFallback ?? false,
        onRetry: () => _loadUrl(_activeUrl),
        onSwitch: _switchManually,
        onSettings: _openSettings,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const _BootView();
    }
    return WebViewWidget(controller: controller);
  }

}

class _BootView extends StatelessWidget {
  const _BootView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.paper,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(height: 18),
          const Text(
            '正在检测网络环境…',
            style: TextStyle(fontSize: 13.5, color: AppPalette.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.url,
    required this.showSwitch,
    required this.onRetry,
    required this.onSwitch,
    required this.onSettings,
  });

  final String url;
  final bool showSwitch;
  final VoidCallback onRetry;
  final VoidCallback onSwitch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.paper,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 48, color: AppPalette.inkSoft.withValues(alpha: .7)),
          const SizedBox(height: 18),
          const Text(
            '打不开便签页面',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            url,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppPalette.inkSoft),
          ),
          const SizedBox(height: 6),
          Text(
            showSwitch
                ? '已尝试备用地址仍失败，请检查服务是否运行、地址是否正确。'
                : '请检查服务是否运行、地址是否正确，或确认手机已连着能访问该地址的 WiFi。',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12.5, height: 1.5, color: AppPalette.inkSoft),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: 220,
            child: FilledButton(onPressed: onRetry, child: const Text('重试')),
          ),
          if (showSwitch) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 220,
              child: OutlinedButton.icon(
                onPressed: onSwitch,
                icon: const Icon(Icons.sync_alt, size: 18),
                label: const Text('切换到另一地址'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.accent,
                  side:
                      BorderSide(color: AppPalette.accent.withValues(alpha: .4)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: 220,
            child: TextButton(onPressed: onSettings, child: const Text('检查设置')),
          ),
        ],
      ),
    );
  }
}
