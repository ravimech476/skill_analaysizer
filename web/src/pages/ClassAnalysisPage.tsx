import { useState } from 'react';
import { Card, Col, Empty, Progress, Row, Select, Space, Spin, Statistic, Table, Tag, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { api, errorMessage } from '../api/client';
import { useClasses } from '../api/lookups';
import { HBars, DonutChart, scaleColor } from '../components/Charts';

async function fetchClassAnalysis(id: number) {
  const r = await api.get(`/analyzer/class/${id}`);
  return r.data.data;
}

export default function ClassAnalysisPage() {
  const { data: classes } = useClasses();
  const [classId, setClassId] = useState<number>();
  const { data, isLoading, error } = useQuery({
    queryKey: ['analyzer', 'class', classId],
    queryFn: () => fetchClassAnalysis(classId!),
    enabled: !!classId,
  });

  return (
    <Card>
      <Space direction="vertical" size="large" style={{ width: '100%' }}>
        <Select
          placeholder="Select a class"
          style={{ width: 300 }}
          value={classId}
          onChange={setClassId}
          options={(classes ?? []).map((c: any) => ({ value: c.id, label: c.label }))}
        />
        {!classId && <Empty description="Select a class to view analysis" />}
        {isLoading && <Spin size="large" style={{ display: 'block', margin: '80px auto' }} />}
        {error && <Typography.Text type="danger">{errorMessage(error)}</Typography.Text>}
        {data && (
          <>
            <Row gutter={16}>
              <Col xs={12} md={6}><Card size="small"><Statistic title="Students" value={data.students} /></Card></Col>
              <Col xs={12} md={6}><Card size="small"><Statistic title="Avg CGPA" value={data.avg_cgpa} precision={2} /></Card></Col>
              <Col xs={12} md={6}><Card size="small"><Statistic title="Pass %" value={data.pass_percent} suffix="%" precision={1} /></Card></Col>
              <Col xs={12} md={6}><Card size="small"><Statistic title="Top CGPA" value={data.top_cgpa} precision={2} /></Card></Col>
            </Row>

            <Card title="Subject Performance" size="small">
              <Table dataSource={data.subjects} rowKey="subject_id" size="small" pagination={false}
                columns={[
                  { title: 'Subject', render: (_: any, r: any) => `${r.code} — ${r.name}` },
                  { title: 'Avg %', dataIndex: 'avg_percent', render: (v: number) => `${v?.toFixed(1)}%`, sorter: (a: any, b: any) => a.avg_percent - b.avg_percent },
                  { title: 'Pass %', dataIndex: 'pass_percent', render: (v: number) => {
                    const color = v >= 75 ? '#15803d' : v >= 60 ? '#b45309' : '#be123c';
                    return <Typography.Text style={{ color }}>{v?.toFixed(1)}%</Typography.Text>;
                  }},
                  { title: 'Failed', dataIndex: 'failed', render: (v: number) => v > 0 ? <Typography.Text type="danger">{v}</Typography.Text> : 0 },
                  { title: 'Highest', dataIndex: 'highest' },
                ]}
              />
            </Card>

            {/* Charts row: Subject Avg bar chart + Class Pass Rate donut */}
            <Row gutter={16}>
              <Col xs={24} md={14}>
                {data.subjects?.length > 0 && (
                  <Card title="Subject Avg %" size="small">
                    <HBars
                      data={(data.subjects ?? []).map((s: any) => ({
                        key: s.subject_id,
                        label: s.code,
                        value: s.avg_percent ?? 0,
                        display: `${s.avg_percent?.toFixed(1)}%`,
                        color: scaleColor(s.avg_percent ?? 0),
                        tooltip: `${s.name}: Pass ${s.pass_percent?.toFixed(1)}%, Failed ${s.failed}`,
                      }))}
                      max={100}
                    />
                  </Card>
                )}
              </Col>
              <Col xs={24} md={10}>
                <Card title="Class Pass Rate" size="small">
                  <div style={{ display: 'flex', justifyContent: 'center' }}>
                    <DonutChart
                      size={160}
                      data={[
                        { key: 'pass', label: 'All Clear', value: Math.round((data.pass_percent ?? 0) / 100 * data.students), color: '#15803d' },
                        { key: 'fail', label: 'With Backlogs', value: data.students - Math.round((data.pass_percent ?? 0) / 100 * data.students), color: '#be123c' },
                      ]}
                      label={`${data.pass_percent?.toFixed(0)}%`}
                      sublabel="pass rate"
                    />
                  </div>
                </Card>
              </Col>
            </Row>

            {data.skill_summary?.length > 0 && (
              <Card title="Skill Coverage" size="small">
                {data.skill_summary.map((s: any) => (
                  <div key={s.skill_id} style={{ marginBottom: 8 }}>
                    <Space style={{ width: '100%', justifyContent: 'space-between' }}>
                      <Typography.Text>{s.name}</Typography.Text>
                      <Typography.Text type="secondary">{s.students_with_skill}/{s.total_students}</Typography.Text>
                    </Space>
                    <Progress percent={Math.round(s.coverage_percent)} size="small"
                      strokeColor={s.coverage_percent >= 75 ? '#15803d' : s.coverage_percent >= 50 ? '#b45309' : '#be123c'} />
                  </div>
                ))}
              </Card>
            )}

            <Card title="Student Ranking" size="small">
              <Table dataSource={data.student_ranking} rowKey="student_id" size="small"
                pagination={{ pageSize: 20, hideOnSinglePage: true }}
                columns={[
                  { title: '#', render: (_: any, __: any, i: number) => i + 1, width: 50 },
                  { title: 'Name', dataIndex: 'name' },
                  { title: 'Register No', dataIndex: 'register_no' },
                  { title: 'CGPA', dataIndex: 'cgpa', render: (v: number) => v?.toFixed(2), sorter: (a: any, b: any) => a.cgpa - b.cgpa, defaultSortOrder: 'descend' as const },
                  { title: 'Skills', dataIndex: 'skill_count' },
                  { title: 'Status', dataIndex: 'placed', render: (v: boolean) => v ? <Tag color="green">Placed</Tag> : <Tag>Active</Tag> },
                ]}
              />
            </Card>
          </>
        )}
      </Space>
    </Card>
  );
}
