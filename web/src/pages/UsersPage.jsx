import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  User, Plus, Edit, Trash2, Bot, Users,
} from 'lucide-react'
import { usersApi } from '../api/users.api'
import {
  Card,
  Button,
  IconButton,
  IconBox,
  Badge,
  DotBadge,
  SectionHeader,
  Loading,
} from '../components/ui/design'

export default function UsersPage() {
  const queryClient = useQueryClient()
  const [selectedUser, setSelectedUser] = useState(null)
  const [isEditing, setIsEditing] = useState(false)
  const [isCreating, setIsCreating] = useState(false)

  const { data, isLoading } = useQuery({
    queryKey: ['users'],
    queryFn: async () => {
      const response = await usersApi.list()
      return response.users
    },
  })

  const deleteMutation = useMutation({
    mutationFn: (id) => usersApi.delete(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })

  const users = data || []

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-4xl mx-auto px-6 py-8">
        {/* Header */}
        <div className="flex items-start justify-between mb-8">
          <SectionHeader title="Users" description="Manage your profile, proxy, and contacts" icon={Users} />
          <Button size="md" icon={Plus} onClick={() => setIsCreating(true)} className="mt-2">
            Add Contact
          </Button>
        </div>

        {isLoading ? (
          <Loading text="Loading users..." />
        ) : (
          <div className="space-y-3">
            {users.map((user) => (
              <UserCard
                key={user.id}
                user={user}
                onEdit={() => {
                  setSelectedUser(user)
                  setIsEditing(true)
                }}
                onDelete={() => {
                  if (confirm(`Delete ${user.name}?`)) {
                    deleteMutation.mutate(user.id)
                  }
                }}
              />
            ))}
          </div>
        )}

        {/* Create Modal */}
        {isCreating && (
          <UserEditModal
            user={null}
            onClose={() => setIsCreating(false)}
            onSave={() => {
              setIsCreating(false)
              queryClient.invalidateQueries({ queryKey: ['users'] })
            }}
          />
        )}

        {/* Edit Modal */}
        {isEditing && selectedUser && (
          <UserEditModal
            user={selectedUser}
            onClose={() => {
              setIsEditing(false)
              setSelectedUser(null)
            }}
            onSave={() => {
              setIsEditing(false)
              setSelectedUser(null)
              queryClient.invalidateQueries({ queryKey: ['users'] })
            }}
          />
        )}
      </div>
    </div>
  )
}

function UserCard({ user, onEdit, onDelete }) {
  const isProxy = user.role === 'proxy'
  const isDefault = user.id === 'user-default' || user.id === 'proxy-default'

  return (
    <Card variant="elevated" className="overflow-hidden">
      <div className="p-5">
        <div className="flex items-center gap-4">
          <IconBox
            icon={isProxy ? Bot : User}
            variant={isProxy ? 'info' : 'accent'}
            size="md"
          />

          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="text-base font-semibold text-text-primary truncate">
                {user.name}
              </h3>
              {user.active ? (
                <DotBadge color="emerald" />
              ) : (
                <DotBadge color="gray" />
              )}
              {isDefault && (
                <Badge size="sm" variant="primary">Default</Badge>
              )}
            </div>
            <p className="text-xs text-text-muted mt-0.5">
              {isProxy ? 'AI Proxy' : user.bio || 'No bio'}
            </p>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <IconButton icon={Edit} variant="ghost" size="sm" onClick={onEdit} title="Edit" />
            {!isDefault && (
              <IconButton icon={Trash2} variant="danger" size="sm" onClick={onDelete} title="Delete" />
            )}
          </div>
        </div>
      </div>
    </Card>
  )
}

function UserEditModal({ user, onClose, onSave }) {
  const queryClient = useQueryClient()
  const isEdit = user !== null

  const [form, setForm] = useState({
    name: user?.name || '',
    bio: user?.bio || '',
    profile: user?.profile || '',
    active: user?.active ?? false,
    preferences: user?.preferences || {},
  })

  const [showProxyConfig, setShowProxyConfig] = useState(false)

  const mutation = useMutation({
    mutationFn: (body) => {
      if (isEdit) {
        return usersApi.update(user.id, body)
      } else {
        return usersApi.create({
          ...body,
          role: 'contact',
          active: false,
        })
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      onSave()
    },
  })

  const handleSubmit = (e) => {
    e.preventDefault()
    mutation.mutate(form)
  }

  const set = (field) => (e) => setForm(p => ({ ...p, [field]: e.target.value }))

  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto border border-gray-200 dark:border-gray-800" onClick={e => e.stopPropagation()}>
        <div className="p-5 border-b border-gray-100 dark:border-gray-800">
          <div className="flex items-center gap-3">
            <IconBox icon={isEdit ? User : Plus} variant="accent" size="sm" />
            <h2 className="text-lg font-semibold text-text-primary">
              {isEdit ? 'Edit User' : 'Add Contact'}
            </h2>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <Field label="Name">
            <input
              type="text"
              value={form.name}
              onChange={set('name')}
              className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm focus:outline-none focus:border-accent/50 transition-colors"
              placeholder="Name"
              required
            />
          </Field>

          <Field label="Bio">
            <textarea
              value={form.bio}
              onChange={set('bio')}
              className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm focus:outline-none focus:border-accent/50 transition-colors min-h-[60px] resize-y"
              placeholder="Brief description"
              rows={2}
            />
          </Field>

          <Field label="Profile (Markdown)">
            <textarea
              value={form.profile}
              onChange={set('profile')}
              className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm font-mono focus:outline-none focus:border-accent/50 transition-colors min-h-[140px] resize-y leading-relaxed"
              placeholder="## About Me\n\n- Role: ...\n- Skills: ...\n"
              rows={8}
            />
          </Field>

          {user?.role === 'proxy' && (
            <>
              <div className="pt-2 pb-2">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowProxyConfig(!showProxyConfig)}
                >
                  {showProxyConfig ? 'Hide' : 'Show'} Proxy Configuration
                </Button>
              </div>

              {showProxyConfig && (
                <div className="space-y-4 p-4 bg-gray-50 dark:bg-gray-800/50 rounded-xl border border-gray-200 dark:border-gray-700">
                  <Field label="Autonomy Level">
                    <select
                      value={form.preferences?.autonomy_level || 'medium'}
                      onChange={e => setForm(p => ({
                        ...p,
                        preferences: { ...p.preferences, autonomy_level: e.target.value }
                      }))}
                      className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm focus:outline-none focus:border-accent/50 transition-colors"
                    >
                      <option value="low">Low - Ask for everything</option>
                      <option value="medium">Medium - Decide on routine tasks</option>
                      <option value="high">High - Decide autonomously</option>
                    </select>
                  </Field>

                  <Field label="Proxy Prompt">
                    <textarea
                      value={form.preferences?.proxy_prompt || ''}
                      onChange={e => setForm(p => ({
                        ...p,
                        preferences: { ...p.preferences, proxy_prompt: e.target.value }
                      }))}
                      className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm font-mono focus:outline-none focus:border-accent/50 transition-colors min-h-[100px] resize-y"
                      placeholder="Custom instructions for the proxy..."
                      rows={5}
                    />
                  </Field>
                </div>
              )}
            </>
          )}

          <div className="flex justify-end gap-3 pt-4">
            <Button type="button" variant="secondary" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending ? 'Saving...' : isEdit ? 'Save' : 'Create'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div>
      <label className="block text-sm font-medium text-text-primary mb-1.5">{label}</label>
      {children}
    </div>
  )
}
