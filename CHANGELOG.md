# Changelog

## 0.1.0 — 2026-11-24 (GitHub Preview)

- 建立原生 macOS 14+ SwiftPM 工程与 `.app` 打包链路，移除 iOS 遗留依赖与触摸转场。
- 新建 Mac 桌面多栏目导航与单窗口阅读体验，支持楼层连续加载、只看楼主与楼中楼 Inspector 检视。
- 引入阅读位置记忆与恢复机制，支持跨栏目切换保留滚动锚点与上下文，支持快捷键历史导航。
- 原生多图预览：正文与楼中楼图片支持点击大图预览、多档缩放、键盘左右切换与加载重试。
- 账号互动闭环：支持贴吧关注/取消关注、帖子收藏/取消收藏，回读服务端状态后即时刷新侧栏。
- 检索与排序优化：支持全站与吧内双层搜索及排序切换（最新/相关），贴吧支持时间排序与「只看精华」筛选。
- 隔离登录与安全存储：系统 WebKit 原生隔离登录，会话凭据加密写入 Keychain，支持会话过期检测。
- 支持 Apple Silicon 与 Intel 的 Universal 通用包。Sparkle 2 已集成，自动更新将在配置签名更新源的版本中启用。
- 工程化与合规资产：引入根目录 Makefile、Homebrew Cask 分发规范、基于夹具的 UI 自动化测试与隐私声明。

### English

- Establish native macOS 14+ SwiftPM project and `.app` bundle pipeline, removing legacy iOS dependencies.
- Add desktop sidebar navigation and single-window reader, featuring continuous floor scrolling, author-only reading, and subpost inspector.
- Preserve and restore scroll positions and reading progress across sections, with keyboard-driven history navigation.
- Native image preview: click post and subpost images for full-size inspection, zoom, keyboard navigation, and retry handling.
- Account library loop: follow/unfollow forums and bookmark/unbookmark threads with server readback verification and live sidebar updates.
- Search and sorting: site-wide and in-forum search with latest/relevance sorting, and forum thread time sorting with featured topic filtering.
- Isolated login and secure storage: WebKit container authentication, Keychain session encryption, and proactive expiration detection.
- Universal build for Apple Silicon and Intel. Sparkle 2 is integrated and will enable automatic updates in builds with a signed update feed.
- Engineering and compliance: root Makefile, Homebrew Cask distribution, fixture-based UI automation, and privacy documentation.
