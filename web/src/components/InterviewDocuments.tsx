import { Form, Select, Tag } from 'antd';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import type { FileLink } from '../api/files';
import { mastersApi } from '../api/phase2';
import type { Company } from '../api/placement';
import { useAuth } from '../auth/AuthContext';
import { DocumentFileCell, MultiUpload } from './DocumentLibrary';
import MasterCrud from './MasterCrud';

const TYPES = [
  { value: 'mixed', label: 'Mixed' },
  { value: 'technical', label: 'Technical' },
  { value: 'aptitude', label: 'Aptitude' },
  { value: 'hr', label: 'HR' },
  { value: 'coding', label: 'Coding' },
  { value: 'group_discussion', label: 'Group Discussion' },
  { value: 'case_study', label: 'Case Study' },
];
const TYPE_COLORS: Record<string, string> = { mixed: 'default', technical: 'blue', aptitude: 'cyan', hr: 'green', coding: 'purple', group_discussion: 'orange', case_study: 'magenta' };

interface InterviewDocument {
  id: number;
  company_id: number;
  company_name: string | null;
  title: string;
  doc_type: string;
  role: string | null;
  year: number | null;
  description: string | null;
  tags: string | null;
  file: FileLink | null;
  is_active: boolean;
}

const currentYear = new Date().getFullYear();
const YEARS = Array.from({ length: 12 }, (_, i) => ({ value: currentYear - i, label: String(currentYear - i) }));

/** Company interview documents: one row per document (questions and answers as a PDF or Word file). */
export default function InterviewDocuments() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data: companies } = useQuery({ queryKey: ['lookup', 'companies'], queryFn: () => mastersApi.all<Company>('companies'), staleTime: 5 * 60_000 });
  const companyOptions = (companies ?? []).map((c) => ({ value: c.id, label: c.name }));
  const refresh = () => qc.invalidateQueries({ queryKey: ['master', 'interview-documents'] });

  return (
    <MasterCrud<InterviewDocument>
      path="interview-documents"
      perm="interview"
      noun="document"
      toolbar={
        can('interview.create') && can('interview.update') ? (
          <MultiUpload label="Upload interview documents" path="interview-documents" category="interview_document" masterPath="interview-documents" initialValues={{ doc_type: 'mixed' }} onDone={refresh}>
            {() => (
              <>
                <Form.Item name="company_id" label="Company" rules={[{ required: true, message: 'Choose the company' }]}>
                  <Select showSearch optionFilterProp="label" options={companyOptions} placeholder="Select company" />
                </Form.Item>
                <Form.Item name="doc_type" label="Type">
                  <Select options={TYPES} />
                </Form.Item>
                <Form.Item name="year" label="Year (optional)">
                  <Select allowClear options={YEARS} />
                </Form.Item>
              </>
            )}
          </MultiUpload>
        ) : undefined
      }
      fields={[
        { name: 'company_id', label: 'Company', type: 'select', options: companyOptions, required: true },
        { name: 'title', label: 'Title', type: 'text', required: true, extra: 'e.g. TCS NQT interview questions and answers 2025' },
        { name: 'doc_type', label: 'Type', type: 'select', options: TYPES },
        { name: 'role', label: 'Role or drive', type: 'text', extra: 'Optional, e.g. Ninja or System Engineer' },
        { name: 'year', label: 'Year', type: 'select', options: YEARS },
        { name: 'description', label: 'Description', type: 'text' },
        { name: 'tags', label: 'Tags', type: 'text', extra: 'Comma separated' },
      ]}
      columns={[
        { title: 'Company', dataIndex: 'company_name', width: 130 },
        {
          title: 'Document',
          dataIndex: 'title',
          render: (v: string, r) => (
            <div>
              <div style={{ fontWeight: 500 }}>{v}</div>
              {(r.role || r.description) && <div style={{ fontSize: 12, opacity: 0.65 }}>{[r.role, r.description].filter(Boolean).join(' · ')}</div>}
            </div>
          ),
        },
        { title: 'Type', dataIndex: 'doc_type', width: 130, render: (v: string) => <Tag color={TYPE_COLORS[v]}>{TYPES.find((t) => t.value === v)?.label ?? v}</Tag> },
        { title: 'Year', dataIndex: 'year', width: 70, render: (v: number | null) => v ?? '—' },
        {
          title: 'File',
          key: 'file',
          width: 280,
          render: (_: unknown, r) => (
            <DocumentFileCell path="interview-documents" category="interview_document" id={r.id} file={r.file} canEdit={can('interview.update')} canIndex={can('kb.manage')} onChanged={refresh} />
          ),
        },
      ]}
    />
  );
}

