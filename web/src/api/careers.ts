import { api } from './client';
import type { Envelope, ListEnvelope } from './types';

const data = <T,>(p: Promise<{ data: Envelope<T> }>) => p.then((r) => r.data.data);

/** The evidence a blended skill score is built from. */
export type ScoreSource = 'declared' | 'test' | 'cert' | 'academic';

export const SOURCE_LABELS: Record<ScoreSource, string> = {
  declared: 'Recorded by staff',
  test: 'Assessment',
  cert: 'Verified certificate',
  academic: 'Subject marks',
};

export interface SourceScore {
  source: ScoreSource;
  score: number;
  weight: number;
  detail: {
    proficiency?: number;
    entered_as?: string;
    verified_at?: string | null;
    subjects?: { subject_id: number; percent: number; weight: number }[];
  };
}

export interface SkillScore {
  skill_id: number;
  name: string;
  category: string;
  score: number;
  level: number;
  sources: Partial<Record<ScoreSource, number>>;
  breakdown: SourceScore[];
}

export interface SkillScores {
  student_id: number;
  computed_at: string | null;
  weights: Partial<Record<ScoreSource, number>>;
  scores: SkillScore[];
}

export interface ScoringSetting {
  key: string;
  value: Record<string, number>;
  description: string | null;
  updated_at: string;
  updated_by: string | null;
}

export interface Scoring {
  settings: ScoringSetting[];
  skill_sources: ScoreSource[];
}

export interface SubjectMapping {
  subject_id: number;
  subject_code: string;
  subject_name: string;
  skills: { skill_id: number; name: string; category: string; weight: number }[];
}

export interface CareerSkill {
  skill_id: number;
  skill_name: string;
  category: string;
  required_level: number;
  weight: number;
  is_core: boolean;
}

export interface Career {
  id: number;
  code: string;
  name: string;
  domain: string | null;
  description: string | null;
  avg_package: number | null;
  min_cgpa: number;
  course_count: number;
  is_active: boolean;
  skills: CareerSkill[];
}

export interface CareerInput {
  code: string;
  name: string;
  domain?: string | null;
  description?: string | null;
  avg_package?: number | null;
  min_cgpa: number;
  skills: { skill_id: number; required_level: number; weight: number; is_core: boolean }[];
}

export interface Course {
  id: number;
  skill_id: number;
  skill_name: string;
  title: string;
  provider: string | null;
  url: string | null;
  level: number;
  duration_hours: number | null;
  is_certification: boolean;
  is_free: boolean;
  is_active: boolean;
}

export type Readiness = 'ready' | 'close' | 'explore';

export interface SkillStanding {
  skill_id: number;
  name: string;
  category: string;
  score: number;
  level: number;
  required_level: number;
  required_score: number;
  gap: number;
  is_core: boolean;
  weight: number;
  courses?: { id: number; title: string; provider: string | null; url: string | null; level: number; duration_hours: number | null; is_free: boolean }[];
}

export interface CareerMatch {
  career_id: number;
  code: string;
  name: string;
  domain: string | null;
  description: string | null;
  avg_package: number | null;
  min_cgpa: number;
  rank: number;
  skill_score: number;
  academic_score: number;
  final_score: number;
  readiness: Readiness;
  strengths: SkillStanding[];
  gaps: SkillStanding[];
  explanation: string;
  computed_at: string;
  is_stale: boolean;
  feedback: { rating: number; is_useful: boolean; comment: string | null; created_at: string } | null;
}

export interface CareerMatches {
  student_id: number;
  computed_at: string | null;
  is_stale: boolean;
  counts: Record<Readiness, number>;
  total: number;
  matches: CareerMatch[];
}

export const READINESS: Record<Readiness, { label: string; color: string; hint: string }> = {
  ready: { label: 'Ready', color: 'green', hint: 'Every core skill is met and the CGPA is in range' },
  close: { label: 'Close', color: 'gold', hint: 'More than half of what is needed is in place' },
  explore: { label: 'Explore', color: 'default', hint: 'A longer way off — worth exploring' },
};

export const careersApi = {
  list: (params: { search?: string; domain?: string } = {}) => data<Career[]>(api.get('/careers', { params })),
  get: (id: number) => data<Career>(api.get(`/careers/${id}`)),
  domains: () => data<string[]>(api.get('/careers/domains')),
  create: (body: CareerInput) => data<Career>(api.post('/careers', body)),
  update: (id: number, body: CareerInput) => data<Career>(api.put(`/careers/${id}`, body)),
  remove: (id: number) => api.delete(`/careers/${id}`),
  courses: (id: number) => data<Course[]>(api.get(`/careers/${id}/courses`)),

  matches: (studentId: number, params: { refresh?: boolean } = {}) =>
    data<CareerMatches>(api.get(`/students/${studentId}/career-matches`, { params })),
  run: (studentId: number) => data<CareerMatches>(api.post(`/students/${studentId}/career-matches`)),
  feedback: (studentId: number, careerId: number, body: { rating: number; is_useful?: boolean; comment?: string | null }) =>
    data<CareerMatches>(api.post(`/students/${studentId}/career-matches/${careerId}/feedback`, body)),
};

export const scoresApi = {
  of: (studentId: number) => data<SkillScores>(api.get(`/students/${studentId}/skill-scores`)),
  recompute: (body: { student_ids?: number[]; class_id?: number; department_id?: number; all?: boolean }) =>
    data<{ message: string; students?: number }>(api.post('/skill-scores/recompute', body)),

  scoring: () => data<Scoring>(api.get('/config/scoring')),
  saveScoring: (body: { skill_score_weights?: Record<string, number>; match_weights?: Record<string, number> }) =>
    data<Scoring>(api.put('/config/scoring', body)),

  subjectMappings: (params: { search?: string; mapped?: 'true' | 'false' } = {}) =>
    data<{ subjects: SubjectMapping[]; total: number; mapped: number }>(api.get('/subject-skills', { params })),
  setSubjectSkills: (subjectId: number, skills: { skill_id: number; weight: number }[]) =>
    data<SubjectMapping>(api.put(`/subjects/${subjectId}/skills`, { skills })),

  /** Marks a skill's certificate as checked. Returns the student's skills, as the skills API does. */
  verifyCertificate: (studentId: number, skillId: number, verified: boolean) =>
    data<unknown>(api.put(`/students/${studentId}/skills/${skillId}/verify`, { verified })),
};

export const coursesApi = {
  list: (params: Record<string, unknown> = { all: true }) => api.get<ListEnvelope<Course>>('/courses', { params }).then((r) => r.data),
};
