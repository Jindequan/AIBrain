import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Plus, Trash2, X, Pencil, ToggleLeft, ToggleRight, Zap } from 'lucide-react'
import { automationRulesApi } from '../api/automation-rules.api'
import { mutationError } from '../store/toastStore'
import {
  Card,
  Button,
  IconButton,
  IconBox,
  Badge,
  SectionHeader,
} from '../components/ui/design'

const TRIGGER_TYPES = ['cron', 'time', 'event', 'condition', 'manual']
const RISK_LEVELS = ['low', 'medium', 'high', 'critical']
const CONFIRM_POLICIES = ['never', 'ask_for_write', 'always', 'disabled']
const STATUSES = ['active', 'paused', 'completed', 'cancelled']

function emptyForm() {
  return {
    name: '',
    description: '',
    trigger_type: 'cron',
    trigger_config: '{}',
    action: '{\n  "type": "run_query",\n  "prompt": ""\n}',
    risk_level: 'medium',
    confirmation_policy: 'never',
    status: 'active',
  }
}

export default function AutomationRulesPage() {
  const queryClient = useQueryClient()
  const [showForm, setShowForm] = useState(false)
  const [editingId, setEditingId] = useState(null)
  const [form, setForm] = useState(emptyForm())

  const { data } = useQuery({
    queryKey: ['automation-rules'],
    queryFn: () => automationRulesApi.list(),
  })

  const createMutation = useMutation({
    mutationFn: (body) => automationRulesApi.create(body),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['automation-rules'] }); closeForm() },
    onError: mutationError('Create rule failed'),
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, body }) => automationRulesApi.update(id, body),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['automation-rules'] }); closeForm() },
    onError: mutationError('Update rule failed'),
  })

  const deleteMutation = useMutation({
    mutationFn: (id) => automationRulesApi.delete(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['automation-rules'] }),
    onError: mutationError('Delete rule failed'),
  })

  const toggleMutation = useMutation({
    mutationFn: ({ id, status }) => automationRulesApi.update(id, { status }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['automation-rules'] }),
    onError: mutationError('Toggle rule failed'),
  })

  function closeForm() {
    setShowForm(false)
    setEditingId(null)
    setForm(emptyForm())
  }

  function startEdit(rule) {
    setEditingId(rule.id)
    const action = {
      type: rule.action_type || rule.action?.type || 'run_query',
      ...(rule.action_config || rule.action || {}),
    }

    setForm({
      name: rule.name,
      description: rule.description || '',
      trigger_type: rule.trigger_type || 'cron',
      trigger_config: JSON.stringify(rule.trigger_config || {}, null, 2),
      action: JSON.stringify(action, null, 2),
      risk_level: rule.risk_level || 'medium',
      confirmation_policy: rule.confirmation_policy || 'never',
      status: rule.status || 'active',
    })
    setShowForm(true)
  }

  function handleSubmit(e) {
    e.preventDefault()
    if (!form.name.trim()) return
    let triggerConfig, action
    try { triggerConfig = JSON.parse(form.trigger_config) } catch { return }
    try { action = JSON.parse(form.action) } catch { return }

    const body = { ...form, trigger_config: triggerConfig, action }
    if (editingId) {
      updateMutation.mutate({ id: editingId, body })
    } else {
      createMutation.mutate(body)
    }
  }

  const rules = data?.automation_rules || []
  const isPending = createMutation.isPending || updateMutation.isPending

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-4xl mx-auto px-6 py-8">
        <div className="flex items-start justify-between mb-8">
          <SectionHeader title="Automation Rules" description="Define automated triggers and actions" icon={Zap} />
          <Button size="md" icon={showForm ? X : Plus} onClick={() => showForm ? closeForm() : startEdit(emptyForm())} className="mt-2">
            {showForm ? 'Cancel' : 'Add Rule'}
          </Button>
        </div>

        {showForm && (
          <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50" onClick={closeForm}>
            <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-2xl max-w-xl w-full max-h-[90vh] overflow-hidden border border-gray-200 dark:border-gray-800" onClick={e => e.stopPropagation()}>
              <div className="p-5 border-b border-gray-100 dark:border-gray-800 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <IconBox icon={Zap} variant="info" size="sm" />
                  <h2 className="text-sm font-semibold text-text-primary">
                    {editingId ? `Edit: ${form.name}` : 'New Automation Rule'}
                  </h2>
                </div>
                <IconButton icon={X} onClick={closeForm} />
              </div>

              <form onSubmit={handleSubmit} className="p-5 space-y-4">
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Name *</label>
                  <input value={form.name} onChange={(e) => setForm(f => ({ ...f, name: e.target.value }))}
                    placeholder="Daily backup rule"
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors" />
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Description</label>
                  <textarea value={form.description} onChange={(e) => setForm(f => ({ ...f, description: e.target.value }))}
                    rows={2}
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors resize-none" />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-text-secondary mb-1.5">Trigger Type</label>
                    <select value={form.trigger_type} onChange={(e) => setForm(f => ({ ...f, trigger_type: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors">
                      {TRIGGER_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-text-secondary mb-1.5">Risk Level</label>
                    <select value={form.risk_level} onChange={(e) => setForm(f => ({ ...f, risk_level: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors">
                      {RISK_LEVELS.map(r => <option key={r} value={r}>{r}</option>)}
                    </select>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-text-secondary mb-1.5">Confirmation Policy</label>
                    <select value={form.confirmation_policy} onChange={(e) => setForm(f => ({ ...f, confirmation_policy: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors">
                      {CONFIRM_POLICIES.map(p => <option key={p} value={p}>{p}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-text-secondary mb-1.5">Status</label>
                    <select value={form.status} onChange={(e) => setForm(f => ({ ...f, status: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors">
                      {STATUSES.map(s => <option key={s} value={s}>{s}</option>)}
                    </select>
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Trigger Config (JSON)</label>
                  <textarea value={form.trigger_config} onChange={(e) => setForm(f => ({ ...f, trigger_config: e.target.value }))}
                    rows={3}
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-xs font-mono focus:outline-none focus:border-accent/50 transition-colors" />
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Action (JSON)</label>
                  <textarea value={form.action} onChange={(e) => setForm(f => ({ ...f, action: e.target.value }))}
                    rows={3}
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-xs font-mono focus:outline-none focus:border-accent/50 transition-colors" />
                </div>
                <Button type="submit" disabled={isPending || !form.name.trim()} className="w-full">
                  {isPending ? 'Saving...' : editingId ? 'Update' : 'Create'}
                </Button>
              </form>
            </div>
          </div>
        )}

        <div className="space-y-3">
          {rules.map(rule => (
            <Card key={rule.id} variant="elevated" className="overflow-hidden">
              <div className="p-5">
                <div className="flex items-start gap-4">
                  <IconBox
                    icon={Zap}
                    variant={rule.status === 'active' ? 'success' : 'gray'}
                    size="md"
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="font-semibold text-sm text-text-primary">{rule.name}</span>
                      <Badge size="sm" variant={
                        rule.risk_level === 'critical' ? 'danger' :
                        rule.risk_level === 'high' ? 'danger' :
                        rule.risk_level === 'medium' ? 'warning' :
                        'success'
                      }>{rule.risk_level}</Badge>
                      <Badge size="sm" variant="default">{rule.trigger_type}</Badge>
                      <Badge size="sm" variant={
                        rule.status === 'active' ? 'success' :
                        rule.status === 'paused' ? 'warning' :
                        'default'
                      }>{rule.status}</Badge>
                    </div>
                    {rule.description && <p className="text-xs text-text-secondary mt-0.5 truncate">{rule.description}</p>}
                    {rule.next_fire_at && <p className="text-[10px] text-text-muted mt-0.5">Next: {rule.next_fire_at.slice(0, 16)}</p>}
                  </div>
                  <div className="flex gap-1.5 shrink-0">
                    <IconButton
                      icon={rule.status === 'active' ? ToggleRight : ToggleLeft}
                      variant="ghost"
                      size="sm"
                      onClick={() => toggleMutation.mutate({
                        id: rule.id,
                        status: rule.status === 'active' ? 'paused' : 'active',
                      })}
                      className={rule.status === 'active' ? 'text-accent' : ''}
                      title={rule.status === 'active' ? 'Pause' : 'Activate'}
                    />
                    <IconButton
                      icon={Pencil}
                      variant="ghost"
                      size="sm"
                      onClick={() => startEdit(rule)}
                      title="Edit"
                    />
                    <IconButton
                      icon={Trash2}
                      variant="danger"
                      size="sm"
                      onClick={() => { if (confirm('Delete this rule?')) deleteMutation.mutate(rule.id) }}
                      title="Delete"
                    />
                  </div>
                </div>
              </div>
            </Card>
          ))}
          {rules.length === 0 && (
            <div className="flex flex-col items-center py-16">
              <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
                <Zap className="w-8 h-8 text-gray-500 dark:text-gray-400" />
              </div>
              <p className="text-text-muted text-sm">No automation rules defined.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
