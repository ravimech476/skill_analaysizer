import { api } from './client';
import type { Envelope } from './types';

export const KB_DOC_TYPES = [
  { value: 'syllabus', label: 'Syllabus' },
  { value: 'notes', label: 'Notes' },
  { value: 'question_paper', label: 'Question paper' },
  { value: 'placement', label: 'Placement' },
  { value: 'resume', label: 'Resume tips' },
  { value: 'roadmap', label: 'Career roadmap' },
  { value: 'other', label: 'Other' },
];

export interface KbDocument {
  id: number;
  title: string;
  doc_type: string;
  department_id: number | null;
  department_name: string | null;
  subject_id: number | null;
  subject_name: string | null;
  source_name: string;
  chunk_count: number;
  created_at: string;
}

export interface KbHit {
  document_id: number;
  title: string;
  doc_type: string;
  content: string;
  score: number;
}

export interface KbUpload {
  file: File;
  title?: string;
  doc_type: string;
  department_id?: number;
  subject_id?: number;
}

// Indexing embeds every passage with a local model, so a long document can take a while.
const UPLOAD_TIMEOUT_MS = 600_000;

export const kbApi = {
  list: async () => (await api.get<Envelope<KbDocument[]>>('/kb/documents')).data.data,
  upload: async (u: KbUpload) => {
    const f = new FormData();
    f.append('file', u.file);
    f.append('doc_type', u.doc_type);
    if (u.title) f.append('title', u.title);
    if (u.department_id) f.append('department_id', String(u.department_id));
    if (u.subject_id) f.append('subject_id', String(u.subject_id));
    return (await api.post<Envelope<{ id: number; title: string; chunk_count: number }>>('/kb/documents', f, { timeout: UPLOAD_TIMEOUT_MS })).data.data;
  },
  remove: async (id: number) => (await api.delete<Envelope<{ message: string }>>(`/kb/documents/${id}`)).data.data,
  /** Reads a study material's attached file and adds it to the AI assistant's knowledge base. */
  indexDocument: async (path: 'study-materials' | 'interview-documents' | 'question-papers', id: number) =>
    (await api.post<Envelope<{ document_id: number; chunk_count: number }>>(`/${path}/${id}/index-for-ai`, undefined, { timeout: 600_000 })).data.data,
  indexMaterial: async (materialId: number) =>
    (await api.post<Envelope<{ document_id: number; chunk_count: number }>>(`/study-materials/${materialId}/index-for-ai`, undefined, { timeout: 600_000 })).data.data,
  search: async (query: string) => (await api.post<Envelope<KbHit[]>>('/kb/search', { query }, { timeout: 60_000 })).data.data,
};
