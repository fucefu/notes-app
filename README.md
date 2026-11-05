# 便签 App

配合 [zhaoolee/notes](https://github.com/zhaoolee/notes)（开源版锤子便签）使用的双端壳应用，
判断逻辑参考 Home Assistant Companion：**连接指定 WiFi 时优先走内网地址，否则走公网域名**。

本项目只负责「选对地址 + 加载网页」，便签 UI、数据、账号全部由你已部署的 notes 服务提供。

## 功能

- **首次引导**：填写内网地址、公网地址、内网 WiFi 名称（可一键读取当前 WiFi）
- **自动判定**：启动时读取当前 WiFi 的 SSID，命中配置则优先内网，否则直接公网
- **可达性探测**：在内网 WiFi 上先用 3 秒超时探测内网地址，不通就直接走公网，不白屏
- **自动回退**：主地址加载失败（主文档资源错误）自动切备用地址并提示
- **手动切换**：右上角胶囊按钮点开菜单，可切换内网/公网、刷新、重新检测、改设置、清空重来
- **配置持久化**：`shared_preferences` 保存，重装前一直生效

## 地址填写说明

| 字段 | 示例 | 说明 |
| --- | --- | --- |
| 内网地址 | `http://192.0.2.10:18080` | 局域网访问用的地址 |
| 公网地址 | `https://notes.example.com` | 外网/反代地址 |
| 内网 WiFi 名称 | `HomeWiFi` | 区分大小写，比较时忽略首尾空白 |

未写 `http://` / `https://` 时自动补 `http://`，尾部斜杠会自动去掉。

> **重要**：zhaoolee/notes 的 Docker 默认端口映射是 `-p 127.0.0.1:18080:3001`，
> 只监听本机回环地址。要让手机在内网访问，需要改成 `-p 18080:3001`。

## 权限说明

- **Android**：需要 `ACCESS_FINE_LOCATION` 运行时权限。这是系统的硬限制——Android 9+
  不授予定位权限就读不到 WiFi SSID。首次启动会申请，也可在设置页点「读取当前」时再申请。
- **iOS**：需要定位权限 `NSLocationWhenInUseUsageDescription`，且 iOS 14+ 需在
  「设置 → 隐私 → 定位服务」里允许**精确定位**，否则系统返回的 SSID 可能是空值或占位
  `WiFi`。SSID 读取失败时按「非内网」处理，由公网地址兜底——这是 iOS 平台的固有限制，
  不是 App 缺陷。

## 下载安装

到 [Releases](../../releases) 页面下载对应产物。

- **Android**：下载 `*-arm64-v8a-release.apk` 直接安装（64 位真机通用，
  含小米/华为等绝大多数机型）。
- **iOS**：下载 `*-ios-unsigned.ipa`，用 **[巨魔（TrollStore）](https://github.com/opa334/TrollStore)**
  直接安装，**不需要 Apple 签名**。非越狱设备需自行签名（AltStore / Sideloadly 等）。

## 构建

本地开发：

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug        # 本地只出 debug
```

> **注意**：Android 构建请使用 **JDK 17~24**。Android Studio 自带的 JDK 25 会让
> `File.canWrite()` 对任意路径返回 `false`（实际写入却成功），导致 Gradle 误判项目目录
> 不可写而拒绝构建，报 `Configuring project ... without an existing directory`。
> 本项目在 JDK 21 下验证通过。

Release 通过 GitHub Actions 构建（`.github/workflows/build.yml`）：

- 打 tag（`v1.2.3`）自动触发，或到 Actions 页面手动 `Run workflow`
- Android：`flutter build apk --release --split-per-abi`
- iOS：`flutter build ios --release --no-codesign`，手工打成 ipa（无需签名）
- 两个产物会自动挂到对应 Release

可选：若想让 CI 用你自己的签名，在仓库 Secrets 里配 `ANDROID_KEYSTORE_BASE64`
（debug.keystore 的 base64）。不配也能出包（CI 现场生成一份）。


## 目录结构

```
lib/
  main.dart                     # 入口，配置为空时进引导页
  theme.dart                    # 暖白纸感配色
  models/app_config.dart        # 配置模型 + 地址规范化 + EndpointPlan
  services/
    config_store.dart           # shared_preferences 持久化
    wifi_service.dart           # 读取 SSID（含权限申请、去引号）
    endpoint_resolver.dart      # 判定主/备地址 + 可达性探测
  pages/
    config_form_page.dart       # 引导页 / 设置页共用表单
    home_page.dart              # WebView + 回退 + 底部菜单
test/
  app_config_test.dart          # 规范化、SSID、JSON 往返
  widget_test.dart              # 引导页校验与提交
```

## 已知限制

- iOS 的 SSID 读取不如 Android 可靠（`NEHotspotHelper` 需 Apple 特批权限，普通账号拿不到），
  靠公网兜底。
- WebView 内不做原生注入，所有页面交互仍走 notes 网页本身。
- 仅当「主文档」加载失败才回退；页面内某个子资源 404 不会触发切换。

## 许可

本 App 自有代码按 MIT 使用。上游 [zhaoolee/notes](https://github.com/zhaoolee/notes) 采用
Apache-2.0，与本仓库无关。
