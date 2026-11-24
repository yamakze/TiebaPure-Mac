# Mac 工程迁移决策

## 目标与来源

TiebaPure-Mac 基于上游 `5a87225` 建立独立的原生 macOS 客户端，仅维护 macOS 14+。保留原作者历史、GPL 许可证和 GitHub fork 关系，不重建 Git 仓库。

## 阅读顺序与状态归属

1. `App/TiebaPureMacApp.swift` 定义窗口与设置场景。
2. `Application/MacSession.swift` 持有应用级账号、会话失效订阅和写入协调。登录提交、关注和收藏回读通过会话层。
3. `App/Reader/ReaderWorkspace.swift` 按窗口、栏目保存查询、排序、导航与滚动位置。菜单命令通过焦点场景作用于当前窗口。
4. `App/Reader/MacThreadView.swift` 渲染楼层和楼中楼 Inspector。列表、帖子和楼中楼共用 `ReaderPages` 的请求标识、去重、重试和加载状态。
5. `Infrastructure/Network/TiebaAPIService.swift` 定义数据请求和写入边界，`Network/Mapping` 把协议响应转换为领域模型。图片由 `Infrastructure/Media/ReaderImageLoader.swift` 下载和解码。

当前按源码职责组织为一个 SwiftPM 应用模块。目录不是编译隔离边界；未将所有 internal 类型改为 public。独立模块应由实际复用需求推动。

## 平台清理

删除 iOS target、XcodeGen 配置、Action Extension、IPA 与模拟器脚本、UIKit 阅读视图及触摸转场。WebKit 登录包装改用 NSViewRepresentable；请求设备信息由 Mac 提供；面板和工具栏使用 SwiftUI，图片通过 ImageIO 解码。

Mac 从新的存储命名空间开始，不导入 iOS 沙箱。删除 iOS 16 文件后端选择和文件到 SwiftData 的后端迁移标记。保留本地保存包、资源文件的版本、校验、备份以及存储失败语义。SwiftData 的持久容器打开失败时，沿用上游的内存显示降级并显式标记不可持久化，禁止将其当成成功落盘。

离线 fixture 位于 `DebugSupport`，通过 `#if DEBUG` 供单元测试和截图应用共用。截图脚本在 `.build/screenshot-runner` 生成 XCTest 工程。SwiftPM 是应用的构建入口。

## 取消与失败边界

页面读取由 SwiftUI task 生命周期取消。成功返回后先检查取消状态，再提交页面状态。网络、协议、账号和存储失败保留各自的错误类型。被移除的 iOS 页面策略测试随实现删除，协议、映射、写操作和存储测试继续维护。

## 后续验收

本地回归覆盖离线阅读、搜索、图片预览和关注收藏流程。发布验收另行验证真实账号回读与签名后的分发产物。macOS 已接入的功能以 README 为准。
