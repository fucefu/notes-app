import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // iOS 左缘返回手势的拖动状态
  bool _edgeDragActive = false;
  double _edgeDragDistance = 0;
  int _progress = 0;

  /// 网页里的设置面板（浅灰底、全屏）是否打开：打开时状态栏图标要用深色。
  /// 由注入的 JS 监听面板开关后通过 uiBridge 通道回报。
  bool _settingsPanelOpen = false;

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
      ..addJavaScriptChannel('uiBridge', onMessageReceived: (message) {
        // 网页里的设置面板开/关 → 状态栏图标明暗要跟着换
        if (!mounted) return;
        final open = message.message == 'open';
        if (_settingsPanelOpen != open) setState(() => _settingsPanelOpen = open);
      })
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
            _injectSafeAreaInsets();
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

  /// notes 网页的移动端布局靠 `--mobile-safe-area-*` 把系统栏垫进自己的
  /// 棕色顶栏/底部按钮区。这些变量默认吃 `env(safe-area-inset-*)`，但实测
  /// 双端都不可靠：Android WebView 里恒为 0（Chromium 限制），iOS 的
  /// webview_flutter 视口也不上报真实 inset（此前 iOS 顶栏被切就是证据）。
  /// 因此两端统一由 Flutter 把实测高度注入网页预留的 CSS 变量。
  ///
  /// 同时覆盖上游四个「全屏浮层」的安全区缺口（它们按浏览器场景设计，没有
  /// 预留状态栏）：设置面板头部、图片预览关闭钮、图片裁剪头部、AI 校对头部。
  /// 另注入 MutationObserver 监听设置面板开关，通知 Flutter 切换状态栏图标
  /// 明暗（棕色顶栏用白色，浅灰设置栏用深色）。
  void _injectSafeAreaInsets() {
    final view = MediaQuery.viewPaddingOf(context);
    // 双端统一：网页铺满全屏，top/bottom 都注入，由网页棕色顶栏/底部按钮区
    // 自己吸收系统栏（Android WebView 的 env() 恒为 0，iOS 场景同样不可靠）。
    final top = view.top.toInt();
    final bottom = view.bottom.toInt();
    _controller?.runJavaScript('''
(function () {
  var root = document.documentElement;
  root.style.setProperty('--mobile-safe-area-top', '${top}px');
  root.style.setProperty('--mobile-safe-area-bottom', '${bottom}px');

  if (!document.getElementById('app-safe-area-fix')) {
    var st = document.createElement('style');
    st.id = 'app-safe-area-fix';
    st.textContent = [
      // WKWebView 默认给可点元素闪一层半透明灰（tap highlight），Android 无此
      // 行为——iOS 点击便签进编辑页时的灰色遮罩即来源于此，双端统一关闭。
      'html { -webkit-tap-highlight-color: transparent; }',
      '@media (max-width: 640px) {',
      '  .settings-panel-header {',
      '    padding-top: var(--mobile-safe-area-top);',
      '    min-height: calc(52px + var(--mobile-safe-area-top));',
      '  }',
      '}',
      '.editor-image-preview-close { top: max(18px, var(--mobile-safe-area-top)); }',
      '.image-crop-header { padding: var(--mobile-safe-area-top) 16px 0; }',
      '.ai-review-header { padding-top: max(14px, var(--mobile-safe-area-top)); }'
    ].join('\\n');
    document.head.appendChild(st);
  }

  if (!window.__statusBarBridgeInstalled && window.uiBridge) {
    window.__statusBarBridgeInstalled = true;
    var report = function () {
      var panel = document.querySelector('.settings-panel');
      var open = !!panel && panel.offsetParent !== null;
      try { window.uiBridge.postMessage(open ? 'open' : 'closed'); } catch (e) {}
    };
    new MutationObserver(report).observe(document.documentElement,
      { childList: true, subtree: true, attributes: true });
    report();
  }
})();
    ''');
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

  /// 统一的「返回」处理，Android 返回键与 iOS 边缘滑动都走这里。
  ///
  /// 顺序：网页有历史就先后退 → SPA 弹层交给网页自己关 → 两次返回才退出。
  Future<void> _handleBack() async {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) {
      Navigator.of(context).maybePop();
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
      _toast('再滑/按一次返回退出');
      return;
    }
    _lastBackAt = null;
    navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // 网页已加载时顶部是棕色顶栏，状态栏文字要用白色；
    // 双端沉浸式后状态栏背后都是网页内容：棕色顶栏 → 白色图标；
    // 设置面板（浅灰）打开或引导/错误页（纸色）→ 深色图标。
    final onWeb = !_booting && !_failed && _controller != null;
    final lightIcons = onWeb && !_settingsPanelOpen;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lightIcons
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: AppPalette.paper,
              systemNavigationBarIconBrightness: Brightness.dark,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
      child: PopScope(
      // 只要还在网页里，返回手势先交给网页处理；网页处理不了才退出。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        // 双端统一沉浸式：WebView 铺满全屏，状态栏区域由网页自己的棕色顶栏
        // 吸收（高度经 _injectSafeAreaInsets 写入 CSS 变量）。
        // iOS 此前保留顶部 SafeArea 是因为当时还没有注入机制，网页顶栏会被
        // 状态栏切掉；注入方案落地后两端走同一套逻辑。
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              // 进度条不再常驻占位：那 2px 的 SizedBox 会在顶栏上方露出一条
              // 脚手架纸色细缝。改为叠在网页顶部的覆盖层，仅加载时可见。
              Expanded(
                child: Stack(
                  children: [
                    _buildBodyWithEdgeBack(),
                    if (_loading && !_booting)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SizedBox(
                          height: 2,
                          child: LinearProgressIndicator(
                            value: _progress <= 0 ? null : _progress / 100,
                            backgroundColor: AppPalette.accent.withValues(alpha: .25),
                            color: Colors.white.withValues(alpha: .85),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
      ),
    );
  }

  /// iOS 没有可用的系统返回手势（App 是 MaterialApp 根路由，没有 UINavigationController
  /// 导航栈），所以在屏幕左缘加一条很窄的滑动区，手势行为与 Android 返回键一致。
  ///
  /// Android 本身已有系统返回键/侧滑，无需重复处理，这里只在 iOS 上生效。
  Widget _buildBodyWithEdgeBack() {
    final body = _buildBody();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return body;
    }
    return Stack(
      children: [
        Positioned.fill(child: body),
        // 左缘 24px 的手势区。用 translucent 让区域内其余触摸仍能落到网页上，
        // 但横向拖动会被这里识别为返回，避免与网页内部横向滚动打架。
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _edgeDragActive = true,
            onHorizontalDragUpdate: (details) {
              if (!_edgeDragActive) return;
              _edgeDragDistance += details.delta.dx;
            },
            onHorizontalDragEnd: (_) async {
              final dragged = _edgeDragDistance;
              _edgeDragActive = false;
              _edgeDragDistance = 0;
              // 向右拖动超过 60 逻辑像素才算一次返回手势
              if (dragged > 60) await _handleBack();
            },
            onHorizontalDragCancel: () {
              _edgeDragActive = false;
              _edgeDragDistance = 0;
            },
          ),
        ),
      ],
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
