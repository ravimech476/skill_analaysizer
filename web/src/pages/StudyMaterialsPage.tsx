import { Card, Tag, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { mastersApi, type Subject } from '../api/phase2';
import MasterCrud from '../components/MasterCrud';

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
  is_active: boolean;
}

function StudyMaterialsCrud() {
  const { data: subjects } = useQuery({
    queryKey: ['lookup', 'subjects'],
    queryFn: () => mastersApi.all<Subject>('subjects'),
    staleTime: 5 * 60_000,
  });

  const subjectOptions = (subjects ?? []).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }));

  return (
    <MasterCrud<StudyMaterial>
      path="study-materials"
      perm="study_material"
      noun="material"
      fields={[
        { name: 'subject_id', label: 'Subject', type: 'select', options: subjectOptions },
        { name: 'title', label: 'Title', type: 'text', required: true },
        { name: 'material_type', label: 'Type', type: 'select', options: MATERIAL_TYPES },
        { name: 'description', label: 'Description', type: 'text' },
        { name: 'url', label: 'URL', type: 'text', extra: 'Link to the material (Google Drive, YouTube, etc.)' },
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
          width: 120,
          render: (v: string) =>
            v ? (
              <Typography.Link href={v} target="_blank" rel="noopener noreferrer">
                Open
              </Typography.Link>
            ) : (
              '—'
            ),
        },
      ]}
    />
  );
}

export default function StudyMaterialsPage() {
  return (
    <Card>
      <StudyMaterialsCrud />
    </Card>
  );
}
