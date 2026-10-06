import { useState } from 'react';
import {
  Alert,
  Button,
  Card,
  DatePicker,
  Drawer,
  Dropdown,
  Form,
  Input,
  Modal,
  Select,
  Space,
  Table,
  Tag,
  Typography,
  message,
} from 'antd';
import { MoreOutlined, PlusOutlined } from '@ant-design/icons';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { rolesApi, usersApi, type UserFilter, type UserInput } from '../api/endpoints';
import { errorMessage } from '../api/client';
import type { User } from '../api/types';
import { useAuth } from '../auth/AuthContext';
import { ROLE_COLORS } from '../auth/access';

function useRoleOptions() {
  const { data } = useQuery({ queryKey: ['roles'], queryFn: rolesApi.list });
  return (data ?? []).map((r) => ({ value: r.id, label: r.name, slug: r.slug }));
}

type FormValues = Omit<UserInput, 'dob'> & { dob?: dayjs.Dayjs | null };

function UserDrawer({ user, open, onClose }: { user: User | null; open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const roleOptions = useRoleOptions();
  const { hasRole } = useAuth();
  const [form] = Form.useForm<FormValues>();
  const [error, setError] = useState<string>();
  const editing = !!user;

  const save = useMutation({
    mutationFn: (v: FormValues) => {
      const body: UserInput = { ...v, dob: v.dob ? v.dob.format('YYYY-MM-DD') : null };
      return editing ? usersApi.update(user.id, body) : usersApi.create(body);
    },
    onSuccess: () => {
      message.success(editing ? 'User updated' : 'User created');
      qc.invalidateQueries({ queryKey: ['users'] });
      onClose();
    },
    onError: (e) => setError(errorMessage(e)),
  });

  return (
    <Drawer
      title={editing ? `Edit ${user.name}` : 'New user'}
      open={open}
      onClose={onClose}
      size={Math.min(480, window.innerWidth)}
      destroyOnHidden
      afterOpenChange={(o) => {
        if (!o) return;
        setError(undefined);
        form.resetFields();
        if (user) form.setFieldsValue({ ...user, dob: user.dob ? dayjs(user.dob) : null });
      }}
      extra={
        <Button type="primary" loading={save.isPending} onClick={() => form.submit()}>
          Save
        </Button>
      }
    >
      {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
      <Form form={form} layout="vertical" onFinish={(v) => save.mutate(v)} requiredMark="optional">
        <Form.Item name="name" label="Full name" rules={[{ required: true }]}>
          <Input />
        </Form.Item>
        <Form.Item
          name="username"
          label="Username"
          rules={[{ required: true, min: 3 }, { pattern: /^[A-Za-z0-9._-]+$/, message: 'Letters, digits, . _ - only' }]}
        >
          <Input />
        </Form.Item>
        <Form.Item name="reference_number" label="Reference number" extra="Register number for students, employee code for staff">
          <Input />
        </Form.Item>
        <Form.Item name="mobile" label="Mobile" rules={[{ pattern: /^[6-9]\d{9}$/, message: 'Valid 10-digit mobile number' }]} extra="Needed for OTP login">
          <Input maxLength={10} />
        </Form.Item>
        <Form.Item name="email" label="Email" rules={[{ type: 'email' }]}>
          <Input />
        </Form.Item>
        <Space style={{ display: 'flex' }} align="start">
          <Form.Item name="gender" label="Gender" style={{ minWidth: 160 }}>
            <Select allowClear options={['male', 'female', 'other'].map((g) => ({ value: g, label: g[0].toUpperCase() + g.slice(1) }))} />
          </Form.Item>
          <Form.Item name="dob" label="Date of birth">
            <DatePicker disabledDate={(d) => d.isAfter(dayjs())} format="DD-MM-YYYY" />
          </Form.Item>
        </Space>
        {!editing && (
          <>
            <Form.Item name="role_ids" label="Roles" rules={[{ required: true, message: 'Pick at least one role' }]} extra="A user can have more than one role">
              <Select
                mode="multiple"
                options={roleOptions.filter((r) => r.slug !== 'admin' || hasRole('admin'))}
                optionFilterProp="label"
              />
            </Form.Item>
            <Form.Item name="password" label="Password" rules={[{ min: 8 }]} extra="Optional. Without one, the user signs in with OTP.">
              <Input.Password autoComplete="new-password" />
            </Form.Item>
          </>
        )}
      </Form>
    </Drawer>
  );
}

function RolesModal({ user, onClose }: { user: User | null; onClose: () => void }) {
  const qc = useQueryClient();
  const roleOptions = useRoleOptions();
  const { hasRole } = useAuth();
  const [value, setValue] = useState<number[]>([]);
  const save = useMutation({
    mutationFn: () => usersApi.setRoles(user!.id, value),
    onSuccess: () => {
      message.success('Roles updated');
      qc.invalidateQueries({ queryKey: ['users'] });
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  return (
    <Modal
      title={`Roles for ${user?.name}`}
      open={!!user}
      onCancel={onClose}
      onOk={() => save.mutate()}
      okButtonProps={{ disabled: value.length === 0, loading: save.isPending }}
      afterOpenChange={(o) => o && setValue(user?.roles.map((r) => r.id) ?? [])}
      destroyOnHidden
    >
      <Select
        mode="multiple"
        style={{ width: '100%' }}
        value={value}
        onChange={setValue}
        options={roleOptions.filter((r) => r.slug !== 'admin' || hasRole('admin'))}
      />
    </Modal>
  );
}

function PasswordModal({ user, onClose }: { user: User | null; onClose: () => void }) {
  const [form] = Form.useForm();
  const save = useMutation({
    mutationFn: (v: { password: string }) => usersApi.setPassword(user!.id, v.password),
    onSuccess: () => {
      message.success('Password updated');
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  return (
    <Modal
      title={`Set password for ${user?.name}`}
      open={!!user}
      onCancel={onClose}
      onOk={() => form.submit()}
      okButtonProps={{ loading: save.isPending }}
      destroyOnHidden
    >
      <Form form={form} layout="vertical" preserve={false} onFinish={(v) => save.mutate(v)}>
        <Form.Item name="password" label="New password" rules={[{ required: true, min: 8 }]}>
          <Input.Password autoComplete="new-password" />
        </Form.Item>
      </Form>
    </Modal>
  );
}

export default function UsersPage() {
  const { can, user: me } = useAuth();
  const qc = useQueryClient();
  const roleOptions = useRoleOptions();
  const [filter, setFilter] = useState<UserFilter>({ page: 1, page_size: 20, status: 'active' });
  const [drawer, setDrawer] = useState<{ open: boolean; user: User | null }>({ open: false, user: null });
  const [rolesFor, setRolesFor] = useState<User | null>(null);
  const [passwordFor, setPasswordFor] = useState<User | null>(null);

  const { data, isFetching } = useQuery({
    queryKey: ['users', filter],
    queryFn: () => usersApi.list(filter),
    placeholderData: keepPreviousData,
  });

  const toggle = useMutation({
    mutationFn: (u: User) => usersApi.setStatus(u.id, !u.is_active),
    onSuccess: (u) => {
      message.success(u.is_active ? 'User activated' : 'User deactivated');
      qc.invalidateQueries({ queryKey: ['users'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <Card
      title={<span style={{ fontWeight: 600 }}>{data?.meta.total ?? 0} accounts</span>}
      extra={
        can('user.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setDrawer({ open: true, user: null })}>
            New user
          </Button>
        )
      }
    >
      <Space wrap style={{ marginBottom: 16 }}>
        <Input.Search
          placeholder="Name, username, mobile, ref no."
          allowClear
          style={{ width: 280 }}
          onSearch={(search) => setFilter((f) => ({ ...f, search, page: 1 }))}
        />
        <Select
          placeholder="All roles"
          allowClear
          style={{ width: 180 }}
          options={roleOptions.map((r) => ({ value: r.slug, label: r.label }))}
          onChange={(role) => setFilter((f) => ({ ...f, role, page: 1 }))}
        />
        <Select
          value={filter.status}
          style={{ width: 140 }}
          options={[
            { value: 'active', label: 'Active' },
            { value: 'inactive', label: 'Inactive' },
            { value: 'all', label: 'All' },
          ]}
          onChange={(status) => setFilter((f) => ({ ...f, status, page: 1 }))}
        />
      </Space>

      <Table<User>
        rowKey="id"
        loading={isFetching}
        dataSource={data?.data}
        scroll={{ x: 900 }}
        pagination={{
          current: filter.page,
          pageSize: filter.page_size,
          total: data?.meta.total,
          showSizeChanger: true,
          showTotal: (t) => `${t} users`,
          onChange: (page, page_size) => setFilter((f) => ({ ...f, page, page_size })),
        }}
        columns={[
          {
            title: 'Name',
            render: (_, u) => (
              <div>
                <Typography.Text strong>{u.name}</Typography.Text>
                <br />
                <Typography.Text type="secondary">@{u.username}</Typography.Text>
              </div>
            ),
          },
          { title: 'Ref. no', dataIndex: 'reference_number', render: (v) => v ?? '—' },
          { title: 'Mobile', dataIndex: 'mobile', render: (v) => v ?? '—' },
          {
            title: 'Roles',
            render: (_, u) =>
              u.roles.map((r) => (
                <Tag key={r.id} color={ROLE_COLORS[r.slug]}>
                  {r.name}
                </Tag>
              )),
          },
          {
            title: 'Status',
            render: (_, u) => (u.is_active ? <Tag color="success">Active</Tag> : <Tag>Inactive</Tag>),
          },
          {
            title: 'Last login',
            dataIndex: 'last_login_at',
            render: (v) => (v ? dayjs(v).format('DD MMM YYYY, HH:mm') : 'Never'),
          },
          {
            title: '',
            width: 56,
            fixed: 'right',
            render: (_, u) => {
              const items = [
                can('user.update') && { key: 'edit', label: 'Edit details' },
                can('user.update') && { key: 'roles', label: 'Change roles' },
                can('user.update') && { key: 'password', label: 'Set password' },
                can('user.delete') && u.id !== me?.id && { key: 'toggle', label: u.is_active ? 'Deactivate' : 'Activate', danger: u.is_active },
              ].filter(Boolean) as { key: string; label: string; danger?: boolean }[];
              if (!items.length) return null;
              return (
                <Dropdown
                  trigger={['click']}
                  menu={{
                    items,
                    onClick: ({ key }) => {
                      if (key === 'edit') setDrawer({ open: true, user: u });
                      if (key === 'roles') setRolesFor(u);
                      if (key === 'password') setPasswordFor(u);
                      if (key === 'toggle')
                        Modal.confirm({
                          title: `${u.is_active ? 'Deactivate' : 'Activate'} ${u.name}?`,
                          content: u.is_active ? 'They will be signed out and unable to log in.' : undefined,
                          onOk: () => toggle.mutateAsync(u),
                        });
                    },
                  }}
                >
                  <Button type="text" icon={<MoreOutlined />} aria-label="Actions" />
                </Dropdown>
              );
            },
          },
        ]}
      />

      <UserDrawer open={drawer.open} user={drawer.user} onClose={() => setDrawer({ open: false, user: null })} />
      <RolesModal user={rolesFor} onClose={() => setRolesFor(null)} />
      <PasswordModal user={passwordFor} onClose={() => setPasswordFor(null)} />
    </Card>
  );
}
