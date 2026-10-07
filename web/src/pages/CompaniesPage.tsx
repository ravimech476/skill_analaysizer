import { Card, Tabs, Typography } from 'antd';
import { useAuth } from '../auth/AuthContext';
import { CompaniesUpload } from './BulkUploadPage';
import { lpa, placementApi, type Company } from '../api/placement';
import MasterCrud from '../components/MasterCrud';

function CompaniesCrud() {
  return (
    <MasterCrud<Company>
      path="companies"
      perm="company"
      noun="company"
      fields={[
        { name: 'name', label: 'Company name', type: 'text', required: true },
        { name: 'industry', label: 'Industry', type: 'text' },
        { name: 'location', label: 'Location', type: 'text' },
        { name: 'website', label: 'Website', type: 'text' },
        { name: 'contact_person', label: 'Contact person', type: 'text' },
        { name: 'contact_email', label: 'Contact email', type: 'text' },
        { name: 'contact_mobile', label: 'Contact mobile', type: 'text' },
        { name: 'description', label: 'About', type: 'text' },
      ]}
      columns={[
        { title: 'Company', dataIndex: 'name', render: (v, c) => <div><b>{v}</b><br /><Typography.Text type="secondary">{[c.industry, c.location].filter(Boolean).join(' · ')}</Typography.Text></div> },
        { title: 'Contact', render: (_, c) => [c.contact_person, c.contact_mobile].filter(Boolean).join(' · ') || '—' },
        { title: 'Roles', dataIndex: 'job_role_count', width: 80 },
        { title: 'Placed', dataIndex: 'placed_count', width: 80 },
        { title: 'Highest', dataIndex: 'highest_package', width: 110, render: (v) => lpa(v) },
      ]}
    />
  );
}

export default function CompaniesPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs
        items={[
          { key: 'list', label: 'Companies', children: <CompaniesCrud /> },
          ...(can('company.create') ? [{ key: 'import', label: 'Import', children: <CompaniesUpload /> }] : []),
        ]}
      />
    </Card>
  );
}
