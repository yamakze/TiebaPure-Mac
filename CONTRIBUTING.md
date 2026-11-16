# 贡献约定

仅维护原生 macOS 客户端，最低 macOS 14。构建配置以 `Package.swift` 为准，应用版本以 `Resources/Info.plist` 为准。

## 开发与验证

```sh
swift test
scripts/compile_and_run.sh debug
```

协议、状态或存储变更须有行为回归验证。使用 Conventional Commits，提交信息及 PR 标题用英文，PR 详情用中文。列出实际验证及未验证范围。

错误、取消、空数据与持久化失败应分别表达。不要记录 Cookie、凭证、手机号和含敏感参数的请求地址。

## 代码边界

- `Domain` 保存模型、映射与业务规则；平台图片、WebKit 和窗口代码放在 `App` 或 `Infrastructure`。
- `Infrastructure` 保存协议、媒体下载、认证及系统存储实现，写操作复用已有协调器。
- `App` 保存 Mac 场景、界面及窗口状态。账号归应用，选中内容及导航归窗口。
- 当前使用一个应用模块。出现真实模块复用需求时再拆 target，避免为目录分层暴露大量 public API。
- 不新增 iOS、Catalyst、IPA、模拟器构建或旧系统兼容分支。

## 上游与生成代码

`origin` 指向本 fork，`upstream` 指向原项目。按具体协议修复选择性引入上游提交，保留作者信息；不整体合并已删除的 iOS 工程。

修改 `Protos` 后运行 `scripts/generate-protos.sh`，同步提交生成文件。生成器版本须与 SwiftProtobuf 运行时匹配。协议测试使用独立 wire fixture。

## 发布

更新 `CHANGELOG.md` 与 `Resources/Info.plist`。Mac 标签使用 `mac-vX.Y.Z`，避免混淆历史 iOS 标签。CI 产物仅供构建验证；正式分发须完成 Developer ID 签名、公证及安装验证。
