const { contextBridge, ipcRenderer, clipboard, shell } = require('electron')

contextBridge.exposeInMainWorld('electronAPI', {
  platform: process.platform,
  isElectron: true,

  // ── Window controls ──
  minimize: () => ipcRenderer.invoke('window:minimize'),
  maximize: () => ipcRenderer.invoke('window:maximize'),
  close: () => ipcRenderer.invoke('window:close'),
  isMaximized: () => ipcRenderer.invoke('window:isMaximized'),
  onMaximizeChange: (callback) => {
    ipcRenderer.on('window:maximize-change', (_event, isMaximized) => callback(isMaximized))
  },
  removeMaximizeListener: () => {
    ipcRenderer.removeAllListeners('window:maximize-change')
  },
  onMenuAction: (callback) => {
    ipcRenderer.on('menu-action', (_event, action) => callback(action))
  },
  removeMenuActionListener: () => {
    ipcRenderer.removeAllListeners('menu-action')
  },

  // ── File dialogs ──
  openFile: (opts) => ipcRenderer.invoke('dialog:openFile', opts),
  openFiles: (opts) => ipcRenderer.invoke('dialog:openFiles', opts),
  saveFile: (opts) => ipcRenderer.invoke('dialog:saveFile', opts),

  // ── System notifications ──
  notify: (title, body) => ipcRenderer.invoke('notification:show', title, body),

  // ── Window state persistence ──
  getWindowState: () => ipcRenderer.invoke('window:getState'),
  setWindowState: (state) => ipcRenderer.invoke('window:setState', state),

  // ── Clipboard helpers ──
  readClipboard: () => clipboard.readText(),
  writeClipboard: (text) => clipboard.writeText(text),

  // ── File system helpers ──
  openInOS: (filePath) => shell.openPath(filePath),

  // Save binary data to a temp file, returns the path
  saveTempFile: (data, filename) => ipcRenderer.invoke('file:saveTemp', data, filename),
})
