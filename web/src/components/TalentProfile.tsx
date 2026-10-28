import { useEffect, useState } from 'react';
import dayjs from 'dayjs';
import { Alert, Button, Card, Empty, Form, Input, InputNumber, Modal, Popconfirm, Progress, Radio, Select, Space, Spin, Statistic, Table, Tag, Tooltip, Typography, message } from 'antd';
import { CheckCircleFilled, ClockCircleOutlined, DeleteOutlined, EditOutlined, PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import {
  aptitudeApi,
  COMMUNICATION_RUBRIC,
  PLATFORMS,
  RUBRIC,
  talentApi,
  type AssessmentKind,
  type AptitudeQuestion,
  type AssessmentResult,
  type CodingPlatform,
  type PlatformInput,
  type Project,
  type ProjectInput,
  type TalentProfile as Profile,
  type TraitScore,
} from '../api/talent';
import { useAuth } from '../auth/AuthContext';

const LEVEL_COLOR: Record<TraitScore['level'], string> = { high: '#16a34a', moderate: '#d97706', low: '#dc2626' };
const KIND_TITLE: Record<AssessmentKind, string> = { personality: 'Personality', interests: 'Interests and values', learning: 'Learning behaviour', communication: 'Communication and soft skills' };
const KINDS: AssessmentKind[] = ['personality', 'interests', 'learning'];
const platformLabel = (v: string) => PLATFORMS.find((p) => p.value === v)?.label ?? v;

/** Everything the college knows about a student beyond marks: psychometric results and coding data. */
export default function TalentProfile({ studentId }: { studentId: number }) {
  const { user, can } = useAuth();
  const staff = can('student_skill.update');
  const self = user?.id === studentId;
  const { data, isLoading, error } = useQuery({ queryKey: ['talent', studentId], queryFn: () => talentApi.profile(studentId) });
  if (isLoading) return <Spin style={{ display: 'block', margin: '24px auto' }} />;
  if (error || !data) return <Alert type="error" showIcon title={errorMessage(error)} />;
  return (
    <>
      <PsychometricCard studentId={studentId} profile={data} canWrite={self || staff} />
      <AptitudeCard studentId={studentId} canTake={self} />
      <CommunicationCard studentId={studentId} profile={data} canWrite={self || staff} canReview={staff && !self} />
      <CodingCard studentId={studentId} profile={data} canWrite={self || staff} canReview={staff && !self} />
    </>
  );
}

// ---------------------------------------------------------------- psychometric

function TraitBars({ traits }: { traits: TraitScore[] }) {
  return (
    <div style={{ display: 'grid', gap: 6 }}>
      {traits.map((t) => (
        <Tooltip key={t.key} title={t.meaning}>
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(120px, 210px) 1fr 70px', gap: 10, alignItems: 'center', fontSize: 13 }}>
            <span>{t.label}</span>
            <Progress percent={Math.round(t.score)} showInfo={false} strokeColor={LEVEL_COLOR[t.level]} size="small" />
            <Tag color={t.level === 'high' ? 'success' : t.level === 'low' ? 'error' : 'warning'} style={{ margin: 0, textAlign: 'center' }}>
              {t.level}
            </Tag>
          </div>
        </Tooltip>
      ))}
    </div>
  );
}

function PsychometricCard({ studentId, profile, canWrite }: { studentId: number; profile: Profile; canWrite: boolean }) {
  const [taking, setTaking] = useState<AssessmentKind | null>(null);
  return (
    <Card
      title="Psychometric profile"
      extra={profile.aptitude_score != null && <Tag color="blue">Aptitude score {profile.aptitude_score}</Tag>}
    >
      <Typography.Paragraph type="secondary">
        Short questionnaires that show working style, interests and study habits. They describe tendencies, not ability, and are meant to guide advice.
      </Typography.Paragraph>
      <Space orientation="vertical" size={20} style={{ width: '100%' }}>
        {KINDS.map((kind) => {
          const r: AssessmentResult | undefined = profile.psychometric[kind];
          return (
            <div key={kind}>
              <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }} wrap>
                <Space>
                  <Typography.Text strong>{KIND_TITLE[kind]}</Typography.Text>
                  {r && <Typography.Text type="secondary" style={{ fontSize: 12 }}>taken {dayjs(r.taken_at).format('DD MMM YYYY')}</Typography.Text>}
                </Space>
                {canWrite && (
                  <Button size="small" onClick={() => setTaking(kind)}>
                    {r ? 'Retake' : 'Take questionnaire'}
                  </Button>
                )}
              </Space>
              {r ? (
                <>
                  <Alert type="info" showIcon style={{ marginBottom: 10 }} title={r.headline} />
                  <TraitBars traits={r.traits} />
                  {kind === 'learning' && r.signals && (
                    <Typography.Text type="secondary" style={{ display: 'block', marginTop: 8, fontSize: 12 }}>
                      From the app: {r.signals.attendance_percent != null ? `attendance ${r.signals.attendance_percent}%, ` : ''}
                      {r.signals.ai_questions_30_days ?? 0} question{r.signals.ai_questions_30_days === 1 ? '' : 's'} asked to the AI assistant in the last 30 days.
                    </Typography.Text>
                  )}
                </>
              ) : (
                <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="Not taken yet" styles={{ image: { height: 40 } }} />
              )}
            </div>
          );
        })}
      </Space>
      {taking && <QuestionnaireModal studentId={studentId} kind={taking} onClose={() => setTaking(null)} />}
    </Card>
  );
}

