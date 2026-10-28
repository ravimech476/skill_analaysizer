import { Alert, Card, Col, Progress, Row, Space, Spin, Statistic, Table, Tag, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { reportsApi } from '../api/reports';

const SEVERITY = { error: { color: 'red', label: 'Error' }, warning: { color: 'orange', label: 'Warning' }, info: { color: 'default', label: 'Optional' } } as const;
const pctColor = (p: number) => (p >= 90 ? '#16a34a' : p >= 60 ? '#d97706' : '#dc2626');

/** How complete and consistent the student data is. Skill, career and insight results all depend on it. */
export default function DataQuality({ departmentId }: { departmentId?: number }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'data-quality', departmentId],
    queryFn: () => reportsApi.dataQuality({ department_id: departmentId }),
  });
  if (isLoading) return <Spin />;
  if (error || !data) return <Alert type="error" showIcon title={errorMessage(error)} />;
  const r = data.report;
  const ready = r.students ? Math.round((r.clean_students / r.students) * 100) : 0;

  return (
    <Card title="Data quality" extra={<Typography.Text type="secondary">Checked before analysis</Typography.Text>}>
      <Typography.Paragraph type="secondary">
        Skill, career and insight results are only as good as the records behind them. These checks find missing and contradictory data so it can be fixed first.
      </Typography.Paragraph>
      <Row gutter={[16, 16]}>
        <Col xs={12} md={6}>
          <Statistic title="Students checked" value={r.students} />
        </Col>
        <Col xs={12} md={6}>
          <Statistic title="Ready for analysis" value={ready} suffix="%" valueStyle={{ color: pctColor(ready) }} />
        </Col>
        <Col xs={12} md={6}>
          <Statistic title="Errors" value={r.errors} valueStyle={{ color: r.errors ? '#dc2626' : undefined }} />
        </Col>
        <Col xs={12} md={6}>
          <Statistic title="Warnings" value={r.warnings} />
        </Col>
      </Row>

      <Typography.Title level={5} style={{ marginTop: 20 }}>Completeness by area</Typography.Title>
      <div style={{ display: 'grid', gap: 8, maxWidth: 560 }}>
        {r.areas.map((a) => (
          <div key={a.key} style={{ display: 'grid', gridTemplateColumns: '170px 1fr 56px', gap: 10, alignItems: 'center', fontSize: 13 }}>
            <span>{a.label}</span>
            <Progress percent={a.percent} showInfo={false} strokeColor={pctColor(a.percent)} size="small" />
            <span>{a.percent}%</span>
          </div>
        ))}
      </div>

      <Typography.Title level={5} style={{ marginTop: 20 }}>Issues found</Typography.Title>
      <Table
        size="small"
        rowKey="key"
        pagination={false}
        dataSource={r.checks.filter((c) => c.count > 0)}
        locale={{ emptyText: 'No issues found.' }}
        columns={[
          { title: '', dataIndex: 'severity', width: 90, render: (s: keyof typeof SEVERITY) => <Tag color={SEVERITY[s].color}>{SEVERITY[s].label}</Tag> },
          {
            title: 'Issue',
            render: (_, c) => (
              <>
                <div>{c.label}</div>
                <Typography.Text type="secondary" style={{ fontSize: 12 }}>{c.hint}</Typography.Text>
              </>
            ),
          },
          { title: 'Students', dataIndex: 'count', width: 90, align: 'right', render: (v, c) => `${v} (${c.percent}%)` },
          { title: 'For example', width: 260, render: (_, c) => c.sample.map((p) => p.register_no).join(', ') },
        ]}
      />

      {r.need_attention.length > 0 && (
        <>
          <Typography.Title level={5} style={{ marginTop: 20 }}>Students to fix first</Typography.Title>
          <Table
            size="small"
            rowKey="id"
            pagination={false}
            dataSource={r.need_attention}
            columns={[
              { title: 'Student', width: 220, render: (_, s) => <Space size={4}><strong>{s.register_no}</strong>{s.name}</Space> },
              { title: 'Issues', render: (_, s) => s.issues.join(' · ') },
            ]}
          />
        </>
      )}
    </Card>
  );
}
