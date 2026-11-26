# macOS 架构设计决策

## 目标与来源

TiebaPure-Mac 基于上游 `5a87225`（v1.4.15）建立独立的原生 macOS 客户端，仅维护 macOS 14+，保留原作者历史、GPL-3.0-only 许可证与 GitHub fork 关系。

## 阅读顺序与状态归属

1. `App/TiebaPureMacApp.swift` 定义窗口与设置场景。
2. `Application/MacSession.swift` 持有应用级账号、会话失效订阅和写入协调。登录提交、关注和收藏回读通过会话层。
3. `App/Reader/ReaderWorkspace.swift` 按窗口、栏目保存查询、排序、导航与滚动位置。菜单命令通过焦点场景作用于当前窗口。
4. `App/Reader/MacThreadView.swift` 渲染楼层和楼中楼 Inspector。列表、帖子和楼中楼共用 `ReaderPages` 的请求标识、去重、重试和加载状态。
5. `Infrastructure/Network/TiebaAPIService.swift` 定义数据请求和写入边界，`Network/Mapping` 把协议响应转换为领域模型。图片由 `Infrastructure/Media/ReaderImageLoader.swift` 下载和解码。

当前按源码职责组织为一个 SwiftPM 应用模块，未为目录分层暴露过多 public API；独立模块由实际复用需求推动。

## 平台与构建收敛

应用入口为 SwiftPM，使用 AppKit/SwiftUI 场景、`NSViewRepresentable` 封装 WebKit 登录、ImageIO 图片解码及 macOS Keychain。持久化存储位于独立命名空间 `Application Support/TiebaPure-Mac/Persistence/v1`。SwiftData 持久容器打开失败时，降级为内存容器并显式标记不可持久化。

离线 fixture 位于 `DebugSupport`，通过 `#if DEBUG` 供单元测试和截图脚本共用；截图脚本在 `.build/screenshot-runner` 生成临时 XCTest 工程。

## 取消与失败边界

页面读取由 SwiftUI `task` 生命周期驱动取消；请求返回后先检查取消状态，再提交页面状态。网络、协议、账号和存储失败保留各自的错误类型，不静默吞错。
