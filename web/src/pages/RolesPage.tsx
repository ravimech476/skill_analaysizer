import { useMemo, useState } from 'react';
import { Alert, Button, Card, Checkbox, Drawer, Form, Input, Modal, Space, Table, Tag, Typography, message } from 'antd';
import { PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { permissionsApi, rolesApi } from '../api/endpoints';
import { errorMessage } from '../api/client';
import type { Role } from '../api/types';
import { useAuth } from '../auth/AuthContext';
import { ROLE_COLORS } from '../auth/access';

const ACTIONS = ['view', 'create', 'update', 'delete'];
const pretty = (s: string) => s.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

function PermissionMatrix({ role, onClose }: { role: Role | null; onClose: () => void }) {
  const qc = useQueryClient();
  const { can } = useAuth();
  const readOnly = !can('role.update') || role?.slug === 'admin';
  const { data: groups } = useQuery({ queryKey: ['permissions'], queryFn: permissionsApi.grouped });
  const { data: detail } = useQuery({
    queryKey: ['roles', role?.id],
    queryFn: () => rolesApi.get(role!.id),
    enabled: !!role,
  });
  const [selected, setSelected] = useState<Set<number> | null>(null);
  const current = selected ?? new Set(detail?.permission_ids ?? []);
  const allIds = useMemo(() => groups?.flatMap((g) => g.permissions.map((p) => p.id)) ?? [], [groups]);
  const isAdmin = role?.slug === 'admin';

  const save = useMutation({
    mutationFn: () => rolesApi.setPermissions(role!.id, [...current]),
    onSuccess: () => {
      message.success('Permissions saved');
      qc.invalidateQueries({ queryKey: ['roles'] });
      close();
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  const close = () => {
    setSelected(null);
    onClose();
  };
  const toggle = (ids: number[], on: boolean) => {
    const next = new Set(current);
    ids.forEach((id) => (on ? next.add(id) : next.delete(id)));
    setSelected(next);
  };

  return (
    <Drawer
      title={`Permissions: ${role?.name ?? ''}`}
      open={!!role}
      onClose={close}
      size={Math.min(720, window.innerWidth)}
      destroyOnHidden
      extra={
        !readOnly && (
          <Button type="primary" loading={save.isPending} onClick={() => save.mutate()}>
            Save
          </Button>
        )
      }
    >
      {isAdmin && <Alert type="info" showIcon style={{ marginBottom: 16 }} title="Admin always has every permission." />}
      <Table
        size="small"
        rowKey="module"
        pagination={false}
        dataSource={groups}
        scroll={{ x: 520 }}
        columns={[
          {
            title: 'Module',
            dataIndex: 'module',
            render: (m: string, g) => {
              const ids = g.permissions.map((p) => p.id);
              const n = ids.filter((id) => isAdmin || current.has(id)).length;
              return (
                <Checkbox
                  disabled={readOnly}
                  checked={n === ids.length}
                  indeterminate={n > 0 && n < ids.length}
                  onChange={(e) => toggle(ids, e.target.checked)}
                >
                  {pretty(m)}
                </Checkbox>
              );
            },
          },
          ...ACTIONS.map((a) => ({
            title: pretty(a),
            key: a,
            align: 'center' as const,
            render: (_: unknown, g: { permissions: { id: number; action: string }[] }) => {
              const p = g.permissions.find((x) => x.action === a);
              if (!p) return null;
              return (
                <Checkbox disabled={readOnly} checked={isAdmin || current.has(p.id)} onChange={(e) => toggle([p.id], e.target.checked)} />
              );
            },
          })),
        ]}
      />
      {!readOnly && (
        <Space style={{ marginTop: 12 }}>
          <Button size="small" onClick={() => setSelected(new Set(allIds))}>
            Select all
          </Button>
          <Button size="small" onClick={() => setSelected(new Set())}>
            Clear all
          </Button>
        </Space>
      )}
    </Drawer>
  );
}

function RoleFormModal({ role, open, onClose }: { role: Role | null; open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const [form] = Form.useForm();
  const [error, setError] = useState<string>();
  const save = useMutation({
    mutationFn: (v: { name: string; description?: string }) => (role ? rolesApi.update(role.id, v) : rolesApi.create(v)),
    onSuccess: () => {
      message.success(role ? 'Role updated' : 'Role created. Now choose its permissions.');
      qc.invalidateQueries({ queryKey: ['roles'] });
      onClose();
    },
    onError: (e) => setError(errorMessage(e)),
  });
  return (
    <Modal
      title={role ? 'Edit role' : 'New role'}
      open={open}
      onCancel={onClose}
      onOk={() => form.submit()}
      okButtonProps={{ loading: save.isPending }}
      destroyOnHidden
      afterOpenChange={(o) => {
        if (!o) return;
        setError(undefined);
        form.setFieldsValue({ name: role?.name, description: role?.description });
      }}
    >
      {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
      <Form form={form} layout="vertical" preserve={false} onFinish={(v) => save.mutate(v)}>
        <Form.Item name="name" label="Name" rules={[{ required: true }]}>
          <Input />
        </Form.Item>
        <Form.Item name="description" label="Description">
          <Input.TextArea rows={2} />
        </Form.Item>
      </Form>
    </Modal>
  );
}

export default function RolesPage() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['roles'], queryFn: rolesApi.list });
  const [matrixFor, setMatrixFor] = useState<Role | null>(null);
  const [form, setForm] = useState<{ open: boolean; role: Role | null }>({ open: false, role: null });

  const remove = useMutation({
    mutationFn: (r: Role) => rolesApi.remove(r.id),
    onSuccess: () => {
      message.success('Role deleted');
      qc.invalidateQueries({ queryKey: ['roles'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <Card
      extra={
        can('role.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setForm({ open: true, role: null })}>
            New role
          </Button>
        )
      }
    >
      <Table<Role>
        rowKey="id"
        loading={isLoading}
        dataSource={data}
        pagination={false}
        scroll={{ x: 700 }}
        columns={[
          {
            title: 'Role',
            render: (_, r) => (
              <div>
                <Tag color={ROLE_COLORS[r.slug] ?? 'default'}>{r.name}</Tag>
                {r.is_system && <Typography.Text type="secondary">system</Typography.Text>}
                <br />
                <Typography.Text type="secondary">{r.description}</Typography.Text>
              </div>
            ),
          },
          { title: 'Users', dataIndex: 'user_count', width: 90 },
          { title: 'Permissions', dataIndex: 'permission_count', width: 120 },
          {
            title: '',
            width: 260,
            render: (_, r) => (
              <Space>
                <Button size="small" onClick={() => setMatrixFor(r)}>
                  Permissions
                </Button>
                {can('role.update') && (
                  <Button size="small" onClick={() => setForm({ open: true, role: r })}>
                    Edit
                  </Button>
                )}
                {can('role.delete') && !r.is_system && (
                  <Button
                    size="small"
                    danger
                    onClick={() =>
                      Modal.confirm({ title: `Delete role "${r.name}"?`, onOk: () => remove.mutateAsync(r) })
                    }
                  >
                    Delete
                  </Button>
                )}
              </Space>
            ),
          },
        ]}
      />
      <PermissionMatrix role={matrixFor} onClose={() => setMatrixFor(null)} />
      <RoleFormModal open={form.open} role={form.role} onClose={() => setForm({ open: false, role: null })} />
    </Card>
  );
}
