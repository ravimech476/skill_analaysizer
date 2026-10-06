import { api } from './client';
import type { Envelope } from './types';

const data = <T,>(p: Promise<{ data: Envelope<T> }>) => p.then((r) => r.data.data);

export interface Target {
  class_id: number;
  class_label: string;
  semester_id: number;
  sem_no: number;
  subject_id: number;
  subject_code: string;
  subject_name: string;
  reason: 'admin' | 'hod' | 'incharge' | 'allocated';
}

export interface Stats {
  entered: number;
  absent: number;
  passed: number;
  failed: number;
  average: number;
  highest: number;
  pass_percent: number;
}

export interface EntryRow {
  student_id: number;
  register_no: string;
  name: string;
  marks_obtained: number | null;
  is_absent: boolean;
  grade: string | null;
  result: 'pass' | 'fail' | 'absent' | null;
  updated_at: string | null;
  in_class: boolean;
}

export interface EntryKey {
  class_id: number;
  semester_id: number;
  subject_id: number;
  exam_type_id: number;
  attempt_no: number;
}

export interface EntrySheet extends EntryKey {
  class_label: string;
  sem_no: number;
  subject_code: string;
  subject_name: string;
  credits: number;
  exam_name: string;
  max_marks: number;
  is_final: boolean;
  pass_percent: number;
  can_edit: boolean;
  rows: EntryRow[];
  stats: Stats;
}

export interface SheetCell {
  marks: number | null;
  result: string | null;
  grade: string | null;
}

export interface ResultSheet {
  class_label: string;
  exam_name: string;
  max_marks: number;
  subjects: { id: number; code: string; name: string; credits: number; stats: Stats }[];
  rows: { student_id: number; register_no: string; name: string; marks: Record<string, SheetCell>; failed: number }[];
}

export interface ExamMark {
  exam_type_id: number;
  exam_code: string;
  exam_name: string;
  is_final: boolean;
  attempt_no: number;
  marks: number | null;
  max_marks: number;
  result: string | null;
  grade: string | null;
}

export interface MarkHistory {
  student_id: number;
  name: string;
  register_no: string;
  class_label: string | null;
  cgpa: number;
  backlog_count: number;
  semesters: {
    semester_id: number;
    sem_no: number;
    name: string;
    academic_year: string;
    class_label: string | null;
    sgpa: number | null;
    credits_earned: number;
    backlogs: number;
    subjects: { subject_id: number; code: string; name: string; credits: number; final_grade: string | null; final_result: string | null; exams: ExamMark[] }[];
  }[];
}

export interface Allocation {
  id: number;
  staff_id: number;
  staff_name: string;
  class_id: number;
  class_label: string;
  academic_year_name: string;
  semester_id: number;
  sem_no: number;
  subject_id: number;
  subject_code: string;
  subject_name: string;
}

export interface ExamType {
  id: number;
  name: string;
  code: string;
  max_marks: number;
  is_final: boolean;
  sort_order: number;
  pass_percent: number;
}

export const marksApi = {
  mySubjects: () => data<Target[]>(api.get('/marks/my-subjects')),
  entry: (k: EntryKey) => data<EntrySheet>(api.get('/marks/entry', { params: k })),
  save: (k: EntryKey, entries: { student_id: number; marks_obtained: number | null; is_absent: boolean }[]) =>
    data<EntrySheet>(api.put('/marks/entry', { ...k, entries })),
  sheet: (p: { class_id: number; semester_id: number; exam_type_id: number; attempt_no?: number }) =>
    data<ResultSheet>(api.get('/marks/sheet', { params: p })),
  history: (studentId: number) => data<MarkHistory>(api.get(`/marks/students/${studentId}`)),
  examTypes: () => api.get<{ data: ExamType[] }>('/exam-types', { params: { all: true } }).then((r) => r.data.data),
};

export const allocationsApi = {
  list: (params: { class_id?: number; staff_id?: number; department_id?: number }) => data<Allocation[]>(api.get('/subject-allocations', { params })),
  create: (body: { staff_id: number; class_id: number; subject_id: number; semester_id?: number }) => data<Allocation>(api.post('/subject-allocations', body)),
  remove: (id: number) => api.delete(`/subject-allocations/${id}`),
};
