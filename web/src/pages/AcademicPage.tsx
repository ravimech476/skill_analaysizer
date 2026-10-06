import { useState } from 'react';
import { Button, Card, Empty, Modal, Select, Space, Table, Tabs, Tag, Typography, message } from 'antd';
import { PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { errorMessage } from '../api/client';
import { curriculumApi, type AcademicYear, type CurriculumRow, type Department, type ExamType, type GradeScale, type Subject } from '../api/phase2';
import { useDepartments, useSemesters, useSubjects, useYearLevels } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';
import MasterCrud from '../components/MasterCrud';

const SUBJECT_TYPES = ['theory', 'lab', 'elective', 'project'].map((v) => ({ value: v, label: v[0].toUpperCase() + v.slice(1) }));

function Departments() {
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

function Grades() {
  return (
    <MasterCrud<GradeScale>
      path="grade-scales"
      perm="exam_type"
      noun="grade"
      searchable={false}
      fields={[
        { name: 'grade', label: 'Grade', type: 'upper', required: true },
        { name: 'min_percent', label: 'From percentage', type: 'number', required: true, min: 0, max: 100, extra: 'A mark gets the highest grade whose starting % it reaches' },
        { name: 'grade_point', label: 'Grade point', type: 'number', required: true, min: 0, max: 10 },
        { name: 'is_pass', label: 'Pass grade', type: 'bool' },
      ]}
      columns={[
        { title: 'Grade', dataIndex: 'grade', width: 90, render: (v, r) => <Tag color={r.is_pass ? 'green' : 'red'}>{v}</Tag> },
        { title: 'From %', dataIndex: 'min_percent', width: 100 },
        { title: 'Grade point', dataIndex: 'grade_point', width: 120 },
        { title: 'Result', dataIndex: 'is_pass', render: (v) => (v ? 'Pass' : 'Fail') },
      ]}
    />
  );
}

function Curriculum() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data: depts } = useDepartments();
  const { data: sems } = useSemesters();
  const { data: subjects } = useSubjects();
  const [deptId, setDeptId] = useState<number>();
  const [semId, setSemId] = useState<number>();
  const [adding, setAdding] = useState<number[] | null>(null);

  const { data: rows, isLoading } = useQuery({
    queryKey: ['curriculum', deptId, semId],
    queryFn: () => curriculumApi.list(deptId!, semId),
    enabled: !!deptId,
  });

  const add = useMutation({
    mutationFn: () => curriculumApi.add({ department_id: deptId!, semester_id: semId!, subject_ids: adding ?? [] }),
    onSuccess: (r) => {
      message.success(r.added ? `${r.added} subject(s) added` : 'Those subjects were already in the curriculum');
      qc.invalidateQueries({ queryKey: ['curriculum'] });
      setAdding(null);
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const remove = useMutation({
    mutationFn: (id: number) => curriculumApi.remove(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['curriculum'] }),
    onError: (e) => message.error(errorMessage(e)),
  });

  const existing = new Set((rows ?? []).filter((r) => r.semester_id === semId).map((r) => r.subject_id));
  const canEdit = can('subject.update') || can('subject.create');

  return (
    <>
      <Space wrap style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Space wrap>
          <Select
            placeholder="Department"
            style={{ width: 240 }}
            value={deptId}
            onChange={setDeptId}
            showSearch
            optionFilterProp="label"
            options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))}
          />
          <Select placeholder="All semesters" allowClear style={{ width: 160 }} value={semId} onChange={setSemId} options={(sems ?? []).map((s) => ({ value: s.id, label: s.name }))} />
        </Space>
        {canEdit && (
          <Button type="primary" icon={<PlusOutlined />} disabled={!deptId || !semId} onClick={() => setAdding([])}>
            Add subjects
          </Button>
        )}
      </Space>
      {!deptId ? (
        <Empty description="Pick a department to see its curriculum" />
      ) : (
        <Table<CurriculumRow>
          rowKey="id"
          loading={isLoading}
          dataSource={rows}
          pagination={false}
          scroll={{ x: 600 }}
          columns={[
            { title: 'Semester', dataIndex: 'sem_no', width: 100, render: (v) => `Sem ${v}` },
            { title: 'Code', dataIndex: 'subject_code', width: 130 },
            { title: 'Subject', dataIndex: 'subject_name' },
            { title: 'Credits', dataIndex: 'credits', width: 90 },
            { title: 'Type', dataIndex: 'subject_type', width: 100, render: (v) => <Tag>{v}</Tag> },
            ...(canEdit
              ? [{ title: '', key: 'x', width: 90, render: (_: unknown, r: CurriculumRow) => <Button size="small" danger onClick={() => remove.mutate(r.id)}>Remove</Button> }]
              : []),
          ]}
        />
      )}
      <Modal title="Add subjects to curriculum" open={adding !== null} onCancel={() => setAdding(null)} onOk={() => add.mutate()} okButtonProps={{ disabled: !adding?.length, loading: add.isPending }}>
        <Typography.Paragraph type="secondary">
          {depts?.find((d) => d.id === deptId)?.name} · {sems?.find((s) => s.id === semId)?.name}
        </Typography.Paragraph>
        <Select
          mode="multiple"
          style={{ width: '100%' }}
          placeholder="Select subjects"
          value={adding ?? []}
          onChange={setAdding}
          optionFilterProp="label"
          options={(subjects ?? []).filter((s) => !existing.has(s.id)).map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }))}
        />
      </Modal>
    </>
  );
}

function YearsAndSemesters() {
  const { data: levels } = useYearLevels();
  const { data: sems } = useSemesters();
  return (
    <Table
      rowKey="id"
      pagination={false}
      dataSource={levels}
      columns={[
        { title: 'Year of study', dataIndex: 'name' },
        {
          title: 'Semesters',
          render: (_, l) => (sems ?? []).filter((s) => s.year_level_id === l.id).map((s) => <Tag key={s.id}>{s.name}</Tag>),
        },
      ]}
    />
  );
}

export default function AcademicPage() {
  return (
    <Card>
      <Tabs
        items={[
          { key: 'departments', label: 'Departments', children: <Departments /> },
          { key: 'years', label: 'Academic Years', children: <AcademicYears /> },
          { key: 'subjects', label: 'Subjects', children: <Subjects /> },
          { key: 'curriculum', label: 'Curriculum', children: <Curriculum /> },
          { key: 'exams', label: 'Exam Types', children: <ExamTypes /> },
          { key: 'grades', label: 'Grades', children: <Grades /> },
          { key: 'levels', label: 'Years & Semesters', children: <YearsAndSemesters /> },
        ]}
      />
    </Card>
  );
}
