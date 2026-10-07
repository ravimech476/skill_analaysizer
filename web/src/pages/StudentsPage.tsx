import { useEffect, useState } from 'react';
import {
  Alert,
  AutoComplete,
  Button,
  Card,
  Col,
  DatePicker,
  Descriptions,
  Drawer,
  Empty,
  Form,
  Input,
  InputNumber,
  Modal,
  Rate,
  Row,
  Select,
  Space,
  Spin,
  Switch,
  Table,
  Tabs,
  Tag,
  Typography,
  message,
} from 'antd';
import { DownloadOutlined, MinusCircleOutlined, PlusOutlined } from '@ant-design/icons';
import { exportsApi } from '../api/reports';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { api, errorMessage } from '../api/client';
import { studentsApi, type ParentInput, type Student, type StudentInput } from '../api/phase2';
import { useClasses, useDepartments } from '../api/lookups';
import { placementApi } from '../api/placement';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { MarkHistoryView } from './MarksPage';
import { lifecycleApi, LIFECYCLE_COLORS } from '../api/lifecycle';
import { StudentSkillsEditor } from './SkillsPage';
import { filesApi } from '../api/files';
import { FileSlot, UploadButton, UserAvatar } from '../components/Files';
import StudentDocuments from '../components/StudentDocuments';
import { StudentsUpload as StudentsUploadTab, SkillsUpload as SkillsUploadTab } from './BulkUploadPage';

const RELATIONS = [
  { value: 'father', label: 'Father' },
  { value: 'mother', label: 'Mother' },
  { value: 'guardian', label: 'Guardian' },
];
const GENDERS = ['male', 'female', 'other'].map((g) => ({ value: g, label: g[0].toUpperCase() + g.slice(1) }));
const mobileRule = { pattern: /^[6-9]\d{9}$/, message: 'Valid 10-digit mobile' };

// ---------- create / edit ----------

type FormValues = Omit<StudentInput, 'dob'> & { dob?: dayjs.Dayjs | null; skills?: { name: string; proficiency: number }[] };

