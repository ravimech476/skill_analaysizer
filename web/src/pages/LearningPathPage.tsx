import { useState } from 'react';
import {
  Alert, Card, Col, Empty, Row, Select, Space, Spin, Table, Tabs, Tag, Typography,
} from 'antd';
import { useQuery } from '@tanstack/react-query';
import { careersApi, coursesApi, type CareerMatch, type Course } from '../api/careers';
import { studentsApi } from '../api/phase2';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import MasterCrud from '../components/MasterCrud';
import PrepPlan from '../components/PrepPlan';
import { useSkills } from './SkillsPage';
import { StudentPicker } from './PlacementPage';

/** Flatten the gap-courses from every career match into a deduplicated list. */
function gapCourses(matches: CareerMatch[]) {
  const seen = new Set<number>();
  const out: { course: CareerMatch['gaps'][number]['courses'] extends (infer C)[] | undefined ? C : never; skill: string; careers: string[] }[] = [];
  for (const m of matches) {
    for (const g of m.gaps) {
      for (const c of g.courses ?? []) {
        if (seen.has(c.id)) {
          const existing = out.find((o) => o.course.id === c.id);
          if (existing && !existing.careers.includes(m.name)) existing.careers.push(m.name);
          continue;
        }
        seen.add(c.id);
        out.push({ course: c, skill: g.name, careers: [m.name] });
      }
    }
  }
  return out;
}

/** Student / parent view: courses recommended from career-match gaps. */
function MyLearningPath({ studentId }: { studentId: number }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['career-matches', studentId],
    queryFn: () => careersApi.matches(studentId),
  });

  if (isLoading) return <Spin />;
  if (error) return <Alert type="error" showIcon message={String(error)} />;
  if (!data || !data.total) return <Empty description="No career matches yet -- run the career prediction first to get personalised course recommendations." />;

  const rows = gapCourses(data.matches);
  if (!rows.length) return <Empty description="No skill gaps found -- your skills already cover the career requirements." />;

  return (
    <Space direction="vertical" size="middle" style={{ width: '100%' }}>
      <PrepPlan studentId={studentId} />
      <Typography.Title level={5} style={{ margin: '8px 0 0' }}>All recommended courses</Typography.Title>
      <Typography.Paragraph type="secondary">
        Courses recommended to close the skill gaps found in your career matches. Focus on the top items first.
      </Typography.Paragraph>
      <Table
        rowKey={(r) => r.course.id}
        size="small"
        dataSource={rows}
        pagination={{ pageSize: 20, hideOnSinglePage: true }}
        columns={[
          { title: 'Course', dataIndex: ['course', 'title'], render: (v, r) => r.course.url ? <a href={r.course.url} target="_blank" rel="noreferrer">{v}</a> : v },
          { title: 'Skill', dataIndex: 'skill', width: 160 },
          { title: 'Provider', dataIndex: ['course', 'provider'], width: 140, render: (v) => v ?? '—' },
          { title: 'Level', dataIndex: ['course', 'level'], width: 90, render: (v) => `Level ${v}` },
          { title: 'Hours', dataIndex: ['course', 'duration_hours'], width: 80, render: (v) => v ?? '—' },
          {
            title: '', key: 'flags', width: 140,
            render: (_, r) => (
              <Space size={4}>
                {r.course.is_free && <Tag color="green">Free</Tag>}
                {r.careers.map((c) => <Tag key={c}>{c}</Tag>)}
              </Space>
            ),
          },
        ]}
      />
    </Space>
  );
}

/** Staff view: pick a student, see their recommended courses. */
function StudentLearningPath() {
  const [studentId, setStudentId] = useState<number>();
  const [search, setSearch] = useState('');
  const { data } = useQuery({
    queryKey: ['students', 'lp-picker', search],
    queryFn: () => studentsApi.list({ page: 1, page_size: 50, search }),
  });
  return (
    <Space direction="vertical" size="middle" style={{ width: '100%' }}>
      <Select
        showSearch
        filterOption={false}
        style={{ width: '100%', maxWidth: 480 }}
        placeholder="Search a student by name or register number"
        value={studentId}
        onSearch={setSearch}
        onChange={setStudentId}
        options={(data?.data ?? []).map((s) => ({ value: s.id, label: `${s.register_no} · ${s.name}${s.class_label ? ` · ${s.class_label}` : ''}` }))}
      />
      {!studentId ? (
        <Empty description="Pick a student to see courses recommended for their skill gaps" />
      ) : (
        <MyLearningPath studentId={studentId} />
      )}
    </Space>
  );
}

/** Admin/staff course CRUD. */
function CoursesMaster() {
  const { data: skills } = useSkills();
  return (
    <MasterCrud<Course>
      path="courses"
      perm="career"
      noun="course"
      fields={[
        { name: 'skill_id', label: 'Skill it teaches', type: 'select', required: true, options: (skills ?? []).map((s) => ({ value: s.id, label: s.name })) },
        { name: 'title', label: 'Course title', type: 'text', required: true },
        { name: 'provider', label: 'Provider', type: 'text', extra: 'NPTEL, Coursera, in-house…' },
        { name: 'url', label: 'Link', type: 'text' },
        { name: 'level', label: 'Level it takes you to', type: 'number', min: 1, max: 5 },
        { name: 'duration_hours', label: 'Hours', type: 'number', min: 0, max: 2000 },
        { name: 'is_certification', label: 'Gives a certificate', type: 'bool' },
        { name: 'is_free', label: 'Free', type: 'bool' },
      ]}
      columns={[
        { title: 'Course', dataIndex: 'title' },
        { title: 'Skill', dataIndex: 'skill_name', width: 170 },
        { title: 'Provider', dataIndex: 'provider', width: 140, render: (v) => v ?? '—' },
        { title: 'Takes you to', dataIndex: 'level', width: 110, render: (v) => `Level ${v}` },
        { title: 'Hours', dataIndex: 'duration_hours', width: 80, render: (v) => v ?? '—' },
        {
          title: '', key: 'flags', width: 150,
          render: (_, c) => (
            <Space size={4}>
              {c.is_free && <Tag color="green">Free</Tag>}
              {c.is_certification && <Tag color="blue">Certificate</Tag>}
            </Space>
          ),
        },
        {
          title: 'Link', key: 'link', width: 80,
          render: (_, c) => c.url ? <a href={c.url} target="_blank" rel="noreferrer">Open</a> : <Typography.Text type="secondary">{'—'}</Typography.Text>,
        },
      ]}
    />
  );
}

export default function LearningPathPage() {
  const { user, can } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  const mine = audience === 'student' || audience === 'parent';

  if (mine) {
    return (
      <Card>
        <Typography.Paragraph type="secondary">
          Courses recommended to close the skill gaps found by career prediction. Complete them to improve your career readiness.
        </Typography.Paragraph>
        <StudentPicker parent={audience === 'parent'}>
          {(id) => <MyLearningPath studentId={id} />}
        </StudentPicker>
      </Card>
    );
  }

  return (
    <Card>
      <Tabs
        items={[
          { key: 'student', label: 'Student recommendations', children: <StudentLearningPath /> },
          ...(can('career.create') || can('career.update')
            ? [{ key: 'courses', label: 'Course catalogue', children: <CoursesMaster /> }]
            : []),
        ]}
      />
    </Card>
  );
}
