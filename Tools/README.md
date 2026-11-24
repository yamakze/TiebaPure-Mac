# 工具与独立测试模块

本目录存放独立于 SwiftPM 默认单元测试套件的开发与辅助测试工程。

## ScreenshotTests

`Tools/ScreenshotTests/ScreenshotTests.swift` 为基于 XCTest 框架编写的原生 UI 界面自动化审查测试用例。

### 设计与隔离原则

- **隔离 SwiftPM 测试扫描**：UI 测试依赖 XCTest 的 `XCUIApplication` 宿主注入机制，在标准命令行 `swift test` 下无法直接构建与执行。将其独立置于 `Tools/` 目录下，可保证日常单元测试纯粹由 SwiftPM 管理，避免引入图形宿主依赖。
- **动态工程生成机制**：运行 `scripts/capture-ui.sh` 时，脚本调用 `scripts/lib/screenshot-project.py` 在 `.build/screenshot-runner/` 临时生成一次性使用的 `ScreenshotRunner.xcodeproj`，通过 `xcodebuild test` 驱动独立构建的 `TiebaPure-Mac-Screenshots.app` 捕获界面各状态截图。
- **免污染生产环境**：测试运行过程仅使用 DebugSupport 下的内存模拟接口与独立 Bundle ID，不读取真实 Keychain 凭据或线上网络接口。
