# TiebaPure-Mac

基于 [TiebaPure-iOS](https://github.com/infinityf4p/TiebaPure-iOS) 的原生 macOS 百度贴吧客户端。最低 macOS 14，使用 SwiftUI、AppKit、WebKit 与 SwiftPM。

本仓库保留 GitHub fork 关系、上游提交历史和原作者署名。来源基线与修改声明见 [NOTICE.md](NOTICE.md)，许可证为 [GPL-3.0-only](LICENSE)。

## 命名约定

| 用途 | 名称 |
| --- | --- |
| GitHub 仓库、工作目录、SwiftPM package | `TiebaPure-Mac` |
| 应用包、系统显示名、应用窗口 | `TiebaPure-Mac` / `TiebaPure-Mac.app` |
| Swift 模块、可执行文件 | `TiebaPureMac`（Swift 标识符形式） |
| 测试模块 | `TiebaPureMacTests` |
| Bundle ID、Keychain 及偏好命名空间 | `io.github.yamakze.TiebaPureMac` |
| 截图应用 | `TiebaPure-Mac-Screenshots.app`，独立 Bundle ID 后缀 `.Screenshots` |

`TiebaPure-iOS` 用于标识上游来源、历史及版权声明。协议生成类型和请求中的上游标识保留其兼容含义，不作为当前应用名称。

## 当前进度

这是 Mac 工程迁移后的开发基线，尚未完成上游全部功能的桌面实现。

| 范围 | 状态 |
| --- | --- |
| 推荐、进吧、搜索、帖子与楼中楼 | 列表与楼层连续加载，右侧阅读楼中楼。最近访问和搜索历史保存在本机 |
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
scripts/compile_and_run.sh
# 优化构建并启动
scripts/compile_and_run.sh release
```

`scripts/compile_and_run.sh` 默认使用 debug，构建成功后重启当前检出目录对应的应用，并向 LaunchServices 注册最新名称和图标。可从任意工作目录调用脚本。

`build/TiebaPure-Mac.app` 为本地应用包，默认使用 ad-hoc 签名。`scripts/build-app.sh release` 生成优化构建；正式对外分发仍需 Developer ID 签名、公证与安装验收。当前不提供正式 Mac Release。

日常测试使用确定性 fixture，不访问真实贴吧服务。需要只读线上检查时显式运行：

```sh
RUN_ANONYMOUS_LIVE_SMOKE=1 swift test --filter AnonymousLiveSmokeTests
```

## 键盘操作

| 快捷键 | 操作 |
| --- | --- |
| `⌘1` / `⌘2` / `⌘3` | 首页 / 进吧 / 搜索 |
| `⌘F` | 打开搜索并聚焦工具栏搜索框 |
| `Return` | 提交贴吧名称或搜索词 |
| `Esc` | 清空输入或退出输入焦点 |
| `⌘R` | 刷新当前列表或帖子 |
| `⌘[` / `⌘]` | 返回列表 / 前进到刚读过的帖子 |

## 界面截图

```sh
scripts/capture-ui.sh
# 或指定新的输出目录
scripts/capture-ui.sh screenshots/review-01
```

在已登录图形桌面的 Mac 上运行，需要 Xcode 命令行工具和系统允许 UI 测试。脚本构建独立的 `TiebaPure-Mac-Screenshots.app`，用 XCTest 操作实际界面，输出 24 张 PNG、`index.html`、`manifest.json` 和 `Review.xcresult`。覆盖首页、进吧入口及结果、搜索入口及结果、帖子、楼中楼、登录、设置的浅色和深色，以及首页空白、错误、加载、翻页重试、账号底栏和个人资料。页面编号可直接用于反馈。

业务页面复用 DEBUG 样例 API；截图应用使用独立 bundle ID、偏好域、内存账号和内存历史，不读取真实 Keychain。登录页仍加载百度 WebKit 页面，网络内容需单独验收。样例 API 与截图启动参数不会进入 Release 构建。系统分享菜单、图片右键菜单和 macOS 权限弹窗不属于页面截图清单。

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
