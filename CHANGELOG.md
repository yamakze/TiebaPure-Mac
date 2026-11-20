# Changelog

## 0.1.0 — Unreleased

- 建立原生 macOS 14+ SwiftPM 工程与 `.app` 打包链路。
- 继承上游协议、映射、状态协调和核心回归测试。
- 新建 Mac 侧栏与单内容区导航，支持搜索、进吧及 WebKit 登录。
- 复用上游应用图标，增加浅色/深色全页面截图脚本。
- 移除 iOS 工程、分享扩展、触摸转场、IPA 脚本与模拟器 CI。

- 统一 TiebaPure-Mac 应用命名与缓存前缀，增加一键构建启动脚本。
- 改用透明底 Mac 图标，应用产物移至 `artifacts/macos`。
- 本地化系统菜单，将刷新移至「显示」，提供外观切换和发布记录入口。
- 使用 Sparkle 检查和安装签名更新，增加 Universal 应用公证与发布草稿流程。

### English

- Establish a native macOS 14+ project with SwiftPM and app bundle packaging.
- Reuse upstream protocol, mapping, state coordination, and core regression tests.
- Add sidebar and stack navigation, search, forum browsing, and WebKit login.
- Reuse the upstream app icon and add a full-page light/dark screenshot script.
- Remove the iOS project, action extension, touch transitions, IPA scripts, and simulator CI.
- Unify TiebaPure-Mac app naming and cache prefixes; add a build-and-run script.
- Use a transparent Mac app icon and publish local bundles under `artifacts/macos`.
- Localize native menus and add menu actions for refresh, appearance, and release history.
- Integrate signed Sparkle updates and a notarized Universal release workflow.
