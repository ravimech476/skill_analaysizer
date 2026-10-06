import type { FileLink } from './files';
import { api } from './client';
import type { Envelope } from './types';

const data = <T,>(p: Promise<{ data: Envelope<T> }>) => p.then((r) => r.data.data);

export type SkillCategory = 'programming' | 'framework' | 'database' | 'tool' | 'technical' | 'soft_skill' | 'domain';

export interface Skill {
  id: number;
  name: string;
  category: SkillCategory;
  student_count: number;
  job_role_count: number;
  is_active: boolean;
}

export interface Company {
  id: number;
  name: string;
  industry: string | null;
  website: string | null;
  location: string | null;
  contact_person: string | null;
  contact_email: string | null;
  contact_mobile: string | null;
  description: string | null;
  job_role_count: number;
  placed_count: number;
  highest_package: number | null;
  is_active: boolean;
}

export interface StudentSkill {
  skill_id: number;
  name: string;
  category: SkillCategory;
  proficiency: number;
  source: string;
  certificate_url: string | null;
  remarks: string | null;
  updated_at: string;
  recorded_by: string | null;
  certificate: FileLink | null;
  certificate_verified: boolean;
  certificate_verified_at: string | null;
  certificate_verified_by: string | null;
  /** Blended 0-100 score for this skill (null until the scores have been worked out). */
  score: number | null;
}

export interface RoleSkill {
  skill_id: number;
  skill_name: string;
  required_level: number;
  is_mandatory: boolean;
  weight: number;
}

export type RoleStatus = 'upcoming' | 'open' | 'closed' | 'completed';

export interface JobRole {
  id: number;
  company_id: number;
  company_name: string;
  title: string;
  description: string | null;
  package_lpa: number;
  drive_date: string | null;
  last_apply_date: string | null;
  min_cgpa: number;
  max_backlogs: number;
  eligible_batch: string | null;
  openings: number | null;
  status: RoleStatus;
  application_count: number;
  selected_count: number;
  analyzed_at: string | null;
  skills: RoleSkill[];
  departments: { id: number; code: string; name: string }[];
  company_logo: FileLink | null;
  jd: FileLink | null;
}

export interface JobRoleInput {
  company_id: number;
  title: string;
  description?: string | null;
  package_lpa: number;
  drive_date?: string | null;
  last_apply_date?: string | null;
  min_cgpa: number;
  max_backlogs: number;
  eligible_batch?: string | null;
  openings?: number | null;
  status: RoleStatus;
  department_ids: number[];
  skills: { skill_id: number; required_level: number; is_mandatory: boolean; weight: number }[];
}

export interface Gap {
  skill_id: number;
  name: string;
  required_level: number;
  student_level: number;
  /** The blended 0-100 score behind student_level, and the score the required level asks for. */
  student_score: number;
  required_score: number;
  is_mandatory: boolean;
  weight: number;
}

export interface Match {
  student_id: number;
  name: string;
  register_no: string;
  department_code: string | null;
  class_label: string | null;
  batch: string;
  cgpa: number;
  backlog_count: number;
  skill_score: number;
  academic_score: number;
  final_score: number;
  is_eligible: boolean;
  ineligible_reasons: string[];
  matched_skills: Gap[];
  missing_skills: Gap[];
  application_status: string | null;
  /** This row was worked out before the student's skill scores last changed. */
  is_stale: boolean;
}

export interface Ranking {
  analyzed_at: string | null;
  total: number;
  eligible: number;
  /** How many ranked students have moved on since the ranking was run. */
  stale: number;
  matches: Match[];
}

export type AppStatus = 'shortlisted' | 'applied' | 'in_process' | 'selected' | 'rejected' | 'withdrawn';

export interface Application {
  id: number;
  job_role_id: number;
  job_title: string;
  company_name: string;
  package_lpa: number;
  drive_date: string | null;
  student_id: number;
  student_name: string;
  register_no: string;
  department_code: string | null;
  cgpa: number;
  match_score: number | null;
  status: AppStatus;
  remarks: string | null;
  offer_date: string | null;
}

export interface Placement {
  id: number;
  student_id: number;
  student_name: string;
  register_no: string;
  department_code: string | null;
  batch: string;
  company_name: string;
  job_title: string;
  package_lpa: number;
  offer_date: string | null;
  offer_letter: FileLink | null;
}

