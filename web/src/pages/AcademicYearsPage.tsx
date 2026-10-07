import { Card, Space, Tabs, Tag } from 'antd';
import dayjs from 'dayjs';
import type { AcademicYear } from '../api/phase2';
import MasterCrud from '../components/MasterCrud';
import { useAuth } from '../auth/AuthContext';
import { AcademicYearsUpload } from './BulkUploadPage';

function AcademicYearsCrud() {
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

export default function AcademicYearsPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs items={[
        { key: 'list', label: 'Academic Years', children: <AcademicYearsCrud /> },
        ...(can('academic_year.create') ? [{ key: 'import', label: 'Import', children: <AcademicYearsUpload /> }] : []),
      ]} />
    </Card>
  );
}
