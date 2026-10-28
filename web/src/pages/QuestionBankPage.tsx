import { Card, Tag } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { mastersApi, type Subject, type ExamType } from '../api/phase2';
import MasterCrud from '../components/MasterCrud';

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

function QuestionBankCrud() {
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
      fields={[
        { name: 'subject_id', label: 'Subject', type: 'select', options: subjectOptions, required: true },
        { name: 'exam_type_id', label: 'Exam Type', type: 'select', options: examTypeOptions },
        { name: 'year', label: 'Year', type: 'select', options: yearOptions },
        { name: 'question', label: 'Question', type: 'text', required: true },
        { name: 'marks', label: 'Marks', type: 'number', required: true, min: 1 },
        { name: 'blooms_level', label: "Bloom's Level", type: 'select', options: BLOOMS_LEVELS },
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
        {
          title: "Bloom's",
          dataIndex: 'blooms_level',
          width: 120,
          render: (v: string) => {
            if (!v) return '—';
            const found = BLOOMS_LEVELS.find((b) => b.value === v);
            return <Tag color={BLOOMS_COLORS[v]}>{found?.label ?? v}</Tag>;
          },
        },
        { title: 'Unit', dataIndex: 'unit', width: 100, render: (v: string) => v || '—' },
      ]}
    />
  );
}

export default function QuestionBankPage() {
  return (
    <Card>
      <QuestionBankCrud />
    </Card>
  );
}
