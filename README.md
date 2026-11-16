# TiebaPure-Mac

基于 [TiebaPure-iOS](https://github.com/infinityf4p/TiebaPure-iOS) 的原生 macOS 百度贴吧客户端。最低 macOS 14，使用 SwiftUI、AppKit、WebKit 与 SwiftPM。

本仓库保留 GitHub fork 关系、上游提交历史和原作者署名。来源基线与修改声明见 [NOTICE.md](NOTICE.md)，许可证为 [GPL-3.0-only](LICENSE)。

## 当前进度

这是 Mac 工程迁移后的开发基线，尚未完成上游全部功能的桌面实现。

| 范围 | 状态 |
| --- | --- |
| 侧栏导航、推荐、进吧、搜索、帖子与楼中楼 | 已接入原生界面，真实服务需单独验收 |
| WebKit 登录、Keychain 凭证、会话失效处理 | 已接入 Mac 平台，真实账号登录需单独验收 |
| 图片及表情 | 原生显示；复杂图文排版、预览、保存和加载缓存仍待完善 |
| 视频及语音 | 通过系统打开远端链接；尚无内嵌播放器 |
| 关注、收藏、签到、消息、发帖及回复 | 保留协议与协调器及核心测试，尚未接入 Mac 界面 |
| 历史、阅读位置、草稿及本地保存 | 保留存储能力，尚未接入 Mac 界面 |

iOS 工程、分享扩展、触摸转场、IPA 打包和模拟器 CI 已从活动源码中移除，可在上游历史中查阅。

## 构建

本地开发基线为 Xcode 26.2。无需 XcodeGen；在 Xcode 中打开 `Package.swift`，或使用命令行：

```sh
scripts/verify-project.sh
swift test
scripts/build-app.sh debug
open build/TiebaPure-Mac.app
```

`build/TiebaPure-Mac.app` 为本地应用包，默认使用 ad-hoc 签名。`scripts/build-app.sh release` 生成优化构建；正式对外分发仍需 Developer ID 签名、公证与安装验收。当前不提供正式 Mac Release。

日常测试使用确定性 fixture，不访问真实贴吧服务。需要只读线上检查时显式运行：

```sh
RUN_ANONYMOUS_LIVE_SMOKE=1 swift test --filter AnonymousLiveSmokeTests
```

## 界面截图

```sh
scripts/capture-ui.sh
# 或指定新的输出目录
scripts/capture-ui.sh screenshots/review-01
```

在已登录图形桌面的 Mac 上运行，需要 Xcode 命令行工具和系统允许 UI 测试。脚本构建独立的 `TiebaPure-Screenshots.app`，用 XCTest 操作实际界面，输出 21 张 PNG、`index.html`、`manifest.json` 和 `Review.xcresult`。覆盖首页、进吧入口及结果、搜索入口及结果、帖子、楼中楼、登录、设置的浅色和深色，以及首页空白、错误和加载状态。页面编号可直接用于反馈。

业务页面复用 DEBUG 样例 API；截图应用使用独立 bundle ID、偏好域和内存账号，不读取真实 Keychain。登录页仍加载百度 WebKit 页面，网络内容需单独验收。样例 API 与截图启动参数不会进入 Release 构建。系统分享菜单、图片右键菜单和 macOS 权限弹窗不属于页面截图清单。

## 工程与贡献

源码入口是 `Sources/TiebaPureMac/App/TiebaPureMacApp.swift`。模块边界、上游同步、验证与发布约定见 [CONTRIBUTING.md](CONTRIBUTING.md)，迁移决策见 [docs/architecture.md](docs/architecture.md)。版本信息统一维护在 `Resources/Info.plist`。

```sh
git remote -v
# origin    https://github.com/yamakze/TiebaPure-Mac.git
# upstream  https://github.com/infinityf4p/TiebaPure-iOS.git
```

## 声明与致谢

本项目与百度公司、百度贴吧官方无隶属、授权或认可关系。协议来自非官方接口，服务端行为可能变化。上游将发布、回复和资料编辑标为实验性功能；保留底层实现不代表已在 Mac 验证成功。

感谢 infinityf4p 与上游贡献者，以及 [TiebaLite](https://github.com/HuanCheng65/TiebaLite)、[aiotieba](https://github.com/lumina37/aiotieba) 的协议研究。SwiftProtobuf 许可见 [LICENSES](LICENSES/SwiftProtobuf-Apache-2.0.txt)。
