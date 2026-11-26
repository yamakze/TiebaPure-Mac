# 贡献约定

客户端面向搭载 Apple 芯片的 Mac，最低系统版本为 macOS 14。构建配置以 `Package.swift` 为准，应用版本以 `Resources/Info.plist` 为准。

## 开发与验证

```sh
make test
make verify
make run
```

协议、状态或存储变更须有行为回归验证。使用 Conventional Commits，提交信息及 PR 标题用英文，PR 详情用中文。列出实际验证及未验证范围。

错误、取消、空数据与持久化失败应分别表达。不要记录 Cookie、凭证、手机号和含敏感参数的请求地址。

## 代码边界

- `Domain` 保存领域模型与内容过滤规则。
- `Infrastructure` 保存协议接口、`Network/Mapping` 模型映射、媒体下载、认证及系统存储实现，写操作复用已有协调器。
- `App` 保存 Mac 场景、界面及窗口状态。账号归应用，选中内容及导航归窗口。

## 上游与生成代码

`origin` 指向本 fork，`upstream` 指向原项目。按具体协议修复选择性引入上游提交，并保留原作者信息。

修改 `Protos` 后运行 `scripts/generate-protos.sh`，同步提交生成文件，且生成器版本须与 SwiftProtobuf 运行时匹配。

## 发布

应用版本和对应的双语 `CHANGELOG.md` 小节需要在打标签前准备好。发布标签使用 `vX.Y.Z`。CI 根据上一正式版递增并注入 `CFBundleVersion`。

推送标签后，`macOS Release` 工作流验证标签版本、运行测试，从 `CHANGELOG.md` 提取对应版本的发布说明，并创建或更新 GitHub Release 草稿。已存在的标签可以使用 `workflow_dispatch` 重新生成草稿。审查草稿与下载包后发布，正式版可标为 Latest。

CI 默认构建 Apple Silicon ad-hoc 签名包，使用项目独立的 Sparkle Ed25519 密钥签名更新源和 ZIP。Developer ID 签名与 Apple 公证可选。

Sparkle 更新源的发布流程

1. 首次启用时，使用 `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account TiebaPure-Mac` 建立独立的更新密钥。将公钥提交到 `Resources/SparklePublicKey.txt`，或设置仓库变量 `SPARKLE_PUBLIC_KEY`。用同一命令加 `-x <private-key-file>`，将私钥导出到权限受限的临时目录，通过 `gh secret set SPARKLE_PRIVATE_KEY < <private-key-file>` 存为仓库 Secret 后删除导出文件。后续发布沿用同一套密钥。
2. 如需 Apple 公证，配置 `MACOS_SIGN_IDENTITY` 仓库变量及 `MACOS_CERTIFICATE_P12`（Base64）、`MACOS_CERTIFICATE_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` 仓库 Secrets。
3. 审查草稿和安装包后，将版本发布为 Latest。稳定更新源使用该 Release 的 `appcast.xml`，它和对应的 ZIP 均包含在 `SHA256SUMS.txt` 中。旧版应用需先手动升级到包含 Sparkle 公钥和更新源的版本，才能接收应用内更新。
