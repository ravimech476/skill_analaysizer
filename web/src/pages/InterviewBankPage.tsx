import { Card, Tabs, Tag } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { mastersApi } from '../api/phase2';
import type { Company } from '../api/placement';
import { useAuth } from '../auth/AuthContext';
import InterviewDocuments from '../components/InterviewDocuments';
import MasterCrud from '../components/MasterCrud';
import { InterviewUpload } from './BulkUploadPage';

const CATEGORIES = [
  { value: 'technical', label: 'Technical' },
  { value: 'aptitude', label: 'Aptitude' },
  { value: 'hr', label: 'HR' },
  { value: 'coding', label: 'Coding' },
  { value: 'group_discussion', label: 'Group Discussion' },
  { value: 'case_study', label: 'Case Study' },
];

const DIFFICULTIES = [
  { value: 'easy', label: 'Easy' },
  { value: 'medium', label: 'Medium' },
  { value: 'hard', label: 'Hard' },
];

const DIFFICULTY_COLORS: Record<string, string> = { easy: 'green', medium: 'orange', hard: 'red' };

interface InterviewQuestion {
  id: number;
  company_id: number | null;
  company_name: string | null;
  category: string;
  question: string;
  answer: string | null;
  difficulty: string | null;
  tags: string | null;
  is_active: boolean;
}

function InterviewCrud() {
  const { data: companies } = useQuery({
    queryKey: ['lookup', 'companies'],
    queryFn: () => mastersApi.all<Company>('companies'),
    staleTime: 5 * 60_000,
  });

  const companyOptions = (companies ?? []).map((c) => ({ value: c.id, label: c.name }));

  return (
    <MasterCrud<InterviewQuestion>
      path="interview-questions"
      perm="interview"
      noun="question"
      fields={[
        { name: 'company_id', label: 'Company', type: 'select', options: companyOptions },
        { name: 'category', label: 'Category', type: 'select', options: CATEGORIES },
        { name: 'question', label: 'Question', type: 'text', required: true },
        { name: 'answer', label: 'Answer', type: 'text' },
        { name: 'difficulty', label: 'Difficulty', type: 'select', options: DIFFICULTIES },
        { name: 'tags', label: 'Tags', type: 'text', extra: 'Comma separated: arrays, loops, OOP' },
      ]}
      columns={[
        {
          title: 'Question',
          dataIndex: 'question',
          render: (v: string) => (v?.length > 80 ? v.slice(0, 80) + '…' : v),
        },
        { title: 'Company', dataIndex: 'company_name', width: 140 },
        {
          title: 'Category',
          dataIndex: 'category',
          width: 130,
          render: (v: string) => {
            const found = CATEGORIES.find((c) => c.value === v);
            return found ? <Tag>{found.label}</Tag> : v;
          },
        },
        {
          title: 'Difficulty',
          dataIndex: 'difficulty',
          width: 110,
          render: (v: string) => v ? <Tag color={DIFFICULTY_COLORS[v]}>{v[0].toUpperCase() + v.slice(1)}</Tag> : '—',
        },
        { title: 'Tags', dataIndex: 'tags', width: 160, render: (v: string) => v || '—' },
      ]}
    />
  );
}

export default function InterviewBankPage() {
  const { can } = useAuth();
  // Students see the documents. The one-by-one question list and the Excel import are for staff.
  const staff = can('interview.create');
  return (
    <Card>
      <Tabs
        items={[
          { key: 'documents', label: 'Documents', children: <InterviewDocuments /> },
          ...(staff ? [{ key: 'questions', label: 'Questions', children: <InterviewCrud /> }] : []),
          ...(staff ? [{ key: 'import', label: 'Import questions', children: <InterviewUpload /> }] : []),
        ]}
      />
    </Card>
  );
}
