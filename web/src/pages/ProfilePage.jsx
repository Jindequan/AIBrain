import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Save, User, Power, PowerOff, Loader2, CheckCircle, Sparkles,
} from 'lucide-react'
import { cn } from '../lib/utils'
import { usersApi } from '../api/users.api'
import {
  Card,
  CardContent,
  Button,
  IconBox,
  Badge,
  Loading,
} from '../components/ui/design'

export default function ProfilePage() {
  const queryClient = useQueryClient()
  const [saved, setSaved] = useState(false)
  const [form, setForm] = useState({ name: '', bio: '', active: false, profile: '' })

  const { isLoading } = useQuery({
    queryKey: ['user'],
    queryFn: async () => {
      const data = await usersApi.get()
      setForm({ name: data.name, bio: data.bio || '', active: data.active, profile: data.profile || '' })
      return data
    },
  })

  const mutation = useMutation({
    mutationFn: (body) => usersApi.updateCurrent(body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user'] })
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
    },
  })

  function handleSave() {
    mutation.mutate({
      name: form.name,
      bio: form.bio || null,
      active: form.active,
      profile: form.profile || null,
    })
  }

  if (isLoading) {
    return <Loading text="Loading profile..." />
  }

  const setField = (field) => (e) => setForm(p => ({ ...p, [field]: e.target.value }))

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-2xl mx-auto px-6 py-8 space-y-6">
        {/* Proxy active toggle */}
        <Card variant="glass" className={cn(
          'transition-all duration-300',
          form.active && 'border-accent/30'
        )}>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4">
                <IconBox
                  icon={form.active ? Power : PowerOff}
                  variant={form.active ? 'accent' : 'gray'}
                  size="md"
                />
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold text-text-primary">
                      {form.active ? 'Proxy Active' : 'Proxy Inactive'}
                    </span>
                    {form.active && <Badge size="sm" variant="success">Running</Badge>}
                  </div>
                  <p className="text-xs text-text-muted mt-0.5">
                    {form.active
                      ? 'Proxy is running — autonomously advancing tasks'
                      : 'Proxy is stopped — no autonomous actions'}
                  </p>
                </div>
              </div>
              <button
                onClick={() => setForm(p => ({ ...p, active: !p.active }))}
                className={cn(
                  'relative w-11 h-6 rounded-full transition-all shrink-0',
                  form.active ? 'bg-accent shadow-sm' : 'bg-gray-300 dark:bg-gray-600'
                )}
              >
                <span className={cn(
                  'absolute top-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform',
                  form.active ? 'translate-x-5.5' : 'translate-x-0.5'
                )} />
              </button>
            </div>
          </CardContent>
        </Card>

        {/* Profile section */}
        <Card variant="glass">
          <CardContent className="pt-6">
            <div className="flex items-center gap-3 mb-6 pb-4 border-b border-gray-100 dark:border-gray-800">
              <IconBox icon={User} variant="accent" size="sm" />
              <div>
                <h2 className="text-lg font-semibold text-text-primary">Profile</h2>
                <p className="text-xs text-text-muted">Edit your personal information and preferences</p>
              </div>
            </div>

            <div className="space-y-5">
              <Field label="Name">
                <input
                  type="text"
                  value={form.name}
                  onChange={setField('name')}
                  className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm focus:outline-none focus:border-accent/50 transition-colors"
                  placeholder="Your name"
                />
              </Field>

              <Field label="Bio">
                <textarea
                  value={form.bio}
                  onChange={setField('bio')}
                  className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm focus:outline-none focus:border-accent/50 transition-colors min-h-[60px] resize-y"
                  placeholder="Brief self-introduction"
                  rows={2}
                />
              </Field>

              <Field label="Profile (Markdown)">
                <textarea
                  value={form.profile}
                  onChange={setField('profile')}
                  className="w-full px-3.5 py-2.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl text-sm font-mono focus:outline-none focus:border-accent/50 transition-colors min-h-[200px] resize-y leading-relaxed"
                  rows={10}
                  placeholder={`## About Me\n\n- Role: ...\n- Skills: ...\n- Values: ...`}
                />
                <p className="text-xs text-text-muted mt-1.5 flex items-center gap-1.5">
                  <Sparkles className="w-3 h-3" />
                  Write in Markdown. This helps the proxy understand who you are.
                </p>
              </Field>

              <div className="flex justify-end pt-2">
                <Button
                  size="md"
                  icon={mutation.isPending ? Loader2 : saved ? CheckCircle : Save}
                  onClick={handleSave}
                  disabled={mutation.isPending}
                  className={saved ? '!bg-gradient-to-r !from-emerald-500 !to-teal-600 !shadow-emerald-500/20' : ''}
                >
                  {mutation.isPending ? 'Saving...' : saved ? 'Saved' : 'Save'}
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>
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
