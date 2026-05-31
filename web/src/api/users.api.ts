import { request } from './client'
import type { User } from '../models/types'

export const usersApi = {
  list: () => request<{ users: User[] }>('/api/v1/users'),

  get: () => request<User>('/api/v1/user'),

  getById: (id: string) => request<User>(`/api/v1/users/${id}`),

  create: (body: Partial<Pick<User, 'id' | 'name' | 'bio' | 'role' | 'active' | 'profile' | 'preferences'>>) =>
    request<User>('/api/v1/users', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  update: (id: string, body: Partial<Pick<User, 'name' | 'bio' | 'profile' | 'active' | 'preferences'>>) =>
    request<User>(`/api/v1/users/${id}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  updateCurrent: (body: Partial<Pick<User, 'name' | 'bio' | 'profile' | 'active' | 'preferences'>>) =>
    request<User>('/api/v1/user', {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  delete: (id: string) =>
    request<{ message: string }>(`/api/v1/users/${id}`, {
      method: 'DELETE',
    }),
}
