import { useState } from 'react';
import {
  Alert,
  Avatar,
  Button,
  Card,
  Col,
  DatePicker,
  Descriptions,
  Empty,
  Form,
  Input,
  InputNumber,
  Modal,
  Progress,
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
import { MinusCircleOutlined, PlusOutlined } from '@ant-design/icons';
import { filesApi, fileUrl } from '../api/files';
import { FileAnchor, FileSlot } from '../components/Files';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import {
  lpa,
  placementApi,
  pretty,
  STATUS_COLORS,
  type AppStatus,
  type Application,
  type JobRole,
  type JobRoleInput,
  type Match,
  type Opportunity,
  type RoleStatus,
} from '../api/placement';
import { studentsApi } from '../api/phase2';
import { useDepartments } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { useSkills } from './SkillsPage';
import { PlacementDrivesUpload } from './BulkUploadPage';

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
    <Modal
      title={role ? `Edit ${role.title}` : 'New job role / drive'}
      open={open}
      onCancel={onClose}
      width={720}
      centered
      forceRender
      styles={{ body: { maxHeight: 'calc(100vh - 200px)', overflowY: 'auto', overflowX: 'hidden', scrollbarWidth: 'none' } }}
      footer={[
        <Button key="cancel" onClick={onClose}>Cancel</Button>,
        <Button key="save" type="primary" loading={save.isPending} onClick={() => form.submit()}>Save</Button>,
      ]}
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
                <div key={f.key} style={{ display: 'flex', gap: 6, alignItems: 'flex-start', flexWrap: 'wrap', marginBottom: 4 }}>
                  <Form.Item name={[f.name, 'skill_id']} rules={[{ required: true, message: 'Skill' }]} style={{ flex: '1 1 160px', marginBottom: 8 }}>
                    <Select showSearch optionFilterProp="label" placeholder="Skill" options={(skills ?? []).map((s) => ({ value: s.id, label: s.name }))} />
                  </Form.Item>
                  <Form.Item name={[f.name, 'required_level']} rules={[{ required: true }]} style={{ flex: '0 0 90px', marginBottom: 8 }}>
                    <Select options={[1, 2, 3, 4, 5].map((n) => ({ value: n, label: `Lv ${n}` }))} />
                  </Form.Item>
                  <Form.Item name={[f.name, 'weight']} style={{ flex: '0 0 65px', marginBottom: 8 }}>
                    <Select options={[1, 2, 3].map((n) => ({ value: n, label: `×${n}` }))} />
                  </Form.Item>
                  <Form.Item name={[f.name, 'is_mandatory']} valuePropName="checked" style={{ flex: '0 0 auto', marginBottom: 8 }}>
                    <Switch checkedChildren="Must" unCheckedChildren="Nice" />
                  </Form.Item>
                  <Button type="text" icon={<MinusCircleOutlined />} onClick={() => remove(f.name)} aria-label="Remove skill" style={{ marginTop: 4 }} />
                </div>
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
    </Modal>
  );
}

// ---------- job role detail ----------

