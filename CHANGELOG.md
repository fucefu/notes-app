# 更新日志

本项目版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.1.1] - 2026-11-05

### 新增

- iOS 沉浸式状态栏：与 Android 统一为「网页铺满全屏 + Flutter 注入状态栏
  高度」方案，棕色顶栏自己吸收状态栏，双端观感一致；状态栏图标明暗
  联动（棕色顶栏白色，浅灰设置面板深色）同样对 iOS 生效。

### 修改

- **Android 产物精简为单个 arm64-v8a APK**：CI 仍按 ABI 拆分构建，但只发布
  `*-arm64-v8a-release.apk`（约 18MB），v7a / x86_64 两份构建后丢弃——
  目标设备均为 arm64，其余两版没有使用场景。
- **versionCode 基数调整为 build 号 3000**：split 时代 arm64 包 versionCode
  为 2002（ABI 前缀 2000 + build 2），取 3000 保证从 v1.1.0 及更早版本
  均可正常覆盖升级。今后发版 build 号继续递增。
- CI android job 产物命名为 `notes-app-<version>-arm64-v8a-release.apk`。

## [1.1.0] - 2026-11-05

### 新增

- 全新应用图标：扁平风格，纸色底（`#FAF6EF`）+ 棕色铅笔（`#8C6A4A`）+ 一条横线，
  笔尖压在横线上。Android 自适应图标（背景层 + 前景层，内容占比 63%）与
  iOS 全部 15 个尺寸，squircle 超椭圆造型，导出脚本可复现。
- 安全区注入：页面加载后由 Flutter 把实测的状态栏 / 手势条高度写入网页预留的
  `--mobile-safe-area-top` / `--mobile-safe-area-bottom` CSS 变量。
  背景：Android WebView 中 `env(safe-area-inset-top)` 恒为 0（Chromium 限制），
  iOS WKWebView 在本工程场景下同样拿不到真实 inset，导致网页版 notes 的
  移动端顶栏（按 `48px + safe-area-inset-top` 设计）在两端都会被状态栏压住。
- 上游四个全屏浮层的安全区补丁（注入 CSS 覆盖）：设置面板头部、
  图片预览关闭按钮、图片裁剪头部、AI 校对头部。
- 设置面板开关联动状态栏图标明暗：棕色顶栏用白色图标，
  打开浅灰设置面板时自动切回深色（通过 JS 通道 `uiBridge` 回报）。
- iOS 左缘返回手势：屏幕左缘 24px 滑动区，向右拖动超过 60px 触发返回，
  行为与 Android 返回键一致（`PopScope` 统一处理）。
- 单元测试 `test/edge_back_test.dart`：覆盖返回手势判定阈值与仅内网模式表单校验。

### 修改

- **包名更换**：Android `applicationId` / `namespace` 与 iOS
  `PRODUCT_BUNDLE_IDENTIFIER` 统一为 `com.notesapp.mobile`。
  ⚠️ **不兼容升级**：v1.0.0 使用的旧包名与本版本互认作两个不同应用，
  无法覆盖升级，需先卸载再安装；App 内保存的地址配置会随之清空，需重新填写。
- Android 端 WebView 改为沉浸式铺到屏幕最顶（去掉此前为修顶栏遮挡而加的全局
  `SafeArea`，改为仅 iOS 保留顶部 SafeArea）：高状态栏机型上不再出现
  一条与网页顶栏脱节的浅色空白。
- 加载进度条从常驻 2px 占位改为覆盖层：此前占位会在网页顶栏上方露出一条
  脚手架底色细缝，现在仅在加载时叠显示于网页顶边。
- CI 发布流程：Release 正文改为自动截取本文件中对应版本的段落，
  不再使用固定模板；版本号自 `pubspec.yaml` 读取并同步为 tag。

### 废除

- 移除旧包名对应的 Kotlin 源码目录（随包名更换废弃）。

## [1.0.0] - 2026-11-05

### 新增

- 初版：全屏 WebView 加载自部署的 [zhaoolee/notes](https://github.com/zhaoolee/notes)
  （开源版锤子便签）。
- 按 WiFi 自动切换地址：连上指定内网 WiFi 时优先走内网地址，
  否则走公网域名；主地址不可达时自动回退备用地址（3 秒可达性探测）。
- 支持仅填内网地址的使用方式（无公网地址时不做回退，直连内网）。
- 引导页与设置页：内网地址、公网地址（可选）、内网 WiFi 名称（支持读取当前）。
- Android 返回键三级处理：网页历史后退 → SPA 弹层交给网页关闭 → 两次返回退出。
- GitHub Actions 双端 CI：Android 按 ABI 拆分三份 release APK；
  iOS 走 `--no-codesign` 产出未签名 ipa（供 TrollStore 侧载，无需 Apple 签名）。

[1.1.1]: https://github.com/fucefu/notes-app/releases/tag/v1.1.1
[1.1.0]: https://github.com/fucefu/notes-app/releases/tag/v1.1.0
[1.0.0]: https://github.com/fucefu/notes-app/releases/tag/v1.0.0
