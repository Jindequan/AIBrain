const { app, BrowserWindow, nativeImage, dialog, Menu, ipcMain, shell } = require('electron')
const path = require('path')
const { spawn } = require('child_process')
const http = require('http')
const fs = require('fs')
const os = require('os')

const iconPath = path.join(__dirname, 'dist', 'logo.png')
const dockIcon = nativeImage.createFromPath(iconPath)
const appIcon = dockIcon.isEmpty() ? undefined : dockIcon

if (!dockIcon.isEmpty() && process.platform === 'darwin') {
  app.dock.setIcon(dockIcon)
}

let mainWindow
let backendProcess

function getBackendPath() {
  const isDev = process.env.NODE_ENV === 'development'
  const executableName = process.platform === 'win32' ? 'ai_brain.bat' : 'ai_brain'

  if (isDev) {
    return path.join(__dirname, '..', 'backend', '_build', 'prod', 'rel', 'ai_brain', 'bin', executableName)
  }
  return path.join(process.resourcesPath, 'backend', 'bin', executableName)
}

function findDistDir() {
  const candidates = [
    path.join(__dirname, 'dist'),
    path.join(process.resourcesPath, 'app.asar.unpacked', 'dist'),
    path.join(path.dirname(process.execPath), 'dist'),
  ]
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'index.html'))) return candidate
  }
  return path.join(__dirname, 'dist')
}

const BACKEND_START_PORT = parseInt(process.env.AIBRAIN_PORT || '43225', 10)

function waitForBackend(port, retries = 30, interval = 1000) {
  return new Promise((resolve, reject) => {
    const check = (attempt) => {
      const req = http.get(`http://localhost:${port}/api/v1/health`, (res) => {
        if (res.statusCode === 200) { res.resume(); resolve() }
        else if (attempt < retries) { res.resume(); setTimeout(() => check(attempt + 1), interval) }
        else reject(new Error(`Backend health check returned status ${res.statusCode}`))
      })
      req.on('error', () => {
        if (attempt < retries) setTimeout(() => check(attempt + 1), interval)
        else reject(new Error('Backend did not become ready'))
      })
      req.end()
    }
    check(0)
  })
}

function startBackend(port) {
  const backendPath = getBackendPath()
  if (!fs.existsSync(backendPath)) {
    showErrorAndExit('Backend Not Found', `Could not find the AIBrain backend at:\n${backendPath}\n\nMake sure to run 'bin/build' first.`)
    return 0
  }
  const env = { ...process.env, AIBRAIN_PORT: String(port), STATIC_DIR: findDistDir() }
  backendProcess = spawn(backendPath, ['start'], { env, stdio: ['ignore', 'pipe', 'pipe'] })
  backendProcess.stdout.on('data', (data) => console.log(`[backend] ${data.toString().trim()}`))
  backendProcess.stderr.on('data', (data) => console.error(`[backend] ${data.toString().trim()}`))
  backendProcess.on('error', (err) => { console.error('Failed to start backend:', err); showErrorAndExit('Backend Error', `Could not start the AIBrain backend:\n${err.message}`) })
  backendProcess.on('exit', (code, signal) => {
    const exitMsg = signal != null ? `killed with signal ${signal}` : `exited with code ${code}`
    console.log(`Backend ${exitMsg}`)
    if (mainWindow && !mainWindow.isDestroyed()) showErrorAndExit('Backend Crashed', `The AIBrain backend stopped unexpectedly (${exitMsg}).\nThe application will now close.`, true)
  })
}

function showErrorAndExit(title, message, offerRestart = false) {
  if (offerRestart) {
    const result = dialog.showMessageBoxSync({ type: 'error', title, message, buttons: ['Restart', 'Quit'], defaultId: 1 })
    if (result === 0) { restartBackend(); return }
  } else {
    dialog.showErrorBox(title, message)
  }
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.close()
  app.quit()
}

let resolvedPort = null

function restartBackend() {
  if (backendProcess) { backendProcess.kill('SIGTERM'); backendProcess = null }
  startBackend(resolvedPort || BACKEND_START_PORT)
  waitForBackend(resolvedPort || BACKEND_START_PORT)
    .then(() => { if (mainWindow && !mainWindow.isDestroyed()) mainWindow.loadURL(`http://localhost:${resolvedPort || BACKEND_START_PORT}`) })
    .catch(() => showErrorAndExit('Backend Unavailable', 'Could not restart the backend.'))
}

// ── Native Menu (macOS) ────────────────────────────────────────────