export interface PlacementStats {
  total_students: number;
  placed_students: number;
  placed_percent: number;
  total_offers: number;
  highest_package: number | null;
  average_package: number | null;
  by_department: { code: string; name: string; students: number; placed: number; percent: number }[];
  by_company: { company: string; offers: number; highest: number }[];
}

export interface Opportunity {
  job_role: JobRole;
  is_eligible: boolean;
  ineligible_reasons: string[];
  skill_score: number;
  final_score: number;
  matched_skills: Gap[];
  missing_skills: Gap[];
  application_status: string | null;
}

export interface Opportunities {
  student_id: number;
  name: string;
  cgpa: number;
  backlog_count: number;
  skills: StudentSkill[];
  applications: Application[];
  opportunities: Opportunity[];
}

export interface SkillMatrix {
  skills: { id: number; name: string; category: string }[];
  rows: { student_id: number; name: string; register_no: string; skills: Record<string, number>; skill_count: number }[];
}

export const placementApi = {
  skills: () => api.get<{ data: Skill[] }>('/skills', { params: { all: true } }).then((r) => r.data.data),
  companies: () => api.get<{ data: Company[] }>('/companies', { params: { all: true } }).then((r) => r.data.data),
  studentSkills: (id: number) => data<StudentSkill[]>(api.get(`/students/${id}/skills`)),
  saveStudentSkill: (
    id: number,
    body: { skill_id: number; proficiency: number; source?: string; remarks?: string | null; certificate_url?: string | null; certificate_file_id?: number; remove_certificate?: boolean },
  ) =>
    data<StudentSkill[]>(api.put(`/students/${id}/skills`, body)),
  removeStudentSkill: (id: number, skillId: number) => data<StudentSkill[]>(api.delete(`/students/${id}/skills/${skillId}`)),
  matrix: (classId: number) => data<SkillMatrix>(api.get('/student-skills/matrix', { params: { class_id: classId } })),

  roles: (params: { status?: string; search?: string; company_id?: number } = {}) => data<JobRole[]>(api.get('/job-roles', { params })),
  role: (id: number) => data<JobRole>(api.get(`/job-roles/${id}`)),
  createRole: (body: JobRoleInput) => data<JobRole>(api.post('/job-roles', body)),
  updateRole: (id: number, body: JobRoleInput) => data<JobRole>(api.put(`/job-roles/${id}`, body)),
  setRoleStatus: (id: number, status: RoleStatus) => data<JobRole>(api.patch(`/job-roles/${id}/status`, { status })),
  deleteRole: (id: number) => api.delete(`/job-roles/${id}`),

  analyze: (id: number) => data<Ranking>(api.post(`/job-roles/${id}/analyze`)),
  matches: (id: number) => data<Ranking>(api.get(`/job-roles/${id}/matches`)),
  shortlist: (id: number, student_ids: number[]) =>
    data<{ added: number; skipped: { student_id: number; name: string; reason: string }[] }>(api.post(`/job-roles/${id}/shortlist`, { student_ids })),
  applications: (id: number) => data<Application[]>(api.get(`/job-roles/${id}/applications`)),
  updateApplication: (id: number, body: { status: AppStatus; remarks?: string }) => data<Application>(api.patch(`/applications/${id}`, body)),

  placements: (params: { search?: string; department_id?: number; company_id?: number; batch?: string } = {}) => data<Placement[]>(api.get('/placements', { params })),
  stats: (batch?: string) => data<PlacementStats>(api.get('/placements/stats', { params: { batch } })),
  opportunities: (studentId: number) => data<Opportunities>(api.get(`/students/${studentId}/opportunities`)),
};

export const STATUS_COLORS: Record<string, string> = {
  upcoming: 'blue',
  open: 'green',
  closed: 'default',
  completed: 'purple',
  shortlisted: 'blue',
  applied: 'cyan',
  in_process: 'gold',
  selected: 'green',
  rejected: 'red',
  withdrawn: 'default',
};

export const pretty = (s: string) => s.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
export const lpa = (v: number | null | undefined) => (v == null ? '—' : `₹ ${v} LPA`);
