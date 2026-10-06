import { useState } from 'react';
import { Alert, Button, Card, DatePicker, Drawer, Form, Input, Modal, Select, Space, Table, Tag, Typography, message } from 'antd';
import { PlusOutlined } from '@ant-design/icons';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import { staffApi, type Staff, type StaffInput } from '../api/phase2';
import { useDepartments } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';
import { ROLE_COLORS } from '../auth/access';
import { UserAvatar } from '../components/Files';

const STAFF_ROLES = [
  { value: 'staff', label: 'Staff' },
  { value: 'hod', label: 'HOD' },
  { value: 'placement_officer', label: 'Placement Officer' },
];

type FormValues = Omit<StaffInput, 'dob' | 'joined_on'> & { dob?: dayjs.Dayjs | null; joined_on?: dayjs.Dayjs | null };

function StaffDrawer({ row, open, onClose }: { row: Staff | null; open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const [form] = Form.useForm<FormValues>();
  const [error, setError] = useState<string>();
  const { data: depts } = useDepartments();

  const save = useMutation({
    mutationFn: (v: FormValues) => {
      const body: StaffInput = {
        ...v,
        dob: v.dob ? v.dob.format('YYYY-MM-DD') : null,
        joined_on: v.joined_on ? v.joined_on.format('YYYY-MM-DD') : null,
      };
      return row ? staffApi.update(row.id, body) : staffApi.create(body);
    },
    onSuccess: () => {
      message.success(row ? 'Staff updated' : 'Staff added');
      qc.invalidateQueries({ queryKey: ['staff'] });
      onClose();
    },
    onError: (e) => setError(errorMessage(e)),
  });

  return (
    <Drawer
      title={row ? `Edit ${row.name}` : 'New staff member'}
      open={open}
      onClose={onClose}
      size={Math.min(520, window.innerWidth)}
      forceRender
      afterOpenChange={(o) => {
        if (!o) return;
        setError(undefined);
        form.resetFields();
        form.setFieldsValue(
          row
            ? { ...row, dob: row.dob ? dayjs(row.dob) : null, joined_on: row.joined_on ? dayjs(row.joined_on) : null, roles: row.roles.filter((r) => STAFF_ROLES.some((s) => s.value === r)) } as FormValues
            : { roles: ['staff'] },
        );
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
        <Space style={{ display: 'flex' }} align="start">
          <Form.Item name="employee_code" label="Employee code" rules={[{ required: true }]} normalize={(v: string) => v?.toUpperCase()}>
            <Input />
          </Form.Item>
          <Form.Item name="username" label="Username" extra="Defaults to the employee code">
            <Input />
          </Form.Item>
        </Space>
        <Form.Item name="roles" label="Roles" rules={[{ required: true, message: 'Pick at least one role' }]}>
          <Select mode="multiple" options={STAFF_ROLES} />
        </Form.Item>
        <Form.Item name="department_id" label="Department">
          <Select allowClear showSearch optionFilterProp="label" options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
        </Form.Item>
        <Space style={{ display: 'flex' }} align="start">
          <Form.Item name="designation" label="Designation">
            <Input placeholder="Assistant Professor" />
          </Form.Item>
          <Form.Item name="qualification" label="Qualification">
            <Input placeholder="M.E., Ph.D." />
          </Form.Item>
        </Space>
        <Space style={{ display: 'flex' }} align="start">
          <Form.Item name="mobile" label="Mobile" rules={[{ pattern: /^[6-9]\d{9}$/, message: 'Valid 10-digit mobile' }]}>
            <Input maxLength={10} />
          </Form.Item>
          <Form.Item name="email" label="Email" rules={[{ type: 'email' }]}>
            <Input />
          </Form.Item>
        </Space>
        <Space style={{ display: 'flex' }} align="start">
          <Form.Item name="gender" label="Gender" style={{ minWidth: 140 }}>
            <Select allowClear options={['male', 'female', 'other'].map((g) => ({ value: g, label: g[0].toUpperCase() + g.slice(1) }))} />
          </Form.Item>
          <Form.Item name="dob" label="Date of birth">
            <DatePicker format="DD-MM-YYYY" disabledDate={(d) => d.isAfter(dayjs())} />
          </Form.Item>
          <Form.Item name="joined_on" label="Joined on">
            <DatePicker format="DD-MM-YYYY" disabledDate={(d) => d.isAfter(dayjs())} />
          </Form.Item>
        </Space>
        {!row && (
          <Form.Item name="password" label="Password" rules={[{ min: 8 }]} extra="Optional. Without one, they sign in with OTP.">
            <Input.Password autoComplete="new-password" />
          </Form.Item>
        )}
      </Form>
    </Drawer>
  );
}

export default function StaffPage() {
  const { can, user } = useAuth();
  const qc = useQueryClient();
  const { data: depts } = useDepartments();
  const [filter, setFilter] = useState<{ page: number; page_size: number; search?: string; department_id?: number; role?: string; status?: string }>({ page: 1, page_size: 20 });
  const [drawer, setDrawer] = useState<{ open: boolean; row: Staff | null }>({ open: false, row: null });

  const { data, isFetching } = useQuery({ queryKey: ['staff', filter], queryFn: () => staffApi.list(filter), placeholderData: keepPreviousData });

  const toggle = useMutation({
    mutationFn: (s: Staff) => staffApi.setStatus(s.id, !s.is_active),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['staff'] }),
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <Card
      title={<span style={{ fontWeight: 600 }}>{data?.meta.total ?? 0} staff members</span>}
      extra={
        can('staff.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setDrawer({ open: true, row: null })}>
            New staff
          </Button>
        )
      }
    >
      <Space wrap style={{ marginBottom: 16 }}>
        <Input.Search allowClear placeholder="Name, employee code, mobile" style={{ width: 260 }} onSearch={(search) => setFilter((f) => ({ ...f, search, page: 1 }))} />
        <Select allowClear placeholder="All departments" style={{ width: 220 }} options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} onChange={(department_id) => setFilter((f) => ({ ...f, department_id, page: 1 }))} />
        <Select allowClear placeholder="All roles" style={{ width: 180 }} options={STAFF_ROLES} onChange={(role) => setFilter((f) => ({ ...f, role, page: 1 }))} />
        {can('staff.delete') && (
          <Select
            style={{ width: 130 }}
            defaultValue="active"
            options={[{ value: 'active', label: 'Active' }, { value: 'inactive', label: 'Inactive' }, { value: 'all', label: 'All' }]}
            onChange={(status) => setFilter((f) => ({ ...f, status, page: 1 }))}
          />
        )}
      </Space>
      <Table<Staff>
        rowKey="id"
        loading={isFetching}
        dataSource={data?.data}
        scroll={{ x: 900 }}
        pagination={{
          current: filter.page,
          pageSize: filter.page_size,
          total: data?.meta.total,
          showTotal: (t) => `${t} staff`,
          onChange: (page, page_size) => setFilter((f) => ({ ...f, page, page_size })),
        }}
        columns={[
          {
            title: 'Name',
            render: (_, s) => (
              <Space>
                <UserAvatar name={s.name} photo={s.photo} />
                <div>
                  <Typography.Text strong>{s.name}</Typography.Text>
                  <br />
                  <Typography.Text type="secondary">{s.designation ?? '@' + s.username}</Typography.Text>
                </div>
              </Space>
            ),
          },
          { title: 'Emp. code', dataIndex: 'employee_code', render: (v) => v ?? '—' },
          { title: 'Department', dataIndex: 'department_name', render: (v) => v ?? '—' },
          { title: 'Roles', dataIndex: 'roles', render: (roles: string[]) => roles.map((r) => <Tag key={r} color={ROLE_COLORS[r]}>{r.replace('_', ' ')}</Tag>) },
          { title: 'Class incharge', dataIndex: 'incharge_of', render: (v) => (v ? <Tag>{v}</Tag> : '—') },
          { title: 'Mobile', dataIndex: 'mobile', render: (v) => v ?? '—' },
          {
            title: '',
            key: 'actions',
            width: 190,
            align: 'right',
            render: (_, s) => (
              <Space>
                {can('staff.update') && (
                  <Button size="small" onClick={() => setDrawer({ open: true, row: s })}>
                    Edit
                  </Button>
                )}
                {can('staff.delete') && s.id !== user?.id && (
                  <Button
                    size="small"
                    danger={s.is_active}
                    onClick={() =>
                      Modal.confirm({
                        title: `${s.is_active ? 'Deactivate' : 'Activate'} ${s.name}?`,
                        onOk: () => toggle.mutateAsync(s),
                      })
                    }
                  >
                    {s.is_active ? 'Deactivate' : 'Activate'}
                  </Button>
                )}
              </Space>
            ),
          },
        ]}
      />
      <StaffDrawer open={drawer.open} row={drawer.row} onClose={() => setDrawer({ open: false, row: null })} />
    </Card>
  );
}