function StudentForm({ row, open, onClose }: { row: Student | null; open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const [form] = Form.useForm<FormValues>();
  const [error, setError] = useState<string>();
  const { data: depts } = useDepartments();
  const deptId = Form.useWatch('department_id', form);
  const { data: classes } = useClasses(deptId);
  const { data: skillOptions } = useQuery({
    queryKey: ['lookup', 'skills'],
    queryFn: async () => {
      const r = await api.get('/skills', { params: { all: true } });
      return r.data.data as Array<{ id: number; name: string; category: string }>;
    },
    staleTime: 5 * 60_000,
  });
  const { data: studentSkills } = useQuery({
    queryKey: ['student-skills', row?.id],
    queryFn: () => placementApi.studentSkills(row!.id),
    enabled: !!row?.id,
  });

  useEffect(() => {
    if (studentSkills && open) {
      form.setFieldValue('skills', studentSkills.map((s: any) => ({ name: s.name, proficiency: s.proficiency })));
    }
  }, [studentSkills, open]);

  const save = useMutation({
    mutationFn: (v: FormValues) => {
      const body: StudentInput = { ...v, dob: v.dob ? v.dob.format('YYYY-MM-DD') : null, class_id: v.class_id ?? null, skills: v.skills };
      return row ? studentsApi.update(row.id, body) : studentsApi.create(body);
    },
    onSuccess: () => {
      message.success(row ? 'Student updated' : 'Student added');
      qc.invalidateQueries({ queryKey: ['students'] });
      qc.invalidateQueries({ queryKey: ['classes'] });
      qc.invalidateQueries({ queryKey: ['student-skills'] });
      onClose();
    },
    onError: (e) => setError(errorMessage(e)),
  });

  return (
    <Drawer
      title={row ? `Edit ${row.name}` : 'New student'}
      open={open}
      onClose={onClose}
      size={Math.min(600, window.innerWidth)}
      forceRender
      afterOpenChange={(o) => {
        if (!o) return;
        setError(undefined);
        form.resetFields();
        form.setFieldsValue(
          row
            ? ({ ...row, dob: row.dob ? dayjs(row.dob) : null } as unknown as FormValues)
            : { admission_year: dayjs().year(), parents: [{ relation: 'father', name: '', mobile: '' }] },
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
        <Row gutter={12}>
          <Col xs={24} sm={14}>
            <Form.Item name="name" label="Full name" rules={[{ required: true }]}>
              <Input />
            </Form.Item>
          </Col>
          <Col xs={24} sm={10}>
            <Form.Item name="register_no" label="Register number" rules={[{ required: true }]} normalize={(v: string) => v?.toUpperCase()}>
              <Input />
            </Form.Item>
          </Col>
          <Col xs={24} sm={12}>
            <Form.Item name="department_id" label="Department" rules={[{ required: true }]}>
              <Select
                showSearch
                optionFilterProp="label"
                options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))}
                onChange={() => form.setFieldValue('class_id', null)}
              />
            </Form.Item>
          </Col>
          <Col xs={24} sm={12}>
            <Form.Item name="class_id" label="Class" extra={deptId && !classes?.length ? 'No classes for this department in the current year' : undefined}>
              <Select allowClear disabled={!deptId} options={(classes ?? []).map((c) => ({ value: c.id, label: `${c.label} · ${c.academic_year_name}` }))} />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="admission_year" label="Admission year" rules={[{ required: true }]}>
              <InputNumber min={1990} max={dayjs().year() + 1} style={{ width: '100%' }} />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="batch" label="Batch" extra="Default: admission + 4" rules={[{ pattern: /^\d{4}-\d{4}$/, message: 'e.g. 2023-2027' }]}>
              <Input placeholder="2023-2027" />
            </Form.Item>
          </Col>
          <Col xs={24} sm={8}>
            <Form.Item name="username" label="Username" extra="Default: register no.">
              <Input />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="gender" label="Gender">
              <Select allowClear options={GENDERS} />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="dob" label="Date of birth">
              <DatePicker format="DD-MM-YYYY" style={{ width: '100%' }} disabledDate={(d) => d.isAfter(dayjs())} />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="blood_group" label="Blood group">
              <Input maxLength={5} />
            </Form.Item>
          </Col>
          <Col xs={12} sm={12}>
            <Form.Item name="mobile" label="Mobile" rules={[mobileRule]}>
              <Input maxLength={10} />
            </Form.Item>
          </Col>
          <Col xs={24} sm={12}>
            <Form.Item name="email" label="Email" rules={[{ type: 'email' }]}>
              <Input />
            </Form.Item>
          </Col>
          <Col span={24}>
            <Form.Item name="address" label="Address">
              <Input.TextArea rows={2} />
            </Form.Item>
          </Col>
          {!row && (
            <Col span={24}>
              <Form.Item name="password" label="Password" rules={[{ min: 8 }]} extra="Optional. Without one, the student signs in with OTP.">
                <Input.Password autoComplete="new-password" />
              </Form.Item>
            </Col>
          )}
        </Row>

        {!row && (
          <>
            <Typography.Title level={5}>Parents / guardians</Typography.Title>
            <Typography.Paragraph type="secondary" style={{ marginTop: -4 }}>
              A parent account is created on first use and reused for siblings with the same mobile number. Parents log in with OTP.
            </Typography.Paragraph>
            <Form.List name="parents">
              {(fields, { add, remove }) => (
                <>
                  {fields.map((f) => (
                    <Row gutter={8} key={f.key} align="top">
                      <Col xs={24} sm={8}>
                        <Form.Item name={[f.name, 'name']} rules={[{ required: true, message: 'Name' }]}>
                          <Input placeholder="Name" />
                        </Form.Item>
                      </Col>
                      <Col xs={12} sm={7}>
                        <Form.Item name={[f.name, 'mobile']} rules={[{ required: true, message: 'Mobile' }, mobileRule]}>
                          <Input placeholder="Mobile" maxLength={10} />
                        </Form.Item>
                      </Col>
                      <Col xs={10} sm={7}>
                        <Form.Item name={[f.name, 'relation']}>
                          <Select options={RELATIONS} />
                        </Form.Item>
                      </Col>
                      <Col xs={2} sm={2}>
                        <Button type="text" icon={<MinusCircleOutlined />} onClick={() => remove(f.name)} aria-label="Remove parent" />
                      </Col>
                    </Row>
                  ))}
                  {fields.length < 3 && (
                    <Button type="dashed" icon={<PlusOutlined />} onClick={() => add({ relation: fields.length === 0 ? 'father' : 'mother' })}>
                      Add parent
                    </Button>
                  )}
                </>
              )}
            </Form.List>
          </>
        )}

        <Typography.Title level={5}>Skills</Typography.Title>
        <Form.Item label="Skills">
          <Form.List name="skills">
            {(fields, { add, remove }) => (
              <>
                {fields.map(({ key, name, ...restField }) => (
                  <Space key={key} align="start" style={{ display: 'flex', marginBottom: 8 }}>
                    <Form.Item {...restField} name={[name, 'name']} rules={[{ required: true, message: 'Skill name' }]} style={{ marginBottom: 0 }}>
                      <AutoComplete
                        style={{ width: 200 }}
                        placeholder="Type or pick skill"
                        options={(skillOptions ?? []).map((s) => ({ value: s.name, label: s.name }))}
                        filterOption={(input, option) => (option?.label as string)?.toLowerCase().includes(input.toLowerCase())}
                      />
                    </Form.Item>
                    <Form.Item {...restField} name={[name, 'proficiency']} rules={[{ required: true, message: 'Level' }]} style={{ marginBottom: 0 }}>
                      <Rate count={5} />
                    </Form.Item>
                    <MinusCircleOutlined onClick={() => remove(name)} />
                  </Space>
                ))}
                <Button type="dashed" onClick={() => add({ proficiency: 3 })} icon={<PlusOutlined />} style={{ width: '100%' }}>
                  Add Skill
                </Button>
              </>
            )}
          </Form.List>
        </Form.Item>
      </Form>
    </Drawer>
  );
}

// ---------- detail ----------

function AddParentModal({ student, open, onClose }: { student: Student; open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const [form] = Form.useForm<ParentInput & { existing?: string }>();
  const [search, setSearch] = useState('');
  const [existingId, setExistingId] = useState<number>();
  const { data: matches } = useQuery({ queryKey: ['parents', search], queryFn: () => studentsApi.parents(search), enabled: search.length >= 3 });

  const save = useMutation({
    mutationFn: (v: ParentInput) => studentsApi.addParent(student.id, existingId ? { id: existingId, relation: v.relation, is_primary: v.is_primary } : v),
    onSuccess: () => {
      message.success('Parent linked');
      qc.invalidateQueries({ queryKey: ['students'] });
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <Modal
      title={`Add parent for ${student.name}`}
      open={open}
      onCancel={onClose}
      onOk={() => form.submit()}
      okButtonProps={{ loading: save.isPending }}
      forceRender
      afterOpenChange={(o) => {
        if (o) {
          form.resetFields();
          form.setFieldsValue({ relation: 'guardian' });
          setExistingId(undefined);
        }
      }}
    >
      <Form form={form} layout="vertical" onFinish={(v) => save.mutate(v)}>
        <Form.Item label="Link an existing parent (search name or mobile)">
          <AutoComplete
            allowClear
            onSearch={setSearch}
            onSelect={(_, o) => {
              setExistingId(o.id);
              form.setFieldsValue({ name: o.pname, mobile: o.mobile ?? '' });
            }}
            onClear={() => setExistingId(undefined)}
            options={(matches ?? []).map((p) => ({
              value: `${p.name} · ${p.mobile ?? ''}`,
              label: `${p.name} · ${p.mobile ?? ''}${p.children.length ? ` (parent of ${p.children.join(', ')})` : ''}`,
              id: p.id,
              pname: p.name,
              mobile: p.mobile,
            }))}
          />
        </Form.Item>
        <Typography.Paragraph type="secondary">…or enter a new parent:</Typography.Paragraph>
        <Form.Item name="name" label="Name" rules={[{ required: !existingId }]}>
          <Input disabled={!!existingId} />
        </Form.Item>
        <Form.Item name="mobile" label="Mobile" rules={existingId ? [] : [{ required: true }, mobileRule]}>
          <Input maxLength={10} disabled={!!existingId} />
        </Form.Item>
        <Form.Item name="email" label="Email" rules={[{ type: 'email' }]}>
          <Input disabled={!!existingId} />
        </Form.Item>
        <Space>
          <Form.Item name="relation" label="Relation">
            <Select options={RELATIONS} style={{ width: 160 }} />
          </Form.Item>
          <Form.Item name="is_primary" label="Primary contact" valuePropName="checked">
            <Switch />
          </Form.Item>
        </Space>
      </Form>
    </Modal>
  );
}

export function StudentProfile({ id, onEdit }: { id: number; onEdit?: (s: Student) => void }) {
  const { can, user, reload } = useAuth();
  const aud = audienceOf(user?.roles ?? []);
  const isSelf = user?.id === id;
  // Photos and resumes: the student themself, or staff of the department (the server checks the scope).
  const canFiles = isSelf || aud === 'admin' || aud === 'staff';
  const qc = useQueryClient();
  const refreshStudent = () => {
    qc.invalidateQueries({ queryKey: ['students'] });
    if (isSelf) reload();
  };
  const [adding, setAdding] = useState(false);
  const { data: s, isLoading } = useQuery({ queryKey: ['students', 'detail', id], queryFn: () => studentsApi.get(id) });

  const unlink = useMutation({
    mutationFn: (parentId: number) => studentsApi.removeParent(id, parentId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['students'] }),
    onError: (e) => message.error(errorMessage(e)),
  });
  const toggle = useMutation({
    mutationFn: () => studentsApi.setStatus(id, !s!.is_active),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['students'] }),
    onError: (e) => message.error(errorMessage(e)),
  });
  const { data: history } = useQuery({ queryKey: ['students', 'history', id], queryFn: () => lifecycleApi.history(id) });
  const [readmit, setReadmit] = useState<{ open: boolean; classId?: number; remarks?: string }>({ open: false });
  const { data: readmitClasses } = useClasses(s?.department_id ?? undefined);
  const lifecycle = useMutation({
    mutationFn: (b: { action: 'discontinue' | 'readmit'; class_id?: number; remarks?: string }) => lifecycleApi.studentAction(id, b),
    onSuccess: () => {
      message.success('Student updated');
      setReadmit({ open: false });
      qc.invalidateQueries({ queryKey: ['students'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const discontinue = () => {
    let remarks = '';
    Modal.confirm({
      title: `Discontinue ${s?.name}?`,
      content: <Input placeholder="Reason (optional)" onChange={(e) => (remarks = e.target.value)} />,
      okButtonProps: { danger: true },
      onOk: () => lifecycle.mutateAsync({ action: 'discontinue', remarks: remarks || undefined }),
    });
  };

  if (isLoading || !s) return <Spin />;
  const canEdit = can('student.update');

  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      <Descriptions
        bordered
        size="small"
        column={{ xs: 1, sm: 2 }}
        title={
          <Space wrap>
            <UserAvatar name={s.name} photo={s.photo} size={56} />
            {s.name}
            {!s.is_active && <Tag color="red">Inactive</Tag>}
            {s.lifecycle_status !== 'studying' && (
              <Tag color={LIFECYCLE_COLORS[s.lifecycle_status]}>
                {s.lifecycle_status === 'passed_out' ? `Passed out ${s.passed_out_year ?? ''}` : 'Discontinued'}
              </Tag>
            )}
          </Space>
        }
        extra={
          <Space>
            {canEdit && onEdit && <Button onClick={() => onEdit(s)}>Edit</Button>}
            {can('promotion.create') && s.lifecycle_status === 'studying' && <Button danger onClick={discontinue}>Discontinue</Button>}
            {can('promotion.create') && s.lifecycle_status !== 'studying' && <Button onClick={() => setReadmit({ open: true })}>Re-admit</Button>}
            {can('student.delete') && (
              <Button danger={s.is_active} onClick={() => Modal.confirm({ title: `${s.is_active ? 'Deactivate' : 'Activate'} ${s.name}?`, onOk: () => toggle.mutateAsync() })}>
                {s.is_active ? 'Deactivate' : 'Activate'}
              </Button>
            )}
          </Space>
        }
      >
        <Descriptions.Item label="Register no">{s.register_no}</Descriptions.Item>
        <Descriptions.Item label="Username">{s.username}</Descriptions.Item>
        <Descriptions.Item label="Department">{s.department_name ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Class">{s.class_label ? <Tag>{s.class_label}</Tag> : '—'}</Descriptions.Item>
        <Descriptions.Item label="Class incharge">{s.class_incharge_name ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Batch">{s.batch}</Descriptions.Item>
        <Descriptions.Item label="CGPA">{s.cgpa ? s.cgpa.toFixed(2) : '—'}</Descriptions.Item>
        <Descriptions.Item label="Backlogs">{s.backlog_count}</Descriptions.Item>
        <Descriptions.Item label="Mobile">{s.mobile ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Email">{s.email ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Gender">{s.gender ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Date of birth">{s.dob ? dayjs(s.dob).format('DD MMM YYYY') : '—'}</Descriptions.Item>
        <Descriptions.Item label="Blood group">{s.blood_group ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Address">{s.address ?? '—'}</Descriptions.Item>
        {s.status_remarks && <Descriptions.Item label="Status note">{s.status_remarks}</Descriptions.Item>}
        <Descriptions.Item label="Photo">
          {canFiles ? (
            <Space wrap>
              <UploadButton size="small" category="profile_photo" onUploaded={(f) => filesApi.setUserPhoto(id, f.id).then(refreshStudent)}>
                {s.photo ? 'Change photo' : 'Upload photo'}
              </UploadButton>
              {s.photo && (
                <Button size="small" danger onClick={() => filesApi.setUserPhoto(id, null).then(refreshStudent, (e) => message.error(errorMessage(e)))}>
                  Remove
                </Button>
              )}
            </Space>
          ) : s.photo ? 'On file' : '—'}
        </Descriptions.Item>
        <Descriptions.Item label="Resume">
          <FileSlot category="resume" value={s.resume} canEdit={canFiles} save={(fid) => filesApi.setResume(id, fid).then(refreshStudent)} emptyText="No resume" uploadLabel="Upload PDF" />
        </Descriptions.Item>
      </Descriptions>

      {!!history?.length && (
        <div>
          <Typography.Title level={5}>Academic history</Typography.Title>
          <Table size="small" rowKey={(h) => `${h.academic_year}-${h.sem_no}`} pagination={false} dataSource={history}
            columns={[
              { title: 'Academic year', dataIndex: 'academic_year' },
              { title: 'Semester', dataIndex: 'semester' },
              { title: 'Class', dataIndex: 'class_label' },
              { title: 'Status', dataIndex: 'status', render: (v: string) => <Tag color={LIFECYCLE_COLORS[v]}>{v.replace('_', ' ')}</Tag> },
            ]} />
        </div>
      )}
      <Modal title={`Re-admit ${s.name}`} open={readmit.open} onCancel={() => setReadmit({ open: false })}
        onOk={() => lifecycle.mutate({ action: 'readmit', class_id: readmit.classId, remarks: readmit.remarks })}
        okButtonProps={{ disabled: !readmit.classId, loading: lifecycle.isPending }}>
        <Space orientation="vertical" style={{ width: '100%' }}>
          <Select placeholder="Class (current academic year)" style={{ width: '100%' }} value={readmit.classId}
            onChange={(v) => setReadmit((r) => ({ ...r, classId: v }))}
            options={(readmitClasses ?? []).map((c) => ({ value: c.id, label: c.label }))} />
          <Input placeholder="Remarks (optional)" value={readmit.remarks} onChange={(e) => setReadmit((r) => ({ ...r, remarks: e.target.value }))} />
        </Space>
      </Modal>

      <div>
        <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }}>
          <Typography.Title level={5} style={{ margin: 0 }}>
            Parents / guardians
          </Typography.Title>
          {canEdit && (
            <Button size="small" icon={<PlusOutlined />} onClick={() => setAdding(true)}>
              Add parent
            </Button>
          )}
        </Space>
        <Table
          rowKey="id"
          size="small"
          pagination={false}
          dataSource={s.parents ?? []}
          locale={{ emptyText: 'No parents linked' }}
          columns={[
            { title: 'Name', dataIndex: 'name', render: (v, p) => <Space>{v}{p.is_primary && <Tag color="gold">Primary</Tag>}</Space> },
            { title: 'Relation', dataIndex: 'relation', render: (v) => v[0].toUpperCase() + v.slice(1) },
            { title: 'Mobile', dataIndex: 'mobile', render: (v) => v ?? '—' },
            { title: 'Login', dataIndex: 'username' },
            ...(canEdit
              ? [{
                  title: '',
                  key: 'x',
                  width: 90,
                  render: (_: unknown, p: { id: number; name: string }) => (
                    <Button size="small" danger onClick={() => Modal.confirm({ title: `Unlink ${p.name}?`, content: 'The parent account is kept; it is only removed from this student.', onOk: () => unlink.mutateAsync(p.id) })}>
                      Unlink
                    </Button>
                  ),
                }]
              : []),
          ]}
        />
      </div>
      {can('document.view') && (
        <div>
          <Typography.Title level={5}>Documents</Typography.Title>
          <StudentDocuments studentId={id} />
        </div>
      )}
      {can('student_skill.view') && (
        <div>
          <Typography.Title level={5}>Skills</Typography.Title>
          <StudentSkillsEditor studentId={id} />
        </div>
      )}
      {can('marks.view') && (
        <div>
          <Typography.Title level={5}>Marks</Typography.Title>
          <MarkHistoryView studentId={id} />
        </div>
      )}
      <AddParentModal student={s} open={adding} onClose={() => setAdding(false)} />
    </Space>
  );
}

// ---------- page ----------

function StudentDirectory() {
  const { can } = useAuth();
  const { data: depts } = useDepartments();
  const [filter, setFilter] = useState<{ page: number; page_size: number; search?: string; department_id?: number; class_id?: number; status?: string; lifecycle?: string }>({ page: 1, page_size: 20, lifecycle: 'studying' });
  const { data: classes } = useClasses(filter.department_id);
  const [form, setForm] = useState<{ open: boolean; row: Student | null }>({ open: false, row: null });
  const [viewing, setViewing] = useState<number | null>(null);

  const { data, isFetching } = useQuery({ queryKey: ['students', filter], queryFn: () => studentsApi.list(filter), placeholderData: keepPreviousData });

  return (
    <>
      <Space wrap style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Space wrap>
          <Input.Search allowClear placeholder="Name, register no, mobile" style={{ width: 260 }} onSearch={(search) => setFilter((f) => ({ ...f, search, page: 1 }))} />
          <Select
            allowClear
            placeholder="All departments"
            style={{ width: 220 }}
            options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))}
            onChange={(department_id) => setFilter((f) => ({ ...f, department_id, class_id: undefined, page: 1 }))}
          />
          <Select
            allowClear
            placeholder="All classes"
            style={{ width: 180 }}
            value={filter.class_id}
            options={(classes ?? []).map((c) => ({ value: c.id, label: c.label }))}
            onChange={(class_id) => setFilter((f) => ({ ...f, class_id, page: 1 }))}
          />
          <Select
            style={{ width: 150 }}
            value={filter.lifecycle ?? 'all'}
            options={[{ value: 'studying', label: 'Studying' }, { value: 'passed_out', label: 'Alumni' }, { value: 'discontinued', label: 'Discontinued' }, { value: 'all', label: 'All students' }]}
            onChange={(v) => setFilter((f) => ({ ...f, lifecycle: v === 'all' ? undefined : v, page: 1 }))}
          />
          {can('student.delete') && (
            <Select
              style={{ width: 130 }}
              defaultValue="active"
              options={[{ value: 'active', label: 'Active' }, { value: 'inactive', label: 'Inactive' }, { value: 'all', label: 'All' }]}
              onChange={(status) => setFilter((f) => ({ ...f, status, page: 1 }))}
            />
          )}
          <Button
            icon={<DownloadOutlined />}
            onClick={() => {
              const { page: _p, page_size: _s, ...rest } = filter;
              void _p;
              void _s;
              exportsApi.students(rest);
            }}
          >
            Export (.xlsx)
          </Button>
        </Space>
        {can('student.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setForm({ open: true, row: null })}>
            New student
          </Button>
        )}
      </Space>
      <Table<Student>
        rowKey="id"
        loading={isFetching}
        dataSource={data?.data}
        scroll={{ x: 860 }}
        onRow={(s) => ({ onClick: () => setViewing(s.id), style: { cursor: 'pointer' } })}
        pagination={{
          current: filter.page,
          pageSize: filter.page_size,
          total: data?.meta.total,
          showSizeChanger: true,
          showTotal: (t) => `${t} students`,
          onChange: (page, page_size) => setFilter((f) => ({ ...f, page, page_size })),
        }}
        columns={[
          { title: 'Register no', dataIndex: 'register_no', width: 130 },
          { title: 'Name', dataIndex: 'name', render: (v, s) => <Space><UserAvatar name={v} photo={s.photo} size="small" />{v}{!s.is_active && <Tag color="red">Inactive</Tag>}{s.lifecycle_status !== 'studying' && <Tag color={LIFECYCLE_COLORS[s.lifecycle_status]}>{s.lifecycle_status.replace('_', ' ')}</Tag>}</Space> },
          { title: 'Class', dataIndex: 'class_label', render: (v) => (v ? <Tag>{v}</Tag> : '—') },
          { title: 'Batch', dataIndex: 'batch', width: 110 },
          { title: 'Mobile', dataIndex: 'mobile', render: (v) => v ?? '—' },
          { title: 'Parents', dataIndex: 'parent_count', width: 90, render: (v) => (v ? v : <Tag color="orange">none</Tag>) },
        ]}
      />
      <StudentForm open={form.open} row={form.row} onClose={() => setForm({ open: false, row: null })} />
      <Drawer title="Student profile" open={viewing !== null} onClose={() => setViewing(null)} size={Math.min(760, window.innerWidth)} destroyOnHidden>
        {viewing !== null && <StudentProfile id={viewing} onEdit={(s) => setForm({ open: true, row: s })} />}
      </Drawer>
    </>
  );
}

function MyProfile() {
  const { data, isLoading } = useQuery({ queryKey: ['students', 'mine'], queryFn: () => studentsApi.list({ page: 1, page_size: 1 }) });
  if (isLoading) return <Spin />;
  const me = data?.data[0];
  return <Card>{me ? <StudentProfile id={me.id} /> : <Empty description="Your student profile has not been set up yet. Please contact the office." />}</Card>;
}

function MyChildren() {
  const { data, isLoading } = useQuery({ queryKey: ['students', 'children'], queryFn: () => studentsApi.list({ page: 1, page_size: 50 }) });
  const [selected, setSelected] = useState<number | null>(null);
  if (isLoading) return <Spin />;
  const children = data?.data ?? [];
  if (!children.length) return <Card><Empty description="No children are linked to your account yet. Please contact the college office." /></Card>;
  const active = selected ?? children[0].id;
  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      <Row gutter={[16, 16]}>
        {children.map((c) => (
          <Col xs={24} sm={12} lg={8} key={c.id}>
            <Card hoverable onClick={() => setSelected(c.id)} style={{ borderColor: c.id === active ? 'var(--accent)' : undefined }}>
              <Card.Meta title={c.name} description={<Space wrap>{c.register_no}{c.class_label && <Tag>{c.class_label}</Tag>}</Space>} />
            </Card>
          </Col>
        ))}
      </Row>
      <Card>
        <StudentProfile id={active} />
      </Card>
    </Space>
  );
}

function StudentsAdmin() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs
        items={[
          { key: 'list', label: 'Student List', children: <StudentDirectory /> },
          ...(can('bulk_upload.create') ? [{ key: 'import', label: 'Import', children: (
            <Space direction="vertical" size="large" style={{ width: '100%' }}>
              <Typography.Title level={5} style={{ marginTop: 0 }}>Import Students</Typography.Title>
              <StudentsUploadTab />
              <Typography.Title level={5}>Import Student Skills</Typography.Title>
              <SkillsUploadTab />
            </Space>
          ) }] : []),
        ]}
      />
    </Card>
  );
}

export default function StudentsPage() {
  const { user } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  if (audience === 'student') return <MyProfile />;
  if (audience === 'parent') return <MyChildren />;
  return <StudentsAdmin />;
}
