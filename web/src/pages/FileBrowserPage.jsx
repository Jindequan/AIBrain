import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Folder, File, ChevronRight, Home, ArrowLeft, FolderOpen, FileText, Image, Code, ExternalLink } from 'lucide-react'
import { fsApi } from '../api/filesystem.api'
import {
  Card,
  SectionHeader,
} from '../components/ui/design'

const DEFAULT_PATH = '/Users'

function fileIcon(name) {
  const ext = name.split('.').pop()?.toLowerCase()
  if (['jpg', 'jpeg', 'png', 'gif', 'svg', 'webp', 'ico'].includes(ext || '')) return Image
  if (['js', 'ts', 'jsx', 'tsx', 'py', 'rb', 'go', 'rs', 'java', 'c', 'cpp', 'h'].includes(ext || '')) return Code
  if (['md', 'txt', 'json', 'yaml', 'yml', 'toml', 'xml', 'csv'].includes(ext || '')) return FileText
  return File
}

export default function FileBrowserPage() {
  const [currentPath, setCurrentPath] = useState(DEFAULT_PATH)

  const { data, isLoading, error } = useQuery({
    queryKey: ['fs', currentPath],
    queryFn: () => fsApi.list(currentPath),
  })

  function goToParent() {
    if (data?.parent) setCurrentPath(data.parent)
  }

  function goHome() {
    setCurrentPath('/')
  }

  const pathParts = currentPath.split('/').filter(Boolean)

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-4xl mx-auto px-6 py-8">
        <SectionHeader title="File Browser" description="Browse and preview files on the server" icon={Folder} />

        {/* Breadcrumb + controls */}
        <div className="flex items-center gap-2 mb-4 mt-6">
          <button onClick={goHome}
            className="p-1.5 rounded-lg hover:bg-white dark:hover:bg-gray-800 text-text-muted hover:text-text-primary transition-colors">
            <Home className="w-4 h-4" />
          </button>
          {window.electronAPI?.openFile && (
            <button onClick={async () => {
              const path = await window.electronAPI.openFile()
              if (path) setCurrentPath(path)
            }}
              className="p-1.5 rounded-lg hover:bg-white dark:hover:bg-gray-800 text-text-muted hover:text-text-primary transition-colors"
              title="Open from file dialog">
              <FolderOpen className="w-4 h-4" />
            </button>
          )}
          <button onClick={goToParent} disabled={!data?.parent}
            className="p-1.5 rounded-lg hover:bg-white dark:hover:bg-gray-800 text-text-muted hover:text-text-primary disabled:opacity-30 disabled:cursor-default transition-colors">
            <ArrowLeft className="w-4 h-4" />
          </button>
          <div className="flex items-center gap-1 text-xs font-mono text-text-secondary bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl px-3 py-1.5 flex-1 overflow-hidden">
            <span className="text-accent cursor-pointer hover:underline" onClick={goHome}>~</span>
            {pathParts.map((part, i) => (
              <span key={i} className="flex items-center gap-1 whitespace-nowrap min-w-0">
                <ChevronRight className="w-3 h-3 text-text-muted" />
                <span
                  className={i < pathParts.length - 1 ? 'cursor-pointer hover:text-accent hover:underline' : 'text-text-primary'}
                  onClick={() => setCurrentPath('/' + pathParts.slice(0, i + 1).join('/'))}
                >
                  {part}
                </span>
              </span>
            ))}
          </div>
          <span className="text-xs text-text-muted">
            {((data?.dirs?.length || 0) + (data?.files?.length || 0))} items
          </span>
        </div>

        {/* Content */}
        <Card variant="default" className="overflow-hidden">
          {isLoading && (
            <div className="px-5 py-12 text-center text-text-muted text-sm">Loading...</div>
          )}

          {error && (
            <div className="px-5 py-12 text-center">
              <p className="text-red-500 text-sm font-medium">Error</p>
              <p className="text-text-muted text-xs mt-1">{error.message}</p>
            </div>
          )}

          {!isLoading && !error && data && (
            <div>
              {data.parent && (
                <button onClick={goToParent}
                  className="w-full flex items-center gap-3 px-5 py-2.5 text-sm text-text-secondary hover:bg-gray-50 dark:hover:bg-gray-800/30 border-b border-gray-100 dark:border-gray-800 transition-colors">
                  <ArrowLeft className="w-4 h-4 text-text-muted" />
                  <span className="text-text-muted">..</span>
                </button>
              )}

              {data.dirs?.map(dir => (
                <button key={dir.path} onClick={() => setCurrentPath(dir.path)}
                  className="w-full flex items-center gap-3 px-5 py-2.5 text-sm text-text-primary hover:bg-gray-50 dark:hover:bg-gray-800/30 border-b border-gray-100 dark:border-gray-800 transition-colors text-left">
                  <FolderOpen className="w-4 h-4 text-amber-500 shrink-0" />
                  <span className="truncate">{dir.name}</span>
                  <ChevronRight className="w-3.5 h-3.5 text-text-muted ml-auto shrink-0" />
                </button>
              ))}

              {data.files?.map(file => {
                const Icon = fileIcon(file.name)
                return (
                  <div key={file.path}
                    className="flex items-center gap-3 px-5 py-2.5 text-sm text-text-secondary hover:bg-gray-50 dark:hover:bg-gray-800/30 border-b border-gray-100 dark:border-gray-800 last:border-b-0 transition-colors group">
                    <Icon className="w-4 h-4 text-text-muted shrink-0" />
                    <span className="truncate flex-1">{file.name}</span>
                    {file.size != null && (
                      <span className="text-xs text-text-muted shrink-0">
                        {file.size > 1024 * 1024
                          ? `${(file.size / 1024 / 1024).toFixed(1)} MB`
                          : file.size > 1024
                          ? `${(file.size / 1024).toFixed(1)} KB`
                          : `${file.size} B`}
                      </span>
                    )}
                    {window.electronAPI?.openInOS && (
                      <button onClick={(e) => { e.stopPropagation(); window.electronAPI.openInOS(file.path) }}
                        className="p-1 rounded-lg opacity-0 group-hover:opacity-100 hover:bg-gray-200 text-text-muted hover:text-text-primary transition-all shrink-0"
                        title="Open in Finder">
                        <ExternalLink className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                )
              })}

              {(!data.dirs || data.dirs.length === 0) && (!data.files || data.files.length === 0) && (
                <div className="px-5 py-12 text-center text-text-muted text-sm">Empty directory</div>
              )}
            </div>
          )}
        </Card>
      </div>
    </div>
  )
}
