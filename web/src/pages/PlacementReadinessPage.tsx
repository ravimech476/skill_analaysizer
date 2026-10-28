import { useState } from 'react';
import { Card, Checkbox, Col, Empty, Row, Select, Space, Spin, Statistic, Table, Tag, Tooltip, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { api, errorMessage } from '../api/client';
import { useDepartments, useClasses } from '../api/lookups';
import { DonutChart } from '../components/Charts';
import ScoreHistory from '../components/ScoreHistory';

interface ReadinessRow {
  student_id: number;
  name: string;
  register_no: string;
  class_label: string;
  cgpa: number;
  skills_score: number;
  aptitude_score: number;
  attendance_score: number;
  communication_score: number;
  readiness_score: number;
  coding_score: number | null;
  change: number | null;
  risk_level: 'none' | 'medium' | 'high';
  risk_reasons: { level: string; text: string }[];
}

interface ReadinessData {
  students: ReadinessRow[];
  avg_readiness: number;
  above_70_percent: number;
  top_student: string | null;
  at_risk: { high: number; medium: number };
}

const RISK = { high: { color: 'red', label: 'High risk' }, medium: { color: 'orange', label: 'Watch' } } as const;

function readinessColor(score: number): string {
  if (score >= 70) return '#15803d';
  if (score >= 50) return '#b45309';
  return '#be123c';
}

function readinessTag(score: number) {
  if (score >= 70) return <Tag color="green">Ready</Tag>;
  if (score >= 50) return <Tag color="orange">Moderate</Tag>;
  return <Tag color="red">Low</Tag>;
}

function ReadinessDashboard({ classId, departmentId }: { classId?: number; departmentId?: number }) {
  const [onlyRisk, setOnlyRisk] = useState(false);
  const { data, isLoading, error } = useQuery<ReadinessData>({
    queryKey: ['analyzer', 'readiness', classId, departmentId],
    queryFn: () =>
      api
        .get('/analyzer/readiness', { params: { class_id: classId, department_id: departmentId } })
        .then((r) => r.data.data),
  });

  if (isLoading) return <Spin size="large" style={{ display: 'block', margin: '80px auto' }} />;
  if (error) return <Typography.Text type="danger">{errorMessage(error)}</Typography.Text>;
  if (!data || !data.students?.length) return <Empty description="No readiness data available" />;

  const students = [...data.students].sort((a, b) => b.readiness_score - a.readiness_score);
  const ranked = students.map((s, i) => ({ ...s, rank: i + 1 })).filter((s) => !onlyRisk || s.risk_level !== 'none');

  const ready = students.filter((s) => s.readiness_score >= 70).length;
  const moderate = students.filter((s) => s.readiness_score >= 50 && s.readiness_score < 70).length;
  const atRisk = students.filter((s) => s.readiness_score < 50).length;

  return (
    <Space direction="vertical" size="large" style={{ width: '100%' }}>
      {/* Stats */}
      <Row gutter={16}>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic title="Avg Readiness" value={data.avg_readiness} precision={1} suffix="%" />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic title="Ready (>=70%)" value={data.above_70_percent} precision={1} suffix="%" valueStyle={{ color: '#15803d' }} />
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic
              title="Needing attention"
              value={data.at_risk.high + data.at_risk.medium}
              suffix={`of ${students.length}`}
              valueStyle={{ color: data.at_risk.high ? '#be123c' : undefined }}
            />
            <Typography.Text type="secondary" style={{ fontSize: 12 }}>
              {data.at_risk.high} high risk, {data.at_risk.medium} to watch
            </Typography.Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card size="small">
            <Statistic title="Top Student" value={data.top_student || '—'} valueStyle={{ fontSize: 16 }} />
          </Card>
        </Col>
      </Row>

      {/* Donut + Table */}
      <Row gutter={16}>
        <Col xs={24} md={8}>
          <Card title="Readiness Distribution" size="small">
            <DonutChart
              data={[
                { key: 'ready', label: 'Ready (>=70)', value: ready, color: '#15803d' },
                { key: 'moderate', label: 'Moderate (50-69)', value: moderate, color: '#d97706' },
                { key: 'atRisk', label: 'Low (<50)', value: atRisk, color: '#be123c' },
              ]}
              label={students.length}
              sublabel="students"
            />
          </Card>
        </Col>
        <Col xs={24} md={16}>
          <Card title="Student Rankings" size="small" extra={<Checkbox checked={onlyRisk} onChange={(e) => setOnlyRisk(e.target.checked)}>Only students needing attention</Checkbox>}>
            <Table
              dataSource={ranked}
              rowKey="student_id"
              size="small"
              pagination={{ pageSize: 15, hideOnSinglePage: true }}
              scroll={{ x: 1000 }}
              expandable={{
                rowExpandable: () => true,
                expandedRowRender: (r: ReadinessRow) => (
                  <Row gutter={[16, 8]}>
                    <Col xs={24} md={10}>
                      <Typography.Text strong>Why</Typography.Text>
                      {r.risk_reasons.length ? (
                        <ul style={{ margin: '4px 0 0', paddingLeft: 18 }}>
                          {r.risk_reasons.map((x) => <li key={x.text}>{x.text}</li>)}
                        </ul>
                      ) : (
                        <div><Typography.Text type="secondary">Nothing worrying on record.</Typography.Text></div>
                      )}
                    </Col>
                    <Col xs={24} md={14}>
                      <Typography.Text strong>Readiness over time</Typography.Text>
                      <ScoreHistory studentId={r.student_id} />
                    </Col>
                  </Row>
                ),
              }}
              columns={[
                { title: '#', dataIndex: 'rank', width: 50, align: 'center' },
                {
                  title: 'Student',
                  key: 'student',
                  width: 200,
                  render: (_, r) => (
                    <Space direction="vertical" size={0}>
                      <Typography.Text strong>{r.name}</Typography.Text>
                      <Typography.Text type="secondary" style={{ fontSize: 12 }}>{r.register_no}</Typography.Text>
                    </Space>
                  ),
                },
                { title: 'Class', dataIndex: 'class_label', width: 100 },
                { title: 'CGPA', dataIndex: 'cgpa', width: 70, align: 'right', render: (v: number) => v?.toFixed(2) ?? '—' },
                { title: 'Skills', dataIndex: 'skills_score', width: 70, align: 'right', render: (v: number) => v != null ? `${v}` : '—' },
                { title: 'Aptitude', dataIndex: 'aptitude_score', width: 80, align: 'right', render: (v: number) => v != null ? `${v}` : '—' },
                { title: 'Attend.', dataIndex: 'attendance_score', width: 80, align: 'right', render: (v: number) => v != null ? `${v}` : '—' },
                { title: 'Comm.', dataIndex: 'communication_score', width: 80, align: 'right', render: (v: number) => v != null ? `${v}` : '—' },
                {
                  title: 'Readiness',
                  dataIndex: 'readiness_score',
                  width: 120,
                  align: 'right',
                  sorter: (a: ReadinessRow, b: ReadinessRow) => a.readiness_score - b.readiness_score,
                  render: (v: number) => (
                    <Space size={4}>
                      <span style={{ color: readinessColor(v), fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
                        {v?.toFixed(1)}
                      </span>
                      {readinessTag(v)}
                    </Space>
                  ),
                },
                {
                  title: 'Change',
                  dataIndex: 'change',
                  width: 80,
                  align: 'right',
                  render: (v: number | null) =>
                    v == null ? '—' : <span style={{ color: v < 0 ? '#be123c' : v > 0 ? '#15803d' : undefined }}>{v > 0 ? '+' : ''}{v}</span>,
                },
                {
                  title: 'Risk',
                  dataIndex: 'risk_level',
                  width: 100,
                  render: (v: 'none' | 'medium' | 'high', r: ReadinessRow) =>
                    v === 'none' ? '—' : (
                      <Tooltip title={r.risk_reasons.map((x) => x.text).join('. ')}>
                        <Tag color={RISK[v].color}>{RISK[v].label}</Tag>
                      </Tooltip>
                    ),
                },
              ]}
            />
          </Card>
        </Col>
      </Row>
    </Space>
  );
}

export default function PlacementReadinessPage() {
  const [departmentId, setDepartmentId] = useState<number>();
  const [classId, setClassId] = useState<number>();
  const { data: departments } = useDepartments();
  const { data: classes } = useClasses(departmentId, 'all');

  const deptOptions = (departments ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }));
  const classOptions = (classes ?? []).map((c) => ({ value: c.id, label: c.label }));

  return (
    <Card>
      <Space direction="vertical" size="large" style={{ width: '100%' }}>
        <Space wrap>
          <Select
            allowClear
            showSearch
            optionFilterProp="label"
            placeholder="Filter by department"
            style={{ width: 260 }}
            options={deptOptions}
            value={departmentId}
            onChange={(v) => {
              setDepartmentId(v);
              setClassId(undefined);
            }}
          />
          <Select
            allowClear
            showSearch
            optionFilterProp="label"
            placeholder="Filter by class"
            style={{ width: 220 }}
            options={classOptions}
            value={classId}
            onChange={setClassId}
          />
        </Space>
        <ReadinessDashboard classId={classId} departmentId={departmentId} />
      </Space>
    </Card>
  );
}
