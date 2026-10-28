import { api } from './client';
import type { Envelope } from './types';

export type Confidence = 'high' | 'medium' | 'low';

export interface BloomSuggestion {
  level: string;
  confidence: Confidence;
  reason: string;
  method: 'verb+model' | 'verb' | 'model';
}

export interface BloomReviewItem extends BloomSuggestion {
  id: number;
  question: string;
  subject: string;
  marks: number;
  current: string;
  differs: boolean;
}

/** The server classifies one question per model call, so reviews are sent in small batches. */
export const REVIEW_BATCH = 5;

export const bloomsApi = {
  suggest: async (question: string, marks?: number) =>
    (await api.post<Envelope<BloomSuggestion>>('/blooms/suggest', { question, marks: marks ?? 0 }, { timeout: 120_000 })).data.data,
  review: async (ids: number[]) => (await api.post<Envelope<BloomReviewItem[]>>('/blooms/review', { ids }, { timeout: 300_000 })).data.data,
  apply: async (items: { id: number; level: string }[]) => (await api.post<Envelope<{ updated: number }>>('/blooms/apply', { items })).data.data,
};
