import { api, errorMessage } from './client';
import { saveBlob, type UploadJob } from './phase2';
import type { EntryKey, EntrySheet } from './marks';
import { message } from 'antd';

// ---------- downloads ----------

/** Fetch a file endpoint and save it under the server's file name (falls back to `name`). */
export async function download(path: string, name: string, params?: Record<string, unknown>) {
  try {
    const r = await api.get<Blob>(path, { params, responseType: 'blob', timeout: 120_000 });
    const m = /filename="?([^";]+)"?/.exec(r.headers['content-disposition'] ?? '');
    saveBlob(r.data, m?.[1] ?? name);
  } catch (e) {
    // Error bodies arrive as a Blob when responseType is blob: surface the JSON message.
    const blob = (e as { response?: { data?: Blob } }).response?.data;
    if (blob instanceof Blob) {
      try {
        const j = JSON.parse(await blob.text());
        message.error(j?.error?.message ?? 'Download failed');
        return;
      } catch {
        /* fall through */
      }
    }
    message.error(errorMessage(e));
  }
}

export const exportsApi = {
  students: (params: Record<string, unknown>) => download('/students/export.xlsx', 'students.xlsx', params),
  placements: (params: Record<string, unknown>) => download('/placements.xlsx', 'placements.xlsx', params),
  ranking: (roleId: number, eligibleOnly = false) =>
    download(`/job-roles/${roleId}/matches.xlsx`, 'ranking.xlsx', eligibleOnly ? { eligible_only: true } : undefined),
  classResults: (p: { class_id: number; semester_id: number; exam_type_id: number; attempt_no?: number }) =>
    download('/marks/sheet.xlsx', 'results.xlsx', p),
  statement: (studentId: number) => download(`/marks/students/${studentId}/statement.pdf`, 'mark_statement.pdf'),
  marksTemplate: (k: EntryKey) => download('/marks/entry/template', 'marks.xlsx', { ...k }),
};

// ---------- uploads ----------

export interface MarksUploadResult {
  job: UploadJob;
  saved: boolean;
  sheet?: EntrySheet;
}

function form(file: File, fields: Record<string, string | number | boolean | undefined>) {
  const f = new FormData();
  f.append('file', file);
  Object.entries(fields).forEach(([k, v]) => v !== undefined && v !== '' && f.append(k, String(v)));
  return f;
}

export const uploadsApi = {
  marks: (k: EntryKey, file: File, dry_run: boolean) =>
    api.post<{ data: MarksUploadResult }>('/marks/entry/upload', form(file, { ...k, dry_run })).then((r) => r.data.data),
  staff: (file: File, opts: { dry_run: boolean; default_password?: string }) =>
    api.post<{ data: UploadJob }>('/bulk-upload/staff', form(file, opts), { timeout: 300_000 }).then((r) => r.data.data),
  skills: (file: File, opts: { dry_run: boolean }) =>
    api.post<{ data: UploadJob }>('/bulk-upload/skills', form(file, opts), { timeout: 300_000 }).then((r) => r.data.data),
  staffTemplate: () => download('/bulk-upload/staff/template', 'staff_upload_template.xlsx'),
  skillsTemplate: (params?: { class_id?: number; skill_id?: number }) => download('/bulk-upload/skills/template', 'student_skills_template.xlsx', params),
};

// ---------- dashboard ----------

export interface ClassPass {
  class_id: number;
  class_label: string;
  department_code: string;
  students: number;
  all_clear: number;
  appeared: number;
  passed: number;
  pass_percent: number;
  all_clear_percent: number;
}

export interface SkillGapRow {
  skill_id: number;
  name: string;
  roles: number;
  mandatory_in: number;
  required_level: number;
  students_meeting: number;
  students_recorded: number;
  coverage_percent: number;
  avg_level: number;
  students_base: number;
}

export interface Dashboard {
  scope_department: string | null;
  headline: {
    students: number;
    staff: number;
    classes: number;
    avg_cgpa: number | null;
    with_backlogs: number;
    placed: number;
    placed_percent: number;
    open_drives: number;
  };
  exams: { id: number; name: string }[];
  exam: { id: number; name: string } | null;
  pass_by_class: ClassPass[];
  cgpa_distribution: { label: string; min: number; total: number; by_department: Record<string, number> }[];
  cgpa_not_graded: number;
  departments: string[];
  skill_gaps: SkillGapRow[];
  skill_gap_source: string;
  placement_by_batch: {
    batch: string;
    students: number;
    placed: number;
    placed_percent: number;
    offers: number;
    highest_package: number | null;
    average_package: number | null;
    median_package: number | null;
  }[];
  placement_by_month: { month: string; offers: number; average_package: number | null }[];
}

export const reportsApi = {
  dashboard: (params: { department_id?: number; exam_type_id?: number }) =>
    api.get<{ data: Dashboard }>('/reports/dashboard', { params }).then((r) => r.data.data),
};
