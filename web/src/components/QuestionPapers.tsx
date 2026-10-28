import { Form, Input, InputNumber, Select, Tag } from 'antd';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import type { FileLink } from '../api/files';
import { mastersApi, type ExamType, type Subject } from '../api/phase2';
import { useAuth } from '../auth/AuthContext';
import { DocumentFileCell, MultiUpload } from './DocumentLibrary';
import MasterCrud from './MasterCrud';

const TYPES = [
  { value: 'question_paper', label: 'Question paper' },
  { value: 'model_paper', label: 'Model paper' },
  { value: 'important_questions', label: 'Important questions' },
  { value: 'answer_key', label: 'Answer key' },
];
const TYPE_COLORS: Record<string, string> = { question_paper: 'blue', model_paper: 'purple', important_questions: 'orange', answer_key: 'green' };

interface QuestionPaper {
  id: number;
  subject_id: number;
  subject_name: string | null;
  title: string;
  doc_type: string;
  exam_type_id: number | null;
  exam_type_name: string | null;
  year: number | null;
  semester: string | null;
  unit: string | null;
  max_marks: number | null;
  description: string | null;
  file: FileLink | null;
  is_active: boolean;
}

const currentYear = new Date().getFullYear();
const YEARS = Array.from({ length: 12 }, (_, i) => ({ value: currentYear - i, label: String(currentYear - i) }));

/** Question papers: one row per paper (a PDF or Word file) with its subject, exam, year and marks. */
export default function QuestionPapers() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data: subjects } = useQuery({ queryKey: ['lookup', 'subjects'], queryFn: () => mastersApi.all<Subject>('subjects'), staleTime: 5 * 60_000 });
  const { data: examTypes } = useQuery({ queryKey: ['lookup', 'exam-types'], queryFn: () => mastersApi.all<ExamType>('exam-types'), staleTime: 5 * 60_000 });
  const subjectOptions = (subjects ?? []).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }));
  const examOptions = (examTypes ?? []).map((e) => ({ value: e.id, label: e.name }));
  const refresh = () => qc.invalidateQueries({ queryKey: ['master', 'question-papers'] });

  return (
    <MasterCrud<QuestionPaper>
      path="question-papers"
      perm="question_bank"
      noun="paper"
      toolbar={
        can('question_bank.create') && can('question_bank.update') ? (
          <MultiUpload label="Upload question papers" path="question-papers" category="question_paper" masterPath="question-papers" initialValues={{ doc_type: 'question_paper' }} onDone={refresh}>
            {() => (
              <>
                <Form.Item name="subject_id" label="Subject" rules={[{ required: true, message: 'Choose the subject' }]}>
                  <Select showSearch optionFilterProp="label" options={subjectOptions} placeholder="Select subject" />
                </Form.Item>
                <Form.Item name="doc_type" label="Document type">
                  <Select options={TYPES} />
                </Form.Item>
                <Form.Item name="exam_type_id" label="Exam type (optional)">
                  <Select allowClear options={examOptions} />
                </Form.Item>
                <Form.Item name="year" label="Year (optional)">
                  <Select allowClear options={YEARS} />
                </Form.Item>
                <Form.Item name="semester" label="Semester (optional)">
                  <Input maxLength={30} placeholder="e.g. Semester 4" />
                </Form.Item>
                <Form.Item name="max_marks" label="Max marks (optional)">
                  <InputNumber min={0} max={1000} style={{ width: '100%' }} />
                </Form.Item>
              </>
            )}
          </MultiUpload>
        ) : undefined
      }
      fields={[
        { name: 'subject_id', label: 'Subject', type: 'select', options: subjectOptions, required: true },
        { name: 'title', label: 'Title', type: 'text', required: true, extra: 'e.g. Data Structures end semester, Nov 2024' },
        { name: 'doc_type', label: 'Document type', type: 'select', options: TYPES },
        { name: 'exam_type_id', label: 'Exam type', type: 'select', options: examOptions },
        { name: 'year', label: 'Year', type: 'select', options: YEARS },
        { name: 'semester', label: 'Semester', type: 'text' },
        { name: 'unit', label: 'Unit', type: 'text', extra: 'Optional, if the paper covers specific units' },
        { name: 'max_marks', label: 'Max marks', type: 'number', min: 0, max: 1000 },
        { name: 'description', label: 'Description', type: 'text' },
      ]}
      columns={[
        { title: 'Subject', dataIndex: 'subject_name', width: 170 },
        {
          title: 'Paper',
          dataIndex: 'title',
          render: (v: string, r) => (
            <div>
              <div style={{ fontWeight: 500 }}>{v}</div>
              <div style={{ fontSize: 12, opacity: 0.65 }}>{[r.exam_type_name, r.semester, r.unit, r.max_marks ? `${r.max_marks} marks` : null].filter(Boolean).join(' · ')}</div>
            </div>
          ),
        },
        { title: 'Type', dataIndex: 'doc_type', width: 150, render: (v: string) => <Tag color={TYPE_COLORS[v]}>{TYPES.find((t) => t.value === v)?.label ?? v}</Tag> },
        { title: 'Year', dataIndex: 'year', width: 70, render: (v: number | null) => v ?? '—' },
        {
          title: 'File',
          key: 'file',
          width: 280,
          render: (_: unknown, r) => (
            <DocumentFileCell path="question-papers" category="question_paper" id={r.id} file={r.file} canEdit={can('question_bank.update')} canIndex={can('kb.manage')} onChanged={refresh} />
          ),
        },
      ]}
    />
  );
}
