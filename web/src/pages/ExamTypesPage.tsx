import { Card, Tabs, Tag } from 'antd';
import type { ExamType } from '../api/phase2';
import MasterCrud from '../components/MasterCrud';
import { useAuth } from '../auth/AuthContext';
import { ExamTypesUpload } from './BulkUploadPage';

function ExamTypesCrud() {
  return (
    <MasterCrud<ExamType>
      path="exam-types"
      perm="exam_type"
      noun="exam type"
      searchable={false}
      fields={[
        { name: 'name', label: 'Name', type: 'text', required: true },
        { name: 'code', label: 'Code', type: 'upper', required: true },
        { name: 'max_marks', label: 'Maximum marks', type: 'number', required: true, min: 1, max: 1000 },
        { name: 'is_final', label: 'Final (end-semester) exam', type: 'bool', extra: 'Final exam results are used for CGPA and backlogs' },
        { name: 'sort_order', label: 'Display order', type: 'number', min: 0 },
        { name: 'pass_percent', label: 'Pass percentage', type: 'number', min: 0, max: 100, extra: 'Internal exams: pass at or above this %. Final exams use the grade scale.' },
      ]}
      columns={[
        { title: 'Order', dataIndex: 'sort_order', width: 80 },
        { title: 'Name', dataIndex: 'name' },
        { title: 'Code', dataIndex: 'code', width: 110 },
        { title: 'Max marks', dataIndex: 'max_marks', width: 110 },
        { title: 'Pass %', dataIndex: 'pass_percent', width: 90 },
        { title: '', dataIndex: 'is_final', width: 100, render: (v) => v && <Tag color="purple">Final</Tag> },
      ]}
    />
  );
}

export default function ExamTypesPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs items={[
        { key: 'list', label: 'Exam Types', children: <ExamTypesCrud /> },
        ...(can('exam_type.create') ? [{ key: 'import', label: 'Import', children: <ExamTypesUpload /> }] : []),
      ]} />
    </Card>
  );
}
