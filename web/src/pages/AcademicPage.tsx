import { Card, Space, Tabs, Tag } from 'antd';
import dayjs from 'dayjs';
import type { AcademicYear, ExamType, Subject } from '../api/phase2';
import { useAuth } from '../auth/AuthContext';
import MasterCrud from '../components/MasterCrud';
import { SubjectsUpload } from './BulkUploadPage';

const SUBJECT_TYPES = ['theory', 'lab', 'elective', 'project'].map((v) => ({ value: v, label: v[0].toUpperCase() + v.slice(1) }));

function AcademicYears() {
  return (
    <MasterCrud<AcademicYear>
      path="academic-years"
      perm="academic_year"
      noun="academic year"
      fields={[
        { name: 'name', label: 'Name', type: 'text', required: true, extra: 'e.g. 2026-27' },
        { name: 'start_date', label: 'Start date', type: 'date', required: true },
        { name: 'end_date', label: 'End date', type: 'date', required: true },
        { name: 'is_current', label: 'Current academic year', type: 'bool', extra: 'Marking this year current un-marks the previous one. New classes and bulk uploads use the current year.' },
      ]}
      columns={[
        { title: 'Name', dataIndex: 'name', render: (v, r) => <Space>{v}{r.is_current && <Tag color="green">Current</Tag>}</Space> },
        { title: 'Start', dataIndex: 'start_date', render: (v) => dayjs(v).format('DD MMM YYYY') },
        { title: 'End', dataIndex: 'end_date', render: (v) => dayjs(v).format('DD MMM YYYY') },
      ]}
    />
  );
}

function Subjects() {
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

function ExamTypes() {
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

function AcademicImport() {
  return (
    <Space direction="vertical" size="large" style={{ width: '100%' }}>
      <SubjectsUpload />
    </Space>
  );
}

export default function AcademicPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs
        items={[
          { key: 'years', label: 'Academic Years', children: <AcademicYears /> },
          { key: 'subjects', label: 'Subjects', children: <Subjects /> },
          { key: 'exams', label: 'Exam Types', children: <ExamTypes /> },
          ...(can('subject.create') ? [{ key: 'import', label: 'Import', children: <AcademicImport /> }] : []),
        ]}
      />
    </Card>
  );
}