function RoleDetail({ roleId, onEdit, onClose }: { roleId: number; onEdit: (r: JobRole) => void; onClose: () => void }) {
  const { can } = useAuth();
  const qc = useQueryClient();
  const [selectedIds, setSelectedIds] = useState<number[]>([]);
  const { data: role } = useQuery({ queryKey: ['job-roles', 'detail', roleId], queryFn: () => placementApi.role(roleId) });
  const { data: apps, isFetching } = useQuery({ queryKey: ['job-roles', 'apps', roleId], queryFn: () => placementApi.applications(roleId) });
  const { data: eligibleData, isLoading: loadingEligible, refetch: refetchEligible } = useQuery({
    queryKey: ['job-roles', 'eligible', roleId],
    queryFn: () => placementApi.analyze(roleId),
    enabled: role?.status === 'open' || role?.status === 'upcoming',
  });
  const shortlistMut = useMutation({
    mutationFn: () => placementApi.shortlist(roleId, selectedIds),
    onSuccess: (r) => {
      message.success(`Shortlisted ${r.added} students`);
      setSelectedIds([]);
      qc.invalidateQueries({ queryKey: ['job-roles'] });
      refetchEligible();
    },
    onError: (e) => message.error(errorMessage(e)),
  });

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

  const eligibleStudents = eligibleData?.matches?.filter((m) => m.is_eligible) ?? [];
  const byDept: Record<string, Record<string, Match[]>> = {};
  for (const m of eligibleStudents) {
    const dept = m.department_code ?? 'Unknown';
    const cls = m.class_label ?? 'Unassigned';
    if (!byDept[dept]) byDept[dept] = {};
    if (!byDept[dept][cls]) byDept[dept][cls] = [];
    byDept[dept][cls].push(m);
  }

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
      {(role.status === 'open' || role.status === 'upcoming') && (
        <div>
          <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }}>
            <Typography.Title level={5} style={{ margin: 0 }}>
              Eligible Students ({eligibleData?.eligible ?? 0} of {eligibleData?.total ?? 0})
            </Typography.Title>
            {selectedIds.length > 0 && can('placement.create') && (
              <Space>
                <Typography.Text type="secondary">{selectedIds.length} selected</Typography.Text>
                <Button type="primary" loading={shortlistMut.isPending}
                  onClick={() => shortlistMut.mutate()}>
                  Shortlist &amp; Notify ({selectedIds.length})
                </Button>
              </Space>
            )}
          </Space>
          {loadingEligible ? <Spin /> : (
            Object.entries(byDept).map(([dept, byClass]) => {
              const deptStudents = Object.values(byClass).flat();
              const selectableDept = deptStudents.filter((m) => m.application_status == null).map((m) => m.student_id);
              const allDeptSelected = selectableDept.length > 0 && selectableDept.every((id) => selectedIds.includes(id));
              return (
              <Card key={dept} size="small" title={
                <Space style={{ width: '100%', justifyContent: 'space-between' }}>
                  <span>Department: {dept} ({deptStudents.length} eligible)</span>
                  {can('placement.create') && selectableDept.length > 0 && (
                    <Button size="small" type={allDeptSelected ? 'default' : 'link'}
                      onClick={() => {
                        if (allDeptSelected) {
                          setSelectedIds((prev) => prev.filter((id) => !selectableDept.includes(id)));
                        } else {
                          setSelectedIds((prev) => [...new Set([...prev, ...selectableDept])]);
                        }
                      }}>
                      {allDeptSelected ? `Deselect all ${dept}` : `Select all ${dept}`}
                    </Button>
                  )}
                </Space>
              } style={{ marginBottom: 12 }}>
                {Object.entries(byClass).map(([cls, students]) => {
                  const selectableCls = students.filter((m) => m.application_status == null).map((m) => m.student_id);
                  const allClsSelected = selectableCls.length > 0 && selectableCls.every((id) => selectedIds.includes(id));
                  return (
                  <div key={cls} style={{ marginBottom: 16 }}>
                    <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 4 }}>
                      <Typography.Text strong>{cls} ({students.length} eligible)</Typography.Text>
                      {can('placement.create') && selectableCls.length > 0 && (
                        <Button size="small" type={allClsSelected ? 'default' : 'link'}
                          onClick={() => {
                            if (allClsSelected) {
                              setSelectedIds((prev) => prev.filter((id) => !selectableCls.includes(id)));
                            } else {
                              setSelectedIds((prev) => [...new Set([...prev, ...selectableCls])]);
                            }
                          }}>
                          {allClsSelected ? 'Deselect all' : 'Select all'}
                        </Button>
                      )}
                    </Space>
                    <Table<Match>
                      rowKey="student_id"
                      size="small"
                      pagination={false}
                      rowSelection={can('placement.create') ? {
                        selectedRowKeys: selectedIds,
                        onChange: (keys) => setSelectedIds(keys as number[]),
                        getCheckboxProps: (r) => ({ disabled: r.application_status != null }),
                      } : undefined}
                      dataSource={students}
                      columns={[
                        { title: 'Student', render: (_, m) => <span>{m.name} <Typography.Text type="secondary">{m.register_no}</Typography.Text></span> },
                        { title: 'CGPA', dataIndex: 'cgpa', width: 70, render: (v: number) => v?.toFixed(2) },
                        { title: 'Skills', render: (_, m) => (
                          <Space size={4} wrap>
                            {(m.matched_skills ?? []).map((s) => <Tag key={s.skill_id} color="green">{s.name}</Tag>)}
                            {(m.missing_skills ?? []).map((s) => <Tag key={s.skill_id} color="red">{s.name}</Tag>)}
                          </Space>
                        )},
                        { title: 'Status', render: (_, m) => m.application_status ? <Tag color="blue">{m.application_status}</Tag> : null, width: 100 },
                      ]}
                    />
                  </div>
                  );
                })}
              </Card>
              );
            })
          )}
          {!loadingEligible && eligibleStudents.length === 0 && <Empty description="No eligible students for this drive" />}
        </div>
      )}
      <div>
        <Typography.Title level={5} style={{ margin: 0, marginBottom: 8 }}>
          Applications ({apps?.length ?? 0})
        </Typography.Title>
        <Table<Application>
          rowKey="id"
          size="small"
          loading={isFetching}
          dataSource={apps}
          pagination={false}
          scroll={{ x: 640 }}
          locale={{ emptyText: 'No applications yet.' }}
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
  const qc = useQueryClient();
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
        scroll={{ x: 1100 }}
        onRow={(r) => ({ onClick: () => setViewing(r.id), style: { cursor: 'pointer' } })}
        columns={[
          { title: 'Role', width: 230, render: (_, r) => <div><Typography.Text strong>{r.title}</Typography.Text><br /><Typography.Text type="secondary">{r.company_name}</Typography.Text></div> },
          { title: 'Package', dataIndex: 'package_lpa', width: 100, render: (v) => lpa(v) },
          { title: 'Drive', dataIndex: 'drive_date', width: 100, render: (v) => (v ? dayjs(v).format('DD MMM YY') : '—') },
          { title: 'Skills', width: 250, render: (_, r) => <RoleSkillsTags role={r} /> },
          { title: 'Applied', width: 80, render: (_, r) => r.application_count },
          { title: 'Status', dataIndex: 'status', width: 100, render: (v) => <Tag color={STATUS_COLORS[v]}>{pretty(v)}</Tag> },
          ...(can('job_role.update') || can('job_role.delete') ? [{
            title: 'Actions',
            width: 140,
            render: (_: any, r: JobRole) => (
              <Space size={4} onClick={(e) => e.stopPropagation()}>
                {can('job_role.update') && <Button size="small" onClick={() => setForm({ open: true, role: r })}>Edit</Button>}
                {can('job_role.delete') && <Button size="small" danger onClick={() => Modal.confirm({
                  title: `Delete "${r.title}"?`,
                  content: `This will remove the ${r.company_name} drive permanently.`,
                  okButtonProps: { danger: true },
                  onOk: () => placementApi.deleteRole(r.id).then(() => {
                    message.success('Drive deleted');
                    qc.invalidateQueries({ queryKey: ['job-roles'] });
                  }),
                })}>Delete</Button>}
              </Space>
            ),
          }] : []),
        ]}
      />
      <JobRoleDrawer open={form.open} role={form.role} onClose={() => setForm({ open: false, role: null })} />
      <Modal title="Job role" open={viewing !== null} onCancel={() => setViewing(null)} width={900} centered footer={null} destroyOnHidden
        styles={{ body: { maxHeight: 'calc(100vh - 180px)', overflowY: 'auto', overflowX: 'hidden', scrollbarWidth: 'none' } }}>
        {viewing !== null && <RoleDetail roleId={viewing} onEdit={(r) => { setViewing(null); setForm({ open: true, role: r }); }} onClose={() => setViewing(null)} />}
      </Modal>
    </>
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
      <Tabs items={[
        { key: 'drives', label: 'Drives', children: <Drives /> },
        ...(can('job_role.create') ? [{ key: 'import', label: 'Import', children: <PlacementDrivesUpload /> }] : []),
      ]} />
    </Card>
  );
}
