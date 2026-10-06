import { useState } from 'react';
import {
  Alert, Button, Card, Col, Collapse, Divider, Empty, Input, InputNumber, Modal, Progress, Rate, Row, Segmented,
  Select, Space, Spin, Switch, Table, Tabs, Tag, Tooltip, Typography, message,
} from 'antd';
import { PlusOutlined, ThunderboltOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import {
  careersApi, READINESS, type Career, type CareerInput, type CareerMatch, type Course, type Readiness,
  type SkillStanding,
} from '../api/careers';
import { lpa } from '../api/placement';
import { studentsApi } from '../api/phase2';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import MasterCrud from '../components/MasterCrud';
import { useSkills } from './SkillsPage';
import { StudentPicker } from './PlacementPage';

const FILTERS: { value: 'all' | Readiness; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'ready', label: 'Ready' },
  { value: 'close', label: 'Close' },
  { value: 'explore', label: 'Explore' },
];

/** One required skill as a bar: how far the student is from the level the career asks for. */
function StandingBar({ s }: { s: SkillStanding }) {
  const met = s.gap === 0;
  return (
    <Row gutter={8} align="middle" style={{ marginBottom: 2 }}>
      <Col flex="170px">
        <Typography.Text strong={s.is_core}>
          {s.name}
          {s.is_core ? ' *' : ''}
        </Typography.Text>
      </Col>
      <Col flex="auto">
        <Progress
          percent={Math.min(100, (s.score / s.required_score) * 100)}
          size="small"
          showInfo={false}
          status={met ? 'success' : s.is_core ? 'exception' : 'normal'}
        />
      </Col>
      <Col flex="94px" style={{ textAlign: 'right' }}>
        <Tooltip title={`Blended score ${s.score} of the ${s.required_score} needed for level ${s.required_level}`}>
          <Typography.Text type={met ? 'success' : 'danger'}>
            {s.level}/{s.required_level}
          </Typography.Text>
        </Tooltip>
      </Col>
    </Row>
  );
}

function MatchCard({ m, onRate }: { m: CareerMatch; onRate?: (rating: number) => void }) {
  const r = READINESS[m.readiness];
  return (
    <Card size="small" style={{ marginBottom: 12 }}>
      <Row gutter={[16, 8]} align="top">
        <Col xs={24} md={16}>
          <Space wrap size={6}>
            <Typography.Text type="secondary">#{m.rank}</Typography.Text>
            <Typography.Text strong style={{ fontSize: 15 }}>{m.name}</Typography.Text>
            {m.domain && <Tag>{m.domain}</Tag>}
            <Tooltip title={r.hint}>
              <Tag color={r.color}>{r.label}</Tag>
            </Tooltip>
            {m.avg_package != null && <Typography.Text type="secondary">typically {lpa(m.avg_package)}</Typography.Text>}
          </Space>
          <Typography.Paragraph type="secondary" style={{ marginTop: 6, marginBottom: 0 }}>
            {m.explanation}
          </Typography.Paragraph>
        </Col>
        <Col xs={24} md={8} style={{ textAlign: 'right' }}>
          <Typography.Text strong style={{ fontSize: 22 }}>{m.final_score}</Typography.Text>
          <Typography.Text type="secondary"> / 100</Typography.Text>
          <div>
            <Typography.Text type="secondary">
              skills {m.skill_score}% · academics {m.academic_score}%
            </Typography.Text>
          </div>
          {onRate && (
            <div style={{ marginTop: 4 }}>
              <Tooltip title="Is this suggestion useful?">
                <Rate count={5} value={m.feedback?.rating ?? 0} onChange={onRate} style={{ fontSize: 14 }} />
              </Tooltip>
            </div>
          )}
        </Col>
      </Row>
      <Collapse
        ghost
        size="small"
        style={{ marginTop: 4 }}
        items={[
          {
            key: 'detail',
            label: (
              <Typography.Text type="secondary">
                {m.strengths.length} of {m.strengths.length + m.gaps.length} requirements met
                {m.gaps.length ? ` · ${m.gaps.length} to close` : ''}
              </Typography.Text>
            ),
            children: (
              <>
                {[...m.gaps, ...m.strengths].map((s) => (
                  <StandingBar key={s.skill_id} s={s} />
                ))}
                {m.gaps.some((g) => g.courses?.length) && (
                  <>
                    <Divider style={{ margin: '12px 0 8px' }} />
                    <Typography.Text type="secondary">What to study next</Typography.Text>
                    {m.gaps
                      .filter((g) => g.courses?.length)
                      .map((g) => (
                        <div key={g.skill_id} style={{ marginTop: 4 }}>
                          <Typography.Text strong>{g.name}: </Typography.Text>
                          <Space size={[6, 4]} wrap>
                            {g.courses!.map((c) => (
                              <Tag key={c.id} color="cyan">
                                {c.url ? (
                                  <a href={c.url} target="_blank" rel="noreferrer">
                                    {c.title}
                                  </a>
                                ) : (
                                  c.title
                                )}
                                {c.provider ? ` · ${c.provider}` : ''}
                                {c.duration_hours ? ` · ${c.duration_hours}h` : ''}
                              </Tag>
                            ))}
                          </Space>
                        </div>
                      ))}
                  </>
                )}
                <Typography.Paragraph type="secondary" style={{ marginTop: 10, marginBottom: 0, fontSize: 12 }}>
                  * core requirement. Levels come from the blended skill score — what staff recorded, verified
                  certificates, assessments and subject marks together.
                </Typography.Paragraph>
              </>
            ),
          },
        ]}
      />
    </Card>
  );
}

