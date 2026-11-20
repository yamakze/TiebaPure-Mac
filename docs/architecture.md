# Mac 工程迁移决策

## 目标与来源

TiebaPure-Mac 基于上游 `5a87225` 建立独立的原生 macOS 客户端，仅维护 macOS 14+。保留原作者历史、GPL 许可证和 GitHub fork 关系，不重建 Git 仓库。

## 阅读顺序与状态归属

1. `App/TiebaPureMacApp.swift` 定义窗口与设置场景。
2. `App/MacSession.swift` 在应用级持有账号、API 与会话失效订阅。
3. `App/MacReaderView.swift` 在窗口内持有栏目、查询及导航路径。菜单命令通过焦点场景指向当前窗口。
4. `App/MacThreadView.swift` 持有连续楼层与楼中楼 Inspector 的状态。首页列表、帖子和楼中楼复用 `ReaderPages` 的请求标识、去重和重试页码。
5. `Infrastructure/Network/TiebaAPIService.swift` 是业务 API 边界，各协议实现负责签名、请求与响应验证。
6. `Domain/Mapping` 将协议数据映射成领域模型，`Infrastructure/State` 保留写操作协调与会话失效边界。

当前按源码职责组织为一个 SwiftPM 应用模块。目录不是编译隔离边界；未将所有 internal 类型改为 public。独立模块应由实际复用需求推动。

## 平台清理

删除 iOS target、XcodeGen 配置、Action Extension、IPA 与模拟器脚本、UIKit 阅读视图及触摸转场。WebKit 登录包装改用 NSViewRepresentable；请求设备信息由 Mac 提供；表情图片使用 NSImage，字体使用 NSFont。

Mac 从新的存储命名空间开始，不导入 iOS 沙箱。删除 iOS 16 文件后端选择和文件到 SwiftData 的后端迁移标记。保留本地保存包、资源文件的版本、校验、备份以及存储失败语义。SwiftData 的持久容器打开失败时，沿用上游的内存显示降级并显式标记不可持久化，禁止将其当成成功落盘。

部分上游模型文件仍同时包含 Store 与存储实现；后续随具体功能迁移收敛职责，不复制两套业务实现。可复用 fixture 放在 DebugSupport 下，受 `#if DEBUG` 限制，供单元测试和截图应用共用，不打包进 Release。截图脚本生成的 XCTest 工程位于 build 下，不另建应用工程配置。

## 取消与失败边界

页面读取由 SwiftUI task 生命周期取消。成功返回后先检查取消状态，再提交页面状态。网络、协议、账号和存储失败保留各自的错误类型。被移除的 iOS 页面策略测试随实现删除，协议、映射、写操作和存储测试继续维护。

## 后续验收

先验收匿名首页、进吧、搜索与长帖阅读，再验证真实登录。正文图片缓存、完整图文排版、内嵌媒体播放及账号写操作界面尚未完成；具体功能状态以 README 为准。当前编译和 fixture 测试不构成线上服务、真实账号或发布签名验收。
