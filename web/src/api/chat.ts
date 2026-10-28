import { api } from './client';
import type { Envelope } from './types';

/** A knowledge-base document an answer was based on. */
export interface ChatSource {
  document_id: number;
  title: string;
  doc_type: string;
}

export interface ChatMessage {
  id: number;
  role: 'user' | 'assistant';
  content: string;
  student_id: number | null;
  created_at: string;
  sources: ChatSource[] | null;
}

// A local model can take a while on a laptop CPU, so these calls wait much longer than the 20s default.
const ASK_TIMEOUT_MS = 240_000;

export const chatApi = {
  history: async (limit = 50) => (await api.get<Envelope<ChatMessage[]>>('/chat/history', { params: { limit } })).data.data,
  ask: async (message: string) =>
    (await api.post<Envelope<{ answer: string; student_id: number | null }>>('/chat', { message }, { timeout: ASK_TIMEOUT_MS })).data.data,
  clear: async () => (await api.delete<Envelope<{ cleared: number }>>('/chat/history')).data.data,
};
