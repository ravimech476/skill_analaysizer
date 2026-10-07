import { useState } from 'react';
import { Card, Col, Empty, Progress, Row, Select, Space, Spin, Statistic, Table, Tag, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { api, errorMessage } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { Columns, HBars, DonutChart, scaleColor, CHART_COLORS } from '../components/Charts';

async function fetchStudentAnalysis(id: number) {
  const r = await api.get(`/analyzer/student/${id}`);
  return r.data.data;
}

function StudentDashboard({ studentId }: { studentId: number }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['analyzer', 'student', studentId],
    queryFn: () => fetchStudentAnalysis(studentId),
  });
  if (isLoading) return <Spin size="large" style={{ display: 'block', margin: '80px auto' }} />;
  if (error) return <Typography.Text type="danger">{errorMessage(error)}</Typography.Text>;
  if (!data) return <Empty />;

  return (
    <Space direction="vertical" size="large" style={{ width: '100%' }}>
      {/* Student Info */}
      <Card>
        <Typography.Title level={4} style={{ marginTop: 0 }}>{data.name} ({data.register_no})</Typography.Title>
        <Row gutter={16}>
          <Col xs={12} md={6}><Statistic title="CGPA" value={data.cgpa} precision={2} /></Col>
          <Col xs={12} md={6}><Statistic title="Backlogs" value={data.backlog_count} /></Col>
          <Col xs={12} md={6}><Statistic title="Department" value={data.department} /></Col>
          <Col xs={12} md={6}><Statistic title="Class" value={data.class_label || '—'} /></Col>
        </Row>
      </Card>

      {/* Semester Performance */}
      <Card title="Semester Performance">
        <Table
          dataSource={data.semesters}
          rowKey="sem_no"
          size="small"
          pagination={false}
          columns={[
            { title: 'Semester', dataIndex: 'name' },
            { title: 'SGPA', dataIndex: 'sgpa', render: (v: number) => v?.toFixed(2) ?? '—' },
            { title: 'Subjects', dataIndex: 'subjects' },
            { title: 'Passed', dataIndex: 'passed' },
            { title: 'Failed', dataIndex: 'failed', render: (v: number) => v > 0 ? <Typography.Text type="danger">{v}</Typography.Text> : 0 },
            { title: 'Avg %', dataIndex: 'avg_percent', render: (v: number) => v != null ? `${v.toFixed(1)}%` : '—' },
          ]}
        />
      </Card>

      {/* SGPA Trend Chart */}
      {data.semesters?.length > 0 && (
        <Card title="SGPA Trend">
          <Columns
            data={(data.semesters ?? []).map((s: any, i: number) => ({
              key: s.sem_no,
              label: s.name,
              value: s.sgpa ?? 0,
              display: s.sgpa?.toFixed(2) ?? '—',
              color: CHART_COLORS[i % CHART_COLORS.length],
            }))}
            height={140}
          />
        </Card>
      )}

      {/* Subject Marks */}
      <Card title="Subject-wise Marks">
        <Table
          dataSource={data.subjects}
          rowKey={(r: any) => `${r.subject_id}-${r.semester}`}
          size="small"
          pagination={false}
          columns={[
            { title: 'Subject', dataIndex: 'name', render: (v: string, r: any) => <Space>{r.code} — {v}</Space> },
            { title: 'Semester', dataIndex: 'semester' },
            { title: 'Marks', render: (_: any, r: any) => `${r.marks_obtained}/${r.max_marks}` },
            { title: '%', dataIndex: 'marks_percent', render: (v: number) => {
              const color = v >= 75 ? '#15803d' : v >= 60 ? '#b45309' : '#be123c';
              return <Typography.Text style={{ color }}>{v.toFixed(1)}%</Typography.Text>;
            }},
            { title: 'Result', dataIndex: 'result', render: (v: string) => <Tag color={v === 'pass' ? 'green' : 'red'}>{v}</Tag> },
            { title: 'Grade', dataIndex: 'grade' },
          ]}
        />
      </Card>

      {/* Subject Marks Bar Chart */}
      {data.subjects?.length > 0 && (
        <Card title="Subject Marks (%)">
          <HBars
            data={(data.subjects ?? []).map((s: any) => ({
              key: `${s.subject_id}-${s.semester}`,
              label: s.code,
              value: s.marks_percent ?? 0,
              display: `${s.marks_percent?.toFixed(1)}%`,
              color: scaleColor(s.marks_percent ?? 0),
              tooltip: `${s.name}: ${s.marks_obtained}/${s.max_marks}`,
            }))}
            max={100}
          />
        </Card>
      )}

      {/* Skills */}
      {data.skills?.length > 0 && (
        <Row gutter={16}>
          <Col xs={24} md={14}>
            <Card title="Skills">
              <Space wrap>
                {data.skills.map((s: any) => (
                  <Tag key={s.skill_id} color="blue">{s.name} — {'★'.repeat(s.proficiency)}{'☆'.repeat(5 - s.proficiency)}</Tag>
                ))}
              </Space>
            </Card>
          </Col>
          <Col xs={24} md={10}>
            <Card title="Skill Distribution">
              <DonutChart
                data={data.skills.map((s: any, i: number) => ({
                  key: String(s.skill_id),
                  label: s.name,
                  value: s.proficiency,
                  color: CHART_COLORS[i % CHART_COLORS.length],
                }))}
                label={data.skills.length}
                sublabel="skills"
              />
            </Card>
          </Col>
        </Row>
      )}

      {/* Performance Overview + Strengths & Weaknesses */}
      <Row gutter={16}>
        <Col xs={24} md={8}>
          <Card title="Performance Overview" size="small">
            <div style={{ display: 'flex', justifyContent: 'center' }}>
              <DonutChart
                size={150}
                data={[
                  { key: 'strong', label: 'Strong (≥75%)', value: data.strengths?.length ?? 0, color: '#15803d' },
                  { key: 'average', label: 'Average', value: Math.max(0, (data.subjects?.length ?? 0) - (data.strengths?.length ?? 0) - (data.weaknesses?.length ?? 0)), color: '#d97706' },
                  { key: 'weak', label: 'Weak (<60%)', value: data.weaknesses?.length ?? 0, color: '#be123c' },
                ]}
                label={data.subjects?.length ?? 0}
                sublabel="subjects"
              />
            </div>
          </Card>
        </Col>
        <Col xs={24} md={8}>
          <Card title="Strengths" size="small">
            {data.strengths?.length ? data.strengths.map((s: string) => <Tag key={s} color="green" style={{ margin: 4 }}>{s}</Tag>) : <Typography.Text type="secondary">No strong subjects yet</Typography.Text>}
          </Card>
        </Col>
        <Col xs={24} md={8}>
          <Card title="Weaknesses" size="small">
            {data.weaknesses?.length ? data.weaknesses.map((s: string) => <Tag key={s} color="red" style={{ margin: 4 }}>{s}</Tag>) : <Typography.Text type="secondary">No weak subjects</Typography.Text>}
          </Card>
        </Col>
      </Row>

      {/* Eligible Drives */}
      {data.eligible_drives?.length > 0 && (
        <Card title="Eligible Placement Drives">
          <Table
            dataSource={data.eligible_drives}
            rowKey="id"
            size="small"
            pagination={false}
            columns={[
              { title: 'Company', dataIndex: 'company' },
              { title: 'Role', dataIndex: 'title' },
              { title: 'Package', dataIndex: 'package_lpa', render: (v: number) => `₹ ${v} LPA` },
              { title: 'Match', dataIndex: 'match_percent', render: (v: number) => <Progress percent={Math.round(v)} size="small" /> },
            ]}
          />
        </Card>
      )}
    </Space>
  );
}

