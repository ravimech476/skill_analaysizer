import { api } from './client';
import type { Envelope, ListEnvelope } from './types';

const data = <T,>(p: Promise<{ data: Envelope<T> }>) => p.then((r) => r.data.data);

// ---- types ----

export interface Department {
  id: number;
  name: string;
  code: string;
  hod_id: number | null;
  hod_name: string | null;
  class_count: number;
  student_count: number;
  is_active: boolean;
}

export interface AcademicYear {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  is_current: boolean;
  is_active: boolean;
}

export interface Subject {
  id: number;
  code: string;
  name: string;
  credits: number;
  subject_type: 'theory' | 'lab' | 'elective' | 'project';
  is_active: boolean;
}

export interface ExamType {
  id: number;
  name: string;
  code: string;
  max_marks: number;
  is_final: boolean;
  sort_order: number;
  pass_percent: number;
  is_active: boolean;
}

export interface GradeScale {
  id: number;
  grade: string;
  min_percent: number;
  grade_point: number;
  is_pass: boolean;
  is_active: boolean;
}

export interface YearLevel {
  id: number;
  name: string;
  level_no: number;
}

export interface Semester {
  id: number;
  name: string;
  sem_no: number;
  year_level_id: number;
}

export interface CurriculumRow {
  id: number;
  department_id: number;
  semester_id: number;
  sem_no: number;
  regulation: string;
  subject_id: number;
  subject_code: string;
  subject_name: string;
  credits: number;
  subject_type: string;
}

export interface ClassRow {
  id: number;
  label: string;
  department_id: number;
  department_name: string;
  department_code: string;
  academic_year_id: number;
  academic_year_name: string;
  is_current_year: boolean;
  year_level_id: number;
  year_level_name: string;
  level_no: number;
  section: string;
  class_incharge_id: number | null;
  class_incharge_name: string | null;
  current_semester_id: number | null;
  current_semester_name: string | null;
  current_sem_no: number | null;
  student_count: number;
}

export interface ClassInput {
  department_id: number;
  academic_year_id: number;
  year_level_id: number;
  section: string;
  class_incharge_id: number | null;
  current_semester_id?: number | null;
}

export interface Staff {
  id: number;
  name: string;
  username: string;
  employee_code: string | null;
  mobile: string | null;
  email: string | null;
  gender: string | null;
  dob: string | null;
  department_id: number | null;
  department_name: string | null;
  designation: string | null;
  qualification: string | null;
  joined_on: string | null;
  roles: string[];
  incharge_of: string | null;
  is_active: boolean;
  photo?: import('./files').FileLink | null;
}

export interface StaffInput {
  name: string;
  username?: string;
  password?: string;
  employee_code: string;
  mobile?: string | null;
  email?: string | null;
  gender?: string | null;
  dob?: string | null;
  department_id?: number | null;
  designation?: string | null;
  qualification?: string | null;
  joined_on?: string | null;
  roles: string[];
}

export interface ParentRef {
  id: number;
  name: string;
  username: string;
  mobile: string | null;
  email: string | null;
  relation: 'father' | 'mother' | 'guardian';
  is_primary: boolean;
}

export interface Student {
  id: number;
  name: string;
  username: string;
  register_no: string;
  mobile: string | null;
  email: string | null;
  gender: string | null;
  dob: string | null;
  department_id: number | null;
  department_name: string | null;
  department_code: string | null;
  admission_year: number;
  batch: string;
  class_id: number | null;
  class_label: string | null;
  class_incharge_name: string | null;
  cgpa: number;
  backlog_count: number;
  blood_group: string | null;
  address: string | null;
  has_password: boolean;
  is_active: boolean;
  parent_count: number;
  lifecycle_status: 'studying' | 'passed_out' | 'discontinued';
  passed_out_year: number | null;
  status_remarks: string | null;
  photo?: import('./files').FileLink | null;
  resume?: import('./files').FileLink | null;
  parents?: ParentRef[];
}

export interface ParentInput {
  id?: number;
  name?: string;
  mobile?: string;
  email?: string | null;
  relation: string;
  is_primary?: boolean;
}

export interface StudentInput {
  name: string;
  username?: string;
  password?: string;
  register_no: string;
  mobile?: string | null;
  email?: string | null;
  gender?: string | null;
  dob?: string | null;
  department_id: number;
  admission_year: number;
  batch?: string;
  class_id?: number | null;
  blood_group?: string | null;
  address?: string | null;
  parents?: ParentInput[];
}

export interface ParentListItem {
  id: number;
  name: string;
  username: string;
  mobile: string | null;
  email: string | null;
  children: string[];
}

export interface UploadJob {
  id: number;
  upload_type: string;
  file_name: string;
  total_rows: number;
  success_rows: number;
  failed_rows: number;
  errors: { row: number; register_no: string; name: string; message: string }[] | null;
  status: string;
  dry_run: boolean;
  created_by_name: string | null;
  created_at: string;
}

