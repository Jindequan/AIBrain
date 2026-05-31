import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { BookOpen, ToggleLeft, ToggleRight, Trash2, Plus, X, Pencil } from 'lucide-react'
import { skillsApi } from '../api/skills-runs.api'
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

function emptyForm() {
  return { name: '', description: '', prompt_body: '', status: 'active' }
}

export default function SkillsPage() {
  const queryClient = useQueryClient()
  const [showForm, setShowForm] = useState(false)
  const [editingName, setEditingName] = useState(null)
  const [form, setForm] = useState(emptyForm())

  const { data, isLoading } = useQuery({
    queryKey: ['skills'],
    queryFn: () => skillsApi.list(),
  })

  const toggleMutation = useMutation({
    mutationFn: (name) => skillsApi.toggle(name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['skills'] }),
    onError: mutationError('Toggle skill failed'),
  })

  const deleteMutation = useMutation({
    mutationFn: (name) => skillsApi.delete(name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['skills'] }),
    onError: mutationError('Delete skill failed'),
  })

  const createMutation = useMutation({
    mutationFn: (body) => skillsApi.create(body),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['skills'] }); closeForm() },
    onError: mutationError('Create skill failed'),
  })

  const updateMutation = useMutation({
    mutationFn: ({ name, body }) => skillsApi.update(name, body),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['skills'] }); closeForm() },
    onError: mutationError('Update skill failed'),
  })

  function closeForm() { setShowForm(false); setEditingName(null); setForm(emptyForm()) }

  function startEdit(s) {
    setEditingName(s.name)
    setForm({ name: s.name, description: s.description || '', prompt_body: s.prompt_body || '', status: s.status || 'active' })
    setShowForm(true)
  }

  function handleSubmit(e) {
    e.preventDefault()
    const trimmed = form.name.trim()
    if (!trimmed) return
    const body = { name: trimmed, description: form.description, prompt_body: form.prompt_body, status: form.status }
    if (editingName) updateMutation.mutate({ name: editingName, body: { description: form.description, prompt_body: form.prompt_body, status: form.status } })
    else createMutation.mutate(body)
  }

  const skills = data?.skills || []
  const isPending = createMutation.isPending || updateMutation.isPending

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-4xl mx-auto px-6 py-8">
        <div className="flex items-start justify-between mb-8">
          <SectionHeader title="Skills" description="Custom AI skill definitions" icon={BookOpen} />
          <Button size="md" icon={showForm ? X : Plus} onClick={() => showForm ? closeForm() : startEdit(emptyForm())} className="mt-2">
            {showForm ? 'Cancel' : 'New Skill'}
          </Button>
        </div>

        {/* Form modal */}
        {showForm && (
          <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50" onClick={closeForm}>
            <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-2xl max-w-xl w-full max-h-[90vh] overflow-hidden border border-gray-200 dark:border-gray-800" onClick={e => e.stopPropagation()}>
              <div className="p-5 border-b border-gray-100 dark:border-gray-800 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <IconBox icon={BookOpen} variant="info" size="sm" />
                  <h2 className="text-sm font-semibold text-text-primary">
                    {editingName ? `Edit: ${editingName}` : 'New Skill'}
                  </h2>
                </div>
                <IconButton icon={X} onClick={closeForm} />
              </div>

              <form onSubmit={handleSubmit} className="p-5 space-y-4">
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Name *</label>
                  <input value={form.name} onChange={(e) => setForm(f => ({ ...f, name: e.target.value }))}
                    disabled={!!editingName}
                    placeholder="my-skill"
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors disabled:opacity-50 disabled:cursor-not-allowed" />
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Description</label>
                  <textarea value={form.description} onChange={(e) => setForm(f => ({ ...f, description: e.target.value }))}
                    rows={2}
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors resize-none" />
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Status</label>
                  <select value={form.status} onChange={(e) => setForm(f => ({ ...f, status: e.target.value }))}
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors">
                    <option value="active">Active</option>
                    <option value="paused">Paused</option>
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Prompt Body</label>
                  <textarea value={form.prompt_body} onChange={(e) => setForm(f => ({ ...f, prompt_body: e.target.value }))}
                    rows={6}
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm font-mono focus:outline-none focus:border-accent/50 transition-colors resize-y" />
                </div>
                <Button type="submit" disabled={isPending || !form.name.trim()} className="w-full">
                  {isPending ? 'Saving...' : editingName ? 'Update' : 'Create'}
                </Button>
              </form>
            </div>
          </div>
        )}

        {/* Skills list */}
        {isLoading ? (
          <Loading text="Loading skills..." />
        ) : (
          <div className="space-y-3">
            {skills.map((s) => (
              <Card key={s.name} variant="elevated" className="overflow-hidden">
                <div className="p-5">
                  <div className="flex items-start gap-4">
                    <IconBox
                      icon={BookOpen}
                      variant={s.status === 'active' ? 'info' : 'gray'}
                      size="md"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-semibold text-sm text-text-primary">{s.name}</span>
                        <Badge size="sm" variant={s.status === 'active' ? 'success' : 'default'}>
                          {s.status}
                        </Badge>
                      </div>
                      {s.description && (
                        <p className="text-xs text-text-secondary line-clamp-2">{s.description}</p>
                      )}
                    </div>
                    <div className="flex gap-1.5 shrink-0">
                      <IconButton icon={Pencil} variant="ghost" size="sm" onClick={() => startEdit(s)} title="Edit" />
                      <IconButton
                        icon={s.status === 'active' ? ToggleRight : ToggleLeft}
                        variant="ghost"
                        size="sm"
                        onClick={() => toggleMutation.mutate(s.name)}
                        title={s.status === 'active' ? 'Pause' : 'Activate'}
                      />
                      <IconButton
                        icon={Trash2}
                        variant="danger"
                        size="sm"
                        onClick={() => { if (confirm(`Delete skill "${s.name}"?`)) deleteMutation.mutate(s.name) }}
                        title="Delete"
                      />
                    </div>
                  </div>
                </div>
              </Card>
            ))}

            {skills.length === 0 && (
              <div className="flex flex-col items-center py-16">
                <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
                  <BookOpen className="w-8 h-8 text-gray-500 dark:text-gray-400" />
                </div>
                <p className="text-text-muted text-sm">No skills defined yet</p>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
