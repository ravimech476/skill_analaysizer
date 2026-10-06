import { api } from './client';
import type { Envelope } from './types';

const data = <T,>(p: Promise<{ data: Envelope<T> }>) => p.then((r) => r.data.data);

export interface SemesterChangeResult {
  changed: { class_id: number; label: string; from: string; to: string }[];
  skipped: { class_id: number; label: string; reason: string }[];
}

export interface PlanStudent {
  id: number;
  name: string;
  register_no: string;
  cgpa: number;
  backlog_count: number;
}

export interface ClassPlan {
  class_id: number;
  label: string;
  level_no: number;
  incharge_name: string | null;
  action: 'promote' | 'pass_out';
  target_label: string | null;
  target_exists: boolean;
  students: PlanStudent[];
}

export interface Preview {
  from: { id: number; name: string; is_current: boolean };
  to: { id: number; name: string; is_current: boolean };
  already_run: boolean;
  classes: ClassPlan[];
  totals: { classes: number; to_promote: number; to_pass_out: number };
}

export interface PromotionResult {
  run_id: number;
  promoted: number;
  detained: number;
  passed_out: number;
  classes_created: number;
  classes: { class: string; action: string; promoted: number; detained: number; passed_out: number }[];
}

export interface PromotionRun {
  id: number;
  from_year: string;
  to_year: string;
  promoted_count: number;
  detained_count: number;
  passed_out_count: number;
  classes_created: number;
  created_by_name: string | null;
  created_at: string;
}

export interface HistoryRow {
  academic_year: string;
  sem_no: number;
  semester: string;
  class_label: string;
  status: 'studying' | 'promoted' | 'detained' | 'passed_out' | 'discontinued';
  updated_at: string;
}

export const lifecycleApi = {
  semesterChange: (class_ids: number[], direction: 'next' | 'previous') =>
    data<SemesterChangeResult>(api.post('/lifecycle/semester-change', { class_ids, direction })),
  preview: (from_year_id: number, to_year_id: number) => data<Preview>(api.post('/lifecycle/promotion/preview', { from_year_id, to_year_id })),
  promote: (body: { from_year_id: number; to_year_id: number; detained_student_ids: number[]; carry_incharge: boolean; set_current: boolean }) =>
    data<PromotionResult>(api.post('/lifecycle/promotion', body)),
  runs: () => data<PromotionRun[]>(api.get('/lifecycle/promotions')),
  studentAction: (id: number, body: { action: 'discontinue' | 'readmit'; class_id?: number; remarks?: string }) =>
    api.post(`/students/${id}/lifecycle`, body),
  history: (id: number) => data<HistoryRow[]>(api.get(`/students/${id}/history`)),
};

export const LIFECYCLE_COLORS: Record<string, string> = {
  studying: 'blue',
  promoted: 'green',
  detained: 'orange',
  passed_out: 'purple',
  discontinued: 'red',
};
