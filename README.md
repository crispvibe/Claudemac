# ClaudeWin

ClaudeWin 是 [ClaudeMac](https://github.com/crispvibe/Claudemac/tree/main) 的 **Windows 端**对应版本,基于 Electron + TypeScript + React 实现的 AI CLI 工作台,用来管理项目、快速浏览/编辑文件,并在 Windows Terminal / PowerShell / cmd 中启动 Claude Code / Codex 会话。

> 本分支(`Windows`)是孤儿分支,与 `main`(macOS 端)完全独立。

## 技术栈

| 分类 | 技术 |
|------|------|
| 桌面框架 | Electron 32 |
| 构建工具 | electron-vite (Vite 5) |
| UI 层 | React 18 + TypeScript 5 |
| 进程模型 | 主进程 / 预加载 / 渲染进程 三层隔离,启用 `contextIsolation` |
| 打包 | electron-builder (NSIS + Portable, x64) |
| 最低系统 | Windows 10 全版本 |

## 环境要求

- **Node.js** ≥ 18.18 (推荐 20 LTS / 22 LTS)
- **npm** ≥ 9 (或 pnpm ≥ 8 / yarn ≥ 1.22)
- **Windows 10 1809+** 用于运行,**Windows 10/11** 用于开发
- 可选:[Windows Terminal](https://aka.ms/terminal) 用于会话调起

## 快速开始

```powershell
# 1. 安装依赖
npm install

# 2. 启动开发模式 (主进程 + 渲染进程热更新)
npm run dev

# 3. 类型检查
npm run typecheck

# 4. 生产构建 (输出到 out/)
npm run build

# 5. 打包 Windows 安装器 (NSIS + Portable, 输出到 dist/)
npm run build:win

# 5b. 仅打包便携版 (单 exe, 免安装)
npm run build:win:portable

# 5c. 打包未压缩目录 (调试)
npm run build:unpack
```

> 国内网络环境会自动使用 npmmirror 镜像下载 Electron 二进制(见 `.npmrc`),如有内网代理可自行覆盖。

## 项目结构

```text
ClaudeWin/
├── electron.vite.config.ts     # electron-vite 主配置
├── electron-builder.yml         # 打包配置 (NSIS + Portable)
├── tsconfig.json                # TS 项目引用根
├── tsconfig.node.json           # 主进程 / 预加载 TS 配置
├── tsconfig.web.json            # 渲染进程 TS 配置
├── package.json
├── .npmrc                       # Electron 镜像配置
├── build/                       # electron-builder 资源 (icon.ico 等)
├── resources/                   # 运行时资源 (asarUnpack)
└── src/
    ├── main/
    │   └── index.ts             # Electron 主进程入口
    ├── preload/
    │   ├── index.ts             # contextBridge 桥接
    │   └── index.d.ts           # window.api 类型声明
    └── renderer/
        ├── index.html
        └── src/
            ├── main.tsx         # React 挂载入口
            ├── App.tsx          # 三栏 UI 骨架
            ├── env.d.ts
            ├── assets/
            │   └── icon.svg
            └── styles/
                └── global.css
```

## 进程通信约定

- 渲染进程 → 主进程:通过 `window.api.*` 调用,内部走 `ipcRenderer.invoke`,返回 Promise。
- 全部启用 `contextIsolation: true`、`nodeIntegration: false`、`sandbox: false`。
- 严禁在渲染进程直接引入 Node 模块,所有原生能力必须经过 `preload/index.ts` 显式暴露。

示例(已实现):

```ts
// preload/index.ts
const api = {
  getAppVersion: (): Promise<string> => ipcRenderer.invoke('app:get-version')
}

// main/index.ts
ipcMain.handle('app:get-version', () => app.getVersion())

// renderer
const v = await window.api.getAppVersion()
```

## 待实现功能 (对齐 ClaudeMac)

- [ ] 添加项目目录(`dialog.showOpenDialog`)
- [ ] 项目列表持久化(`%APPDATA%/ClaudeWin/projects.json`)
- [ ] 文件目录树(忽略 `.git`、`node_modules` 等)
- [ ] 多标签 Monaco Editor 编辑器
- [ ] UTF-8 文本读写,二进制/大文件保护
- [ ] 调起 Windows Terminal / PowerShell / cmd / ConEmu
- [ ] Claude Code 命令构造与转义(PowerShell 引号规则)
- [ ] 历史会话扫描(`%USERPROFILE%/.claude/projects`)
- [ ] 设置窗口
- [ ] 应用图标与签名

## 数据位置 (规划)

```text
%APPDATA%\ClaudeWin\projects.json
%APPDATA%\ClaudeWin\launch-history.json
%USERPROFILE%\.claude\projects   # 只读扫描
```

## 与 macOS 端的差异

| 能力 | macOS (ClaudeMac) | Windows (ClaudeWin) |
|------|-------------------|---------------------|
| UI 框架 | SwiftUI + AppKit | Electron + React |
| 毛玻璃 | NSVisualEffectView | Mica/Acrylic (Win11) / 纯色 (Win10) |
| 编辑器 | NSTextView + NSRulerView | Monaco Editor (规划中) |
| 终端调起 | AppleScript → Terminal/iTerm2 | `child_process.spawn` → wt.exe / powershell.exe |
| 沙箱授权 | security-scoped bookmark | 无需,直接 fs 访问 |
| 命令转义 | POSIX 单引号 quoting | PowerShell 单引号 quoting (`''` 转义) |

## License

MIT
