import { useEffect, useState } from 'react'

function App(): JSX.Element {
  const [version, setVersion] = useState<string>('')

  useEffect(() => {
    window.api.getAppVersion().then(setVersion).catch(console.error)
  }, [])

  return (
    <div className="app-shell">
      <aside className="sidebar sidebar-left">
        <div className="sidebar-title">项目</div>
        <div className="sidebar-empty">
          <p>暂无项目</p>
          <button type="button" className="ghost-btn" disabled>
            添加项目
          </button>
        </div>
      </aside>

      <main className="content">
        <header className="content-header">
          <h1>ClaudeWin</h1>
          <span className="version-tag">v{version || '0.1.0'}</span>
        </header>

        <section className="content-body">
          <p className="welcome-text">
            Windows 端 AI CLI 工作台 · Electron + React + TypeScript
          </p>
          <ul className="todo-list">
            <li>项目管理与持久化</li>
            <li>文件目录树 · 内嵌编辑器</li>
            <li>调起 Windows Terminal / PowerShell / cmd</li>
            <li>Claude Code / Codex 会话集成</li>
          </ul>
        </section>
      </main>

      <aside className="sidebar sidebar-right">
        <div className="sidebar-title">CLI 会话</div>
        <div className="sidebar-empty">
          <p>选择项目以启动会话</p>
        </div>
      </aside>
    </div>
  )
}

export default App
