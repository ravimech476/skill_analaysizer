import { useState } from 'react';
import { Button, Card, Form, Select, Space, Tabs, Tag, Typography, message } from 'antd';
import { RobotOutlined } from '@ant-design/icons';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { filesApi, type FileLink } from '../api/files';
import { kbApi } from '../api/kb';
import { mastersApi, type Subject } from '../api/phase2';
import { useAuth } from '../auth/AuthContext';
import { MultiUpload } from '../components/DocumentLibrary';
import { FileSlot } from '../components/Files';
import MasterCrud from '../components/MasterCrud';
import { MaterialsUpload } from './BulkUploadPage';

const MATERIAL_TYPES = [
  { value: 'notes', label: 'Notes' },
  { value: 'question_paper', label: 'Question Paper' },
  { value: 'slides', label: 'Slides' },
  { value: 'reference', label: 'Reference' },
  { value: 'video', label: 'Video' },
  { value: 'link', label: 'Link' },
];

const TYPE_COLORS: Record<string, string> = {
  notes: 'blue',
  question_paper: 'green',
  slides: 'purple',
  reference: 'orange',
  video: 'red',
  link: 'cyan',
};

interface StudyMaterial {
  id: number;
  subject_id: number | null;
  subject_name: string | null;
  title: string;
  material_type: string;
  description: string | null;
  url: string | null;
  file: FileLink | null;
  is_active: boolean;
}

/** Adds the attached file to the AI assistant's knowledge base (PDF and Word only). */
function IndexForAI({ material }: { material: StudyMaterial }) {
  const [busy, setBusy] = useState(false);
  const name = material.file?.name.toLowerCase() ?? '';
  const readable = /\.(pdf|docx)$/.test(name);
  return (
    <Button
      size="small"
      icon={<RobotOutlined />}
      loading={busy}
      disabled={!readable}
      title={readable ? 'Let the AI assistant answer questions from this file' : 'The AI assistant can read PDF and Word files only'}
      onClick={() => {
        setBusy(true);
        kbApi
          .indexMaterial(material.id)
          .then((r) => message.success(`Added to the AI knowledge base (${r.chunk_count} passage${r.chunk_count === 1 ? '' : 's'})`))
          .catch((e) => message.error(errorMessage(e)))
          .finally(() => setBusy(false));
      }}
    >
      Add to AI
    </Button>
  );
}

function StudyMaterialsCrud() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data: subjects } = useQuery({
    queryKey: ['lookup', 'subjects'],
    queryFn: () => mastersApi.all<Subject>('subjects'),
    staleTime: 5 * 60_000,
  });

  const subjectOptions = (subjects ?? []).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }));
  const canEdit = can('study_material.update');
  const canIndex = can('kb.manage');

  return (
    <MasterCrud<StudyMaterial>
      path="study-materials"
      perm="study_material"
      noun="material"
      toolbar={
        can('study_material.create') && canEdit ? (
          <MultiUpload
            label="Upload study materials"
            path="study-materials"
            category="study_material"
            masterPath="study-materials"
            initialValues={{ material_type: 'notes' }}
            onDone={() => qc.invalidateQueries({ queryKey: ['master', 'study-materials'] })}
          >
            {() => (
              <>
                <Form.Item name="subject_id" label="Subject" rules={[{ required: true, message: 'Choose the subject' }]}>
                  <Select showSearch optionFilterProp="label" options={subjectOptions} placeholder="Select subject" />
                </Form.Item>
                <Form.Item name="material_type" label="Type">
                  <Select options={MATERIAL_TYPES} />
                </Form.Item>
              </>
            )}
          </MultiUpload>
        ) : undefined
      }
      fields={[
        { name: 'subject_id', label: 'Subject', type: 'select', options: subjectOptions },
        { name: 'title', label: 'Title', type: 'text', required: true },
        { name: 'material_type', label: 'Type', type: 'select', options: MATERIAL_TYPES },
        { name: 'description', label: 'Description', type: 'text' },
        { name: 'url', label: 'URL', type: 'text', extra: 'Link to the material (Google Drive, YouTube, etc.). To upload a file instead, save the material and use the File column.' },
      ]}
      columns={[
        { title: 'Title', dataIndex: 'title' },
        { title: 'Subject', dataIndex: 'subject_name', width: 160 },
        {
          title: 'Type',
          dataIndex: 'material_type',
          width: 130,
          render: (v: string) => {
            const found = MATERIAL_TYPES.find((t) => t.value === v);
            return found ? <Tag color={TYPE_COLORS[v]}>{found.label}</Tag> : v;
          },
        },
        {
          title: 'URL',
          dataIndex: 'url',
          width: 90,
          render: (v: string) =>
            v ? (
              <Typography.Link href={v} target="_blank" rel="noopener noreferrer">
                Open
              </Typography.Link>
            ) : (
              '—'
            ),
        },
        {
          title: 'File',
          key: 'file',
          width: 300,
          render: (_: unknown, m: StudyMaterial) => (
            <Space orientation="vertical" size={4}>
              <FileSlot
                category="study_material"
                value={m.file}
                canEdit={canEdit}
                emptyText="No file"
                save={(id) => filesApi.setMaterialFile(m.id, id).then(() => qc.invalidateQueries({ queryKey: ['master', 'study-materials'] }))}
              />
              {canIndex && m.file && <IndexForAI material={m} />}
            </Space>
          ),
        },
      ]}
    />
  );
}

export default function StudyMaterialsPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs
        items={[
          { key: 'list', label: 'Study materials', children: <StudyMaterialsCrud /> },
          ...(can('study_material.create') ? [{ key: 'import', label: 'Import', children: <MaterialsUpload /> }] : []),
        ]}
      />
    </Card>
  );
}
