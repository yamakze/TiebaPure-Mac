<div align="right">

**English** | [简体中文](README.zh-CN.md)

</div>

<div align="center">

<img src="docs/screenshots/icon.png" width="140" alt="TiebaPure-Mac" />

# TiebaPure-Mac

**Native macOS client for Baidu Tieba**

SwiftUI · AppKit · WebKit Login · SwiftPM · Sparkle Auto-Update

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?logo=apple)](#building)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](Package.swift)
[![License](https://img.shields.io/badge/license-GPL--3.0-green)](LICENSE)

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/screenshot-home.png" alt="Home Feed & Sidebar Navigation" /></td>
    <td width="50%"><img src="docs/screenshots/screenshot-thread.png" alt="Thread Reading & Continuous Pagination" /></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/screenshot-subposts.png" alt="Subpost Inspector Sidebar" /></td>
    <td width="50%"><img src="docs/screenshots/screenshot-forum.png" alt="Forum Browsing & Filtering" /></td>
  </tr>
</table>

</div>

## Overview

**TiebaPure-Mac** is a native macOS desktop client derived from [TiebaPure-iOS](https://github.com/infinityf4p/TiebaPure-iOS), engineered with SwiftUI and AppKit and optimized for large desktop displays and keyboard-first navigation.

It preserves full upstream Git history and original author attributions while removing mobile-specific touch transitions and simulator dependencies, focusing on responsive browsing, searching, reading, and account management on macOS.

## Features

- 🧭 **Desktop Navigation** — Unified sidebar with Home Recommendations, Forum Directory, Search, Followed Forums, and Bookmarks. Supports hierarchical navigation stacks and history traversing.
- 📖 **Seamless Reading Experience** — Continuous floor scrolling with author-only and reverse-order sorting options. Native right-hand Inspector drawer for subpost discussion threads.
- 🔍 **Two-Tier Search** — Site-wide forum search and in-forum keyword search. Automatically persists recent forums and query history locally.
- 🔐 **Isolated Login & Secure Storage** — Official authentication inside isolated WebKit containers. Session credentials are encrypted directly in the macOS Keychain with proactive expiration detection.
- 🖼️ **Native Media Rendering** — Displays built-in Tieba emoticons and high-resolution post images with zoom previews. Safely opens voice and video links externally.
- ⌨️ **Keyboard-Driven Shortcuts** — Complete keyboard shortcuts for section switching, search focus, content refreshing, and history navigation.
- 🔄 **Automatic Updates** — Integrated Sparkle 2 framework for Ed25519 signature-verified updates directly from GitHub Releases.
- 🎨 **Adaptive macOS Appearance** — Fluid support for Light and Dark system appearances following Apple Human Interface Guidelines.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘1` / `⌘2` / `⌘3` | Switch to Home / Forums / Search |
| `⌘F` | Focus search bar (in-forum on forum pages, site-wide elsewhere) |
| `Return` | Submit forum name or search query |
| `Esc` | Clear search query or exit input focus |
| `⌘R` | Refresh current page, forum, or thread |
| `⌘[` / `⌘]` | Navigate Back / Forward in history |

## Installation

System requirements: macOS 14+ (Sonoma or later), Apple Silicon and Intel Universal support.

### Homebrew

```bash
brew tap yamakze/tiebapure-mac https://github.com/yamakze/TiebaPure-Mac.git
brew install --cask yamakze/tiebapure-mac/tiebapure-mac
```

Upgrade:

```bash
brew update
brew upgrade --cask yamakze/tiebapure-mac/tiebapure-mac
```

### Manual Download

Download the latest `TiebaPure-Mac-<version>.zip` from [Releases](https://github.com/yamakze/TiebaPure-Mac/releases/latest), unpack it, and drag `TiebaPure-Mac.app` into your **Applications** folder.

> [!NOTE]
> If macOS alerts that the app cannot be opened or is damaged, remove the quarantine flag in Terminal:
> ```bash
> xattr -cr /Applications/TiebaPure-Mac.app
> ```

## Building

Requires macOS 14+ and Xcode 15+. Managed via SwiftPM and orchestrated with the root `Makefile`:

```bash
# Build the local macOS app bundle (artifacts/macos/TiebaPure-Mac.app)
make build

# Build and launch the application directly
make run

# Run core regression test suites
make test

# Verify project boundaries, versioning, and compliance files
make verify

# Build Universal release package
make release

# Clean build caches and review artifacts
make clean
```

Standard tests rely on deterministic local fixtures and avoid live network access. To run read-only online connectivity verification prior to release:

```bash
RUN_ANONYMOUS_LIVE_SMOKE=1 swift test --filter AnonymousLiveSmokeTests
```

## Architecture

```
Sources/TiebaPureMac/
├── App/                # App entry, window scenes, reader view, settings, and updates
├── Domain/             # Core business models, content filtering, and protocol mapping
├── Infrastructure/     # HTTP client, Protobuf models, Keychain auth, local storage, and coordinators
└── DebugSupport/       # Offline development fixtures and screenshot runner support
```

```mermaid
graph TD
    App[App & Views] --> Domain[Domain Models]
    App --> Infra[Infrastructure]
    Domain --> Mappers[Domain Mappers]
    Infra --> Network[Network & TiebaAPI]
    Infra --> Auth[Auth & Keychain]
    Infra --> Persistence[Local Storage]
    Infra --> Protobuf[Protobuf Schemas]
    Network --> Protobuf
```

## Documentation

| Document | Description |
| --- | --- |
| [Architecture Decisions](docs/architecture.md) | macOS architecture convergence, state ownership, and modular boundaries |
| [Privacy & Data Handling](docs/privacy.md) | Official endpoint direct connectivity, Keychain protection, and local boundaries |
| [Contributing & Release](CONTRIBUTING.md) | Development standards, Git commit guidelines, and GitHub Release workflow |
| [Third-Party Licenses](LICENSES/README.md) | Pinned dependency versions and license notices for Sparkle and SwiftProtobuf |
| [Notice & Attribution](NOTICE.md) | Original copyright attributions, baseline commits, and modification notices |

## Declarations & Acknowledgements

- This project is an independent third-party desktop client with no affiliation, authorization, or endorsement from Baidu Inc. or Baidu Tieba. Protocols rely on unofficial endpoints and are subject to server-side changes.
- Special thanks to [infinityf4p](https://github.com/infinityf4p/TiebaPure-iOS) and upstream contributors.
- Protocol research credits to the [TiebaLite](https://github.com/HuanCheng65/TiebaLite) and [aiotieba](https://github.com/lumina37/aiotieba) open-source communities.
- Distributed under the [GPL-3.0-only](LICENSE) license.
