import { Card } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { mastersApi, type Subject } from '../api/phase2';
import { useClasses, useSemesters, useAcademicYears } from '../api/lookups';
import MasterCrud from '../components/MasterCrud';

interface AttendanceRow {
  id: number;
  student_id: number;
  student_name: string;
  class_id: number;
  class_label: string;
  subject_id: number;
  subject_name: string;
  semester_id: number;
  semester_name: string;
  academic_year_id: number;
  academic_year_name: string;
  total_classes: number;
  classes_attended: number;
  percentage: number;
  is_active: boolean;
}

function AttendanceCrud() {
  const { data: classes } = useClasses(undefined, 'all');
  const { data: semesters } = useSemesters();
  const { data: academicYears } = useAcademicYears();
  const { data: subjects } = useQuery({
    queryKey: ['lookup', 'subjects'],
    queryFn: () => mastersApi.all<Subject>('subjects'),
    staleTime: 5 * 60_000,
  });

  const classOptions = (classes ?? []).map((c) => ({ value: c.id, label: c.label }));
  const semesterOptions = (semesters ?? []).map((s) => ({ value: s.id, label: s.name }));
  const yearOptions = (academicYears ?? []).map((y) => ({ value: y.id, label: y.name }));
  const subjectOptions = (subjects ?? []).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }));

  return (
    <MasterCrud<AttendanceRow>
      path="attendance"
      perm="attendance"
      noun="attendance record"
      fields={[
        { name: 'student_id', label: 'Student', type: 'select', options: [], extra: 'Type to search students (populated from class)' },
        { name: 'class_id', label: 'Class', type: 'select', options: classOptions, required: true },
        { name: 'subject_id', label: 'Subject', type: 'select', options: subjectOptions, required: true },
        { name: 'semester_id', label: 'Semester', type: 'select', options: semesterOptions, required: true },
        { name: 'academic_year_id', label: 'Academic Year', type: 'select', options: yearOptions, required: true },
        { name: 'total_classes', label: 'Total Classes', type: 'number', required: true, min: 0 },
        { name: 'classes_attended', label: 'Classes Attended', type: 'number', required: true, min: 0 },
      ]}
      columns={[
        { title: 'Student', dataIndex: 'student_name', width: 180 },
        { title: 'Class', dataIndex: 'class_label', width: 120 },
        { title: 'Subject', dataIndex: 'subject_name', width: 160 },
        { title: 'Semester', dataIndex: 'semester_name', width: 100 },
        { title: 'Year', dataIndex: 'academic_year_name', width: 100 },
        { title: 'Total', dataIndex: 'total_classes', width: 80, align: 'right' },
        { title: 'Attended', dataIndex: 'classes_attended', width: 90, align: 'right' },
        {
          title: '%',
          dataIndex: 'percentage',
          width: 80,
          align: 'right',
          render: (v: number) => {
            const color = v >= 75 ? '#15803d' : v >= 60 ? '#b45309' : '#be123c';
            return <span style={{ color, fontWeight: 600 }}>{v?.toFixed(1)}%</span>;
          },
        },
      ]}
    />
  );
}

export default function AttendancePage() {
  return (
    <Card>
      <AttendanceCrud />
    </Card>
  );
}
