import { useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Button,
  Card,
  Checkbox,
  Col,
  Empty,
  InputNumber,
  Modal,
  Row,
  Select,
  Space,
  Spin,
  Statistic,
  Table,
  Tabs,
  Tag,
  Tooltip,
  Typography,
  message,
} from 'antd';
import { DownloadOutlined, FilePdfOutlined, PlusOutlined, SaveOutlined, UploadOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { allocationsApi, marksApi, type EntryKey, type EntrySheet, type Target } from '../api/marks';
import { curriculumApi, studentsApi, type ClassRow } from '../api/phase2';
import { useClasses, useSemesters, useStaffOptions } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { exportsApi, uploadsApi, type MarksUploadResult } from '../api/reports';
import { JobResult, XlsxPicker } from './BulkUploadPage';

const resultColor = (r?: string | null) => (r === 'pass' ? 'green' : r === 'fail' ? 'red' : r === 'absent' ? 'volcano' : undefined);

function useExamTypes() {
  return useQuery({ queryKey: ['lookup', 'exam-types-full'], queryFn: marksApi.examTypes, staleTime: 5 * 60_000 });
}

function StatsBar({ stats, max }: { stats: EntrySheet['stats']; max?: number }) {
  return (
    <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
      <Col xs={8} md={4}><Statistic title="Entered" value={stats.entered} /></Col>
      <Col xs={8} md={4}><Statistic title="Absent" value={stats.absent} /></Col>
      <Col xs={8} md={4}><Statistic title="Pass %" value={stats.pass_percent} suffix="%" /></Col>
      <Col xs={8} md={4}><Statistic title="Failed" value={stats.failed} styles={{ content: { color: stats.failed ? '#dc2626' : undefined } }} /></Col>
      <Col xs={8} md={4}><Statistic title="Average" value={stats.average} suffix={max ? `/ ${max}` : undefined} /></Col>
      <Col xs={8} md={4}><Statistic title="Highest" value={stats.highest} /></Col>
    </Row>
  );
}

// ---------- enter marks ----------

/** Upload a filled marks template for one class · subject · exam; all-or-nothing. */
function MarksUpload({ entryKey, label, onSaved, onClose }: { entryKey: EntryKey; label: string; onSaved: (s: EntrySheet) => void; onClose: () => void }) {
  const [file, setFile] = useState<File | null>(null);
  const [dryRun, setDryRun] = useState(false);
  const [result, setResult] = useState<MarksUploadResult | null>(null);
  const run = useMutation({
    mutationFn: () => uploadsApi.marks(entryKey, file!, dryRun),
    onSuccess: (r) => {
      setResult(r);
      if (r.saved && r.sheet) {
        onSaved(r.sheet);
        message.success(`${r.job.success_rows} marks saved`);
      }
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  return (
    <Modal open title={`Upload marks · ${label}`} onCancel={onClose} width={720} footer={null} destroyOnHidden>
      <Space orientation="vertical" style={{ width: '100%' }}>
        <Typography.Paragraph type="secondary" style={{ marginBottom: 0 }}>
          Use the template downloaded for this class, subject and exam. Enter a number or <b>AB</b> for absent; blank cells are left unchanged.
          If any row has a problem, nothing is saved.
        </Typography.Paragraph>
        <XlsxPicker
          file={file}
          onChange={(f) => {
            setFile(f);
            setResult(null);
          }}
        />
        <Checkbox checked={dryRun} onChange={(e) => setDryRun(e.target.checked)}>
          <b>Dry run</b>: only check the file
        </Checkbox>
        <Space>
          <Button type="primary" icon={<UploadOutlined />} disabled={!file} loading={run.isPending} onClick={() => run.mutate()}>
            {dryRun ? 'Check file' : 'Upload and save'}
          </Button>
          {result?.saved && <Button onClick={onClose}>Done</Button>}
        </Space>
        {result && <JobResult job={result.job} okLabel={result.saved ? 'Saved' : 'Valid'} />}
      </Space>
    </Modal>
  );
}

type Draft = Record<number, { marks: number | null; absent: boolean }>;

function MarkEntry() {
  const qc = useQueryClient();
  const { data: targets, isLoading } = useQuery({ queryKey: ['marks', 'my-subjects'], queryFn: marksApi.mySubjects });
  const { data: exams } = useExamTypes();
  const [target, setTarget] = useState<Target>();
  const [examId, setExamId] = useState<number>();
  const [attempt, setAttempt] = useState(1);
  const [draft, setDraft] = useState<Draft>({});
  const [dirty, setDirty] = useState(false);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    if (!examId && exams?.length) setExamId(exams[0].id);
  }, [exams, examId]);

  const key: EntryKey | null =
    target && examId ? { class_id: target.class_id, semester_id: target.semester_id, subject_id: target.subject_id, exam_type_id: examId, attempt_no: attempt } : null;

  const { data: sheet, isFetching, error } = useQuery({ queryKey: ['marks', 'entry', key], queryFn: () => marksApi.entry(key!), enabled: !!key });

  // Reset the editable copy whenever a fresh sheet arrives.
  useEffect(() => {
    if (!sheet) return;
    const d: Draft = {};
    sheet.rows.forEach((r) => (d[r.student_id] = { marks: r.marks_obtained, absent: r.is_absent }));
    setDraft(d);
    setDirty(false);
  }, [sheet]);

  const save = useMutation({
    mutationFn: () =>
      marksApi.save(
        key!,
        sheet!.rows.map((r) => ({ student_id: r.student_id, marks_obtained: draft[r.student_id]?.absent ? null : draft[r.student_id]?.marks ?? null, is_absent: !!draft[r.student_id]?.absent })),
      ),
    onSuccess: (s) => {
      qc.setQueryData(['marks', 'entry', key], s);
      qc.invalidateQueries({ queryKey: ['students'] });
      message.success('Marks saved');
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  const grouped = useMemo(() => {
    const m = new Map<string, Target[]>();
    (targets ?? []).forEach((t) => m.set(t.class_label, [...(m.get(t.class_label) ?? []), t]));
    return [...m.entries()];
  }, [targets]);

  if (isLoading) return <Spin />;
  if (!targets?.length) return <Empty description="No subjects are allocated to you for the current academic year. Ask your HOD to allocate subjects." />;

  const tkey = (t: Target) => `${t.class_id}:${t.semester_id}:${t.subject_id}`;
  const confirmSwitch = (fn: () => void) =>
    dirty ? Modal.confirm({ title: 'Discard unsaved marks?', onOk: fn }) : fn();

  return (
    <>
      <Space wrap style={{ marginBottom: 16 }}>
        <Select
          style={{ width: 360 }}
          placeholder="Class · subject"
          showSearch
          optionFilterProp="label"
          value={target ? tkey(target) : undefined}
          onChange={(v) => confirmSwitch(() => setTarget(targets.find((t) => tkey(t) === v)))}
          options={grouped.map(([label, ts]) => ({
            label,
            options: ts.map((t) => ({ value: tkey(t), label: `${label} · Sem ${t.sem_no} · ${t.subject_code} ${t.subject_name}` })),
          }))}
        />
        <Select
          style={{ width: 220 }}
          value={examId}
          onChange={(v) => confirmSwitch(() => setExamId(v))}
          options={(exams ?? []).map((e) => ({ value: e.id, label: `${e.name} (/${e.max_marks})` }))}
        />
        <Select
          style={{ width: 170 }}
          value={attempt}
          onChange={(v) => confirmSwitch(() => setAttempt(v))}
          options={[1, 2, 3].map((n) => ({ value: n, label: n === 1 ? 'Regular exam' : `Arrear attempt ${n}` }))}
        />
      </Space>

      {!key ? (
        <Empty description="Pick a class and subject" />
      ) : error ? (
        <Alert type="error" showIcon title={errorMessage(error)} />
      ) : !sheet ? (
        <Spin />
      ) : (
        <>
          <Space wrap style={{ marginBottom: 12 }}>
            <Typography.Text strong>
              {sheet.class_label} · Sem {sheet.sem_no} · {sheet.subject_code} {sheet.subject_name} · {sheet.exam_name}
            </Typography.Text>
            <Tag>max {sheet.max_marks}</Tag>
            {sheet.is_final ? <Tag color="purple">graded · counts for CGPA</Tag> : <Tag>pass at {sheet.pass_percent}%</Tag>}
          </Space>
          {sheet.can_edit && (
            <Space wrap style={{ marginBottom: 12, display: 'flex' }}>
              <Button size="small" icon={<DownloadOutlined />} onClick={() => exportsApi.marksTemplate(key)}>
                Excel template
              </Button>
              <Button size="small" icon={<UploadOutlined />} onClick={() => (dirty ? message.warning('Save or discard your changes first') : setUploading(true))}>
                Upload Excel
              </Button>
            </Space>
          )}
          {uploading && (
            <MarksUpload
              entryKey={key}
              label={`${sheet.class_label} · ${sheet.subject_code} · ${sheet.exam_name}`}
              onSaved={(s) => {
                qc.setQueryData(['marks', 'entry', key], s);
                qc.invalidateQueries({ queryKey: ['students'] });
              }}
              onClose={() => setUploading(false)}
            />
          )}
          {!sheet.can_edit && <Alert type="info" showIcon style={{ marginBottom: 12 }} title="Read only: you are not allocated this subject for this class." />}
          <StatsBar stats={sheet.stats} max={sheet.max_marks} />
          <Table
            rowKey="student_id"
            size="small"
            loading={isFetching}
            dataSource={sheet.rows}
            pagination={false}
            scroll={{ x: 640 }}
            locale={{ emptyText: attempt > 1 ? 'No students have an arrear in this subject' : 'No students in this class' }}
            columns={[
              { title: 'Register no', dataIndex: 'register_no', width: 130 },
              {
                title: 'Name',
                dataIndex: 'name',
                render: (v, r) => (
                  <Space>
                    {v}
                    {!r.in_class && <Tooltip title="Student has moved to another class"><Tag>moved</Tag></Tooltip>}
                  </Space>
                ),
              },
              {
                title: `Marks (/${sheet.max_marks})`,
                width: 150,
                render: (_, r) => (
                  <InputNumber
                    min={0}
                    max={sheet.max_marks}
                    step={0.5}
                    style={{ width: 110 }}
                    disabled={!sheet.can_edit || draft[r.student_id]?.absent}
                    value={draft[r.student_id]?.marks ?? null}
                    onChange={(v) => {
                      setDraft((d) => ({ ...d, [r.student_id]: { marks: v, absent: false } }));
                      setDirty(true);
                    }}
                  />
                ),
              },
              {
                title: 'Absent',
                width: 90,
                render: (_, r) => (
                  <Checkbox
                    disabled={!sheet.can_edit}
                    checked={!!draft[r.student_id]?.absent}
                    onChange={(e) => {
                      setDraft((d) => ({ ...d, [r.student_id]: { marks: null, absent: e.target.checked } }));
                      setDirty(true);
                    }}
                  />
                ),
              },
              {
                title: 'Saved result',
                width: 150,
                render: (_, r) => r.result && <Space size={4}>{r.grade && <Tag color="blue">{r.grade}</Tag>}<Tag color={resultColor(r.result)}>{r.result}</Tag></Space>,
              },
            ]}
          />
          {sheet.can_edit && sheet.rows.length > 0 && (
            <Space style={{ marginTop: 16 }}>
              <Button type="primary" icon={<SaveOutlined />} loading={save.isPending} disabled={!dirty} onClick={() => save.mutate()}>
                Save marks
              </Button>
              {dirty && <Typography.Text type="warning">Unsaved changes</Typography.Text>}
            </Space>
          )}
        </>
      )}
    </>
  );
}

// ---------- class results ----------

function semestersOf(cls: ClassRow | undefined, sems: { id: number; name: string; year_level_id: number }[] | undefined) {
  return (sems ?? []).filter((s) => cls && s.year_level_id === cls.year_level_id);
}

function ClassResults() {
  const { data: classes } = useClasses();
  const { data: sems } = useSemesters();
  const { data: exams } = useExamTypes();
  const [classId, setClassId] = useState<number>();
  const [semId, setSemId] = useState<number>();
  const [examId, setExamId] = useState<number>();
  const cls = classes?.find((c) => c.id === classId);

  const { data, isFetching, error } = useQuery({
    queryKey: ['marks', 'sheet', classId, semId, examId],
    queryFn: () => marksApi.sheet({ class_id: classId!, semester_id: semId!, exam_type_id: examId! }),
    enabled: !!classId && !!semId && !!examId,
  });

  return (
    <>
      <Space wrap style={{ marginBottom: 16 }}>
        <Select
          style={{ width: 200 }}
          placeholder="Class"
          value={classId}
          onChange={(v) => {
            setClassId(v);
            setSemId(classes?.find((c) => c.id === v)?.current_semester_id ?? undefined);
          }}
          options={(classes ?? []).map((c) => ({ value: c.id, label: c.label }))}
        />
        <Select style={{ width: 160 }} placeholder="Semester" value={semId} onChange={setSemId} disabled={!cls} options={semestersOf(cls, sems).map((s) => ({ value: s.id, label: s.name }))} />
        <Select style={{ width: 220 }} placeholder="Exam" value={examId} onChange={setExamId} options={(exams ?? []).map((e) => ({ value: e.id, label: e.name }))} />
        {data && (
          <Button icon={<DownloadOutlined />} onClick={() => exportsApi.classResults({ class_id: classId!, semester_id: semId!, exam_type_id: examId! })}>
            Result sheet (.xlsx)
          </Button>
        )}
      </Space>
      {error ? (
        <Alert type="error" showIcon title={errorMessage(error)} />
      ) : !data ? (
        <Empty description={isFetching ? 'Loading…' : 'Pick a class, semester and exam'} />
      ) : (
        <>
          <Row gutter={[12, 12]} style={{ marginBottom: 16 }}>
            {data.subjects.map((s) => (
              <Col xs={24} sm={12} lg={8} key={s.id}>
                <Card size="small" title={`${s.code} · ${s.name}`}>
                  <Space wrap size={[16, 4]}>
                    <span>Pass <b>{s.stats.pass_percent}%</b></span>
                    <span>Avg <b>{s.stats.average}</b></span>
                    <span>High <b>{s.stats.highest}</b></span>
                    <span style={{ color: s.stats.failed ? '#dc2626' : undefined }}>Fail <b>{s.stats.failed}</b></span>
                    <span>Absent <b>{s.stats.absent}</b></span>
                  </Space>
                </Card>
              </Col>
            ))}
          </Row>
          <Table
            rowKey="student_id"
            size="small"
            loading={isFetching}
            dataSource={data.rows}
            pagination={false}
            scroll={{ x: 300 + data.subjects.length * 120 }}
            columns={[
              { title: 'Register no', dataIndex: 'register_no', width: 120, fixed: 'left' },
              { title: 'Name', dataIndex: 'name', width: 180 },
              ...data.subjects.map((s) => ({
                title: <Tooltip title={s.name}>{s.code}</Tooltip>,
                key: String(s.id),
                width: 120,
                render: (_: unknown, r: (typeof data.rows)[number]) => {
                  const c = r.marks[String(s.id)];
                  if (!c) return <Typography.Text type="secondary">—</Typography.Text>;
                  const txt = c.result === 'absent' ? 'AB' : `${c.marks ?? ''}${c.grade ? ` ${c.grade}` : ''}`;
                  return <Typography.Text type={c.result === 'pass' ? undefined : 'danger'}>{txt}</Typography.Text>;
                },
              })),
              { title: 'Failed', dataIndex: 'failed', width: 80, render: (v: number) => (v ? <Tag color="red">{v}</Tag> : 0) },
            ]}
          />
        </>
      )}
    </>
  );
}

// ---------- subject allocation ----------

function Allocations() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data: classes } = useClasses();
  const { data: staff } = useStaffOptions();
  const [classId, setClassId] = useState<number>();
  const [adding, setAdding] = useState<{ class_id?: number; subject_id?: number; staff_id?: number } | null>(null);
  const addClass = classes?.find((c) => c.id === adding?.class_id);

  const { data: rows, isFetching } = useQuery({ queryKey: ['allocations', classId], queryFn: () => allocationsApi.list({ class_id: classId }) });
  const { data: subjects } = useQuery({
    queryKey: ['curriculum', addClass?.department_id, addClass?.current_semester_id],
    queryFn: () => curriculumApi.list(addClass!.department_id, addClass!.current_semester_id!),
    enabled: !!addClass?.current_semester_id,
  });

  const add = useMutation({
    mutationFn: () => allocationsApi.create({ staff_id: adding!.staff_id!, class_id: adding!.class_id!, subject_id: adding!.subject_id! }),
    onSuccess: () => {
      message.success('Subject allocated');
      qc.invalidateQueries({ queryKey: ['allocations'] });
      qc.invalidateQueries({ queryKey: ['marks', 'my-subjects'] });
      setAdding(null);
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const remove = useMutation({
    mutationFn: (id: number) => allocationsApi.remove(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['allocations'] }),
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <>
      <Space wrap style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Select allowClear style={{ width: 200 }} placeholder="All classes" value={classId} onChange={setClassId} options={(classes ?? []).map((c) => ({ value: c.id, label: c.label }))} />
        {can('subject_allocation.create') && (
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setAdding({ class_id: classId })}>
            Allocate subject
          </Button>
        )}
      </Space>
      <Table
        rowKey="id"
        size="small"
        loading={isFetching}
        dataSource={rows}
        pagination={{ pageSize: 25, hideOnSinglePage: true }}
        scroll={{ x: 640 }}
        columns={[
          { title: 'Class', dataIndex: 'class_label', width: 120 },
          { title: 'Sem', dataIndex: 'sem_no', width: 70 },
          { title: 'Subject', render: (_, r) => `${r.subject_code} · ${r.subject_name}` },
          { title: 'Staff', dataIndex: 'staff_name' },
          ...(can('subject_allocation.delete')
            ? [{ title: '', key: 'x', width: 90, render: (_: unknown, r: { id: number }) => <Button size="small" danger onClick={() => Modal.confirm({ title: 'Remove this allocation?', content: 'The staff member will no longer be able to enter marks for it.', onOk: () => remove.mutateAsync(r.id) })}>Remove</Button> }]
            : []),
        ]}
      />
      <Modal title="Allocate subject" open={!!adding} onCancel={() => setAdding(null)} onOk={() => add.mutate()} okButtonProps={{ disabled: !adding?.class_id || !adding?.subject_id || !adding?.staff_id, loading: add.isPending }}>
        <Space orientation="vertical" style={{ width: '100%' }}>
          <Select style={{ width: '100%' }} placeholder="Class" value={adding?.class_id} onChange={(v) => setAdding({ class_id: v })} options={(classes ?? []).map((c) => ({ value: c.id, label: `${c.label} · ${c.current_semester_name ?? ''}` }))} />
          <Select
            style={{ width: '100%' }}
            placeholder="Subject (from the class's curriculum for its current semester)"
            value={adding?.subject_id}
            disabled={!addClass}
            onChange={(v) => setAdding((a) => ({ ...a, subject_id: v }))}
            options={(subjects ?? []).map((s) => ({ value: s.subject_id, label: `${s.subject_code} · ${s.subject_name}` }))}
            notFoundContent={addClass ? 'No curriculum for this semester. Add it in Academic Setup.' : undefined}
          />
          <Select
            style={{ width: '100%' }}
            placeholder="Staff"
            showSearch
            optionFilterProp="label"
            value={adding?.staff_id}
            onChange={(v) => setAdding((a) => ({ ...a, staff_id: v }))}
            options={(staff ?? []).filter((s) => s.roles.includes('staff') || s.roles.includes('hod')).map((s) => ({ value: s.id, label: `${s.name}${s.department_name ? ` · ${s.department_name}` : ''}` }))}
          />
        </Space>
      </Modal>
    </>
  );
}

// ---------- history (students, parents, and inside student profiles) ----------

export function MarkHistoryView({ studentId }: { studentId: number }) {
  const { data, isLoading, error } = useQuery({ queryKey: ['marks', 'history', studentId], queryFn: () => marksApi.history(studentId) });
  if (isLoading) return <Spin />;
  if (error) return <Alert type="error" showIcon title={errorMessage(error)} />;
  if (!data) return null;
  return (
    <Space orientation="vertical" size="middle" style={{ width: '100%' }}>
      <Space wrap style={{ width: '100%', justifyContent: 'flex-end' }}>
        <Button icon={<FilePdfOutlined />} onClick={() => exportsApi.statement(studentId)}>
          Mark statement (PDF)
        </Button>
      </Space>
      <Row gutter={16}>
        <Col xs={8}><Statistic title="CGPA" value={data.cgpa ? data.cgpa.toFixed(2) : '—'} /></Col>
        <Col xs={8}><Statistic title="Backlogs" value={data.backlog_count} styles={{ content: { color: data.backlog_count ? '#dc2626' : undefined } }} /></Col>
        <Col xs={8}><Statistic title="Semesters" value={data.semesters.length} /></Col>
      </Row>
      {data.semesters.length === 0 && <Empty description="No marks recorded yet" />}
      {[...data.semesters].reverse().map((sem) => {
        const examCols = [...new Map(sem.subjects.flatMap((s) => s.exams).map((e) => [e.exam_code, e])).values()];
        return (
          <Card
            key={sem.semester_id}
            size="small"
            title={
              <Space wrap>
                {sem.name}
                <Typography.Text type="secondary">{sem.academic_year}{sem.class_label ? ` · ${sem.class_label}` : ''}</Typography.Text>
              </Space>
            }
            extra={
              <Space>
                {sem.sgpa != null && <Tag color="blue">SGPA {sem.sgpa.toFixed(2)}</Tag>}
                {sem.backlogs > 0 && <Tag color="red">{sem.backlogs} backlog{sem.backlogs > 1 ? 's' : ''}</Tag>}
              </Space>
            }
          >
            <Table
              rowKey="subject_id"
              size="small"
              pagination={false}
              dataSource={sem.subjects}
              scroll={{ x: 520 }}
              columns={[
                { title: 'Subject', render: (_, s) => <span><b>{s.code}</b> {s.name}</span> },
                { title: 'Cr', dataIndex: 'credits', width: 50 },
                ...examCols.map((ec) => ({
                  title: ec.exam_code,
                  key: ec.exam_code,
                  width: 110,
                  render: (_: unknown, s: (typeof sem.subjects)[number]) => {
                    const attempts = s.exams.filter((e) => e.exam_code === ec.exam_code);
                    if (!attempts.length) return '—';
                    return attempts.map((e) => (
                      <div key={e.attempt_no}>
                        <Typography.Text type={e.result === 'pass' ? undefined : 'danger'}>
                          {e.result === 'absent' ? 'AB' : `${e.marks}/${e.max_marks}`}
                        </Typography.Text>
                        {e.attempt_no > 1 && <Typography.Text type="secondary"> (attempt {e.attempt_no})</Typography.Text>}
                      </div>
                    ));
                  },
                })),
                { title: 'Grade', width: 80, render: (_, s) => (s.final_grade ? <Tag color={resultColor(s.final_result)}>{s.final_grade}</Tag> : '—') },
              ]}
            />
          </Card>
        );
      })}
    </Space>
  );
}

function MyMarks() {
  const { data, isLoading } = useQuery({ queryKey: ['students', 'mine'], queryFn: () => studentsApi.list({ page: 1, page_size: 1 }) });
  if (isLoading) return <Spin />;
  const me = data?.data[0];
  return <Card>{me ? <MarkHistoryView studentId={me.id} /> : <Empty description="Your student profile has not been set up yet." />}</Card>;
}

function ChildrenMarks() {
  const { data, isLoading } = useQuery({ queryKey: ['students', 'children'], queryFn: () => studentsApi.list({ page: 1, page_size: 50 }) });
  const [selected, setSelected] = useState<number>();
  if (isLoading) return <Spin />;
  const kids = data?.data ?? [];
  if (!kids.length) return <Card><Empty description="No children are linked to your account yet." /></Card>;
  const active = selected ?? kids[0].id;
  return (
    <Card
      extra={kids.length > 1 && <Select value={active} onChange={setSelected} style={{ width: 220 }} options={kids.map((k) => ({ value: k.id, label: k.name }))} />}
    >
      <MarkHistoryView studentId={active} />
    </Card>
  );
}

export default function MarksPage() {
  const { user, can } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  if (audience === 'student') return <MyMarks />;
  if (audience === 'parent') return <ChildrenMarks />;
  return (
    <Card>
      <Tabs
        items={[
          ...(can('marks.create', 'marks.update') ? [{ key: 'entry', label: 'Enter marks', children: <MarkEntry /> }] : []),
          { key: 'results', label: 'Class results', children: <ClassResults /> },
          ...(can('subject_allocation.view') ? [{ key: 'alloc', label: 'Subject allocation', children: <Allocations /> }] : []),
        ]}
      />
    </Card>
  );
}
