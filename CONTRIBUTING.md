# 贡献约定

客户端面向搭载 Apple 芯片的 Mac，最低系统版本为 macOS 14。构建配置以 `Package.swift` 为准，应用版本以 `Resources/Info.plist` 为准。

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

GitHub 试用版使用 `CODE_SIGN_IDENTITY=- make release` 构建 Apple Silicon 包，以 GitHub Pre-release 分发 ZIP 和 SHA-256。下载说明应注明 ad-hoc 签名、公证和更新状态。未配置 `MACOS_SIGN_IDENTITY` 时，推送标签不会启动 Developer ID 构建。

正式版发布流程

1. 更新 `CHANGELOG.md` 对应版本小节、`Resources/Info.plist` 中的 `CFBundleShortVersionString`，并递增 `CFBundleVersion`。发布标签使用 `vX.Y.Z`。
2. 首次发布时，使用 `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account TiebaPure-Mac` 建立独立的更新密钥。公钥可提交到 `Resources/SparklePublicKey.txt`，也可通过仓库变量 `SPARKLE_PUBLIC_KEY` 覆盖。仓库 Secret `SPARKLE_PRIVATE_KEY` 保存对应的私钥。用同一命令加 `-x <private-key-file>` 导出供 Secret 导入的私钥，导入后删除临时文件。后续发布沿用同一套密钥。
3. 配置 `MACOS_SIGN_IDENTITY` 仓库变量，以及 `MACOS_CERTIFICATE_P12`（Base64）、`MACOS_CERTIFICATE_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` 仓库 Secrets。推送版本标签后，发布工作流构建 Apple Silicon 应用，完成 Developer ID 签名和公证，再生成签名更新源和校验文件。
4. 审查 GitHub Release 草稿并验证安装后，将正式版本发布为 Latest。稳定更新源使用该 Release 的 `appcast.xml`，请保留其签名以及同批次的 ZIP。