/** A student's ranked careers. `canRun` adds the recompute button (staff), `canRate` the rating (the student). */
export function CareerMatchesView({ studentId, canRun, canRate }: { studentId: number; canRun: boolean; canRate: boolean }) {
  const qc = useQueryClient();
  const [filter, setFilter] = useState<'all' | Readiness>('all');
  const key = ['career-matches', studentId];
  const { data, isLoading, error } = useQuery({ queryKey: key, queryFn: () => careersApi.matches(studentId) });

  const refresh = useMutation({
    mutationFn: () => (canRun ? careersApi.run(studentId) : careersApi.matches(studentId, { refresh: true })),
    onSuccess: (d) => {
      qc.setQueryData(key, d);
      message.success('Career matches updated');
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const rate = useMutation({
    mutationFn: (v: { careerId: number; rating: number }) => careersApi.feedback(studentId, v.careerId, { rating: v.rating }),
    onSuccess: (d) => {
      qc.setQueryData(key, d);
      message.success('Thanks — your rating helps us suggest better');
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  if (isLoading) return <Spin />;
  if (error) return <Alert type="error" showIcon title={errorMessage(error)} />;
  if (!data) return null;
  if (!data.total) return <Empty description="No careers in the catalogue yet" />;

  const rows = data.matches.filter((m) => filter === 'all' || m.readiness === filter);
  return (
    <Space orientation="vertical" size="middle" style={{ width: '100%' }}>
      <Row gutter={[16, 12]} align="middle">
        <Col xs={24} md={14}>
          <Space wrap>
            {(['ready', 'close', 'explore'] as Readiness[]).map((k) => (
              <Tag key={k} color={READINESS[k].color}>
                {data.counts[k] ?? 0} {READINESS[k].label.toLowerCase()}
              </Tag>
            ))}
            {data.computed_at && (
              <Typography.Text type="secondary">last worked out {dayjs(data.computed_at).format('DD MMM, HH:mm')}</Typography.Text>
            )}
          </Space>
        </Col>
        <Col xs={24} md={10} style={{ textAlign: 'right' }}>
          <Button icon={<ThunderboltOutlined />} loading={refresh.isPending} onClick={() => refresh.mutate()}>
            Work them out again
          </Button>
        </Col>
      </Row>
      {data.is_stale && (
        <Alert
          type="warning"
          showIcon
          title="Skills have changed since this was worked out"
          description="Recompute to take the latest skills, certificates and marks into account."
        />
      )}
      <Segmented value={filter} onChange={(v) => setFilter(v as 'all' | Readiness)} options={FILTERS} />
      {rows.length === 0 ? (
        <Empty description="Nothing in this group yet" />
      ) : (
        <div>
          {rows.map((m) => (
            <MatchCard key={m.career_id} m={m} onRate={canRate ? (rating) => rate.mutate({ careerId: m.career_id, rating }) : undefined} />
          ))}
        </div>
      )}
    </Space>
  );
}

/** Staff view: pick a student, then run and read their matches. */
function StudentMatches() {
  const [studentId, setStudentId] = useState<number>();
  const [search, setSearch] = useState('');
  const { data } = useQuery({
    queryKey: ['students', 'career-picker', search],
    queryFn: () => studentsApi.list({ page: 1, page_size: 50, search }),
  });
  return (
    <Space orientation="vertical" size="middle" style={{ width: '100%' }}>
      <Select
        showSearch
        filterOption={false}
        style={{ width: '100%', maxWidth: 480 }}
        placeholder="Search a student by name or register number"
        value={studentId}
        onSearch={setSearch}
        onChange={setStudentId}
        options={(data?.data ?? []).map((s) => ({ value: s.id, label: `${s.register_no} · ${s.name}${s.class_label ? ` · ${s.class_label}` : ''}` }))}
      />
      {!studentId ? (
        <Empty description="Pick a student to see which careers fit, what is missing and what they could study" />
      ) : (
        <CareerMatchesView studentId={studentId} canRun canRate={false} />
      )}
    </Space>
  );
}

/** Add / edit a career and the skills it needs. */
function CareerForm({ career, onClose }: { career: Career | 'new' | null; onClose: () => void }) {
  const qc = useQueryClient();
  const { data: skills } = useSkills();
  const existing = career && career !== 'new' ? career : null;
  const [form, setForm] = useState<CareerInput>(() =>
    existing
      ? {
          code: existing.code,
          name: existing.name,
          domain: existing.domain,
          description: existing.description,
          avg_package: existing.avg_package,
          min_cgpa: existing.min_cgpa,
          skills: existing.skills.map((s) => ({ skill_id: s.skill_id, required_level: s.required_level, weight: s.weight, is_core: s.is_core })),
        }
      : { code: '', name: '', domain: '', description: '', avg_package: null, min_cgpa: 0, skills: [] },
  );
  const [error, setError] = useState<string>();

  const save = useMutation({
    mutationFn: () => (existing ? careersApi.update(existing.id, form) : careersApi.create(form)),
    onSuccess: () => {
      message.success(existing ? 'Career updated' : 'Career added');
      qc.invalidateQueries({ queryKey: ['careers'] });
      qc.invalidateQueries({ queryKey: ['career-matches'] });
      onClose();
    },
    onError: (e) => setError(errorMessage(e)),
  });

  const setSkill = (i: number, patch: Partial<CareerInput['skills'][number]>) =>
    setForm((f) => ({ ...f, skills: f.skills.map((s, j) => (j === i ? { ...s, ...patch } : s)) }));

  return (
    <Modal
      open={!!career}
      title={existing ? `Edit ${existing.name}` : 'New career'}
      width={760}
      onCancel={onClose}
      onOk={() => save.mutate()}
      okButtonProps={{ loading: save.isPending, disabled: !form.code.trim() || !form.name.trim() }}
      destroyOnHidden
    >
      {error && <Alert type="error" showIcon title={error} style={{ marginBottom: 12 }} />}
      <Row gutter={[12, 12]}>
        <Col xs={24} sm={8}>
          <Typography.Text type="secondary">Code</Typography.Text>
          <Input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} placeholder="SDE" />
        </Col>
        <Col xs={24} sm={16}>
          <Typography.Text type="secondary">Name</Typography.Text>
          <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Software Development Engineer" />
        </Col>
        <Col xs={24} sm={8}>
          <Typography.Text type="secondary">Domain</Typography.Text>
          <Input value={form.domain ?? ''} onChange={(e) => setForm({ ...form, domain: e.target.value })} placeholder="IT / Software" />
        </Col>
        <Col xs={12} sm={8}>
          <Typography.Text type="secondary">Typical package (LPA)</Typography.Text>
          <InputNumber min={0} max={500} style={{ width: '100%' }} value={form.avg_package ?? undefined} onChange={(v) => setForm({ ...form, avg_package: v ?? null })} />
        </Col>
        <Col xs={12} sm={8}>
          <Typography.Text type="secondary">Minimum CGPA</Typography.Text>
          <InputNumber min={0} max={10} step={0.1} style={{ width: '100%' }} value={form.min_cgpa} onChange={(v) => setForm({ ...form, min_cgpa: v ?? 0 })} />
        </Col>
        <Col span={24}>
          <Typography.Text type="secondary">What the job involves</Typography.Text>
          <Input.TextArea rows={2} value={form.description ?? ''} onChange={(e) => setForm({ ...form, description: e.target.value })} />
        </Col>
      </Row>

      <Divider style={{ marginTop: 20 }}>Skills it needs</Divider>
      <Typography.Paragraph type="secondary">
        A core skill must be met before a student counts as ready. Weight decides how much a skill moves the match score.
      </Typography.Paragraph>
      {form.skills.map((s, i) => (
        <Row key={i} gutter={8} align="middle" style={{ marginBottom: 8 }}>
          <Col flex="auto">
            <Select
              showSearch
              optionFilterProp="label"
              style={{ width: '100%' }}
              placeholder="Skill"
              value={s.skill_id || undefined}
              onChange={(v) => setSkill(i, { skill_id: v })}
              options={(skills ?? []).map((k) => ({ value: k.id, label: k.name }))}
            />
          </Col>
          <Col flex="140px">
            <Select
              style={{ width: '100%' }}
              value={s.required_level}
              onChange={(v) => setSkill(i, { required_level: v })}
              options={[1, 2, 3, 4, 5].map((l) => ({ value: l, label: `Level ${l}` }))}
            />
          </Col>
          <Col flex="130px">
            <Tooltip title="How much this skill moves the match score">
              <InputNumber min={0.1} max={10} step={0.5} style={{ width: '100%' }} prefix="weight" value={s.weight} onChange={(v) => setSkill(i, { weight: v ?? 1 })} />
            </Tooltip>
          </Col>
          <Col flex="90px">
            <Tooltip title="Core requirement">
              <Space size={4}>
                <Switch size="small" checked={s.is_core} onChange={(v) => setSkill(i, { is_core: v })} />
                <Typography.Text type="secondary">core</Typography.Text>
              </Space>
            </Tooltip>
          </Col>
          <Col flex="40px">
            <Button size="small" danger onClick={() => setForm({ ...form, skills: form.skills.filter((_, j) => j !== i) })}>
              ✕
            </Button>
          </Col>
        </Row>
      ))}
      <Button
        size="small"
        icon={<PlusOutlined />}
        onClick={() => setForm({ ...form, skills: [...form.skills, { skill_id: 0, required_level: 3, weight: 1, is_core: false }] })}
      >
        Add a skill
      </Button>
    </Modal>
  );
}

function CareerCatalogue() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [domain, setDomain] = useState<string>();
  const [editing, setEditing] = useState<Career | 'new' | null>(null);
  const { data, isLoading } = useQuery({ queryKey: ['careers', search, domain], queryFn: () => careersApi.list({ search, domain }) });
  const { data: domains } = useQuery({ queryKey: ['careers', 'domains'], queryFn: careersApi.domains });

  const remove = useMutation({
    mutationFn: (c: Career) => careersApi.remove(c.id),
    onSuccess: () => {
      message.success('Career deleted');
      qc.invalidateQueries({ queryKey: ['careers'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <>
      <Space wrap style={{ width: '100%', justifyContent: 'space-between', marginBottom: 16 }}>
        <Space wrap>
          <Input.Search allowClear placeholder="Search careers" style={{ width: 240 }} onSearch={setSearch} />
          <Select
            allowClear
            placeholder="All domains"
            style={{ width: 180 }}
            value={domain}
            onChange={setDomain}
            options={(domains ?? []).map((d) => ({ value: d, label: d }))}
          />
        </Space>
        {can('career.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setEditing('new')}>
            New career
          </Button>
        )}
      </Space>
      <Table<Career>
        rowKey="id"
        size="small"
        loading={isLoading}
        dataSource={data}
        pagination={{ pageSize: 20, hideOnSinglePage: true }}
        scroll={{ x: 900 }}
        columns={[
          {
            title: 'Career',
            width: 260,
            render: (_, c) => (
              <div>
                <b>{c.name}</b>
                <br />
                <Typography.Text type="secondary">
                  {c.code}
                  {c.domain ? ` · ${c.domain}` : ''}
                </Typography.Text>
              </div>
            ),
          },
          { title: 'Typical package', dataIndex: 'avg_package', width: 130, render: (v) => lpa(v) },
          { title: 'Min CGPA', dataIndex: 'min_cgpa', width: 100 },
          {
            title: 'Skills it needs',
            render: (_, c) => (
              <Space size={[4, 4]} wrap>
                {c.skills.map((s) => (
                  <Tag key={s.skill_id} color={s.is_core ? 'geekblue' : 'default'}>
                    {s.skill_name} L{s.required_level}
                    {s.is_core ? ' *' : ''}
                  </Tag>
                ))}
                {!c.skills.length && <Typography.Text type="secondary">none recorded</Typography.Text>}
              </Space>
            ),
          },
          { title: 'Courses', dataIndex: 'course_count', width: 90 },
          ...(can('career.update') || can('career.delete')
            ? [
                {
                  title: '',
                  key: 'x',
                  width: 140,
                  align: 'right' as const,
                  render: (_: unknown, c: Career) => (
                    <Space>
                      {can('career.update') && (
                        <Button size="small" onClick={() => setEditing(c)}>
                          Edit
                        </Button>
                      )}
                      {can('career.delete') && (
                        <Button size="small" danger onClick={() => Modal.confirm({ title: `Delete ${c.name}?`, onOk: () => remove.mutateAsync(c) })}>
                          Delete
                        </Button>
                      )}
                    </Space>
                  ),
                },
              ]
            : []),
        ]}
      />
      <CareerForm career={editing} onClose={() => setEditing(null)} />
    </>
  );
}

function CoursesMaster() {
  const { data: skills } = useSkills();
  return (
    <MasterCrud<Course>
      path="courses"
      perm="career"
      noun="course"
      fields={[
        { name: 'skill_id', label: 'Skill it teaches', type: 'select', required: true, options: (skills ?? []).map((s) => ({ value: s.id, label: s.name })) },
        { name: 'title', label: 'Course title', type: 'text', required: true },
        { name: 'provider', label: 'Provider', type: 'text', extra: 'NPTEL, Coursera, in-house…' },
        { name: 'url', label: 'Link', type: 'text' },
        { name: 'level', label: 'Level it takes you to', type: 'number', min: 1, max: 5 },
        { name: 'duration_hours', label: 'Hours', type: 'number', min: 0, max: 2000 },
        { name: 'is_certification', label: 'Gives a certificate', type: 'bool' },
        { name: 'is_free', label: 'Free', type: 'bool' },
      ]}
      columns={[
        { title: 'Course', dataIndex: 'title' },
        { title: 'Skill', dataIndex: 'skill_name', width: 170 },
        { title: 'Provider', dataIndex: 'provider', width: 140, render: (v) => v ?? '—' },
        { title: 'Takes you to', dataIndex: 'level', width: 110, render: (v) => `Level ${v}` },
        { title: 'Hours', dataIndex: 'duration_hours', width: 80, render: (v) => v ?? '—' },
        {
          title: '',
          key: 'flags',
          width: 150,
          render: (_, c) => (
            <Space size={4}>
              {c.is_free && <Tag color="green">Free</Tag>}
              {c.is_certification && <Tag color="blue">Certificate</Tag>}
            </Space>
          ),
        },
        {
          title: 'Link',
          key: 'link',
          width: 80,
          render: (_, c) =>
            c.url ? (
              <a href={c.url} target="_blank" rel="noreferrer">
                Open
              </a>
            ) : (
              <Typography.Text type="secondary">—</Typography.Text>
            ),
        },
      ]}
    />
  );
}

/** Read-only catalogue for students and parents, next to their own matches. */
function BrowseCatalogue() {
  const { data, isLoading } = useQuery({ queryKey: ['careers', '', undefined], queryFn: () => careersApi.list() });
  if (isLoading) return <Spin />;
  return (
    <Row gutter={[12, 12]}>
      {(data ?? []).map((c) => (
        <Col xs={24} md={12} key={c.id}>
          <Card size="small" title={c.name} extra={c.domain && <Tag>{c.domain}</Tag>}>
            <Typography.Paragraph type="secondary" style={{ marginBottom: 8 }}>
              {c.description}
            </Typography.Paragraph>
            <Space size={[4, 4]} wrap>
              {c.skills.map((s) => (
                <Tag key={s.skill_id} color={s.is_core ? 'geekblue' : 'default'}>
                  {s.skill_name} L{s.required_level}
                </Tag>
              ))}
            </Space>
            <Divider style={{ margin: '10px 0' }} />
            <Typography.Text type="secondary">
              Typically {lpa(c.avg_package)} · CGPA {c.min_cgpa} and above · {c.course_count} course
              {c.course_count === 1 ? '' : 's'} listed
            </Typography.Text>
          </Card>
        </Col>
      ))}
    </Row>
  );
}

export default function CareersPage() {
  const { user, can } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  const mine = audience === 'student' || audience === 'parent';

  if (mine) {
    return (
      <Card>
        <Typography.Paragraph type="secondary">
          Careers ranked against what is on record for you — skills your staff recorded, verified certificates and your
          subject marks. Each one says what is missing and what to study to close it.
        </Typography.Paragraph>
        <StudentPicker parent={audience === 'parent'}>
          {(id) => (
            <Tabs
              items={[
                {
                  key: 'matches',
                  label: audience === 'parent' ? 'Matched to them' : 'Matched to me',
                  children: <CareerMatchesView studentId={id} canRun={false} canRate={audience === 'student'} />,
                },
                { key: 'browse', label: 'All careers', children: <BrowseCatalogue /> },
              ]}
            />
          )}
        </StudentPicker>
      </Card>
    );
  }

  return (
    <Card>
      <Tabs
        items={[
          { key: 'students', label: 'Student matches', children: <StudentMatches /> },
          { key: 'catalogue', label: 'Career catalogue', children: <CareerCatalogue /> },
          ...(can('career.create') || can('career.update') ? [{ key: 'courses', label: 'Courses', children: <CoursesMaster /> }] : []),
        ]}
      />
    </Card>
  );
}
