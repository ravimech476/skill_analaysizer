import { useState } from 'react';
import {
  Alert,
  Avatar,
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
  List,
  Modal,
  Progress,
  Row,
  Select,
  Space,
  Spin,
  Statistic,
  Switch,
  Table,
  Tabs,
  Tag,
  Typography,
  message,
} from 'antd';
import { DownloadOutlined, MinusCircleOutlined, PlusOutlined } from '@ant-design/icons';
import { filesApi, fileUrl } from '../api/files';
import { FileAnchor, FileSlot } from '../components/Files';
import { exportsApi } from '../api/reports';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { useNavigate } from 'react-router-dom';
import { errorMessage } from '../api/client';
import {
  lpa,
  placementApi,
  pretty,
  STATUS_COLORS,
  type AppStatus,
  type Application,
  type Company,
  type JobRole,
  type JobRoleInput,
  type Opportunity,
  type RoleStatus,
} from '../api/placement';
import { studentsApi } from '../api/phase2';
import { useDepartments } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import MasterCrud from '../components/MasterCrud';
import { useSkills } from './SkillsPage';

const ROLE_STATUSES: RoleStatus[] = ['upcoming', 'open', 'closed', 'completed'];
const APP_STATUSES: AppStatus[] = ['shortlisted', 'applied', 'in_process', 'selected', 'rejected', 'withdrawn'];

export function RoleSkillsTags({ role }: { role: JobRole }) {
  return (
    <Space size={[4, 4]} wrap>
      {role.skills.map((s) => (
        <Tag key={s.skill_id} color={s.is_mandatory ? 'blue' : undefined}>
          {s.skill_name} ≥{s.required_level}
          {s.is_mandatory ? ' *' : ''}
        </Tag>
      ))}
    </Space>
  );
}

// ---------- job role form ----------

type RoleForm = Omit<JobRoleInput, 'drive_date' | 'last_apply_date'> & { drive_date?: dayjs.Dayjs | null; last_apply_date?: dayjs.Dayjs | null };

