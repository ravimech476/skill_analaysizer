import { Card, Tabs, Tag, Typography } from 'antd';
import { useAuth } from '../auth/AuthContext';
import { DepartmentsUpload } from './BulkUploadPage';
import MasterCrud from '../components/MasterCrud';
import type { Department } from '../api/phase2';

function DepartmentsCrud() {
  return (
    <MasterCrud<Department>
      path="departments"
      perm="department"
      noun="department"
      fields={[
        { name: 'name', label: 'Name', type: 'text', required: true },
        { name: 'code', label: 'Code', type: 'upper', required: true, extra: 'Short code used in class names and bulk upload, e.g. CSE' },
        { name: 'hod_id', label: 'Head of department', type: 'staff' },
      ]}
      columns={[
        { title: 'Code', dataIndex: 'code', width: 100, render: (v) => <Tag color="blue">{v}</Tag> },
        { title: 'Name', dataIndex: 'name' },
        { title: 'HOD', dataIndex: 'hod_name', render: (v) => v ?? <Typography.Text type="secondary">Not set</Typography.Text> },
        { title: 'Classes', dataIndex: 'class_count', width: 90 },
        { title: 'Students', dataIndex: 'student_count', width: 100 },
      ]}
    />
  );
}

export default function DepartmentsPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs items={[
        { key: 'list', label: 'Departments', children: <DepartmentsCrud /> },
        ...(can('department.create') ? [{ key: 'import', label: 'Import', children: <DepartmentsUpload /> }] : []),
      ]} />
    </Card>
  );
}
