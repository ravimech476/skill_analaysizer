import { Card, Tabs, Tag } from 'antd';
import { placementApi, pretty, type Skill } from '../api/placement';
import MasterCrud from '../components/MasterCrud';
import { SkillMasterUpload } from './BulkUploadPage';
import { useAuth } from '../auth/AuthContext';

const CATEGORIES = ['programming', 'framework', 'database', 'tool', 'technical', 'soft_skill', 'domain'].map((c) => ({ value: c, label: pretty(c) }));
const CATEGORY_COLORS: Record<string, string> = { programming: 'blue', framework: 'geekblue', database: 'cyan', tool: 'purple', technical: 'volcano', soft_skill: 'green', domain: 'gold' };

function SkillMasterCrud() {
  return (
    <MasterCrud<Skill>
      path="skills"
      perm="skill"
      noun="skill"
      fields={[
        { name: 'name', label: 'Skill name', type: 'text', required: true },
        { name: 'category', label: 'Category', type: 'select', options: CATEGORIES },
      ]}
      columns={[
        { title: 'Skill', dataIndex: 'name' },
        { title: 'Category', dataIndex: 'category', width: 140, render: (v) => <Tag color={CATEGORY_COLORS[v]}>{pretty(v)}</Tag> },
        { title: 'Students', dataIndex: 'student_count', width: 100 },
        { title: 'Job roles', dataIndex: 'job_role_count', width: 100 },
      ]}
    />
  );
}

export default function SkillMasterPage() {
  const { can } = useAuth();
  return (
    <Card>
      <Tabs items={[
        { key: 'list', label: 'Skills', children: <SkillMasterCrud /> },
        ...(can('skill.create') ? [{ key: 'import', label: 'Import', children: <SkillMasterUpload /> }] : []),
      ]} />
    </Card>
  );
}