function buildMenu() {
  const isMac = process.platform === 'darwin'
  const template = [
    ...(isMac ? [{
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { label: 'Settings', accelerator: 'Cmd+,', click: () => mainWindow?.webContents.send('menu-action', 'settings') },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    }] : []),
    {
      label: 'File',
      submenu: [
        { label: 'New Chat', accelerator: 'CmdOrCtrl+N', click: () => mainWindow?.webContents.send('menu-action', 'new-chat') },
        { type: 'separator' },
        ...(isMac ? [] : [{ label: 'Settings', accelerator: 'Ctrl+,', click: () => mainWindow?.webContents.send('menu-action', 'settings') }, { type: 'separator' }]),
        { role: 'quit' },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        ...(isMac ? [{ type: 'separator' }, { role: 'front' }] : [{ role: 'close' }]),
      ],
    },
    {
      label: 'Help',
      submenu: [
        { label: 'About AIBrain', click: () => mainWindow?.webContents.send('menu-action', 'about') },
      ],
    },
  ]
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

// ── IPC Handlers ────────────────────────────────────────────────────

function setupIPC() {
  // Window controls
  ipcMain.handle('window:minimize', () => mainWindow?.minimize())
  ipcMain.handle('window:maximize', () => {
    if (mainWindow?.isMaximized()) mainWindow.unmaximize()
    else mainWindow?.maximize()
  })
  ipcMain.handle('window:close', () => mainWindow?.close())
  ipcMain.handle('window:isMaximized', () => mainWindow?.isMaximized())
  ipcMain.handle('window:getPlatform', () => process.platform)

  mainWindow?.on('maximize', () => mainWindow?.webContents.send('window:maximize-change', true))
  mainWindow?.on('unmaximize', () => mainWindow?.webContents.send('window:maximize-change', false))

  // File dialogs
  ipcMain.handle('dialog:openFile', async (_event, opts) => {
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openFile'],
      filters: opts?.filters || [],
    })
    return result.canceled ? null : result.filePaths[0]
  })
  ipcMain.handle('dialog:openFiles', async (_event, opts) => {
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openFile', 'multiSelections'],
      filters: opts?.filters || [],
    })
    return result.canceled ? [] : result.filePaths
  })
  ipcMain.handle('dialog:saveFile', async (_event, opts) => {
    const result = await dialog.showSaveDialog(mainWindow, {
      defaultPath: opts?.defaultPath,
      filters: opts?.filters || [],
    })
    return result.canceled ? null : result.filePath
  })

  // System notifications
  ipcMain.handle('notification:show', async (_event, title, body) => {
    new Notification({ title, body, icon: dockIcon }).show()
  })

  // Save binary data to a temp file (for audio recording → STT)
  ipcMain.handle('file:saveTemp', async (_event, data, filename) => {
    const tmpPath = path.join(os.tmpdir(), filename)
    fs.writeFileSync(tmpPath, Buffer.from(data))
    return tmpPath
  })

  // Window state persistence
  const STATE_PATH = path.join(app.getPath('userData'), 'window-state.json')
  ipcMain.handle('window:getState', () => {
    try {
      return JSON.parse(fs.readFileSync(STATE_PATH, 'utf-8'))
    } catch { return null }
  })
  ipcMain.handle('window:setState', (_event, state) => {
    try {
      fs.writeFileSync(STATE_PATH, JSON.stringify(state))
    } catch { /* ignore */ }
  })
}

// ── Create Window ──────────────────────────────────────────────────

function createWindow() {
  const isMac = process.platform === 'darwin'

  const STATE_PATH = path.join(app.getPath('userData'), 'window-state.json')
  let savedState = {}
  try {
    savedState = JSON.parse(fs.readFileSync(STATE_PATH, 'utf-8') || '{}')
  } catch { /* use defaults */ }

  mainWindow = new BrowserWindow({
    width: savedState.width || 1280,
    height: savedState.height || 840,
    x: savedState.x,
    y: savedState.y,
    minWidth: 800,
    minHeight: 600,
    title: 'AIBrain',
    icon: appIcon,
    backgroundColor: '#fafafa',
    titleBarStyle: isMac ? 'hidden' : 'default',
    ...(isMac ? {} : { frame: false }),
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  // Persist window state on resize/move
  const saveState = () => {
    try {
      const bounds = mainWindow.getBounds()
      fs.writeFileSync(STATE_PATH, JSON.stringify({ ...bounds, isMaximized: mainWindow.isMaximized() }))
    } catch { /* ignore */ }
  }
  mainWindow.on('resize', saveState)
  mainWindow.on('move', saveState)
  mainWindow.on('maximize', saveState)
  mainWindow.on('unmaximize', saveState)

  if (savedState.isMaximized) mainWindow.maximize()

  setupIPC()
  buildMenu()

  mainWindow.loadURL(`http://localhost:${resolvedPort}`)

  if (process.env.NODE_ENV === 'development') {
    mainWindow.webContents.openDevTools()
  }
}

async function tryStartBackend(startPort) {
  for (let port = startPort; port < startPort + 10; port++) {
    startBackend(port)
    try {
      await waitForBackend(port, 10, 800)
      resolvedPort = port
      console.log(`Backend ready on port ${port}`)
      return
    } catch (_) {
      if (backendProcess) { backendProcess.kill('SIGTERM'); backendProcess = null }
    }
  }
  throw new Error(`Could not bind any port from ${startPort} to ${startPort + 9}`)
}

app.whenReady().then(async () => {
  try {
    await tryStartBackend(BACKEND_START_PORT)
    createWindow()
  } catch (err) {
    showErrorAndExit('Backend Unavailable', `Could not start the AIBrain backend.\n\n${err.message}\n\nMake sure the backend is built with 'MIX_ENV=prod mix release' before packaging.`)
  }
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    if (backendProcess && resolvedPort) createWindow()
    else tryStartBackend(BACKEND_START_PORT).then(createWindow).catch(() => showErrorAndExit('Backend Unavailable', 'Could not restart the backend.'))
  }
})

app.on('will-quit', () => {
  if (backendProcess) {
    console.log('Shutting down backend...')
    backendProcess.kill('SIGTERM')
    const forceKillTimeout = setTimeout(() => { if (backendProcess) backendProcess.kill('SIGKILL') }, 5000)
    backendProcess.on('exit', () => clearTimeout(forceKillTimeout))
    backendProcess = null
  }
})
