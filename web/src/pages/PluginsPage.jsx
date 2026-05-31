import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Puzzle, ToggleLeft, ToggleRight, Trash2, Plus, X, ExternalLink } from 'lucide-react'
import { pluginsApi } from '../api/plugins.api'
import { mutationError } from '../store/toastStore'
import {
  Card,
  Button,
  IconButton,
  IconBox,
  Badge,
  SectionHeader,
  Loading,
} from '../components/ui/design'

export default function PluginsPage() {
  const queryClient = useQueryClient()
  const [installUrl, setInstallUrl] = useState('')
  const [showInstall, setShowInstall] = useState(false)

  const { data, isLoading } = useQuery({
    queryKey: ['plugins'],
    queryFn: () => pluginsApi.list(),
  })

  const toggleMutation = useMutation({
    mutationFn: ({ name, status }) =>
      status === 'enabled' ? pluginsApi.disable(name) : pluginsApi.enable(name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['plugins'] }),
    onError: mutationError('Toggle plugin failed'),
  })

  const uninstallMutation = useMutation({
    mutationFn: (name) => pluginsApi.uninstall(name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['plugins'] }),
    onError: mutationError('Uninstall failed'),
  })

  const installMutation = useMutation({
    mutationFn: (url) => pluginsApi.install(url),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['plugins'] })
      setInstallUrl('')
      setShowInstall(false)
    },
    onError: mutationError('Install failed'),
  })

  const plugins = data?.plugins ?? []

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-4xl mx-auto px-6 py-8">
        <div className="flex items-start justify-between mb-8">
          <SectionHeader title="Plugins" description="Manage installed plugins. Plugins add tools and capabilities." icon={Puzzle} />
          <Button size="md" icon={showInstall ? X : Plus} onClick={() => setShowInstall(!showInstall)} className="mt-2">
            {showInstall ? 'Cancel' : 'Install Plugin'}
          </Button>
        </div>

        {showInstall && (
          <Card variant="default" className="mb-6 p-4">
            <div className="flex items-center gap-3">
              <input
                type="text"
                value={installUrl}
                onChange={(e) => setInstallUrl(e.target.value)}
                placeholder="GitHub release tarball URL or npm package..."
                className="flex-1 px-3.5 py-2 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm focus:outline-none focus:border-accent/50 transition-colors"
              />
              <Button
                onClick={() => installMutation.mutate(installUrl)}
                disabled={!installUrl || installMutation.isPending}
                size="md"
              >
                {installMutation.isPending ? 'Installing...' : 'Install'}
              </Button>
              <IconButton icon={X} onClick={() => setShowInstall(false)} />
            </div>
            <p className="mt-2 text-xs text-text-muted">
              Enter a URL to a plugin tarball (.tar.gz) containing a plugin.json manifest.
            </p>
          </Card>
        )}

        {isLoading ? (
          <Loading text="Loading plugins..." />
        ) : plugins.length === 0 ? (
          <div className="flex flex-col items-center py-16">
            <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
              <Puzzle className="w-8 h-8 text-gray-500 dark:text-gray-400" />
            </div>
            <p className="text-text-muted text-sm">No plugins installed</p>
            <p className="text-xs text-text-muted mt-1">Install plugins from GitHub releases or use built-in plugins.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {plugins.map((plugin) => (
              <Card key={plugin.name} variant="default" className={plugin.status !== 'enabled' ? 'opacity-60' : ''}>
                <div className="p-5">
                  <div className="flex items-start gap-4">
                    <IconBox
                      icon={Puzzle}
                      variant={plugin.status === 'enabled' ? 'info' : 'gray'}
                      size="md"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-semibold text-sm text-text-primary">{plugin.name}</span>
                        <Badge size="sm" variant="default">{`v${plugin.version}`}</Badge>
                        <Badge size="sm" variant={plugin.status === 'enabled' ? 'success' : 'default'}>
                          {plugin.status}
                        </Badge>
                      </div>
                      {plugin.description && (
                        <p className="text-sm text-text-secondary">{plugin.description}</p>
                      )}
                      {plugin.tools && plugin.tools.length > 0 && (
                        <div className="flex flex-wrap gap-1.5 mt-2">
                          {plugin.tools.map((tool) => (
                            <Badge key={tool.name} size="sm" variant="primary">
                              {tool.name}
                            </Badge>
                          ))}
                        </div>
                      )}
                      {plugin.author && (
                        <p className="text-xs text-text-muted mt-1">by {plugin.author}</p>
                      )}
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      {plugin.repository && (
                        <a
                          href={plugin.repository}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="p-1.5 rounded-lg text-text-muted hover:text-text-primary transition-colors"
                          title="Repository"
                        >
                          <ExternalLink className="w-4 h-4" />
                        </a>
                      )}
                      <IconButton
                        icon={plugin.status === 'enabled' ? ToggleRight : ToggleLeft}
                        variant="ghost"
                        size="sm"
                        onClick={() => toggleMutation.mutate({ name: plugin.name, status: plugin.status })}
                        className={plugin.status === 'enabled' ? 'text-accent' : ''}
                        title={plugin.status === 'enabled' ? 'Disable' : 'Enable'}
                      />
                      <IconButton
                        icon={Trash2}
                        variant="danger"
                        size="sm"
                        onClick={() => {
                          if (confirm(`Uninstall plugin "${plugin.name}"?`)) {
                            uninstallMutation.mutate(plugin.name)
                          }
                        }}
                        title="Uninstall"
                      />
                    </div>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
