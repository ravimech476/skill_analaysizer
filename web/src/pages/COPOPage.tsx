import { Card, Tabs, Tag } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { mastersApi, type Subject } from '../api/phase2';
import { useDepartments } from '../api/lookups';
import MasterCrud from '../components/MasterCrud';

/* ---- Program Outcomes (PO) ---- */

interface ProgramOutcome {
  id: number;
  department_id: number;
  department_name: string;
  code: string;
  description: string;
  is_active: boolean;
}

function POCrud() {
  const { data: departments } = useDepartments();
  const deptOptions = (departments ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }));

  return (
    <MasterCrud<ProgramOutcome>
      path="program-outcomes"
      perm="course_outcome"
      noun="program outcome"
      fields={[
        { name: 'department_id', label: 'Department', type: 'select', options: deptOptions, required: true },
        { name: 'code', label: 'PO Code', type: 'upper', required: true },
        { name: 'description', label: 'Description', type: 'text', required: true },
      ]}
      columns={[
        { title: 'Code', dataIndex: 'code', width: 100 },
        { title: 'Department', dataIndex: 'department_name', width: 160 },
        {
          title: 'Description',
          dataIndex: 'description',
          render: (v: string) => (v?.length > 100 ? v.slice(0, 100) + '...' : v),
        },
      ]}
    />
  );
}

/* ---- Course Outcomes (CO) ---- */

interface CourseOutcome {
  id: number;
  subject_id: number;
  subject_name: string;
  code: string;
  description: string;
  is_active: boolean;
}

function COCrud() {
  const { data: subjects } = useQuery({
    queryKey: ['lookup', 'subjects'],
    queryFn: () => mastersApi.all<Subject>('subjects'),
    staleTime: 5 * 60_000,
  });
  const subjectOptions = (subjects ?? []).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }));

  return (
    <MasterCrud<CourseOutcome>
      path="course-outcomes"
      perm="course_outcome"
      noun="course outcome"
      fields={[
        { name: 'subject_id', label: 'Subject', type: 'select', options: subjectOptions, required: true },
        { name: 'code', label: 'CO Code', type: 'upper', required: true },
        { name: 'description', label: 'Description', type: 'text', required: true },
      ]}
      columns={[
        { title: 'Code', dataIndex: 'code', width: 100 },
        { title: 'Subject', dataIndex: 'subject_name', width: 200 },
        {
          title: 'Description',
          dataIndex: 'description',
          render: (v: string) => (v?.length > 100 ? v.slice(0, 100) + '...' : v),
        },
      ]}
    />
  );
}

/* ---- CO-PO Mapping ---- */

interface COPOMapping {
  id: number;
  course_outcome_id: number;
  course_outcome_code: string;
  program_outcome_id: number;
  program_outcome_code: string;
  strength: number;
  is_active: boolean;
}

const STRENGTH_OPTIONS = [
  { value: 1, label: '1 - Low' },
  { value: 2, label: '2 - Medium' },
  { value: 3, label: '3 - High' },
];

const STRENGTH_COLORS: Record<number, string> = { 1: 'blue', 2: 'orange', 3: 'green' };

function MappingCrud() {
  const { data: cos } = useQuery({
    queryKey: ['lookup', 'course-outcomes'],
    queryFn: () => mastersApi.all<CourseOutcome>('course-outcomes'),
    staleTime: 5 * 60_000,
  });
  const { data: pos } = useQuery({
    queryKey: ['lookup', 'program-outcomes'],
    queryFn: () => mastersApi.all<ProgramOutcome>('program-outcomes'),
    staleTime: 5 * 60_000,
  });

  const coOptions = (cos ?? []).map((c) => ({ value: c.id, label: c.code }));
  const poOptions = (pos ?? []).map((p) => ({ value: p.id, label: p.code }));

  return (
    <MasterCrud<COPOMapping>
      path="co-po-mappings"
      perm="course_outcome"
      noun="mapping"
      fields={[
        { name: 'course_outcome_id', label: 'Course Outcome (CO)', type: 'select', options: coOptions, required: true },
        { name: 'program_outcome_id', label: 'Program Outcome (PO)', type: 'select', options: poOptions, required: true },
        { name: 'strength', label: 'Strength (1-3)', type: 'select', options: STRENGTH_OPTIONS, required: true },
      ]}
      columns={[
        { title: 'CO', dataIndex: 'course_outcome_code', width: 100 },
        { title: 'PO', dataIndex: 'program_outcome_code', width: 100 },
        {
          title: 'Strength',
          dataIndex: 'strength',
          width: 120,
          render: (v: number) => {
            const label = STRENGTH_OPTIONS.find((s) => s.value === v)?.label ?? String(v);
            return <Tag color={STRENGTH_COLORS[v]}>{label}</Tag>;
          },
        },
      ]}
    />
  );
}

/* ---- Main Page ---- */

export default function COPOPage() {
  return (
    <Card>
      <Tabs
        items={[
          { key: 'po', label: 'Program Outcomes (PO)', children: <POCrud /> },
          { key: 'co', label: 'Course Outcomes (CO)', children: <COCrud /> },
          { key: 'mapping', label: 'CO-PO Mapping', children: <MappingCrud /> },
        ]}
      />
    </Card>
  );
}