function QuestionnaireModal({ studentId, kind, onClose }: { studentId: number; kind: AssessmentKind; onClose: () => void }) {
  const qc = useQueryClient();
  const { data: q, isLoading } = useQuery({ queryKey: ['questionnaire', kind], queryFn: () => talentApi.questionnaire(kind), staleTime: Infinity });
  const [answers, setAnswers] = useState<Record<string, number>>({});
  const save = useMutation({
    mutationFn: () => talentApi.submit(studentId, kind, answers),
    onSuccess: () => {
      message.success('Saved');
      qc.invalidateQueries({ queryKey: ['talent', studentId] });
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const total = q?.questions.length ?? 0;
  const done = Object.keys(answers).length;
  const firstValue = q?.questions.findIndex((x) => x.trait.startsWith('val_')) ?? -1;

  return (
    <Modal
      open
      title={q?.title ?? KIND_TITLE[kind]}
      width={680}
      onCancel={() => !save.isPending && onClose()}
      okText="Save answers"
      okButtonProps={{ disabled: !q || done < total, loading: save.isPending }}
      onOk={() => save.mutate()}
      destroyOnHidden
    >
      {isLoading || !q ? (
        <Spin style={{ display: 'block', margin: '32px auto' }} />
      ) : (
        <>
          <Typography.Paragraph type="secondary">{q.intro}</Typography.Paragraph>
          <Typography.Paragraph style={{ fontSize: 12 }}>
            {q.scale.map((s, i) => `${i + 1} = ${s}`).join('  ·  ')}
          </Typography.Paragraph>
          <Progress percent={total ? Math.round((done / total) * 100) : 0} format={() => `${done}/${total}`} size="small" />
          <div style={{ maxHeight: 420, overflowY: 'auto', marginTop: 12, paddingRight: 6 }}>
            {q.questions.map((x, i) => (
              <div key={x.id} style={{ marginBottom: 14 }}>
                {i === firstValue && <Typography.Title level={5}>What matters to you in a job?</Typography.Title>}
                <div style={{ marginBottom: 4 }}>
                  {i + 1}. {x.text}
                </div>
                <Radio.Group
                  optionType="button"
                  size="small"
                  value={answers[x.id]}
                  onChange={(e) => setAnswers((cur) => ({ ...cur, [x.id]: e.target.value }))}
                  options={[1, 2, 3, 4, 5].map((n) => ({ value: n, label: String(n) }))}
                />
              </div>
            ))}
          </div>
        </>
      )}
    </Modal>
  );
}

// ---------------------------------------------------------------- coding

function CodingCard({ studentId, profile, canWrite, canReview }: { studentId: number; profile: Profile; canWrite: boolean; canReview: boolean }) {
  const qc = useQueryClient();
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['talent', studentId] });
    qc.invalidateQueries({ queryKey: ['analyzer'] });
  };
  const c = profile.coding;
  const [platform, setPlatform] = useState<{ row: CodingPlatform | null } | null>(null);
  const [project, setProject] = useState<{ row: Project | null } | null>(null);
  const [review, setReview] = useState<Project | null>(null);

  const verify = useMutation({
    mutationFn: (v: { id: number; verified: boolean }) => talentApi.verifyPlatform(v.id, v.verified),
    onSuccess: refresh,
    onError: (e) => message.error(errorMessage(e)),
  });
  const removePlatform = useMutation({ mutationFn: talentApi.removePlatform, onSuccess: refresh, onError: (e) => message.error(errorMessage(e)) });
  const removeProject = useMutation({ mutationFn: talentApi.removeProject, onSuccess: refresh, onError: (e) => message.error(errorMessage(e)) });

  const status = (verified: boolean) =>
    verified ? (
      <Tag icon={<CheckCircleFilled />} color="success">
        Verified
      </Tag>
    ) : (
      <Tag icon={<ClockCircleOutlined />}>Waiting for staff</Tag>
    );

  return (
    <Card title="Coding profile" style={{ marginTop: 16 }}>
      <Space size={32} wrap align="start" style={{ marginBottom: 16 }}>
        <Tooltip title={c.formula}>
          <div>
            <Statistic title="Programming skill index" value={c.index ?? '—'} suffix={c.index != null ? '/ 100' : undefined} />
          </div>
        </Tooltip>
        <Statistic title="Platform score" value={c.platform_score ?? '—'} styles={{ content: { fontSize: 20 } }} />
        <Statistic title="Project score" value={c.project_score ?? '—'} styles={{ content: { fontSize: 20 } }} />
      </Space>
      {c.index == null ? (
        <Alert type="info" showIcon style={{ marginBottom: 16 }} title="No verified coding data yet. Add your coding platform profiles and projects; once a staff member verifies them, the index appears here and counts towards placement readiness." />
      ) : (
        <Typography.Paragraph type="secondary" style={{ fontSize: 12 }}>
          {c.formula} Counted: {c.problems_counted} problems on {c.verified_platforms} verified platform{c.verified_platforms === 1 ? '' : 's'}, {c.verified_projects} reviewed project{c.verified_projects === 1 ? '' : 's'}.
        </Typography.Paragraph>
      )}

      <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }}>
        <Typography.Text strong>Coding platforms</Typography.Text>
        {canWrite && (
          <Button size="small" icon={<PlusOutlined />} onClick={() => setPlatform({ row: null })}>
            Add platform
          </Button>
        )}
      </Space>
      <Table<CodingPlatform>
        rowKey="id"
        size="small"
        pagination={false}
        dataSource={c.profiles}
        locale={{ emptyText: 'No platforms added' }}
        scroll={{ x: 560 }}
        style={{ marginBottom: 20 }}
        columns={[
          { title: 'Platform', dataIndex: 'platform', render: (v: string) => platformLabel(v) },
          { title: 'Username', dataIndex: 'username', render: (v: string, r) => (r.profile_url ? <Typography.Link href={r.profile_url} target="_blank" rel="noreferrer">{v}</Typography.Link> : v) },
          { title: 'Solved', dataIndex: 'problems_solved', align: 'right', width: 80 },
          { title: 'Rating', dataIndex: 'rating', align: 'right', width: 80, render: (v: number | null) => v ?? '—' },
          { title: 'Status', dataIndex: 'verified', width: 150, render: (v: boolean) => status(v) },
          {
            title: '',
            key: 'x',
            width: 210,
            align: 'right',
            render: (_, r) => (
              <Space size={4}>
                {canReview && (
                  <Button size="small" type={r.verified ? 'default' : 'primary'} onClick={() => verify.mutate({ id: r.id, verified: !r.verified })}>
                    {r.verified ? 'Unverify' : 'Verify'}
                  </Button>
                )}
                {canWrite && <Button size="small" icon={<EditOutlined />} aria-label="Edit platform" onClick={() => setPlatform({ row: r })} />}
                {canWrite && (
                  <Popconfirm title="Remove this platform?" okText="Remove" okButtonProps={{ danger: true }} onConfirm={() => removePlatform.mutate(r.id)}>
                    <Button size="small" danger icon={<DeleteOutlined />} aria-label="Remove platform" />
                  </Popconfirm>
                )}
              </Space>
            ),
          },
        ]}
      />

      <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }}>
        <Typography.Text strong>Projects</Typography.Text>
        {canWrite && (
          <Button size="small" icon={<PlusOutlined />} onClick={() => setProject({ row: null })}>
            Add project
          </Button>
        )}
      </Space>
      <Table<Project>
        rowKey="id"
        size="small"
        pagination={false}
        dataSource={c.projects}
        locale={{ emptyText: 'No projects added' }}
        scroll={{ x: 620 }}
        columns={[
          {
            title: 'Project',
            dataIndex: 'title',
            render: (v: string, r) => (
              <div>
                <div style={{ fontWeight: 500 }}>{v}</div>
                {r.tech_stack && <div style={{ fontSize: 12, opacity: 0.65 }}>{r.tech_stack}</div>}
                <Space size={8} style={{ fontSize: 12 }}>
                  {r.repo_url && <Typography.Link href={r.repo_url} target="_blank" rel="noreferrer">Code</Typography.Link>}
                  {r.live_url && <Typography.Link href={r.live_url} target="_blank" rel="noreferrer">Live</Typography.Link>}
                </Space>
              </div>
            ),
          },
          { title: 'Stage', dataIndex: 'status', width: 100, render: (v: string) => <Tag>{v}</Tag> },
          {
            title: 'Code quality',
            width: 170,
            render: (_, r) =>
              r.verified ? (
                <Tooltip title={r.review_notes || undefined}>
                  <Space size={4}>
                    {status(true)}
                    {r.quality_score != null && <b>{r.quality_score}</b>}
                  </Space>
                </Tooltip>
              ) : (
                status(false)
              ),
          },
          {
            title: '',
            key: 'x',
            width: 210,
            align: 'right',
            render: (_, r) => (
              <Space size={4}>
                {canReview && (
                  <Button size="small" type={r.verified ? 'default' : 'primary'} onClick={() => setReview(r)}>
                    {r.verified ? 'Re-review' : 'Review'}
                  </Button>
                )}
                {canWrite && <Button size="small" icon={<EditOutlined />} aria-label="Edit project" onClick={() => setProject({ row: r })} />}
                {canWrite && (
                  <Popconfirm title="Remove this project?" okText="Remove" okButtonProps={{ danger: true }} onConfirm={() => removeProject.mutate(r.id)}>
                    <Button size="small" danger icon={<DeleteOutlined />} aria-label="Remove project" />
                  </Popconfirm>
                )}
              </Space>
            ),
          },
        ]}
      />

      {platform && <PlatformModal studentId={studentId} row={platform.row} onClose={() => setPlatform(null)} onSaved={refresh} />}
      {project && <ProjectModal studentId={studentId} row={project.row} onClose={() => setProject(null)} onSaved={refresh} />}
      {review && <ReviewModal project={review} onClose={() => setReview(null)} onSaved={refresh} />}
    </Card>
  );
}

