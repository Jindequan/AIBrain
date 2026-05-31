import { request, requestText } from './client'
import type { FsResponse } from '../models/types'

export const fsApi = {
  list: (path?: string) =>
    request<FsResponse>(`/api/v1/fs${path ? `?path=${encodeURIComponent(path)}` : ''}`),
  read: (path: string) =>
    requestText(`/api/v1/file/read?path=${encodeURIComponent(path)}`),
}
