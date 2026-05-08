import { ElectronAPI } from '@electron-toolkit/preload'

declare global {
  interface Window {
    electron: ElectronAPI
    api: {
      getAppVersion: () => Promise<string>
    }
  }
}

export {}
