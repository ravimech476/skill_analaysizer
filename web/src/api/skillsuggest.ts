import { api } from './client';
import type { Envelope } from './types';

export interface MappingSuggestion {
  skill_id: number;
  skill: string;
  weight: number;
  reason: string;
}

export interface MappingResult {
  subject_id: number;
  /** true when uploaded syllabus text for the subject was shown to the model; false when it only had the name. */
  used_syllabus: boolean;
  skills: MappingSuggestion[];
}

export interface SuggestionEvidence {
  subject_id: number;
  subject: string;
  percent: number;
  weight: number;
}

export interface SkillSuggestion {
  id: number;
  student_id: number;
  skill_id: number;
  skill: string;
  suggested_level: number;
  current_level: number | null;
  percent: number;
  evidence: SuggestionEvidence[];
  status: 'pending' | 'accepted' | 'dismissed';
  created_at: string;
}

export interface GenerateResult {
  suggestions: SkillSuggestion[];
  summary: string;
  unmapped_subjects: string[];
}

export const skillSuggestApi = {
  suggestMapping: async (subjectId: number) =>
    (await api.post<Envelope<MappingResult>>(`/subjects/${subjectId}/skill-mapping/suggest`, undefined, { timeout: 120_000 })).data.data,

  pending: async (studentId: number) => (await api.get<Envelope<SkillSuggestion[]>>(`/students/${studentId}/skill-suggestions`)).data.data,
  generate: async (studentId: number) => (await api.post<Envelope<GenerateResult>>(`/students/${studentId}/skill-suggestions/generate`)).data.data,
  accept: async (id: number) => (await api.post<Envelope<{ message: string }>>(`/skill-suggestions/${id}/accept`)).data.data,
  dismiss: async (id: number) => (await api.post<Envelope<{ message: string }>>(`/skill-suggestions/${id}/dismiss`)).data.data,
};