export interface Page {
  page: number;
  page_size: number;
  search?: string;
  status?: string;
}

// ---- generic masters ----

export type MasterPath = 'departments' | 'academic-years' | 'subjects' | 'exam-types' | 'grade-scales' | 'skills' | 'companies' | 'courses';

export const mastersApi = {
  list: <T,>(path: MasterPath | 'year-levels' | 'semesters', params: Record<string, unknown> = { all: true }) =>
    api.get<ListEnvelope<T>>(`/${path}`, { params }).then((r) => r.data),
  all: <T,>(path: MasterPath | 'year-levels' | 'semesters') =>
    api.get<ListEnvelope<T>>(`/${path}`, { params: { all: true } }).then((r) => r.data.data),
  create: <T,>(path: MasterPath, body: Record<string, unknown>) => data<T>(api.post(`/${path}`, body)),
  update: <T,>(path: MasterPath, id: number, body: Record<string, unknown>) => data<T>(api.put(`/${path}/${id}`, body)),
  remove: (path: MasterPath, id: number) => api.delete(`/${path}/${id}`),
  setStatus: (path: MasterPath, id: number, is_active: boolean) => api.patch(`/${path}/${id}/status`, { is_active }),
};

export const curriculumApi = {
  list: (department_id: number, semester_id?: number) =>
    data<CurriculumRow[]>(api.get('/curriculum', { params: { department_id, semester_id } })),
  add: (body: { department_id: number; semester_id: number; subject_ids: number[]; regulation?: string }) =>
    data<{ added: number }>(api.post('/curriculum', body)),
  remove: (id: number) => api.delete(`/curriculum/${id}`),
};

export const classesApi = {
  list: (params: { academic_year_id?: number | 'all'; department_id?: number; search?: string } = {}) =>
    data<ClassRow[]>(api.get('/classes', { params })),
  get: (id: number) => data<ClassRow>(api.get(`/classes/${id}`)),
  create: (body: ClassInput) => data<ClassRow>(api.post('/classes', body)),
  update: (id: number, body: ClassInput) => data<ClassRow>(api.put(`/classes/${id}`, body)),
  remove: (id: number) => api.delete(`/classes/${id}`),
};

export const staffApi = {
  list: (params: Page & { department_id?: number; role?: string; all?: boolean }) =>
    api.get<ListEnvelope<Staff>>('/staff', { params }).then((r) => r.data),
  get: (id: number) => data<Staff>(api.get(`/staff/${id}`)),
  create: (body: StaffInput) => data<Staff>(api.post('/staff', body)),
  update: (id: number, body: StaffInput) => data<Staff>(api.put(`/staff/${id}`, body)),
  setStatus: (id: number, is_active: boolean) => data<Staff>(api.patch(`/staff/${id}/status`, { is_active })),
};

export const studentsApi = {
  list: (params: Page & { department_id?: number; class_id?: number; batch?: string; lifecycle?: string }) =>
    api.get<ListEnvelope<Student>>('/students', { params }).then((r) => r.data),
  get: (id: number) => data<Student>(api.get(`/students/${id}`)),
  create: (body: StudentInput) => data<Student>(api.post('/students', body)),
  update: (id: number, body: StudentInput) => data<Student>(api.put(`/students/${id}`, body)),
  setStatus: (id: number, is_active: boolean) => data<Student>(api.patch(`/students/${id}/status`, { is_active })),
  addParent: (id: number, body: ParentInput) => data<Student>(api.post(`/students/${id}/parents`, body)),
  removeParent: (id: number, parentId: number) => data<Student>(api.delete(`/students/${id}/parents/${parentId}`)),
  parents: (search: string) => data<ParentListItem[]>(api.get('/parents', { params: { search, page_size: 20 } })),
};

export const bulkApi = {
  template: () => api.get<Blob>('/bulk-upload/students/template', { responseType: 'blob' }).then((r) => r.data),
  upload: (file: File, opts: { dry_run: boolean; create_missing_classes: boolean; default_password?: string }) => {
    const form = new FormData();
    form.append('file', file);
    form.append('dry_run', String(opts.dry_run));
    form.append('create_missing_classes', String(opts.create_missing_classes));
    if (opts.default_password) form.append('default_password', opts.default_password);
    return data<UploadJob>(api.post('/bulk-upload/students', form, { timeout: 300_000 }));
  },
  jobs: (page: number, page_size: number, upload_type?: string) =>
    api.get<ListEnvelope<UploadJob>>('/bulk-upload/jobs', { params: { page, page_size, upload_type } }).then((r) => r.data),
  job: (id: number) => data<UploadJob>(api.get(`/bulk-upload/jobs/${id}`)),
  errorReport: (id: number) => api.get<Blob>(`/bulk-upload/jobs/${id}/errors.xlsx`, { responseType: 'blob' }).then((r) => r.data),
};

/** Save a Blob as a file download. */
export function saveBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
