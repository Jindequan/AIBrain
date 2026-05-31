import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Trash2, FileText, Image, Link as LinkIcon, FileCode, Mail, Calendar, Archive } from 'lucide-react'
import { artifactsApi } from '../api/artifacts.api'
import { cn } from '../lib/utils'
import {
  IconButton,
  Badge,
  SectionHeader,
  Button,
} from '../components/ui/design'

const KIND_ICONS = {
  file: FileText,
  url: LinkIcon,
  note: FileText,
  document: FileCode,
  image: Image,
  code_diff: FileCode,
  email_draft: Mail,
  calendar_event: Calendar,
  other: Archive,
}

const KIND_COLORS = {
  file: 'bg-blue-500/10 text-blue-600',
  url: 'bg-accent/10 text-accent',
  note: 'bg-amber-500/10 text-amber-600',
  document: 'bg-purple-500/10 text-purple-600',
  image: 'bg-green-500/10 text-green-600',
  code_diff: 'bg-gray-500/10 text-gray-600',
  email_draft: 'bg-pink-500/10 text-pink-600',
  calendar_event: 'bg-red-500/10 text-red-600',
  other: 'bg-gray-500/10 text-text-muted',
}

const ALL_KINDS = ['', 'file', 'url', 'note', 'document', 'image', 'code_diff', 'email_draft', 'calendar_event', 'other']

export default function ArtifactsPage() {
  const queryClient = useQueryClient()
  const [filterKind, setFilterKind] = useState('')
  const [selectedArtifact, setSelectedArtifact] = useState(null)

  const { data } = useQuery({
    queryKey: ['artifacts', filterKind],
    queryFn: () => artifactsApi.list(filterKind ? { kind: filterKind } : undefined),
  })

  const deleteMutation = useMutation({
    mutationFn: (id) => artifactsApi.delete(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['artifacts'] }),
  })

  const artifacts = data?.artifacts || []

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-4xl mx-auto px-6 py-8">
        <SectionHeader
          title="Artifacts"
          description={`${artifacts.length} artifact${artifacts.length !== 1 ? 's' : ''} total`}
          icon={Archive}
        />

        {/* Kind filter */}
        <div className="flex flex-wrap gap-2 mb-6 mt-6">
          {ALL_KINDS.map(k => (
            <button key={k} onClick={() => setFilterKind(k)}
              className={cn(
                'px-3 py-1.5 rounded-xl text-xs font-medium whitespace-nowrap transition-all border',
                filterKind === k
                  ? 'bg-accent text-white border-accent shadow-sm'
                  : 'bg-white dark:bg-gray-800 border-gray-200 dark:border-gray-700 text-text-muted hover:text-text-primary hover:border-accent/30'
              )}>
              {k || 'All'}
            </button>
          ))}
        </div>

        {/* Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {artifacts.map(art => {
            const Icon = KIND_ICONS[art.kind] || Archive
            return (
              <div key={art.id}
                className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50 shadow-sm hover:shadow-md transition-shadow cursor-pointer relative group"
                onClick={() => setSelectedArtifact(selectedArtifact?.id === art.id ? null : art)}
              >
                <div className="p-4">
                  <div className="flex items-start gap-3">
                    <div className={cn('p-2 rounded-lg shrink-0', KIND_COLORS[art.kind] || 'bg-gray-500/10 text-text-muted')}>
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <h3 className="font-medium text-sm text-text-primary truncate">{art.title}</h3>
                      <div className="flex items-center gap-2 mt-1">
                        <Badge size="sm" variant="default">{art.kind}</Badge>
                        {art.mime_type && <span className="text-[10px] text-text-muted">{art.mime_type}</span>}
                      </div>
                      {art.uri && <p className="text-[10px] text-text-muted mt-1 truncate">{art.uri}</p>}
                      <p className="text-[10px] text-text-muted mt-0.5">{art.inserted_at?.slice(0, 10)}</p>
                    </div>
                  </div>
                  {art.content && (
                    <p className="text-xs text-text-secondary mt-2 line-clamp-3 bg-gray-50 dark:bg-gray-800/30 rounded-lg p-2">{art.content}</p>
                  )}
                </div>
                <IconButton
                  icon={Trash2}
                  variant="danger"
                  size="sm"
                  onClick={(e) => { e.stopPropagation(); if (confirm('Delete artifact?')) deleteMutation.mutate(art.id) }}
                  className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity"
                />
              </div>
            )
          })}
          {artifacts.length === 0 && (
            <div className="col-span-full flex flex-col items-center py-16">
              <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
                <Archive className="w-8 h-8 text-gray-500 dark:text-gray-400" />
              </div>
              <p className="text-text-muted text-sm">No artifacts found.</p>
            </div>
          )}
        </div>

        {/* Detail modal */}
        {selectedArtifact && (
          <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center" onClick={() => setSelectedArtifact(null)}>
            <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-2xl max-w-lg w-full mx-4 max-h-[80vh] overflow-y-auto border border-gray-200 dark:border-gray-800" onClick={e => e.stopPropagation()}>
              <div className="p-5">
                <h2 className="text-base font-semibold text-text-primary mb-3">{selectedArtifact.title}</h2>
                <div className="space-y-2 text-xs">
                  <div className="flex gap-2">
                    <span className="text-text-muted shrink-0 w-16">Kind:</span>
                    <span className="text-text-primary">{selectedArtifact.kind}</span>
                  </div>
                  {selectedArtifact.uri && (
                    <div className="flex gap-2">
                      <span className="text-text-muted shrink-0 w-16">URI:</span>
                      <a href={selectedArtifact.uri} target="_blank" rel="noreferrer"
                        className="text-accent hover:underline break-all">{selectedArtifact.uri}</a>
                    </div>
                  )}
                  {selectedArtifact.mime_type && (
                    <div className="flex gap-2">
                      <span className="text-text-muted shrink-0 w-16">Type:</span>
                      <span className="text-text-primary">{selectedArtifact.mime_type}</span>
                    </div>
                  )}
                  {selectedArtifact.content && (
                    <div>
                      <span className="text-text-muted block mb-1">Content:</span>
                      <pre className="bg-gray-50 dark:bg-gray-800/50 rounded-xl p-3 text-text-secondary overflow-x-auto whitespace-pre-wrap max-h-48 text-xs leading-relaxed">{selectedArtifact.content}</pre>
                    </div>
                  )}
                  {selectedArtifact.metadata && Object.keys(selectedArtifact.metadata).length > 0 && (
                    <div>
                      <span className="text-text-muted block mb-1">Metadata:</span>
                      <pre className="bg-gray-50 dark:bg-gray-800/50 rounded-xl p-3 text-text-secondary overflow-x-auto text-xs">{JSON.stringify(selectedArtifact.metadata, null, 2)}</pre>
                    </div>
                  )}
                </div>
                <Button onClick={() => setSelectedArtifact(null)} className="mt-4 w-full" size="md">
                  Close
                </Button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