export default function StudentAnalysisPage() {
  const { user } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  const [studentId, setStudentId] = useState<number>();
  const [search, setSearch] = useState('');
  const { data: students } = useQuery({
    queryKey: ['students', 'search', search],
    queryFn: () => api.get('/students', { params: { search, page: 1, page_size: 20 } }).then(r => r.data.data),
    enabled: (audience === 'admin' || audience === 'staff') && search.length >= 2,
  });

  if (audience === 'student') {
    return <Card><StudentDashboard studentId={user!.id} /></Card>;
  }
  if (audience === 'parent') {
    return <Card><Typography.Text type="secondary">Select a child to view analysis</Typography.Text></Card>;
  }

  return (
    <Card>
      <Space direction="vertical" size="large" style={{ width: '100%' }}>
        <Select
          showSearch
          placeholder="Search student by name or register no..."
          style={{ width: '100%', maxWidth: 500 }}
          filterOption={false}
          onSearch={setSearch}
          onChange={(v) => setStudentId(v)}
          value={studentId}
          options={(students ?? []).map((s: any) => ({ value: s.id, label: `${s.register_no} — ${s.name} (${s.class_label || s.department_code})` }))}
        />
        {studentId ? <StudentDashboard studentId={studentId} /> : <Empty description="Search and select a student to view their analysis" />}
      </Space>
    </Card>
  );
}
