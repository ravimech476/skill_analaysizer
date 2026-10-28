import { api } from './client';
import type { Envelope } from './types';

export type AssessmentKind = 'personality' | 'interests' | 'learning' | 'communication';

export interface Question {
  id: string;
  text: string;
  trait: string;
}

export interface Questionnaire {
  kind: AssessmentKind;
  title: string;
  intro: string;
  scale: string[];
  traits: { key: string; label: string }[];
  questions: Question[];
}

export interface TraitScore {
  key: string;
  label: string;
  score: number;
  level: 'low' | 'moderate' | 'high';
  meaning: string;
}

export interface AssessmentResult {
  kind: AssessmentKind;
  taken_at: string;
  traits: TraitScore[];
  headline: string;
  signals?: { attendance_percent?: number; ai_questions_30_days?: number };
}

export interface CodingPlatform {
  id: number;
  platform: string;
  username: string;
  profile_url: string | null;
  problems_solved: number;
  rating: number | null;
  verified: boolean;
  verified_at: string | null;
}

export interface Project {
  id: number;
  title: string;
  description: string | null;
  tech_stack: string | null;
  repo_url: string | null;
  live_url: string | null;
  status: 'ongoing' | 'completed';
  verified: boolean;
  verified_at: string | null;
  rubric: Record<string, number> | null;
  quality_score: number | null;
  review_notes: string | null;
}

export interface CodingSummary {
  index: number | null;
  platform_score: number | null;
  project_score: number | null;
  verified_platforms: number;
  verified_projects: number;
  problems_counted: number;
  formula: string;
  profiles: CodingPlatform[];
  projects: Project[];
}

export interface TalentProfile {
  student_id: number;
  psychometric: Partial<Record<AssessmentKind, AssessmentResult>>;
  aptitude_score: number | null;
  communication: CommunicationSummary;
  coding: CodingSummary;
}

export const PLATFORMS = [
  { value: 'leetcode', label: 'LeetCode' },
  { value: 'hackerrank', label: 'HackerRank' },
  { value: 'codechef', label: 'CodeChef' },
  { value: 'codeforces', label: 'Codeforces' },
  { value: 'geeksforgeeks', label: 'GeeksforGeeks' },
  { value: 'hackerearth', label: 'HackerEarth' },
  { value: 'other', label: 'Other' },
];

export const RUBRIC = [
  { key: 'readability', label: 'Readability' },
  { key: 'structure', label: 'Structure' },
  { key: 'testing', label: 'Testing' },
  { key: 'documentation', label: 'Documentation' },
];

export interface PlatformInput {
  platform: string;
  username: string;
  profile_url?: string | null;
  problems_solved: number;
  rating?: number | null;
}

export interface ProjectInput {
  title: string;
  description?: string | null;
  tech_stack?: string | null;
  repo_url?: string | null;
  live_url?: string | null;
  status: 'ongoing' | 'completed';
}

export const talentApi = {
  profile: async (studentId: number) => (await api.get<Envelope<TalentProfile>>(`/students/${studentId}/talent-profile`)).data.data,
  questionnaire: async (kind: AssessmentKind) => (await api.get<Envelope<Questionnaire>>(`/assessments/questionnaires/${kind}`)).data.data,
  submit: async (studentId: number, kind: AssessmentKind, answers: Record<string, number>) =>
    (await api.post<Envelope<AssessmentResult>>(`/students/${studentId}/assessments/${kind}`, { answers })).data.data,

  addPlatform: async (studentId: number, b: PlatformInput) => (await api.post<Envelope<{ id: number }>>(`/students/${studentId}/coding-profiles`, b)).data.data,
  updatePlatform: async (id: number, b: PlatformInput) => (await api.put(`/coding-profiles/${id}`, b)).data,
  removePlatform: async (id: number) => (await api.delete(`/coding-profiles/${id}`)).data,
  verifyPlatform: async (id: number, verified: boolean) => (await api.put(`/coding-profiles/${id}/verify`, { verified })).data,

  addProject: async (studentId: number, b: ProjectInput) => (await api.post<Envelope<{ id: number }>>(`/students/${studentId}/projects`, b)).data.data,
  updateProject: async (id: number, b: ProjectInput) => (await api.put(`/projects/${id}`, b)).data,
  removeProject: async (id: number) => (await api.delete(`/projects/${id}`)).data,
  reviewCommunication: async (studentId: number, rubric: Record<string, number>, notes?: string) =>
    (await api.post(`/students/${studentId}/communication-review`, { rubric, notes })).data,
  reviewProject: async (id: number, b: { verified: boolean; rubric?: Record<string, number>; notes?: string }) => (await api.put(`/projects/${id}/review`, b)).data,
};

// ---------------------------------------------------------------- communication

export interface CommunicationReview {
  rubric: Record<string, number>;
  score: number;
  notes: string | null;
  reviewed_at: string;
  reviewed_by: string | null;
}

export interface CommunicationSummary {
  self: AssessmentResult | null;
  review: CommunicationReview | null;
  score: number | null;
  formula: string;
}

export const COMMUNICATION_RUBRIC = [
  { key: 'speaking', label: 'Speaking' },
  { key: 'writing', label: 'Writing' },
  { key: 'listening', label: 'Listening' },
  { key: 'teamwork', label: 'Teamwork' },
];

// ---------------------------------------------------------------- aptitude

export interface AptitudeQuestion {
  id: number;
  section: 'quantitative' | 'logical' | 'verbal';
  text: string;
  options: string[];
}

export interface AptitudeAttempt {
  attempt_id: number;
  time_limit_sec: number;
  remaining_sec: number;
  questions: AptitudeQuestion[];
}

export interface SectionScore {
  correct: number;
  total: number;
  percent: number;
}

export interface AptitudeResult {
  score: number;
  correct: number;
  total: number;
  sections: Record<string, SectionScore>;
}

export interface AptitudeSummary {
  latest: { id: number; submitted_at: string; score: number; sections: Record<string, SectionScore> } | null;
  history: { id: number; submitted_at: string; score: number; sections: Record<string, SectionScore> }[];
  can_take_after: string | null;
  in_progress: boolean;
  per_section: number;
  time_limit_sec: number;
}

export const aptitudeApi = {
  summary: async (studentId: number) => (await api.get<Envelope<AptitudeSummary>>(`/students/${studentId}/aptitude`)).data.data,
  start: async (studentId: number) => (await api.post<Envelope<AptitudeAttempt>>(`/students/${studentId}/aptitude/start`)).data.data,
  submit: async (attemptId: number, answers: Record<string, string>) =>
    (await api.post<Envelope<AptitudeResult>>(`/aptitude/attempts/${attemptId}/submit`, { answers })).data.data,
};
