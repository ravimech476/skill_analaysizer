import { useState, type ReactNode } from 'react';
import { Alert, Button, DatePicker, Form, Input, InputNumber, Modal, Select, Space, Switch, Table, message } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import { mastersApi, type MasterPath } from '../api/phase2';
import { useStaffOptions } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';

export interface MasterField {
  name: string;
  label: string;
  type: 'text' | 'upper' | 'number' | 'date' | 'bool' | 'select' | 'staff';
  required?: boolean;
  options?: { value: string | number; label: string }[];
  min?: number;
  max?: number;
  extra?: string;
}

interface Props<T> {
  path: MasterPath;
  perm: string; // permission module, e.g. "department"
  noun: string; // "department"
  columns: ColumnsType<T>;
  fields: MasterField[];
  searchable?: boolean;
  toolbar?: ReactNode;
}

function StaffSelect(props: { value?: number | null; onChange?: (v: number | null) => void }) {
  const { data } = useStaffOptions();
  return (
    <Select
      allowClear
      showSearch
      optionFilterProp="label"
      value={props.value ?? undefined}
      onChange={(v) => props.onChange?.(v ?? null)}
      options={(data ?? []).map((s) => ({ value: s.id, label: `${s.name}${s.employee_code ? ` (${s.employee_code})` : ''}` }))}
      placeholder="Select staff"
    />
  );
}

export default function MasterCrud<T extends { id: number; is_active: boolean }>({ path, perm, noun, columns, fields, searchable = true, toolbar }: Props<T>) {
  const { can } = useAuth();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<{ open: boolean; row: T | null }>({ open: false, row: null });
  const [error, setError] = useState<string>();
  const [form] = Form.useForm();

  const { data, isLoading } = useQuery({
    queryKey: ['master', path, search],
    queryFn: () => mastersApi.list<T>(path, { all: true, search }),
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ['master', path] });
    qc.invalidateQueries({ queryKey: ['lookup', path] });
  };

  const save = useMutation({
    mutationFn: (values: Record<string, unknown>) => {
      const body: Record<string, unknown> = { ...values };
      for (const f of fields) {
        if (f.type === 'date') body[f.name] = values[f.name] ? (values[f.name] as dayjs.Dayjs).format('YYYY-MM-DD') : null;
        if (f.type === 'bool') body[f.name] = !!values[f.name];
      }
      return editing.row ? mastersApi.update<T>(path, editing.row.id, body) : mastersApi.create<T>(path, body);
    },
    onSuccess: () => {
      message.success(editing.row ? `${cap(noun)} updated` : `${cap(noun)} created`);
      invalidate();
      setEditing({ open: false, row: null });
    },
    onError: (e) => setError(errorMessage(e)),
  });

  const remove = useMutation({
    mutationFn: (row: T) => mastersApi.remove(path, row.id),
    onSuccess: () => {
      message.success(`${cap(noun)} deleted`);
      invalidate();
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  const open = (row: T | null) => {
    setError(undefined);
    form.resetFields();
    if (row) {
      const values: Record<string, unknown> = { ...row };
      for (const f of fields) if (f.type === 'date') values[f.name] = row[f.name as keyof T] ? dayjs(row[f.name as keyof T] as string) : null;
      form.setFieldsValue(values);
    }
    setEditing({ open: true, row });
  };

  const actionCol: ColumnsType<T> =
    can(`${perm}.update`) || can(`${perm}.delete`)
      ? [
          {
            title: '',
            key: 'actions',
            width: 150,
            align: 'right',
            render: (_, row) => (
              <Space>
                {can(`${perm}.update`) && (
                  <Button size="small" onClick={() => open(row)}>
                    Edit
                  </Button>
                )}
                {can(`${perm}.delete`) && (
                  <Button size="small" danger onClick={() => Modal.confirm({ title: `Delete this ${noun}?`, onOk: () => remove.mutateAsync(row) })}>
                    Delete
                  </Button>
                )}
              </Space>
            ),
          },
        ]
      : [];

  return (
    <>
      <Space wrap style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Space wrap>
          {searchable && <Input.Search allowClear placeholder={`Search ${noun}s`} style={{ width: 260 }} onSearch={setSearch} />}
          {toolbar}
        </Space>
        {can(`${perm}.create`) && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => open(null)}>
            New {noun}
          </Button>
        )}
      </Space>
      <Table<T> rowKey="id" loading={isLoading} dataSource={data?.data} columns={[...columns, ...actionCol]} pagination={{ pageSize: 20, hideOnSinglePage: true }} scroll={{ x: 640 }} />

      <Modal
        title={editing.row ? `Edit ${noun}` : `New ${noun}`}
        open={editing.open}
        onCancel={() => setEditing({ open: false, row: null })}
        onOk={() => form.submit()}
        okButtonProps={{ loading: save.isPending }}
        forceRender
      >
        {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
        <Form form={form} layout="vertical" onFinish={(v) => save.mutate(v)} requiredMark="optional">
          {fields.map((f) => (
            <Form.Item
              key={f.name}
              name={f.name}
              label={f.label}
              extra={f.extra}
              valuePropName={f.type === 'bool' ? 'checked' : 'value'}
              rules={f.required ? [{ required: true, message: `${f.label} is required` }] : undefined}
              normalize={f.type === 'upper' ? (v: string) => v?.toUpperCase() : undefined}
            >
              {f.type === 'number' ? (
                <InputNumber min={f.min} max={f.max} style={{ width: '100%' }} />
              ) : f.type === 'date' ? (
                <DatePicker style={{ width: '100%' }} format="DD-MM-YYYY" />
              ) : f.type === 'bool' ? (
                <Switch />
              ) : f.type === 'select' ? (
                <Select options={f.options} />
              ) : f.type === 'staff' ? (
                <StaffSelect />
              ) : (
                <Input />
              )}
            </Form.Item>
          ))}
        </Form>
      </Modal>
    </>
  );
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
