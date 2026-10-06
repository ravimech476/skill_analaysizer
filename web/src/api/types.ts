export interface ApiErrorBody {
  success: false;
  error: { code: string; message: string; details?: unknown };
}

export interface Envelope<T> {
  success: true;
  data: T;
}

export interface ListEnvelope<T> extends Envelope<T[]> {
  meta: { page: number; page_size: number; total: number };
}

export type RoleSlug = 'admin' | 'staff' | 'hod' | 'placement_officer' | 'student' | 'parent' | string;

export interface SessionUser {
  id: number;
  name: string;
  username: string;
  roles: RoleSlug[];
  permissions: string[];
  photo?: import('./files').FileLink | null;
}

export interface TokenResponse {
  token_type: string;
  access_token: string;
  access_token_expires_at: string;
  refresh_token: string;
  user: SessionUser;
}

export interface OTPSent {
  message: string;
  masked_mobile?: string;
  expires_in_seconds: number;
  debug_otp?: string;
}

export interface RoleRef {
  id: number;
  slug: string;
  name: string;
}

export interface User {
  id: number;
  reference_number: string | null;
  name: string;
  mobile: string | null;
  email: string | null;
  username: string;
  department_id: number | null;
  department_name: string | null;
  gender: 'male' | 'female' | 'other' | null;
  dob: string | null;
  has_password: boolean;
  is_active: boolean;
  last_login_at: string | null;
  created_at: string;
  roles: RoleRef[];
}

export interface Role {
  id: number;
  name: string;
  slug: string;
  description: string | null;
  is_system: boolean;
  is_active: boolean;
  user_count: number;
  permission_count: number;
  permission_ids?: number[];
}

export interface Permission {
  id: number;
  module: string;
  action: string;
  slug: string;
  description: string | null;
}

export interface PermissionGroup {
  module: string;
  permissions: Permission[];
}
