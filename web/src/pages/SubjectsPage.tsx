import { Card, Tabs, Tag } from 'antd';
import type { Subject } from '../api/phase2';
import { useAuth } from '../auth/AuthContext';
import MasterCrud from '../components/MasterCrud';
import { SubjectsUpload } from './BulkUploadPage';

const SUBJECT_TYPES = ['theory', 'lab', 'elective', 'project'].map((v) => ({ value: v, label: v[0].toUpperCase() + v.slice(1) }));

function SubjectsCrud() {
  return (
    <MasterCrud<Subject>
      path="subjects"
      perm="subject"
      noun="subject"
      fields={[
        { name: 'code', label: 'Code', type: 'upper', required: true },
        { name: 'name', label: 'Name', type: 'text', required: true },
        { name: 'credits', label: 'Credits', type: 'number', min: 0, max: 20 },
        { name: 'subject_type', label: 'Type', type: 'select', options: SUBJECT_TYPES },
      ]}
      columns={[
        { title: 'Code', dataIndex: 'code', width: 130 },
        { title: 'Name', dataIndex: 'name' },
        { title: 'Credits', dataIndex: 'credits', width: 90 },
        { title: 'Type', dataIndex: 'subject_type', width: 110, render: (v) => <Tag>{v}</Tag> },
      ]}
    />
  );
}

export default function SubjectsPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs items={[
        { key: 'list', label: 'Subjects', children: <SubjectsCrud /> },
        ...(can('subject.create') ? [{ key: 'import', label: 'Import', children: <SubjectsUpload /> }] : []),
      ]} />
    </Card>
  );
}
