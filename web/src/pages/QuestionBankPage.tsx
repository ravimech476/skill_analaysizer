import { useState } from 'react';
import { Alert, Button, Card, Form, Modal, Progress, Space, Table, Tabs, Tag, Typography, message, type FormInstance } from 'antd';
import { BulbOutlined, ThunderboltOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { bloomsApi, REVIEW_BATCH, type BloomReviewItem, type BloomSuggestion, type Confidence } from '../api/blooms';
import { errorMessage } from '../api/client';
import { mastersApi, type Subject, type ExamType } from '../api/phase2';
import { useAuth } from '../auth/AuthContext';
import MasterCrud from '../components/MasterCrud';
import QuestionPapers from '../components/QuestionPapers';
import { QuestionsUpload } from './BulkUploadPage';

const BLOOMS_LEVELS = [
  { value: 'remember', label: 'Remember' },
  { value: 'understand', label: 'Understand' },
  { value: 'apply', label: 'Apply' },
  { value: 'analyze', label: 'Analyze' },
  { value: 'evaluate', label: 'Evaluate' },
  { value: 'create', label: 'Create' },
];

const BLOOMS_COLORS: Record<string, string> = {
  remember: 'default',
  understand: 'blue',
  apply: 'cyan',
  analyze: 'orange',
  evaluate: 'purple',
  create: 'green',
};

const CONFIDENCE: Record<Confidence, { color: string; label: string }> = {
  high: { color: 'success', label: 'High confidence' },
  medium: { color: 'processing', label: 'Medium confidence' },
  low: { color: 'warning', label: 'Please check' },
};

const levelLabel = (v: string | null | undefined) => BLOOMS_LEVELS.find((b) => b.value === v)?.label ?? v ?? '—';
const LevelTag = ({ level }: { level: string | null | undefined }) => (level ? <Tag color={BLOOMS_COLORS[level]}>{levelLabel(level)}</Tag> : <>—</>);

interface QuestionRow {
  id: number;
  subject_id: number;
  subject_name: string;
  exam_type_id: number | null;
  exam_type_name: string | null;
  year: number | null;
  question: string;
  marks: number;
  blooms_level: string | null;
  unit: string | null;
  is_active: boolean;
}

/** In the question form: asks the AI for a level and lets staff drop it into the field. */
function SuggestLevel({ form }: { form: FormInstance }) {
  const [result, setResult] = useState<BloomSuggestion | null>(null);
  const [error, setError] = useState<string>();
  const question = Form.useWatch('question', form) as string | undefined;
  const marks = Form.useWatch('marks', form) as number | undefined;
  const suggest = useMutation({
    mutationFn: () => bloomsApi.suggest(question ?? '', marks),
    onMutate: () => {
      setError(undefined);
      setResult(null);
    },
    onSuccess: setResult,
    onError: (e) => setError(errorMessage(e)),
  });

  const hasQuestion = !!question?.trim();
  return (
    <div style={{ marginTop: -8, marginBottom: 16 }}>
      <Button size="small" icon={<BulbOutlined />} loading={suggest.isPending} onClick={() => suggest.mutate()} disabled={!hasQuestion && !suggest.isPending}>
        Suggest level with AI
      </Button>
      {!hasQuestion && <Typography.Text type="secondary" style={{ marginLeft: 8, fontSize: 12 }}>Type the question first</Typography.Text>}
      {error && <Alert type="error" showIcon title={error} style={{ marginTop: 8 }} />}
      {result && (
        <Alert
          style={{ marginTop: 8 }}
          type={result.confidence === 'low' ? 'warning' : 'info'}
          showIcon
          title={
            <Space wrap>
              <LevelTag level={result.level} />
              <Tag color={CONFIDENCE[result.confidence].color}>{CONFIDENCE[result.confidence].label}</Tag>
            </Space>
          }
          description={
            <>
              <div>{result.reason}</div>
              <Button
                size="small"
                type="link"
                style={{ paddingInline: 0 }}
                onClick={() => {
                  form.setFieldValue('blooms_level', result.level);
                  setResult(null);
                }}
              >
                Use “{levelLabel(result.level)}”
              </Button>
            </>
          }
        />
      )}
    </div>
  );
}

/** Classifies every question in small batches and lets staff accept the suggestions that differ from what is saved. */
function BloomsReview() {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [running, setRunning] = useState(false);
  const [progress, setProgress] = useState({ done: 0, total: 0 });
  const [items, setItems] = useState<BloomReviewItem[]>([]);
  const [selected, setSelected] = useState<number[]>([]);
  const [error, setError] = useState<string>();

  const start = async () => {
    setOpen(true);
    setRunning(true);
    setError(undefined);
    setItems([]);
    setSelected([]);
    try {
      const all = await mastersApi.list<QuestionRow>('question-bank', { all: true });
      const ids = all.data.map((q) => q.id);
      setProgress({ done: 0, total: ids.length });
      const found: BloomReviewItem[] = [];
      for (let i = 0; i < ids.length; i += REVIEW_BATCH) {
        const batch = await bloomsApi.review(ids.slice(i, i + REVIEW_BATCH));
        found.push(...batch.filter((b) => b.differs));
        setItems([...found]);
        // Pre-tick what is safe to accept in one go; low-confidence ones are left for a person to decide.
        setSelected(found.filter((f) => f.confidence !== 'low').map((f) => f.id));
        setProgress({ done: Math.min(i + REVIEW_BATCH, ids.length), total: ids.length });
      }
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setRunning(false);
    }
  };

  const apply = useMutation({
    mutationFn: () => bloomsApi.apply(items.filter((i) => selected.includes(i.id)).map((i) => ({ id: i.id, level: i.level }))),
    onSuccess: (r) => {
      message.success(`Updated ${r.updated} question${r.updated === 1 ? '' : 's'}`);
      qc.invalidateQueries({ queryKey: ['master', 'question-bank'] });
      setOpen(false);
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <>
      <Button icon={<ThunderboltOutlined />} onClick={start}>
        Review Bloom’s levels
      </Button>
      <Modal
        title="Review Bloom’s levels"
        open={open}
        width={860}
        onCancel={() => !apply.isPending && setOpen(false)}
        okText={`Apply ${selected.length} selected`}
        okButtonProps={{ disabled: selected.length === 0 || running, loading: apply.isPending }}
        onOk={() => apply.mutate()}
        destroyOnHidden
      >
        <Typography.Paragraph type="secondary">
          The AI reads each question and compares its level with what is saved. Tick the suggestions you accept. Nothing changes until you press Apply.
        </Typography.Paragraph>
        {running && <Progress percent={progress.total ? Math.round((progress.done / progress.total) * 100) : 0} status="active" format={() => `${progress.done}/${progress.total}`} />}
        {error && <Alert type="error" showIcon title={error} style={{ marginBottom: 12 }} />}
        {!running && !error && items.length === 0 && <Alert type="success" showIcon title="Every question already has the level the AI would suggest." />}
        {items.length > 0 && (
          <Table<BloomReviewItem>
            rowKey="id"
            size="small"
            dataSource={items}
            pagination={{ pageSize: 8, hideOnSinglePage: true }}
            rowSelection={{ selectedRowKeys: selected, onChange: (keys) => setSelected(keys as number[]) }}
            columns={[
              {
                title: 'Question',
                dataIndex: 'question',
                render: (v: string, r) => (
                  <>
                    <div>{v.length > 110 ? v.slice(0, 110) + '…' : v}</div>
                    <Typography.Text type="secondary" style={{ fontSize: 12 }}>{r.subject} · {r.marks} marks</Typography.Text>
                  </>
                ),
              },
              { title: 'Saved', dataIndex: 'current', width: 110, render: (v: string) => <LevelTag level={v} /> },
              {
                title: 'AI suggests',
                width: 190,
                render: (_, r) => (
                  <Space orientation="vertical" size={2}>
                    <LevelTag level={r.level} />
                    <Tag color={CONFIDENCE[r.confidence].color}>{CONFIDENCE[r.confidence].label}</Tag>
                  </Space>
                ),
              },
            ]}
            expandable={{ expandedRowRender: (r) => <Typography.Text type="secondary">{r.reason}</Typography.Text> }}
          />
        )}
      </Modal>
    </>
  );
}

function QuestionBankCrud() {
  const { can } = useAuth();
  const { data: subjects } = useQuery({
    queryKey: ['lookup', 'subjects'],
    queryFn: () => mastersApi.all<Subject>('subjects'),
    staleTime: 5 * 60_000,
  });
  const { data: examTypes } = useQuery({
    queryKey: ['lookup', 'exam-types'],
    queryFn: () => mastersApi.all<ExamType>('exam-types'),
    staleTime: 5 * 60_000,
  });

  const subjectOptions = (subjects ?? []).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }));
  const examTypeOptions = (examTypes ?? []).map((e) => ({ value: e.id, label: e.name }));

  const currentYear = new Date().getFullYear();
  const yearOptions = Array.from({ length: 10 }, (_, i) => {
    const y = currentYear - i;
    return { value: y, label: String(y) };
  });

  return (
    <MasterCrud<QuestionRow>
      path="question-bank"
      perm="question_bank"
      noun="question"
      toolbar={can('question_bank.update') ? <BloomsReview /> : undefined}
      fields={[
        { name: 'subject_id', label: 'Subject', type: 'select', options: subjectOptions, required: true },
        { name: 'exam_type_id', label: 'Exam Type', type: 'select', options: examTypeOptions },
        { name: 'year', label: 'Year', type: 'select', options: yearOptions },
        { name: 'question', label: 'Question', type: 'text', required: true },
        { name: 'marks', label: 'Marks', type: 'number', required: true, min: 1 },
        { name: 'blooms_level', label: "Bloom's Level", type: 'select', options: BLOOMS_LEVELS, after: (form) => <SuggestLevel form={form} /> },
        { name: 'unit', label: 'Unit', type: 'text', extra: 'Unit number or name (e.g. Unit 1, Arrays)' },
      ]}
      columns={[
        {
          title: 'Question',
          dataIndex: 'question',
          render: (v: string) => (v?.length > 80 ? v.slice(0, 80) + '...' : v),
        },
        { title: 'Subject', dataIndex: 'subject_name', width: 160 },
        { title: 'Exam', dataIndex: 'exam_type_name', width: 120, render: (v: string) => v || '—' },
        { title: 'Year', dataIndex: 'year', width: 80, render: (v: number) => v || '—' },
        { title: 'Marks', dataIndex: 'marks', width: 70, align: 'right' },
        { title: "Bloom's", dataIndex: 'blooms_level', width: 120, render: (v: string) => <LevelTag level={v} /> },
        { title: 'Unit', dataIndex: 'unit', width: 100, render: (v: string) => v || '—' },
      ]}
    />
  );
}

export default function QuestionBankPage() {
  const { can } = useAuth();
  // Students see the question papers. The one-by-one question list (with Bloom's levels) and its Excel import are for staff.
  const staff = can('question_bank.create');
  return (
    <Card>
      <Tabs
        items={[
          { key: 'papers', label: 'Question papers', children: <QuestionPapers /> },
          ...(staff ? [{ key: 'questions', label: 'Questions', children: <QuestionBankCrud /> }] : []),
          ...(staff ? [{ key: 'import', label: 'Import questions', children: <QuestionsUpload /> }] : []),
        ]}
      />
    </Card>
  );
}
