import { useState } from 'react';
import { Alert, Button, Card, Drawer, Form, Input, Modal, Select, Space, Table, Tag, Typography, message } from 'antd';
import { PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { classesApi, studentsApi, type ClassInput, type ClassRow } from '../api/phase2';
import { useAcademicYears, useDepartments, useSemesters, useStaffOptions, useYearLevels } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';

function ClassForm({ row, open, onClose }: { row: ClassRow | null; open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const [form] = Form.useForm<ClassInput>();
  const [error, setError] = useState<string>();
  const { data: depts } = useDepartments();
  const { data: years } = useAcademicYears();
  const { data: levels } = useYearLevels();
  const { data: staff } = useStaffOptions();
  const { data: sems } = useSemesters();
  const levelId = Form.useWatch('year_level_id', form);

  const save = useMutation({
    mutationFn: (v: ClassInput) => {
      const body = { ...v, class_incharge_id: v.class_incharge_id ?? null, current_semester_id: v.current_semester_id ?? null };
      return row ? classesApi.update(row.id, body) : classesApi.create(body);
    },
    onSuccess: () => {
      message.success(row ? 'Class updated' : 'Class created');
      qc.invalidateQueries({ queryKey: ['classes'] });
      qc.invalidateQueries({ queryKey: ['staff'] });
      onClose();
    },
    onError: (e) => setError(errorMessage(e)),
  });

  return (
    <Modal
      title={row ? `Edit ${row.label}` : 'New class'}
      open={open}
      onCancel={onClose}
      onOk={() => form.submit()}
      okButtonProps={{ loading: save.isPending }}
      forceRender
      afterOpenChange={(o) => {
        if (!o) return;
        setError(undefined);
        form.resetFields();
        form.setFieldsValue(
          row
            ? { department_id: row.department_id, academic_year_id: row.academic_year_id, year_level_id: row.year_level_id, section: row.section, class_incharge_id: row.class_incharge_id, current_semester_id: row.current_semester_id }
            : { academic_year_id: years?.find((y) => y.is_current)?.id, section: 'A' },
        );
      }}
    >
      {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
      <Form form={form} layout="vertical" onFinish={(v) => save.mutate(v)} requiredMark="optional">
        <Form.Item name="department_id" label="Department" rules={[{ required: true }]}>
          <Select showSearch optionFilterProp="label" options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
        </Form.Item>
        <Form.Item name="academic_year_id" label="Academic year" rules={[{ required: true }]}>
          <Select options={(years ?? []).map((y) => ({ value: y.id, label: y.is_current ? `${y.name} (current)` : y.name }))} />
        </Form.Item>
        <Space style={{ display: 'flex' }} align="start">
          <Form.Item name="year_level_id" label="Year of study" rules={[{ required: true }]} style={{ minWidth: 180 }}>
            <Select options={(levels ?? []).map((l) => ({ value: l.id, label: l.name }))} onChange={() => form.setFieldValue('current_semester_id', null)} />
          </Form.Item>
          <Form.Item name="current_semester_id" label="Current semester" extra="Default: first semester of the year" style={{ minWidth: 170 }}>
            <Select allowClear disabled={!levelId} options={(sems ?? []).filter((s) => s.year_level_id === levelId).map((s) => ({ value: s.id, label: s.name }))} />
          </Form.Item>
          <Form.Item name="section" label="Section" rules={[{ required: true }]} normalize={(v: string) => v?.toUpperCase()}>
            <Input maxLength={5} style={{ width: 100 }} />
          </Form.Item>
        </Space>
        <Form.Item name="class_incharge_id" label="Class incharge" extra="A staff member can be incharge of only one class per academic year">
          <Select
            allowClear
            showSearch
            optionFilterProp="label"
            placeholder="Select staff"
            options={(staff ?? [])
              .filter((s) => s.roles.includes('staff') || s.roles.includes('hod'))
              .map((s) => ({ value: s.id, label: `${s.name}${s.incharge_of ? ` (incharge of ${s.incharge_of})` : ''}` }))}
          />
        </Form.Item>
      </Form>
    </Modal>
  );
}

function ClassStudents({ row, onClose }: { row: ClassRow | null; onClose: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['students', 'class', row?.id],
    queryFn: () => studentsApi.list({ class_id: row!.id, page: 1, page_size: 200 }),
    enabled: !!row,
  });
  return (
    <Drawer title={row ? `${row.label} · ${row.academic_year_name}` : ''} open={!!row} onClose={onClose} size={Math.min(640, window.innerWidth)}>
      {row && (
        <Typography.Paragraph>
          Class incharge: <b>{row.class_incharge_name ?? 'not assigned'}</b>
        </Typography.Paragraph>
      )}
      <Table
        rowKey="id"
        size="small"
        loading={isLoading}
        dataSource={data?.data}
        pagination={false}
        columns={[
          { title: 'Register no', dataIndex: 'register_no', width: 130 },
          { title: 'Name', dataIndex: 'name' },
          { title: 'Mobile', dataIndex: 'mobile', render: (v) => v ?? '—' },
        ]}
      />
    </Drawer>
  );
}

export default function ClassesPage() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data: years } = useAcademicYears();
  const { data: depts } = useDepartments();
  const [yearId, setYearId] = useState<number | 'all'>();
  const [deptId, setDeptId] = useState<number>();
  const [form, setForm] = useState<{ open: boolean; row: ClassRow | null }>({ open: false, row: null });
  const [viewing, setViewing] = useState<ClassRow | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['classes', 'page', yearId ?? null, deptId ?? null],
    queryFn: () => classesApi.list({ academic_year_id: yearId, department_id: deptId }),
  });

  const remove = useMutation({
    mutationFn: (r: ClassRow) => classesApi.remove(r.id),
    onSuccess: () => {
      message.success('Class deleted');
      qc.invalidateQueries({ queryKey: ['classes'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <Card
      title={<span style={{ fontWeight: 600 }}>{data?.length ?? 0} classes</span>}
      extra={
        can('class.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setForm({ open: true, row: null })}>
            New class
          </Button>
        )
      }
    >
      <Space wrap style={{ marginBottom: 16 }}>
        <Select
          style={{ width: 200 }}
          placeholder="Current academic year"
          allowClear
          value={yearId}
          onChange={setYearId}
          options={[{ value: 'all', label: 'All years' }, ...(years ?? []).map((y) => ({ value: y.id, label: y.is_current ? `${y.name} (current)` : y.name }))]}
        />
        <Select
          style={{ width: 240 }}
          placeholder="All departments"
          allowClear
          value={deptId}
          onChange={setDeptId}
          options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))}
        />
      </Space>
      <Table<ClassRow>
        rowKey="id"
        loading={isLoading}
        dataSource={data}
        pagination={{ pageSize: 25, hideOnSinglePage: true }}
        scroll={{ x: 760 }}
        onRow={(r) => ({ onClick: () => setViewing(r), style: { cursor: 'pointer' } })}
        columns={[
          { title: 'Class', dataIndex: 'label', render: (v) => <Typography.Text strong>{v}</Typography.Text> },
          { title: 'Department', dataIndex: 'department_name' },
          { title: 'Semester', dataIndex: 'current_semester_name', width: 120, render: (v) => v ?? '—' },
          { title: 'Academic year', dataIndex: 'academic_year_name', render: (v, r) => <Space>{v}{r.is_current_year && <Tag color="green">current</Tag>}</Space> },
          { title: 'Class incharge', dataIndex: 'class_incharge_name', render: (v) => v ?? <Typography.Text type="secondary">Not assigned</Typography.Text> },
          { title: 'Students', dataIndex: 'student_count', width: 100 },
          {
            title: '',
            key: 'actions',
            width: 160,
            align: 'right',
            render: (_, r) => (
              <Space onClick={(e) => e.stopPropagation()}>
                {can('class.update') && (
                  <Button size="small" onClick={() => setForm({ open: true, row: r })}>
                    Edit
                  </Button>
                )}
                {can('class.delete') && (
                  <Button size="small" danger onClick={() => Modal.confirm({ title: `Delete ${r.label}?`, onOk: () => remove.mutateAsync(r) })}>
                    Delete
                  </Button>
                )}
              </Space>
            ),
          },
        ]}
      />
      <ClassForm open={form.open} row={form.row} onClose={() => setForm({ open: false, row: null })} />
      <ClassStudents row={viewing} onClose={() => setViewing(null)} />
    </Card>
  );
}
