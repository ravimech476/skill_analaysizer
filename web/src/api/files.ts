import { api, API_URL } from './client';

/** A stored file as the API returns it; `url` is signed, relative to the API root and expires after 1–2 hours. */
export interface FileLink {
  url: string;
  name: string;
  type: string;
  size: number;
}

export interface UploadedFile extends FileLink {
  id: number;
  category: string;
}

export type FileCategory =
  | 'profile_photo'
  | 'resume'
  | 'certificate'
  | 'offer_letter'
  | 'student_document'
  | 'company_logo'
  | 'job_description'
  | 'notification_attachment';

const IMAGES = 'image/jpeg,image/png,image/webp';
const PDF = 'application/pdf';

/** What the file picker accepts and how big a file may be, mirroring the server's rules. */
export const FILE_RULES: Record<FileCategory, { accept: string; maxMB: number; hint: string }> = {
  profile_photo: { accept: IMAGES, maxMB: 2, hint: 'JPG, PNG or WebP, up to 2 MB' },
  company_logo: { accept: IMAGES, maxMB: 1, hint: 'JPG, PNG or WebP, up to 1 MB' },
  resume: { accept: PDF, maxMB: 5, hint: 'PDF, up to 5 MB' },
  job_description: { accept: PDF, maxMB: 5, hint: 'PDF, up to 5 MB' },
  offer_letter: { accept: `${PDF},${IMAGES}`, maxMB: 5, hint: 'PDF or image, up to 5 MB' },
  certificate: { accept: `${PDF},${IMAGES}`, maxMB: 5, hint: 'PDF or image, up to 5 MB' },
  student_document: { accept: `${PDF},${IMAGES}`, maxMB: 5, hint: 'PDF or image, up to 5 MB' },
  notification_attachment: { accept: `${PDF},${IMAGES}`, maxMB: 10, hint: 'PDF or image, up to 10 MB' },
};

export const fileUrl = (l: FileLink, download = false) => API_URL + l.url + (download ? '&download=1' : '');

export const filesApi = {
  upload: (category: FileCategory, file: File) => {
    const f = new FormData();
    f.append('file', file);
    f.append('category', category);
    return api.post<{ data: UploadedFile }>('/files', f, { timeout: 120_000 }).then((r) => r.data.data);
  },
  setMyPhoto: (file_id: number | null) => api.put<{ data: { photo: FileLink | null } }>('/users/me/photo', { file_id }).then((r) => r.data.data.photo),
  setUserPhoto: (userId: number, file_id: number | null) =>
    api.put<{ data: { photo: FileLink | null } }>(`/users/${userId}/photo`, { file_id }).then((r) => r.data.data.photo),
  setResume: (studentId: number, file_id: number | null) =>
    api.put<{ data: { resume: FileLink | null } }>(`/students/${studentId}/resume`, { file_id }).then((r) => r.data.data.resume),
  setCompanyLogo: (companyId: number, file_id: number | null) => api.put(`/companies/${companyId}/logo`, { file_id }),
  setJD: (roleId: number, file_id: number | null) => api.put(`/job-roles/${roleId}/jd`, { file_id }),
  setOfferLetter: (placementId: number, file_id: number | null) => api.put(`/placements/${placementId}/offer-letter`, { file_id }),
};

// ---------- student documents ----------

export type DocStatus = 'pending' | 'verified' | 'rejected';

export interface StudentDocument {
  id: number;
  student_id: number;
  student_name: string;
  register_no: string;
  class_label: string | null;
  doc_type: string;
  doc_type_label: string;
  title: string;
  file: FileLink | null;
  status: DocStatus;
  remarks: string | null;
  verified_by: string | null;
  verified_at: string | null;
  uploaded_by: string | null;
  created_at: string;
}

export const documentsApi = {
  list: (studentId: number) =>
    api
      .get<{ data: { documents: StudentDocument[]; types: Record<string, string> } }>(`/students/${studentId}/documents`)
      .then((r) => r.data.data),
  add: (studentId: number, body: { doc_type: string; title?: string; file_id: number }) =>
    api.post<{ data: StudentDocument }>(`/students/${studentId}/documents`, body).then((r) => r.data.data),
  review: (studentId: number, docId: number, body: { status: DocStatus; remarks?: string }) =>
    api.patch<{ data: StudentDocument }>(`/students/${studentId}/documents/${docId}`, body).then((r) => r.data.data),
  remove: (studentId: number, docId: number) => api.delete(`/students/${studentId}/documents/${docId}`),
  queue: (params: { status?: string; class_id?: number; page: number; page_size: number }) =>
    api
      .get<{ data: StudentDocument[]; meta: { page: number; page_size: number; total: number } }>('/documents/pending', { params })
      .then((r) => r.data),
};

export const DOC_STATUS_COLOR: Record<DocStatus, string> = { pending: 'gold', verified: 'green', rejected: 'red' };
