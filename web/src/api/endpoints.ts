import { api } from './client';
import type {
  Envelope,
  ListEnvelope,
  OTPSent,
  PermissionGroup,
  Role,
  SessionUser,
  TokenResponse,
  User,
} from './types';

const data = <T,>(p: Promise<{ data: Envelope<T> }>) => p.then((r) => r.data.data);

export const authApi = {
  login: (username: string, password: string) =>
    data<TokenResponse>(api.post('/auth/login', { username, password })),
  requestOtp: (identifier: string) => data<OTPSent>(api.post('/auth/otp/request', { identifier })),
  verifyOtp: (identifier: string, otp: string) =>
    data<TokenResponse>(api.post('/auth/otp/verify', { identifier, otp })),
  forgotPassword: (identifier: string) => data<OTPSent>(api.post('/auth/password/forgot', { identifier })),
  resetPassword: (identifier: string, otp: string, new_password: string) =>
    data<{ message: string }>(api.post('/auth/password/reset', { identifier, otp, new_password })),
  me: () => data<SessionUser>(api.get('/auth/me')),
  changePassword: (current_password: string, new_password: string) =>
    data<{ message: string }>(api.post('/auth/password/change', { current_password, new_password })),
  logout: (refresh_token: string) => api.post('/auth/logout', { refresh_token }),
};

export interface UserFilter {
  search?: string;
  role?: string;
  status?: 'active' | 'inactive' | 'all';
  page: number;
  page_size: number;
}

export interface UserInput {
  name: string;
  username: string;
  password?: string;
  reference_number?: string | null;
  mobile?: string | null;
  email?: string | null;
  gender?: string | null;
  dob?: string | null;
  role_ids?: number[];
}

export const usersApi = {
  list: (f: UserFilter) => api.get<ListEnvelope<User>>('/users', { params: f }).then((r) => r.data),
  get: (id: number) => data<User>(api.get(`/users/${id}`)),
  create: (body: UserInput) => data<User>(api.post('/users', body)),
  update: (id: number, body: UserInput) => data<User>(api.put(`/users/${id}`, body)),
  setStatus: (id: number, is_active: boolean) => data<User>(api.patch(`/users/${id}/status`, { is_active })),
  setRoles: (id: number, role_ids: number[]) => data<User>(api.put(`/users/${id}/roles`, { role_ids })),
  setPassword: (id: number, password: string) => data<{ message: string }>(api.put(`/users/${id}/password`, { password })),
};

export const rolesApi = {
  list: () => data<Role[]>(api.get('/roles')),
  get: (id: number) => data<Role>(api.get(`/roles/${id}`)),
  create: (body: { name: string; description?: string; permission_ids?: number[] }) => data<Role>(api.post('/roles', body)),
  update: (id: number, body: { name: string; description?: string }) => data<Role>(api.put(`/roles/${id}`, body)),
  remove: (id: number) => api.delete(`/roles/${id}`),
  setPermissions: (id: number, permission_ids: number[]) =>
    data<Role>(api.put(`/roles/${id}/permissions`, { permission_ids })),
};

export const permissionsApi = {
  grouped: () => data<PermissionGroup[]>(api.get('/permissions')),
};