function JobRoleDrawer({ role, open, onClose }: { role: JobRole | null; open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const [form] = Form.useForm<RoleForm>();
  const [error, setError] = useState<string>();
  const { data: companies } = useQuery({ queryKey: ['lookup', 'companies'], queryFn: placementApi.companies });
  const { data: skills } = useSkills();
  const { data: depts } = useDepartments();

  const save = useMutation({
    mutationFn: (v: RoleForm) => {
      const body: JobRoleInput = {
        ...v,
        drive_date: v.drive_date ? v.drive_date.format('YYYY-MM-DD') : null,
        last_apply_date: v.last_apply_date ? v.last_apply_date.format('YYYY-MM-DD') : null,
        department_ids: v.department_ids ?? [],
        skills: (v.skills ?? []).map((s) => ({ ...s, weight: s.weight || 1, is_mandatory: !!s.is_mandatory })),
      };
      return role ? placementApi.updateRole(role.id, body) : placementApi.createRole(body);
    },
    onSuccess: () => {
      message.success(role ? 'Job role updated' : 'Job role created');
      qc.invalidateQueries({ queryKey: ['job-roles'] });
      onClose();
    },
    onError: (e) => setError(errorMessage(e)),
  });

  return (
    <Drawer
      title={role ? `Edit ${role.title}` : 'New job role / drive'}
      open={open}
      onClose={onClose}
      size={Math.min(640, window.innerWidth)}
      forceRender
      afterOpenChange={(o) => {
        if (!o) return;
        setError(undefined);
        form.resetFields();
        form.setFieldsValue(
          role
            ? {
                ...role,
                drive_date: role.drive_date ? dayjs(role.drive_date) : null,
                last_apply_date: role.last_apply_date ? dayjs(role.last_apply_date) : null,
                department_ids: role.departments.map((d) => d.id),
                skills: role.skills.map((s) => ({ skill_id: s.skill_id, required_level: s.required_level, is_mandatory: s.is_mandatory, weight: s.weight })),
              }
            : { status: 'upcoming', min_cgpa: 6, max_backlogs: 0, skills: [{ required_level: 3, weight: 1, is_mandatory: true }] },
        );
      }}
      extra={<Button type="primary" loading={save.isPending} onClick={() => form.submit()}>Save</Button>}
    >
      {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
      <Form form={form} layout="vertical" onFinish={(v) => save.mutate(v)} requiredMark="optional">
        <Row gutter={12}>
          <Col xs={24} sm={12}>
            <Form.Item name="company_id" label="Company" rules={[{ required: true }]}>
              <Select showSearch optionFilterProp="label" options={(companies ?? []).map((c) => ({ value: c.id, label: c.name }))} />
            </Form.Item>
          </Col>
          <Col xs={24} sm={12}>
            <Form.Item name="title" label="Job title" rules={[{ required: true }]}>
              <Input placeholder="Java Developer" />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="package_lpa" label="Package (LPA)" rules={[{ required: true }]}>
              <InputNumber min={0.1} max={500} step={0.5} style={{ width: '100%' }} />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="openings" label="Openings">
              <InputNumber min={1} style={{ width: '100%' }} />
            </Form.Item>
          </Col>
          <Col xs={24} sm={8}>
            <Form.Item name="status" label="Status">
              <Select options={ROLE_STATUSES.map((s) => ({ value: s, label: pretty(s) }))} />
            </Form.Item>
          </Col>
          <Col xs={12}>
            <Form.Item name="last_apply_date" label="Last date to apply">
              <DatePicker format="DD-MM-YYYY" style={{ width: '100%' }} />
            </Form.Item>
          </Col>
          <Col xs={12}>
            <Form.Item name="drive_date" label="Drive date">
              <DatePicker format="DD-MM-YYYY" style={{ width: '100%' }} />
            </Form.Item>
          </Col>
        </Row>
        <Typography.Title level={5}>Eligibility</Typography.Title>
        <Row gutter={12}>
          <Col xs={12} sm={8}>
            <Form.Item name="min_cgpa" label="Minimum CGPA">
              <InputNumber min={0} max={10} step={0.5} style={{ width: '100%' }} />
            </Form.Item>
          </Col>
          <Col xs={12} sm={8}>
            <Form.Item name="max_backlogs" label="Max backlogs">
              <InputNumber min={0} max={50} style={{ width: '100%' }} />
            </Form.Item>
          </Col>
          <Col xs={24} sm={8}>
            <Form.Item name="eligible_batch" label="Batch" rules={[{ pattern: /^\d{4}-\d{4}$/, message: 'e.g. 2023-2027' }]}>
              <Input placeholder="Any batch" />
            </Form.Item>
          </Col>
          <Col span={24}>
            <Form.Item name="department_ids" label="Departments" extra="Leave empty to allow every department">
              <Select mode="multiple" allowClear placeholder="All departments" options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
            </Form.Item>
          </Col>
        </Row>
        <Typography.Title level={5}>Required skills</Typography.Title>
        <Typography.Paragraph type="secondary" style={{ marginTop: -4 }}>
          Level 1–5. Mandatory skills make a student ineligible if not met; weight sets how much a skill counts in the match score.
        </Typography.Paragraph>
        <Form.List name="skills">
          {(fields, { add, remove }) => (
            <>
              {fields.map((f) => (
                <Row gutter={8} key={f.key} align="middle">
                  <Col xs={24} sm={9}>
                    <Form.Item name={[f.name, 'skill_id']} rules={[{ required: true, message: 'Skill' }]}>
                      <Select showSearch optionFilterProp="label" placeholder="Skill" options={(skills ?? []).map((s) => ({ value: s.id, label: s.name }))} />
                    </Form.Item>
                  </Col>
                  <Col xs={8} sm={5}>
                    <Form.Item name={[f.name, 'required_level']} rules={[{ required: true }]}>
                      <Select options={[1, 2, 3, 4, 5].map((n) => ({ value: n, label: `Level ${n}` }))} />
                    </Form.Item>
                  </Col>
                  <Col xs={7} sm={4}>
                    <Form.Item name={[f.name, 'weight']}>
                      <Select options={[1, 2, 3].map((n) => ({ value: n, label: `×${n}` }))} />
                    </Form.Item>
                  </Col>
                  <Col xs={7} sm={5}>
                    <Form.Item name={[f.name, 'is_mandatory']} valuePropName="checked">
                      <Switch checkedChildren="Must" unCheckedChildren="Nice" />
                    </Form.Item>
                  </Col>
                  <Col xs={2} sm={1}>
                    <Button type="text" icon={<MinusCircleOutlined />} onClick={() => remove(f.name)} aria-label="Remove skill" style={{ marginBottom: 24 }} />
                  </Col>
                </Row>
              ))}
              <Button type="dashed" icon={<PlusOutlined />} onClick={() => add({ required_level: 3, weight: 1, is_mandatory: false })}>
                Add skill
              </Button>
            </>
          )}
        </Form.List>
        <Form.Item name="description" label="Description" style={{ marginTop: 16 }}>
          <Input.TextArea rows={3} />
        </Form.Item>
      </Form>
    </Drawer>
  );
}

// ---------- job role detail ----------

function RoleDetail({ roleId, onEdit, onClose }: { roleId: number; onEdit: (r: JobRole) => void; onClose: () => void }) {
  const { can } = useAuth();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { data: role } = useQuery({ queryKey: ['job-roles', 'detail', roleId], queryFn: () => placementApi.role(roleId) });
  const { data: apps, isFetching } = useQuery({ queryKey: ['job-roles', 'apps', roleId], queryFn: () => placementApi.applications(roleId) });

  const setStatus = useMutation({
    mutationFn: (s: RoleStatus) => placementApi.setRoleStatus(roleId, s),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['job-roles'] }),
    onError: (e) => message.error(errorMessage(e)),
  });
  const updateApp = useMutation({
    mutationFn: (p: { id: number; status: AppStatus }) => placementApi.updateApplication(p.id, { status: p.status }),
    onSuccess: (a) => {
      message.success(a.status === 'selected' ? `${a.student_name} placed at ${a.company_name}` : 'Status updated');
      qc.invalidateQueries({ queryKey: ['job-roles'] });
      qc.invalidateQueries({ queryKey: ['placements'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const remove = useMutation({
    mutationFn: () => placementApi.deleteRole(roleId),
    onSuccess: () => {
      message.success('Job role deleted');
      qc.invalidateQueries({ queryKey: ['job-roles'] });
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  if (!role) return <Spin />;
  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      <Descriptions
        bordered
        size="small"
        column={{ xs: 1, sm: 2 }}
        title={
          <Space wrap>
            {role.company_logo && <Avatar shape="square" size={40} src={fileUrl(role.company_logo)} />}
            {role.title}
            <Typography.Text type="secondary">{role.company_name}</Typography.Text>
          </Space>
        }
        extra={
          <Space wrap>
            {can('job_role.update') && (
              <Select size="small" value={role.status} style={{ width: 130 }} onChange={(v) => setStatus.mutate(v)} options={ROLE_STATUSES.map((s) => ({ value: s, label: pretty(s) }))} />
            )}
            {can('job_role.update') && <Button size="small" onClick={() => onEdit(role)}>Edit</Button>}
            {can('job_role.delete') && <Button size="small" danger onClick={() => Modal.confirm({ title: 'Delete this job role?', onOk: () => remove.mutateAsync() })}>Delete</Button>}
          </Space>
        }
      >
        <Descriptions.Item label="Package">{lpa(role.package_lpa)}</Descriptions.Item>
        <Descriptions.Item label="Openings">{role.openings ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Apply by">{role.last_apply_date ? dayjs(role.last_apply_date).format('DD MMM YYYY') : '—'}</Descriptions.Item>
        <Descriptions.Item label="Drive date">{role.drive_date ? dayjs(role.drive_date).format('DD MMM YYYY') : '—'}</Descriptions.Item>
        <Descriptions.Item label="Min CGPA">{role.min_cgpa}</Descriptions.Item>
        <Descriptions.Item label="Max backlogs">{role.max_backlogs}</Descriptions.Item>
        <Descriptions.Item label="Batch">{role.eligible_batch ?? 'Any'}</Descriptions.Item>
        <Descriptions.Item label="Departments">{role.departments.length ? role.departments.map((d) => <Tag key={d.id}>{d.code}</Tag>) : 'All'}</Descriptions.Item>
        <Descriptions.Item label="Required skills" span={2}><RoleSkillsTags role={role} /></Descriptions.Item>
        {role.description && <Descriptions.Item label="Description" span={2}>{role.description}</Descriptions.Item>}
        <Descriptions.Item label="Job description">
          <FileSlot
            category="job_description"
            value={role.jd}
            canEdit={can('job_role.update')}
            emptyText="No PDF"
            uploadLabel="Upload PDF"
            save={(fid) => filesApi.setJD(role.id, fid).then(() => qc.invalidateQueries({ queryKey: ['job-roles'] }))}
          />
        </Descriptions.Item>
        <Descriptions.Item label="Company logo">
          <FileSlot
            category="company_logo"
            value={role.company_logo}
            canEdit={can('company.update')}
            emptyText="No logo"
            uploadLabel="Upload logo"
            save={(fid) => filesApi.setCompanyLogo(role.company_id, fid).then(() => qc.invalidateQueries({ queryKey: ['job-roles'] }))}
          />
        </Descriptions.Item>
      </Descriptions>
      <div>
        <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }}>
          <Typography.Title level={5} style={{ margin: 0 }}>
            Applications ({apps?.length ?? 0})
          </Typography.Title>
          {can('skill_analyzer.view') && <Button type="primary" onClick={() => navigate(`/skill-analyzer?role=${roleId}`)}>Rank &amp; shortlist students</Button>}
        </Space>
        <Table<Application>
          rowKey="id"
          size="small"
          loading={isFetching}
          dataSource={apps}
          pagination={false}
          scroll={{ x: 640 }}
          locale={{ emptyText: 'No one shortlisted yet. Use the skill analyzer to rank and shortlist students.' }}
          columns={[
            { title: 'Student', render: (_, a) => <span>{a.student_name} <Typography.Text type="secondary">{a.register_no}</Typography.Text></span> },
            { title: 'Dept', dataIndex: 'department_code', width: 80 },
            { title: 'CGPA', dataIndex: 'cgpa', width: 70 },
            { title: 'Match', dataIndex: 'match_score', width: 80, render: (v) => (v != null ? `${v}%` : '—') },
            {
              title: 'Status',
              width: 170,
              render: (_, a) =>
                can('placement.update') ? (
                  <Select
                    size="small"
                    value={a.status}
                    style={{ width: 150 }}
                    onChange={(status) => updateApp.mutate({ id: a.id, status })}
                    options={APP_STATUSES.map((s) => ({ value: s, label: pretty(s) }))}
                  />
                ) : (
                  <Tag color={STATUS_COLORS[a.status]}>{pretty(a.status)}</Tag>
                ),
            },
            { title: 'Offer', dataIndex: 'offer_date', width: 110, render: (v) => (v ? dayjs(v).format('DD MMM YY') : '') },
          ]}
        />
      </div>
    </Space>
  );
}

function Drives() {
  const { can } = useAuth();
  const [status, setStatus] = useState<string>();
  const [search, setSearch] = useState('');
  const [form, setForm] = useState<{ open: boolean; role: JobRole | null }>({ open: false, role: null });
  const [viewing, setViewing] = useState<number | null>(null);
  const { data, isLoading } = useQuery({ queryKey: ['job-roles', status, search], queryFn: () => placementApi.roles({ status, search }) });

  return (
    <>
      <Space wrap style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Space wrap>
          <Input.Search allowClear placeholder="Title or company" style={{ width: 240 }} onSearch={setSearch} />
          <Select allowClear placeholder="All statuses" style={{ width: 150 }} value={status} onChange={setStatus} options={ROLE_STATUSES.map((s) => ({ value: s, label: pretty(s) }))} />
        </Space>
        {can('job_role.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setForm({ open: true, role: null })}>
            New job role
          </Button>
        )}
      </Space>
      <Table<JobRole>
        rowKey="id"
        loading={isLoading}
        dataSource={data}
        pagination={{ pageSize: 20, hideOnSinglePage: true }}
        scroll={{ x: 1040 }}
        onRow={(r) => ({ onClick: () => setViewing(r.id), style: { cursor: 'pointer' } })}
        columns={[
          { title: 'Role', width: 230, render: (_, r) => <div><Typography.Text strong>{r.title}</Typography.Text><br /><Typography.Text type="secondary">{r.company_name}</Typography.Text></div> },
          { title: 'Package', dataIndex: 'package_lpa', width: 110, render: (v) => lpa(v) },
          { title: 'Drive', dataIndex: 'drive_date', width: 110, render: (v) => (v ? dayjs(v).format('DD MMM YY') : '—') },
          { title: 'Eligibility', width: 150, render: (_, r) => <Typography.Text type="secondary">CGPA ≥ {r.min_cgpa} · ≤ {r.max_backlogs} backlogs</Typography.Text> },
          { title: 'Skills', width: 300, render: (_, r) => <RoleSkillsTags role={r} /> },
          { title: 'Applied / placed', width: 130, render: (_, r) => `${r.application_count} / ${r.selected_count}` },
          { title: 'Status', dataIndex: 'status', width: 110, render: (v) => <Tag color={STATUS_COLORS[v]}>{pretty(v)}</Tag> },
        ]}
      />
      <JobRoleDrawer open={form.open} role={form.role} onClose={() => setForm({ open: false, role: null })} />
      <Drawer title="Job role" open={viewing !== null} onClose={() => setViewing(null)} size={Math.min(860, window.innerWidth)} destroyOnHidden>
        {viewing !== null && <RoleDetail roleId={viewing} onEdit={(r) => setForm({ open: true, role: r })} onClose={() => setViewing(null)} />}
      </Drawer>
    </>
  );
}

function Placed() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const [batch, setBatch] = useState<string>();
  const [search, setSearch] = useState('');
  const { data: stats } = useQuery({ queryKey: ['placements', 'stats', batch], queryFn: () => placementApi.stats(batch) });
  const { data: list, isFetching } = useQuery({ queryKey: ['placements', batch, search], queryFn: () => placementApi.placements({ batch, search }) });

  return (
    <>
      <Space wrap style={{ marginBottom: 16 }}>
        <Input placeholder="Batch e.g. 2025-2029" allowClear style={{ width: 200 }} onPressEnter={(e) => setBatch((e.target as HTMLInputElement).value || undefined)} onChange={(e) => !e.target.value && setBatch(undefined)} />
        <Input.Search allowClear placeholder="Student or company" style={{ width: 240 }} onSearch={setSearch} />
        <Button icon={<DownloadOutlined />} onClick={() => exportsApi.placements({ batch, search: search || undefined })}>
          Placement report (.xlsx)
        </Button>
      </Space>
      {stats && (
        <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Placed" value={stats.placed_percent} suffix="%" /><Typography.Text type="secondary">{stats.placed_students} of {stats.total_students} students</Typography.Text></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Offers" value={stats.total_offers} /></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Highest" value={stats.highest_package ?? 0} suffix="LPA" /></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Average (best offer)" value={stats.average_package ?? 0} suffix="LPA" /></Card></Col>
          <Col xs={24} lg={12}>
            <Card size="small" title="By department">
              <List
                size="small"
                dataSource={stats.by_department}
                renderItem={(d) => (
                  <List.Item>
                    <div style={{ width: '100%' }}>
                      <Space style={{ width: '100%', justifyContent: 'space-between' }}><span><b>{d.code}</b> {d.name}</span><span>{d.placed}/{d.students}</span></Space>
                      <Progress percent={d.percent} size="small" />
                    </div>
                  </List.Item>
                )}
              />
            </Card>
          </Col>
          <Col xs={24} lg={12}>
            <Card size="small" title="By company">
              <Table size="small" rowKey="company" pagination={false} dataSource={stats.by_company} locale={{ emptyText: 'No placements yet' }}
                columns={[{ title: 'Company', dataIndex: 'company' }, { title: 'Offers', dataIndex: 'offers', width: 80 }, { title: 'Highest', dataIndex: 'highest', width: 110, render: (v) => lpa(v) }]} />
            </Card>
          </Col>
        </Row>
      )}
      <Table
        rowKey="id"
        size="small"
        loading={isFetching}
        dataSource={list}
        pagination={{ pageSize: 25, hideOnSinglePage: true }}
        scroll={{ x: 760 }}
        columns={[
          { title: 'Student', render: (_, p) => <span>{p.student_name} <Typography.Text type="secondary">{p.register_no}</Typography.Text></span> },
          { title: 'Dept', dataIndex: 'department_code', width: 80 },
          { title: 'Batch', dataIndex: 'batch', width: 110 },
          { title: 'Company', dataIndex: 'company_name' },
          { title: 'Role', dataIndex: 'job_title', width: 180 },
          { title: 'Package', dataIndex: 'package_lpa', width: 110, render: (v) => lpa(v) },
          { title: 'Offer date', dataIndex: 'offer_date', width: 110, render: (v) => (v ? dayjs(v).format('DD MMM YY') : '—') },
          {
            title: 'Offer letter',
            width: 200,
            render: (_, p) => (
              <FileSlot
                category="offer_letter"
                value={p.offer_letter}
                canEdit={can('placement.update')}
                emptyText="—"
                save={(fid) => filesApi.setOfferLetter(p.id, fid).then(() => qc.invalidateQueries({ queryKey: ['placements'] }))}
              />
            ),
          },
        ]}
      />
    </>
  );
}

function Companies() {
  return (
    <MasterCrud<Company>
      path="companies"
      perm="company"
      noun="company"
      fields={[
        { name: 'name', label: 'Company name', type: 'text', required: true },
        { name: 'industry', label: 'Industry', type: 'text' },
        { name: 'location', label: 'Location', type: 'text' },
        { name: 'website', label: 'Website', type: 'text' },
        { name: 'contact_person', label: 'Contact person', type: 'text' },
        { name: 'contact_email', label: 'Contact email', type: 'text' },
        { name: 'contact_mobile', label: 'Contact mobile', type: 'text' },
        { name: 'description', label: 'About', type: 'text' },
      ]}
      columns={[
        { title: 'Company', dataIndex: 'name', render: (v, c) => <div><b>{v}</b><br /><Typography.Text type="secondary">{[c.industry, c.location].filter(Boolean).join(' · ')}</Typography.Text></div> },
        { title: 'Contact', render: (_, c) => [c.contact_person, c.contact_mobile].filter(Boolean).join(' · ') || '—' },
        { title: 'Roles', dataIndex: 'job_role_count', width: 80 },
        { title: 'Placed', dataIndex: 'placed_count', width: 80 },
        { title: 'Highest', dataIndex: 'highest_package', width: 110, render: (v) => lpa(v) },
      ]}
    />
  );
}

// ---------- student / parent view ----------

export function GapBars({ op }: { op: Opportunity }) {
  const all = [...op.missing_skills, ...op.matched_skills];
  return (
    <Space orientation="vertical" size={2} style={{ width: '100%' }}>
      {all.map((g) => (
        <Row key={g.skill_id} gutter={8} align="middle">
          <Col flex="150px">
            <Typography.Text strong={g.is_mandatory}>{g.name}{g.is_mandatory ? ' *' : ''}</Typography.Text>
          </Col>
          <Col flex="auto">
            <Progress percent={Math.min(100, (g.student_level / g.required_level) * 100)} size="small" showInfo={false} status={g.student_level >= g.required_level ? 'success' : g.is_mandatory ? 'exception' : 'normal'} />
          </Col>
          <Col flex="70px">
            <Typography.Text type={g.student_level >= g.required_level ? 'success' : 'danger'}>{g.student_level}/{g.required_level}</Typography.Text>
          </Col>
        </Row>
      ))}
    </Space>
  );
}

export function OpportunitiesView({ studentId, mode }: { studentId: number; mode: 'drives' | 'gap' }) {
  const { data, isLoading, error } = useQuery({ queryKey: ['opportunities', studentId], queryFn: () => placementApi.opportunities(studentId) });
  if (isLoading) return <Spin />;
  if (error) return <Alert type="error" showIcon title={errorMessage(error)} />;
  if (!data) return null;
  const offers = data.applications.filter((a) => a.status === 'selected');
  return (
    <Space orientation="vertical" size="middle" style={{ width: '100%' }}>
      {mode === 'drives' && offers.length > 0 && (
        <Alert type="success" showIcon title={`Placed: ${offers.map((o) => `${o.company_name} (${o.job_title}, ${lpa(o.package_lpa)})`).join(', ')}`} description="You can still apply to drives with a higher package." />
      )}
      {data.opportunities.length === 0 && <Empty description="No open or upcoming placement drives right now" />}
      {data.opportunities.map((op) => (
        <Card
          key={op.job_role.id}
          size="small"
          title={
            <Space wrap>
              {op.job_role.company_logo && <Avatar shape="square" size={28} src={fileUrl(op.job_role.company_logo)} />}
              {op.job_role.title}
              <Typography.Text type="secondary">{op.job_role.company_name}</Typography.Text>
            </Space>
          }
          extra={
            <Space wrap>
              <Tag color={STATUS_COLORS[op.job_role.status]}>{pretty(op.job_role.status)}</Tag>
              {op.application_status && <Tag color={STATUS_COLORS[op.application_status]}>{pretty(op.application_status)}</Tag>}
            </Space>
          }
        >
          <Row gutter={[16, 8]}>
            <Col xs={24} md={8}>
              <Space orientation="vertical" size={2}>
                <Typography.Text>{lpa(op.job_role.package_lpa)}{op.job_role.drive_date ? ` · drive ${dayjs(op.job_role.drive_date).format('DD MMM')}` : ''}</Typography.Text>
                {op.job_role.jd && <FileAnchor link={op.job_role.jd} label="Job description" />}
                <Progress type="circle" size={70} percent={Math.round(op.skill_score)} format={(p) => `${p}%`} />
                <Typography.Text type="secondary">skill match</Typography.Text>
                {op.is_eligible ? <Tag color="green">Eligible</Tag> : <Tag color="red">Not eligible</Tag>}
              </Space>
            </Col>
            <Col xs={24} md={16}>
              {!op.is_eligible && (
                <ul style={{ margin: '0 0 8px', paddingLeft: 18, color: '#dc2626' }}>
                  {op.ineligible_reasons.map((r) => <li key={r}>{r}</li>)}
                </ul>
              )}
              {mode === 'gap' || op.missing_skills.length ? (
                <>
                  <Typography.Text type="secondary">{op.missing_skills.length ? 'Skills to improve (your level / needed):' : 'All required skills met:'}</Typography.Text>
                  <GapBars op={op} />
                </>
              ) : (
                <Typography.Text type="success">You meet every required skill.</Typography.Text>
              )}
            </Col>
          </Row>
        </Card>
      ))}
    </Space>
  );
}

export function StudentPicker({ parent, children }: { parent: boolean; children: (id: number) => React.ReactNode }) {
  const { data, isLoading } = useQuery({ queryKey: ['students', parent ? 'children' : 'mine'], queryFn: () => studentsApi.list({ page: 1, page_size: parent ? 50 : 1 }) });
  const [selected, setSelected] = useState<number>();
  if (isLoading) return <Spin />;
  const kids = data?.data ?? [];
  if (!kids.length) return <Empty description={parent ? 'No children are linked to your account yet.' : 'Your student profile has not been set up yet.'} />;
  const active = selected ?? kids[0].id;
  return (
    <>
      {parent && kids.length > 1 && <Select value={active} onChange={setSelected} style={{ width: 240, marginBottom: 16 }} options={kids.map((k) => ({ value: k.id, label: k.name }))} />}
      {children(active)}
    </>
  );
}

export default function PlacementPage() {
  const { user, can } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  if (audience === 'student' || audience === 'parent') {
    return (
      <Card>
        <StudentPicker parent={audience === 'parent'}>{(id) => <OpportunitiesView studentId={id} mode="drives" />}</StudentPicker>
      </Card>
    );
  }
  return (
    <Card>
      <Tabs
        items={[
          { key: 'drives', label: 'Drives & job roles', children: <Drives /> },
          { key: 'placed', label: 'Placements', children: <Placed /> },
          ...(can('company.view') ? [{ key: 'companies', label: 'Companies', children: <Companies /> }] : []),
        ]}
      />
    </Card>
  );
}
