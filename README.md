# 包工头 Baogong

<img src="assets/branding/app_icon.png" alt="Baogong's icon: the BaoCode bun in a hard hat" width="96" height="96"/>

**包工头**是 [BaoCode](https://github.com/baocode-dev/baocode) 的**非官方修改版**：Claude Code 的桌面界面，自带 IDE，再加上 pi 和 Codex 两种智能体、智能体之间的协作，以及一些自己用着顺手的改动。它基于 BaoCode 1.4.0，选择性合入了 1.5.0 的改动，自 2026 年 10 月起修改，与 BaoCode 官方开发者无关：有问题请在本仓库反馈，不要报给官方。许可证同上游，为 [GPL-3.0](LICENSE)。

> **Unofficial fork.** Baogong is a personal modification of [BaoCode](https://github.com/baocode-dev/baocode) 1.4.0 with selected changes of 1.5.0, not made or supported by the BaoCode developers: report problems here, not upstream. GPL-3.0, as upstream. [In English](#in-english) below.

## 下载

到 [Releases](https://github.com/y0un922/baogong/releases/latest) 下载：

| 系统 | 文件 |
| --- | --- |
| macOS，Apple 芯片 | `Baogong-<版本>-arm64.dmg` |
| macOS，Intel | `Baogong-<版本>-x64.dmg` |
| Windows 10 / 11（x64） | `Baogong-<版本>-setup.exe` |
| Linux（Ubuntu 22.04 及以后，x64 / arm64） | `Baogong-<版本>-linux-{amd64,arm64}.deb`，或免安装的 `.tar.gz` |

- **macOS**：打开 dmg，把包工头拖进“应用程序”。它没有经过苹果公证，首次打开前在“终端”里运行 `xattr -dr com.apple.quarantine /Applications/Baogong.app`。
- **Windows**：安装包没有签名，SmartScreen 拦下时点“更多信息 → 仍要运行”。
- **Linux**：`sudo apt install ./Baogong-<版本>-linux-amd64.deb`，之后从应用菜单或 `baogong` 命令打开。

需要先装好 [Claude Code](https://github.com/anthropics/claude-code)；用 pi 或 Codex 时再装对应的命令行工具。包工头可以和官方 BaoCode 同时安装，但两者共用同一份数据（会话、设置），不要同时打开。它不会自动更新：新版本到 Releases 下载。

## 比 BaoCode 多了什么

### 更多智能体

- **pi 和 Codex**：除了 Claude Code，还能在同一个界面里用 [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) 和 [OpenAI Codex](https://github.com/openai/codex)（`codex app-server`），对话、改动、模型选择和每种智能体自己的设置都在一处。pi 的待办列表和它向你提的问题直接显示在对话里。
- **智能体之间协作**：一个智能体可以在旁边的窗格里启动别的智能体（Claude Code、Codex、pi），给它派活、等它回答、读它的结果，用完把窗格关掉。每个都在你眼前，执行命令前照样问你。
- **在服务器上干活**：智能体在侧栏里打开本机或 ssh 的终端，在里面执行命令、读输出，你在旁边看着，随时能接手；要输密码时它会请你来输。看起来有破坏性的命令只输入不执行，由你按回车。

### 对话

- **消息导航**：对话右边缘，你发的每条消息一道短线；指针移上去列出所有消息，点一下跳过去。
- **拆分窗格**：<kbd>⌘\\</kbd> 在旁边开一个新会话，<kbd>⌘-</kbd> 向下拆分。
- **每轮的结束时间**：每轮结尾显示它在几点结束，用来判断模型的提示缓存还在不在。
- **TPS 按模型请求算**：实际输出的 token 除以模型请求的总耗时，不把本地工具运行的时间算进去。

### 侧栏用键盘操作

| 快捷键 | 作用 |
| --- | --- |
| <kbd>⌥⌘B</kbd> | 打开侧栏并把键盘移进去；在侧栏里再按，收起侧栏回到对话 |
| <kbd>⇧⌥⌘B</kbd> | 显示或隐藏侧栏的页面列表（文件树、改动、终端……） |
| <kbd>⌥⌘T</kbd> | 打开侧栏的终端并聚焦；在终端里再按，收起回到对话 |
| <kbd>⇧⌥⌘T</kbd> | 在侧栏新开一个终端 |
| <kbd>⇧⌘E</kbd> / <kbd>⇧⌘G</kbd> | 打开侧栏的文件 / 改动页，键盘也移过去 |

Windows 和 Linux 上 <kbd>⌘</kbd> 换成 <kbd>Ctrl</kbd>，<kbd>⌥</kbd> 换成 <kbd>Alt</kbd>。

### 浏览器

- 浏览器扩展在 [Arc](https://arc.net) 里也能用（Arc 的标签页分组不响应，改用扩展自己记录共享的标签页）。
- 侧栏里的网页以居中的卡片显示，不再贴在顶部。

### 隐私与其他

- **不向官方发送数据**：不发送每日使用统计，也没有上传诊断日志给官方开发者的入口。
- **不从官方自动更新**：官方安装包会整个替换应用，覆盖这里的改动。
- 去掉了请你去 GitHub 点 Star 的提示。
- 修复 macOS 标题栏的点击问题。
- 自己的名字和图标（戴安全帽的包子），可以和官方 BaoCode 同时安装。

改动细节见 [docs/fork.md](docs/fork.md)，从上游合入了什么见 [docs/upstream-review.md](docs/upstream-review.md)。

## In English

Baogong (包工头, "the foreman") is BaoCode, a desktop UI for Claude Code with an IDE built in, plus:

- **More agents**: [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) and [OpenAI Codex](https://github.com/openai/codex) beside Claude Code, in the same interface; pi's todo list and questions in the chat.
- **Agents working together**: an agent can start other agents (Claude Code, Codex, pi) in panes beside it, give them work, wait for and read their answers, and close them.
- **Work on servers**: agents run commands in terminals in the side panel, on this machine or over ssh, which you watch and can take over.
- **In the chat**: a rail of your messages to jump between them; split panes (<kbd>⌘\\</kbd>, <kbd>⌘-</kbd>); the time each turn ended; TPS measured over the model's requests.
- **The side panel from the keyboard**: <kbd>⌥⌘B</kbd> into and out of it, <kbd>⇧⌥⌘B</kbd> its list of pages, <kbd>⌥⌘T</kbd> / <kbd>⇧⌥⌘T</kbd> its terminals.
- **Browser**: the extension works in Arc.
- **Privacy**: no usage statistics or diagnostics sent upstream, no updates from upstream, no GitHub Star prompt.

Downloads for macOS, Windows and Linux are in [Releases](https://github.com/y0un922/baogong/releases/latest). It installs beside BaoCode, but shares its data: do not run both at once.

---

以下是上游 BaoCode 的 README。 / What follows is upstream's README.

<a href="https://trendshift.io/repositories/289180?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-289180" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/289180/daily?language=Dart" alt="baocode-dev%2Fbaocode | Trendshift" width="250" height="55"/></a>

**English** · [简体中文](README_CN.md) · [日本語](README_JA.md) · [Français](README_FR.md) · [Español](README_ES.md)

**The open-source control plane for [Claude Code](https://github.com/anthropics/claude-code). More than an interface.**

Beyond a detail-rich 360 FPS interface: Claude Code on your other machines, control from your phone, deep Windows tuning, 10× faster browser control, a full code editor, any custom API, usage insights, conversation orchestration and Bots.

[Website](https://baocode.dev) · [Download](https://baocode.dev/download) · [Changelog](https://baocode.dev/changelog)

![BaoCode in Agent mode: agents on several machines, a conversation at work and its usage](https://baocode.dev/readme/agent.webp)

![BaoCode in IDE mode: the file tree and the editor, with the conversation beside them](https://baocode.dev/readme/ide.webp)

![What BaoCode does: 360 FPS rendering, Claude Code over SSH, the browser, any model, Windows, usage and cost](https://baocode.dev/readme/features-en.webp)

## No reinvented wheels, just what works

Claude Code is already good; BaoCode adds only what it lacks. It works out of the box, with nothing new to learn, and feels the way it always should have.

**Why Claude Code?** Customize any agent core far enough and it ends up shaped like Claude Code: the same tools, the same context handling, the same skills and MCP. Rather than rebuild it the long way round, BaoCode uses it directly and bridges other models at the protocol layer, so one setup works with all of them. It runs the Claude Code you already have, with your settings, your sign-in and your `CLAUDE.md`; where Claude Code isn't installed, BaoCode's built-in agent reads the same settings and runs on a model provider you add.

**One conversation runs the rest.** No orchestration canvas. Through built-in MCP, the main conversation directs other sessions and subagents, across servers too; describe a complex flow once, or write it as a skill to reuse.

## Features

### GPU 360 FPS native rendering

No Electron, no DOM reflow. BaoCode is a native app that draws its interface straight on the GPU: fast token streams keep pace with your display's refresh rate, scrolling follows your hand, and it throttles itself down while it waits.

| | BaoCode | VS Code | Cursor |
| --- | --- | --- | --- |
| Launch | ≈ 0.18 s | ≈ 2–3 s | ≈ 2–3 s |
| Memory, one window idle | ≈ 120 MB | ≈ 970 MB | ≈ 1.9 GB |
| Processes, one window | 2 | 8 | 13 |
| Download size, Windows | ≈ 16 MB | ≈ 244 MB | ≈ 214 MB |

### Claude Code over SSH, on any machine

Attach to any Linux, macOS or Windows host and use the Claude Code installed there, while it reaches straight back to your own machine: the Android phone on your USB-C port, your local Chrome, your ports. The window stays with you; files, Git, search, terminals, language servers and Claude Code run on the host. On Windows, WSL distributions open the same way.

### 10× faster browser control

With the BaoCode extension (Chrome, Edge, Brave, Arc), agents work in your live, signed-in browser rather than in a loop of blind screenshots: stylus-grade input, React and Vue state, WebSocket tracing, source breakpoints and 1 ms performance profiling. They only see the tabs you share with them, and everything stays on your computer.

### Every model, plugged in

DeepSeek, Kimi, ChatGPT, Gemini and the other leading models, and platforms like OpenRouter and Ollama, plug straight in. BaoCode adapts each protocol (Anthropic Messages, OpenAI Chat Completions and Responses, Codex, Gemini) in a local proxy, without touching `~/.claude`, so every one of them performs just as well in Claude Code. Keys stay in the system keychain.

### Usage and pricing

See where the tokens go: input, output, cache reads and writes, the cache hit rate and what it saved. Prices follow each provider's rules, peak and off-peak hours, holidays and tiered context included.

### Made for Windows

[bash.exe](https://github.com/baocode-dev/bash-exe) smooths over your Windows' platform differences, so it works much like WSL, and the interface renders on Skia's GPU path just as smoothly as on macOS. x64 and Arm64.

### Your phone, the same sessions

The exact same live sessions, 400K context breakdowns, model quotas and SSH remote codebases, mirrored natively to iOS and Android. Pair by QR code; the connection is end-to-end encrypted, direct or through BaoCode's relays.

### A full code editor

An editor (Monaco, ported to Flutter), a terminal and Source Control with a commit graph, built in, with language servers and VS Code, IntelliJ, Sublime and Atom keymaps. Claude Code drafts your commit messages. Your VS Code themes color the editor, the conversation and the sidebar alike.

### And

- **Keep or Undo** each change Claude made, file by file; checkpoints live in BaoCode's own data folder, never in your repository's `.git`.
- **Goals.** Type `/goal` and what you want done, and Claude keeps working until it is met.
- **A rich-text input.** Code copied from the editor arrives as a reference to its file and lines; pasted images and dropped files sit where you put them in the sentence.
- **Plugins, MCP servers, skills,** subagents, rules, commands and hooks in one place, for you or for a single project.
- **Notifications** when an agent needs you or finishes. Close the window and the agents keep running in the menu bar or tray.
- **Updates itself** in the background, or manually, or not at all.

## Requirements

- **Desktop:** macOS 12 or later (Apple silicon or Intel), Windows 10 or later (x64 or Arm64), or Linux: Ubuntu 22.04 or later and other Debian-based distributions (x64 or arm64).
- **Phone:** Android 7.0 or later, or iOS 15 or later (beta on TestFlight), paired with BaoCode on a computer.
- **Browser extension:** Chrome, Edge, Brave or Arc, on macOS or Windows.
- [Claude Code](https://github.com/anthropics/claude-code), if you have it; without it, a model provider you add.

All of it is on the [download page](https://baocode.dev/download).

## Building from source

BaoCode is a Flutter app (Dart SDK `^3.13.4`).

```sh
flutter pub get
flutter run -d macos        # or: flutter run -d windows
```

To build what is released, into `build/installers/`:

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg and BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe (needs Inno Setup)
flutter build linux --release && sh tool/package_linux_deb.sh   # BaoCode-<version>-linux-{amd64,arm64}.deb and .tar.gz, on Ubuntu
dart run tool/build_remote_server.dart    # the SSH remote server, for Linux, macOS and Windows hosts
```

The full test suite is slow; run the tests for what you changed, for example `flutter test test/update`.

Releases are built and published by CI when a `v*` tag is pushed; versions, signing and where releases go are in [docs/release.md](docs/release.md). More in [docs/](docs): [auto-update](docs/auto-update.md), [SSH remote](docs/ssh-remote.md), [Windows](docs/windows.md), [the phone link](docs/mobile-link.md) (some are in Chinese).

## Repository

| Path | What it is |
| --- | --- |
| [lib/](lib) | The app |
| [packages/bao_agent](packages/bao_agent) | The built-in agent, speaking Claude Code's stream-json protocol |
| [packages/bao_editor](packages/bao_editor) | Monaco, ported to Flutter: the editor, its highlighting, VS Code's themes and keybindings |
| [packages/bao_xterm](packages/bao_xterm) | A Dart port of xterm.js |
| [packages/bao_pty](packages/bao_pty), [bao_conpty](packages/bao_conpty) | Pseudo terminals for Dart: forkpty on macOS and Linux, ConPTY on Windows |
| [packages/bao_remote](packages/bao_remote) | The remote host served over SSH |
| [packages/bao_link](packages/bao_link), [bao_iroh](packages/bao_iroh) | The link to your phone: QR pairing, end-to-end encrypted connections over iroh |
| [packages/bao_markdown](packages/bao_markdown) | A markdown editor that renders as you type |
| [packages/bao_websearch](packages/bao_websearch) | Web search for any model, without a search API |
| [browser_extension/](browser_extension) | The browser extension |
| [macos/](macos), [windows/](windows), [linux/](linux) | The native runners |
| [tool/](tool) | Build, packaging and release scripts |
| [site/](site) | The website, [baocode.dev](https://baocode.dev) |
| [docs/](docs) | Design notes |

## Feedback

Issues and pull requests are welcome. Discuss a change in an issue before you write it; large pull requests, and pull requests for changes not discussed first, are not accepted. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

BaoCode is licensed under the [GNU General Public License v3.0](LICENSE)
(GPL-3.0-only). The editor and terminal packages in [packages/](packages)
(bao_editor, bao_xterm, bao_pty) are MIT. Third-party components keep their
own licenses, found next to them in the source tree.

BaoCode is an independent project, not affiliated with or endorsed by
Anthropic.

<img width="480" alt="Scan to join the BaoCode WeChat group" src="site/readme/wechat-group.jpg" />