function PlatformModal({ studentId, row, onClose, onSaved }: { studentId: number; row: CodingPlatform | null; onClose: () => void; onSaved: () => void }) {
  const [form] = Form.useForm<PlatformInput>();
  const save = useMutation({
    mutationFn: (v: PlatformInput) => (row ? talentApi.updatePlatform(row.id, v) : talentApi.addPlatform(studentId, v)),
    onSuccess: () => {
      message.success(row ? 'Saved. It needs to be verified again.' : 'Added. A staff member will verify it.');
      onSaved();
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  return (
    <Modal open title={row ? 'Edit platform' : 'Add coding platform'} onCancel={onClose} onOk={() => form.validateFields().then((v) => save.mutate(v))} okButtonProps={{ loading: save.isPending }} destroyOnHidden>
      <Form form={form} layout="vertical" initialValues={row ?? { platform: 'leetcode', problems_solved: 0 }}>
        <Form.Item name="platform" label="Platform" rules={[{ required: true }]}>
          <Select options={PLATFORMS} />
        </Form.Item>
        <Form.Item name="username" label="Username" rules={[{ required: true, message: 'Enter your username on that platform' }]}>
          <Input maxLength={100} />
        </Form.Item>
        <Form.Item name="profile_url" label="Profile link (optional)" extra="Staff use this to check the numbers.">
          <Input placeholder="https://leetcode.com/u/yourname" />
        </Form.Item>
        <Form.Item name="problems_solved" label="Problems solved" rules={[{ required: true }]}>
          <InputNumber min={0} max={100000} style={{ width: '100%' }} />
        </Form.Item>
        <Form.Item name="rating" label="Rating (optional)">
          <InputNumber min={0} max={10000} style={{ width: '100%' }} />
        </Form.Item>
      </Form>
    </Modal>
  );
}

function ProjectModal({ studentId, row, onClose, onSaved }: { studentId: number; row: Project | null; onClose: () => void; onSaved: () => void }) {
  const [form] = Form.useForm<ProjectInput>();
  const save = useMutation({
    mutationFn: (v: ProjectInput) => (row ? talentApi.updateProject(row.id, v) : talentApi.addProject(studentId, v)),
    onSuccess: () => {
      message.success(row ? 'Saved. It needs to be reviewed again.' : 'Added. A staff member will review it.');
      onSaved();
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  return (
    <Modal open title={row ? 'Edit project' : 'Add project'} onCancel={onClose} onOk={() => form.validateFields().then((v) => save.mutate(v))} okButtonProps={{ loading: save.isPending }} destroyOnHidden>
      <Form form={form} layout="vertical" initialValues={row ?? { status: 'completed' }}>
        <Form.Item name="title" label="Title" rules={[{ required: true, message: 'Give the project a title' }]}>
          <Input maxLength={150} />
        </Form.Item>
        <Form.Item name="description" label="What it does">
          <Input.TextArea rows={3} maxLength={2000} />
        </Form.Item>
        <Form.Item name="tech_stack" label="Technologies">
          <Input maxLength={300} placeholder="e.g. Java, Spring Boot, React" />
        </Form.Item>
        <Form.Item name="repo_url" label="Code repository link" extra="Staff review the code here, so a public link helps.">
          <Input placeholder="https://github.com/you/project" />
        </Form.Item>
        <Form.Item name="live_url" label="Live demo link (optional)">
          <Input placeholder="https://" />
        </Form.Item>
        <Form.Item name="status" label="Stage">
          <Select options={[{ value: 'completed', label: 'Completed' }, { value: 'ongoing', label: 'Ongoing' }]} />
        </Form.Item>
      </Form>
    </Modal>
  );
}

/** Staff rate the project's code on four criteria; the average becomes its quality score. */
function ReviewModal({ project, onClose, onSaved }: { project: Project; onClose: () => void; onSaved: () => void }) {
  const [rubric, setRubric] = useState<Record<string, number>>(project.rubric ?? {});
  const [notes, setNotes] = useState(project.review_notes ?? '');
  const complete = RUBRIC.every((r) => rubric[r.key]);
  const save = useMutation({
    mutationFn: (verified: boolean) => talentApi.reviewProject(project.id, verified ? { verified: true, rubric, notes } : { verified: false }),
    onSuccess: () => {
      message.success('Saved');
      onSaved();
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  return (
    <Modal
      open
      title={`Review: ${project.title}`}
      onCancel={onClose}
      destroyOnHidden
      footer={
        <Space>
          {project.verified && (
            <Button danger onClick={() => save.mutate(false)} loading={save.isPending}>
              Withdraw verification
            </Button>
          )}
          <Button onClick={onClose}>Cancel</Button>
          <Button type="primary" disabled={!complete} loading={save.isPending} onClick={() => save.mutate(true)}>
            Verify with these ratings
          </Button>
        </Space>
      }
    >
      <Typography.Paragraph type="secondary">
        Open the repository and rate the code from 1 (poor) to 5 (excellent). The average of the four ratings becomes the project&rsquo;s code-quality score.
      </Typography.Paragraph>
      {project.repo_url && (
        <Typography.Paragraph>
          <Typography.Link href={project.repo_url} target="_blank" rel="noreferrer">
            Open repository
          </Typography.Link>
        </Typography.Paragraph>
      )}
      {RUBRIC.map((r) => (
        <div key={r.key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
          <span>{r.label}</span>
          <Radio.Group optionType="button" value={rubric[r.key]} onChange={(e) => setRubric((cur) => ({ ...cur, [r.key]: e.target.value }))} options={[1, 2, 3, 4, 5].map((n) => ({ value: n, label: String(n) }))} />
        </div>
      ))}
      <Input.TextArea rows={2} maxLength={1000} placeholder="Notes for the student (optional)" value={notes} onChange={(e) => setNotes(e.target.value)} />
    </Modal>
  );
}

// ---------------------------------------------------------------- aptitude

const SECTION_LABEL: Record<string, string> = { quantitative: 'Quantitative', logical: 'Logical reasoning', verbal: 'Verbal' };
const percentColor = (p: number) => (p >= 65 ? '#16a34a' : p >= 40 ? '#d97706' : '#dc2626');

function SectionBars({ sections }: { sections: Record<string, { correct: number; total: number; percent: number }> }) {
  return (
    <div style={{ display: 'grid', gap: 6, marginBottom: 12 }}>
      {Object.entries(sections).map(([key, s]) => (
        <div key={key} style={{ display: 'grid', gridTemplateColumns: 'minmax(120px, 210px) 1fr 60px', gap: 10, alignItems: 'center', fontSize: 13 }}>
          <span>{SECTION_LABEL[key] ?? key}</span>
          <Progress percent={Math.round(s.percent)} showInfo={false} strokeColor={percentColor(s.percent)} size="small" />
          <span>
            {s.correct}/{s.total}
          </span>
        </div>
      ))}
    </div>
  );
}

function AptitudeCard({ studentId, canTake }: { studentId: number; canTake: boolean }) {
  const { data, isLoading } = useQuery({ queryKey: ['aptitude', studentId], queryFn: () => aptitudeApi.summary(studentId) });
  const [taking, setTaking] = useState(false);
  if (isLoading || !data) return null;
  const waitUntil = data.can_take_after ? dayjs(data.can_take_after) : null;
  const blocked = !data.in_progress && !!waitUntil;
  return (
    <Card title="Aptitude test" style={{ marginTop: 16 }} extra={data.latest && <Tag color="blue">Score {data.latest.score}</Tag>}>
      <Typography.Paragraph type="secondary">
        {data.per_section * 3} questions (quantitative, logical and verbal), {Math.round(data.time_limit_sec / 60)} minutes. The latest score counts towards placement readiness, and the test can be repeated once a day.
      </Typography.Paragraph>
      {data.latest ? (
        <>
          <SectionBars sections={data.latest.sections} />
          <Typography.Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 12 }}>
            Taken {dayjs(data.latest.submitted_at).format('DD MMM YYYY, HH:mm')}
            {data.history.length > 1 && ` · earlier scores: ${data.history.slice(1, 5).map((h) => h.score).join(', ')}`}
          </Typography.Text>
        </>
      ) : (
        <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="Not taken yet" styles={{ image: { height: 40 } }} />
      )}
      {canTake && (
        <Tooltip title={blocked ? `You can take the test again after ${waitUntil!.format('DD MMM, HH:mm')}` : undefined}>
          <span>
            <Button type="primary" disabled={blocked} onClick={() => setTaking(true)}>
              {data.in_progress ? 'Resume test' : data.latest ? 'Take the test again' : 'Take the test'}
            </Button>
          </span>
        </Tooltip>
      )}
      {taking && <AptitudeTestModal studentId={studentId} onClose={() => setTaking(false)} />}
    </Card>
  );
}

function AptitudeTestModal({ studentId, onClose }: { studentId: number; onClose: () => void }) {
  const qc = useQueryClient();
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [secondsLeft, setSecondsLeft] = useState<number | null>(null);
  const [result, setResult] = useState<Awaited<ReturnType<typeof aptitudeApi.submit>> | null>(null);

  const { data: attempt, isLoading } = useQuery({
    queryKey: ['aptitude-attempt', studentId],
    queryFn: () => aptitudeApi.start(studentId),
    staleTime: Infinity,
    gcTime: 0,
    retry: false,
  });

  const submit = useMutation({
    mutationFn: () => aptitudeApi.submit(attempt!.attempt_id, answers),
    onSuccess: (r) => {
      setResult(r);
      qc.invalidateQueries({ queryKey: ['aptitude', studentId] });
      qc.invalidateQueries({ queryKey: ['talent', studentId] });
      qc.invalidateQueries({ queryKey: ['analyzer'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  // The clock starts when the questions arrive, from the time the server says is left.
  const [deadline, setDeadline] = useState<number | null>(null);
  if (attempt && deadline === null) setDeadline(Date.now() + attempt.remaining_sec * 1000);
  useEffect(() => {
    if (deadline === null || result) return;
    const tick = () => {
      const left = Math.max(0, Math.round((deadline - Date.now()) / 1000));
      setSecondsLeft(left);
      if (left === 0 && !submit.isPending && !submit.isSuccess) submit.mutate();
    };
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [deadline, result]);

  const questions: AptitudeQuestion[] = attempt?.questions ?? [];
  const answered = Object.keys(answers).length;
  const clock = secondsLeft == null ? '' : `${Math.floor(secondsLeft / 60)}:${String(secondsLeft % 60).padStart(2, '0')}`;
  const cantStart = !isLoading && !attempt;

  return (
    <Modal
      open
      width={720}
      title={result ? 'Your result' : 'Aptitude test'}
      closable={!!result || cantStart}
      maskClosable={false}
      keyboard={false}
      onCancel={onClose}
      destroyOnHidden
      footer={
        result || cantStart ? (
          <Button type="primary" onClick={onClose}>
            Close
          </Button>
        ) : (
          <Space>
            <Typography.Text type={secondsLeft != null && secondsLeft < 60 ? 'danger' : 'secondary'}>Time left {clock}</Typography.Text>
            <Button
              type="primary"
              loading={submit.isPending}
              disabled={!attempt}
              onClick={() =>
                Modal.confirm({
                  title: answered < questions.length ? `Submit with ${questions.length - answered} unanswered?` : 'Submit your answers?',
                  content: 'You cannot change them afterwards.',
                  okText: 'Submit',
                  onOk: () => submit.mutateAsync(),
                })
              }
            >
              Submit ({answered}/{questions.length})
            </Button>
          </Space>
        )
      }
    >
      {cantStart ? (
        <Alert type="warning" showIcon title="The test could not be started. You may need to wait before taking it again." />
      ) : isLoading ? (
        <Spin style={{ display: 'block', margin: '32px auto' }} />
      ) : result ? (
        <>
          <Statistic title="Score" value={result.score} suffix="/ 100" />
          <Typography.Paragraph type="secondary" style={{ margin: '8px 0 12px' }}>
            {result.correct} of {result.total} correct.
          </Typography.Paragraph>
          <SectionBars sections={result.sections} />
        </>
      ) : (
        <div style={{ maxHeight: 460, overflowY: 'auto', paddingRight: 6 }}>
          {questions.map((q, i) => (
            <div key={q.id} style={{ marginBottom: 16 }}>
              <div style={{ marginBottom: 4 }}>
                <Tag>{SECTION_LABEL[q.section]}</Tag> {i + 1}. {q.text}
              </div>
              <Radio.Group
                value={answers[q.id]}
                onChange={(e) => setAnswers((cur) => ({ ...cur, [q.id]: e.target.value }))}
                options={q.options.map((o, k) => ({ value: 'abcd'[k], label: `${'ABCD'[k]}. ${o}` }))}
                style={{ display: 'grid', gap: 4 }}
              />
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}

// ---------------------------------------------------------------- communication

function CommunicationCard({ studentId, profile, canWrite, canReview }: { studentId: number; profile: Profile; canWrite: boolean; canReview: boolean }) {
  const [taking, setTaking] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const c = profile.communication;
  return (
    <Card title="Communication and soft skills" style={{ marginTop: 16 }} extra={c.score != null && <Tag color="blue">Score {c.score}</Tag>}>
      <Typography.Paragraph type="secondary">{c.formula}</Typography.Paragraph>

      <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }} wrap>
        <Typography.Text strong>Staff review</Typography.Text>
        {canReview && (
          <Button size="small" onClick={() => setReviewing(true)}>
            {c.review ? 'Update review' : 'Rate communication'}
          </Button>
        )}
      </Space>
      {c.review ? (
        <div style={{ marginBottom: 16 }}>
          <div style={{ display: 'grid', gap: 6 }}>
            {COMMUNICATION_RUBRIC.map((r) => {
              const v = c.review!.rubric[r.key] ?? 0;
              return (
                <div key={r.key} style={{ display: 'grid', gridTemplateColumns: 'minmax(120px, 210px) 1fr 40px', gap: 10, alignItems: 'center', fontSize: 13 }}>
                  <span>{r.label}</span>
                  <Progress percent={v * 20} showInfo={false} strokeColor={percentColor(v * 20)} size="small" />
                  <span>{v}/5</span>
                </div>
              );
            })}
          </div>
          <Typography.Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 6 }}>
            Reviewed {dayjs(c.review.reviewed_at).format('DD MMM YYYY')}
            {c.review.reviewed_by ? ` by ${c.review.reviewed_by}` : ''}
            {c.review.notes ? `. ${c.review.notes}` : ''}
          </Typography.Text>
        </div>
      ) : (
        <Alert type="info" showIcon style={{ marginBottom: 16 }} title="Not reviewed yet. The score appears once a staff member has rated communication." />
      )}

      <Space style={{ width: '100%', justifyContent: 'space-between', marginBottom: 8 }} wrap>
        <Space>
          <Typography.Text strong>Self-assessment</Typography.Text>
          {c.self && (
            <Typography.Text type="secondary" style={{ fontSize: 12 }}>
              taken {dayjs(c.self.taken_at).format('DD MMM YYYY')}
            </Typography.Text>
          )}
        </Space>
        {canWrite && (
          <Button size="small" onClick={() => setTaking(true)}>
            {c.self ? 'Retake' : 'Take questionnaire'}
          </Button>
        )}
      </Space>
      {c.self ? (
        <>
          <Alert type="info" showIcon style={{ marginBottom: 10 }} title={c.self.headline} />
          <TraitBars traits={c.self.traits} />
        </>
      ) : (
        <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="Not taken yet" styles={{ image: { height: 40 } }} />
      )}
      {taking && <QuestionnaireModal studentId={studentId} kind="communication" onClose={() => setTaking(false)} />}
      {reviewing && <CommunicationReviewModal studentId={studentId} existing={c.review} onClose={() => setReviewing(false)} />}
    </Card>
  );
}

function CommunicationReviewModal({ studentId, existing, onClose }: { studentId: number; existing: Profile['communication']['review']; onClose: () => void }) {
  const qc = useQueryClient();
  const [rubric, setRubric] = useState<Record<string, number>>(existing?.rubric ?? {});
  const [notes, setNotes] = useState(existing?.notes ?? '');
  const save = useMutation({
    mutationFn: () => talentApi.reviewCommunication(studentId, rubric, notes),
    onSuccess: () => {
      message.success('Saved');
      qc.invalidateQueries({ queryKey: ['talent', studentId] });
      qc.invalidateQueries({ queryKey: ['analyzer'] });
      onClose();
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const complete = COMMUNICATION_RUBRIC.every((r) => rubric[r.key]);
  return (
    <Modal open title="Rate communication" onCancel={onClose} okText="Save review" okButtonProps={{ disabled: !complete, loading: save.isPending }} onOk={() => save.mutate()} destroyOnHidden>
      <Typography.Paragraph type="secondary">Rate each area from 1 (needs a lot of work) to 5 (excellent), based on presentations, viva, group work and written submissions.</Typography.Paragraph>
      {COMMUNICATION_RUBRIC.map((r) => (
        <div key={r.key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
          <span>{r.label}</span>
          <Radio.Group optionType="button" value={rubric[r.key]} onChange={(e) => setRubric((cur) => ({ ...cur, [r.key]: e.target.value }))} options={[1, 2, 3, 4, 5].map((n) => ({ value: n, label: String(n) }))} />
        </div>
      ))}
      <Input.TextArea rows={2} maxLength={1000} placeholder="Notes for the student (optional)" value={notes} onChange={(e) => setNotes(e.target.value)} />
    </Modal>
  );
}
