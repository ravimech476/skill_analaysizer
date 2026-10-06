import { api } from './client';
import type { Envelope } from './types';
import type { FileLink } from './files';

export type NoticeType = 'general' | 'placement' | 'marks' | 'skill' | 'system';

export interface Notice {
  id: number;
  title: string;
  body: string;
  type: NoticeType;
  reference_type: string | null;
  reference_id: number | null;
  sender_name: string | null;
  is_read: boolean;
  read_at: string | null;
  created_at: string;
  attachment: FileLink | null;
}

export interface Inbox {
  data: Notice[];
  meta: { page: number; page_size: number; total: number };
  unread: number;
}

export interface SentNotice {
  id: number;
  title: string;
  body: string;
  type: NoticeType;
  target_type: string;
  target_label: string | null;
  sender_name: string | null;
  recipients: number;
  read_count: number;
  created_at: string;
  attachment: FileLink | null;
}

export interface SendInput {
  title: string;
  body: string;
  type?: NoticeType;
  target_type: 'all' | 'role' | 'department' | 'class' | 'user';
  target_id?: number | null;
  include_parents?: boolean;
  attachment_file_id?: number;
}

export const notificationsApi = {
  inbox: (params: { page: number; page_size: number; unread_only?: boolean; type?: string }) =>
    api.get<Inbox>('/notifications', { params }).then((r) => r.data),
  unreadCount: () => api.get<Envelope<{ unread: number }>>('/notifications/unread-count').then((r) => r.data.data.unread),
  markRead: (id: number) => api.post(`/notifications/${id}/read`),
  readAll: () => api.post('/notifications/read-all'),
  hide: (id: number) => api.delete(`/notifications/${id}`),
  send: (body: SendInput) => api.post<Envelope<{ id: number; recipients: number }>>('/notifications', body).then((r) => r.data.data),
  sent: () => api.get<Envelope<SentNotice[]>>('/notifications/sent').then((r) => r.data.data),
};

/** Where a notification should take the user when opened. */
export function noticeLink(n: Notice, staff: boolean): string | null {
  switch (n.reference_type) {
    case 'job_role_open':
    case 'job_role':
      return staff && n.reference_id ? `/skill-analyzer?role=${n.reference_id}` : '/placement';
    case 'marks':
      return '/marks';
    case 'skill':
      return '/skills';
    case 'student_document':
      return staff ? '/documents' : '/students';
    default:
      return null;
  }
}

export const TYPE_COLORS: Record<string, string> = { general: 'blue', placement: 'green', marks: 'purple', skill: 'gold', system: 'default' };
