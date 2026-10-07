import { Card, Col, Empty, Progress, Row, Space, Spin, Statistic, Table, Tag, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { api, errorMessage } from '../api/client';
import { Columns, HBars, DonutChart, scaleColor, CHART_COLORS } from '../components/Charts';

async function fetchDeptAnalysis() {
  const r = await api.get('/analyzer/department');
  return r.data.data;
}

export default function DeptAnalysisPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['analyzer', 'department'],
    queryFn: fetchDeptAnalysis,
  });

  if (isLoading) return <div style={{ textAlign: 'center', padding: 80 }}><Spin size="large" /></div>;
  if (error) return <Card><Typography.Text type="danger">{errorMessage(error)}</Typography.Text></Card>;
  if (!data) return <Card><Empty /></Card>;

  const departments: any[] = data.departments ?? [];
  const skillDist: any[] = data.skill_distribution ?? [];
  const semTrend: any[] = data.semester_trend ?? [];
  const weakSubjects: any[] = data.weak_subjects ?? [];

  const totalStudents = departments.reduce((s: number, d: any) => s + (d.students ?? 0), 0);
  const totalPlaced = departments.reduce((s: number, d: any) => s + (d.placed_count ?? 0), 0);
  const avgCGPA = departments.length > 0
    ? departments.reduce((s: number, d: any) => s + (d.avg_cgpa ?? 0) * (d.students ?? 0), 0) / Math.max(totalStudents, 1)
    : 0;
  const avgPass = departments.length > 0
    ? departments.reduce((s: number, d: any) => s + (d.pass_percent ?? 0), 0) / departments.length
    : 0;

  return (
    <Card>
      <Space direction="vertical" size="large" style={{ width: '100%' }}>
        {/* Headline Stats */}
        <Row gutter={16}>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Total Students" value={totalStudents} /></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Avg CGPA" value={avgCGPA} precision={2} /></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Avg Pass %" value={avgPass} suffix="%" precision={1} /></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Total Placed" value={totalPlaced} /></Card></Col>
        </Row>

        {/* Department Comparison Table */}
        {departments.length > 0 && (
          <Card title="Department Comparison" size="small">
            <Table
              dataSource={departments}
              rowKey="id"
              size="small"
              pagination={false}
              columns={[
                { title: 'Department', render: (_: any, r: any) => <Tag color="blue">{r.code}</Tag> },
                { title: 'Name', dataIndex: 'name' },
                { title: 'Students', dataIndex: 'students', sorter: (a: any, b: any) => a.students - b.students },
                { title: 'Avg CGPA', dataIndex: 'avg_cgpa', render: (v: number) => v > 0 ? v.toFixed(2) : '—', sorter: (a: any, b: any) => a.avg_cgpa - b.avg_cgpa },
                {
                  title: 'Pass %', dataIndex: 'pass_percent',
                  render: (v: number) => <Typography.Text style={{ color: scaleColor(v) }}>{v.toFixed(1)}%</Typography.Text>,
                  sorter: (a: any, b: any) => a.pass_percent - b.pass_percent,
                },
                {
                  title: 'Placed', dataIndex: 'placed_count',
                  render: (v: number, r: any) => `${v} (${r.placed_percent?.toFixed(0)}%)`,
                },
                {
                  title: 'Top Skills', dataIndex: 'top_skills',
                  render: (v: string[]) => v?.length ? v.map((s) => <Tag key={s} style={{ marginBottom: 2 }}>{s}</Tag>) : '—',
                },
              ]}
            />
          </Card>
        )}

        {/* CGPA Comparison Chart */}
        {departments.length > 1 && (
          <Card title="Avg CGPA by Department" size="small">
            <Columns
              data={departments.filter((d: any) => d.avg_cgpa > 0).map((d: any, i: number) => ({
                key: d.id,
                label: d.code,
                value: d.avg_cgpa,
                display: d.avg_cgpa.toFixed(2),
                color: CHART_COLORS[i % CHART_COLORS.length],
                tooltip: `${d.name}: ${d.students} students`,
              }))}
              height={140}
            />
          </Card>
        )}

        {/* Placement & Pass Donuts */}
        {totalStudents > 0 && (
          <Row gutter={16}>
            <Col xs={24} md={12}>
              <Card title="Overall Placement Rate" size="small">
                <div style={{ display: 'flex', justifyContent: 'center' }}>
                  <DonutChart
                    size={160}
                    data={[
                      { key: 'placed', label: 'Placed', value: totalPlaced, color: '#15803d' },
                      { key: 'unplaced', label: 'Not Placed', value: totalStudents - totalPlaced, color: '#e5e7eb' },
                    ]}
                    label={`${Math.round((totalPlaced / totalStudents) * 100)}%`}
                    sublabel="placed"
                  />
                </div>
              </Card>
            </Col>
            <Col xs={24} md={12}>
              <Card title="Pass / Fail Ratio" size="small">
                <div style={{ display: 'flex', justifyContent: 'center' }}>
                  {(() => {
                    const passed = Math.round(avgPass / 100 * totalStudents);
                    return (
                      <DonutChart
                        size={160}
                        data={[
                          { key: 'pass', label: 'All Clear', value: passed, color: '#0d9488' },
                          { key: 'fail', label: 'With Backlogs', value: totalStudents - passed, color: '#b45309' },
                        ]}
                        label={`${avgPass.toFixed(0)}%`}
                        sublabel="pass rate"
                      />
                    );
                  })()}
                </div>
              </Card>
            </Col>
          </Row>
        )}

        {/* Skill Distribution */}
        {skillDist.length > 0 && (
          <Card title="Skill Distribution" size="small">
            <Table
              dataSource={skillDist}
              rowKey="skill_id"
              size="small"
              pagination={{ pageSize: 15, hideOnSinglePage: true }}
              columns={[
                { title: 'Skill', dataIndex: 'name' },
                {
                  title: 'Students',
                  render: (_: any, r: any) => {
                    const total = Object.values(r.by_department ?? {}).reduce((s: number, v: any) => s + (v as number), 0) as number;
                    return total;
                  },
                  sorter: (a: any, b: any) => {
                    const ta = Object.values(a.by_department ?? {}).reduce((s: number, v: any) => s + (v as number), 0) as number;
                    const tb = Object.values(b.by_department ?? {}).reduce((s: number, v: any) => s + (v as number), 0) as number;
                    return ta - tb;
                  },
                },
                {
                  title: 'Coverage',
                  render: (_: any, r: any) => {
                    const total = Object.values(r.by_department ?? {}).reduce((s: number, v: any) => s + (v as number), 0) as number;
                    const pct = totalStudents > 0 ? Math.round((total / totalStudents) * 100) : 0;
                    return (
                      <Progress
                        percent={pct}
                        size="small"
                        strokeColor={pct >= 50 ? '#15803d' : pct >= 25 ? '#b45309' : '#be123c'}
                      />
                    );
                  },
                },
                {
                  title: 'By Department',
                  render: (_: any, r: any) => (
                    <Space size={4} wrap>
                      {Object.entries(r.by_department ?? {}).map(([dept, count]) => (
                        <Tag key={dept}>{dept}: {count as number}</Tag>
                      ))}
                    </Space>
                  ),
                },
              ]}
            />
          </Card>
        )}

        {/* Semester Trend */}
        {semTrend.length > 0 && (
          <>
            <Card title="Semester Trend" size="small">
              <Table
                dataSource={semTrend}
                rowKey="semester"
                size="small"
                pagination={false}
                columns={[
                  { title: 'Semester', dataIndex: 'semester' },
                  { title: 'Avg %', dataIndex: 'avg_percent', render: (v: number) => v != null ? `${v.toFixed(1)}%` : '—' },
                  {
                    title: 'Trend',
                    dataIndex: 'avg_percent',
                    key: 'trend',
                    render: (v: number) => (
                      <Progress percent={Math.round(v ?? 0)} size="small" showInfo={false}
                        strokeColor={scaleColor(v ?? 0)} />
                    ),
                  },
                ]}
              />
            </Card>

            <Card title="Semester Avg % Trend" size="small">
              <Columns
                data={semTrend.map((s: any, i: number) => ({
                  key: s.semester,
                  label: s.semester,
                  value: s.avg_percent ?? 0,
                  display: s.avg_percent != null ? `${s.avg_percent.toFixed(1)}%` : '—',
                  color: CHART_COLORS[i % CHART_COLORS.length],
                }))}
                height={140}
              />
            </Card>
          </>
        )}

        {/* Weak Subjects */}
        {weakSubjects.length > 0 && (
          <>
            <Card title="Subjects Needing Attention" size="small">
              <Table
                dataSource={weakSubjects}
                rowKey="subject_id"
                size="small"
                pagination={false}
                columns={[
                  { title: 'Subject', render: (_: any, r: any) => `${r.code} — ${r.name}` },
                  { title: 'Department', dataIndex: 'department' },
                  {
                    title: 'Pass %', dataIndex: 'pass_percent',
                    render: (v: number) => <Tag color={v < 50 ? 'red' : 'orange'}>{v?.toFixed(1)}%</Tag>,
                  },
                  { title: 'Avg %', dataIndex: 'avg_percent', render: (v: number) => `${v?.toFixed(1)}%` },
                ]}
              />
            </Card>

            <Card title="Weak Subject Pass %" size="small">
              <HBars
                data={weakSubjects.map((s: any) => ({
                  key: s.subject_id,
                  label: s.code,
                  value: s.pass_percent ?? 0,
                  display: `${s.pass_percent?.toFixed(1)}%`,
                  color: scaleColor(s.pass_percent ?? 0),
                  tooltip: `${s.name}: Avg ${s.avg_percent?.toFixed(1)}%`,
                }))}
                max={100}
              />
            </Card>
          </>
        )}
      </Space>
    </Card>
  );
}
