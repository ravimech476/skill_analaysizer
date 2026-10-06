import { useState } from 'react';
import dayjs from 'dayjs';
import { Alert, Button, Card, Col, Progress, Row, Select, Space, Spin, Table, Tag, Typography } from 'antd';
import {
  ApartmentOutlined,
  BookOutlined,
  DownloadOutlined,
  IdcardOutlined,
  RocketOutlined,
  SolutionOutlined,
  TrophyOutlined,
  WarningOutlined,
} from '@ant-design/icons';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { useDepartments } from '../api/lookups';
import { exportsApi, reportsApi } from '../api/reports';
import { useAuth } from '../auth/AuthContext';
import { Columns, HBars, scaleColor } from '../components/Charts';
import { series as DEPT_COLORS } from '../theme';



export default function ReportsPage() {
  const { user, can } = useAuth();
  const collegeWide = (user?.roles ?? []).some((r) => r === 'admin' || r === 'placement_officer');
  const { data: depts } = useDepartments();
  const [deptId, setDeptId] = useState<number>();
  const [examId, setExamId] = useState<number>();

  const { data: d, isLoading, isFetching, error } = useQuery({
    queryKey: ['reports', 'dashboard', deptId, examId],
    queryFn: () => reportsApi.dashboard({ department_id: deptId, exam_type_id: examId }),
    placeholderData: keepPreviousData,
  });

  if (isLoading) return <Spin />;
  if (error) return <Alert type="error" showIcon title={errorMessage(error)} />;
  if (!d) return null;
  const h = d.headline;
  const scopeParams = deptId ? { department_id: deptId } : {};

  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      <Card>
        <Space wrap style={{ width: '100%', justifyContent: 'space-between' }}>
          <Space wrap>
            <Typography.Text strong style={{ fontSize: 15 }}>Showing</Typography.Text>
            <Tag color="blue">{d.scope_department ? `${d.scope_department} department` : 'Whole college'}</Tag>
            {isFetching && <Spin size="small" />}
          </Space>
          <Space wrap>
            {collegeWide && (
              <Select
                allowClear
                style={{ width: 240 }}
                placeholder="All departments"
                value={deptId}
                onChange={setDeptId}
                options={(depts ?? []).map((x: { id: number; code: string; name: string }) => ({ value: x.id, label: `${x.code} · ${x.name}` }))}
              />
            )}
            {can('student.view') && (
              <Button icon={<DownloadOutlined />} onClick={() => exportsApi.students({ ...scopeParams, lifecycle: 'studying' })}>
                Student list
              </Button>
            )}
            {can('placement.view') && (
              <Button icon={<DownloadOutlined />} onClick={() => exportsApi.placements(scopeParams)}>
                Placement report
              </Button>
            )}
          </Space>
        </Space>
      </Card>

      <Row gutter={[16, 16]}>
        {[
          { t: 'Students', v: h.students, icon: <SolutionOutlined /> },
          { t: 'Staff', v: h.staff, icon: <IdcardOutlined /> },
          { t: 'Classes', v: h.classes, icon: <ApartmentOutlined /> },
          { t: 'Avg CGPA', v: h.avg_cgpa ?? '—', icon: <BookOutlined /> },
          { t: 'Backlogs', v: h.with_backlogs, icon: <WarningOutlined />, danger: h.with_backlogs > 0 },
          { t: `Placed (${h.placed_percent}%)`, v: h.placed, icon: <TrophyOutlined /> },
          { t: 'Drives', v: h.open_drives, icon: <RocketOutlined /> },
        ].map((s) => (
          <Col xs={12} sm={8} lg={6} xxl={3} key={s.t} style={{ flexGrow: 1 }}>
            <Card size="small" styles={{ body: { padding: 16 } }}>
              <Space size={12} align="center">
                <span className="icon-chip" style={{ width: 34, height: 34, fontSize: 16 }}>{s.icon}</span>
                <span>
                  <div style={{ fontSize: 12.5, color: 'var(--text-soft)', lineHeight: 1.3, whiteSpace: 'nowrap' }}>{s.t}</div>
                  <div className="tabular" style={{ fontSize: 21, fontWeight: 600, lineHeight: 1.25, letterSpacing: '-0.02em', color: s.danger ? 'var(--ant-color-error, #be123c)' : undefined }}>
                    {s.v}
                  </div>
                </span>
              </Space>
            </Card>
          </Col>
        ))}
      </Row>

      <Row gutter={[16, 16]}>
        <Col xs={24} xl={14}>
          <Card
            title="Pass % by class"
            style={{ height: '100%' }}
            extra={
              d.exams.length > 0 && (
                <Select
                  size="small"
                  style={{ width: 150 }}
                  value={d.exam?.id}
                  onChange={setExamId}
                  options={d.exams.map((e) => ({ value: e.id, label: e.name }))}
                />
              )
            }
          >
            <Typography.Paragraph type="secondary" style={{ marginTop: -4 }}>
              Share of subject papers passed in {d.exam?.name ?? 'the selected exam'} (regular attempt, current academic year).
            </Typography.Paragraph>
            <HBars
              max={100}
              empty="No marks entered this academic year"
              data={d.pass_by_class.map((c) => ({
                key: c.class_id,
                label: c.class_label,
                value: c.pass_percent,
                display: `${c.pass_percent}%`,
                color: scaleColor(c.pass_percent),
                tooltip: `${c.passed} of ${c.appeared} papers passed · ${c.all_clear} of ${c.students} students cleared every subject (${c.all_clear_percent}%)`,
              }))}
            />
          </Card>
        </Col>
        <Col xs={24} xl={10}>
          <Card title="CGPA spread" style={{ height: '100%' }}>
            <Columns
              empty="No CGPA computed yet"
              data={d.cgpa_distribution.map((b) => ({
                key: b.label,
                label: b.label,
                value: b.total,
                tooltip: Object.keys(b.by_department).length
                  ? Object.entries(b.by_department).map(([k, v]) => `${k}: ${v}`).join(' · ')
                  : 'No students',
              }))}
            />
            {d.departments.length > 1 && (
              <Table
                size="small"
                style={{ marginTop: 12 }}
                pagination={false}
                rowKey="code"
                dataSource={d.departments.map((code) => ({ code }))}
                columns={[
                  {
                    title: 'Dept',
                    dataIndex: 'code',
                    render: (v: string, _r, i) => <Tag color={DEPT_COLORS[i % DEPT_COLORS.length]}>{v}</Tag>,
                  },
                  ...d.cgpa_distribution.map((b) => ({
                    title: b.label,
                    key: b.label,
                    align: 'right' as const,
                    render: (_: unknown, r: { code: string }) => b.by_department[r.code] ?? 0,
                  })),
                ]}
              />
            )}
            {d.cgpa_not_graded > 0 && (
              <Typography.Text type="secondary" style={{ display: 'block', marginTop: 8 }}>
                {d.cgpa_not_graded} student{d.cgpa_not_graded > 1 ? 's have' : ' has'} no end-semester results yet.
              </Typography.Text>
            )}
          </Card>
        </Col>
      </Row>

      <Card
        title="Skill gaps"
        extra={<Typography.Text type="secondary">Against {d.skill_gap_source}</Typography.Text>}
      >
        <Typography.Paragraph type="secondary" style={{ marginTop: -4 }}>
          For each skill the drives ask for: how many current students already meet the highest level asked. Lowest coverage first.
        </Typography.Paragraph>
        <Table
          size="small"
          rowKey="skill_id"
          dataSource={d.skill_gaps}
          pagination={{ pageSize: 10, hideOnSinglePage: true }}
          scroll={{ x: 720 }}
          locale={{ emptyText: 'No drives with required skills yet' }}
          columns={[
            { title: 'Skill', dataIndex: 'name' },
            {
              title: 'Drives',
              dataIndex: 'roles',
              width: 110,
              render: (v: number, g) => (
                <Space size={4}>
                  {v}
                  {g.mandatory_in > 0 && <Tag color="red">{g.mandatory_in} mandatory</Tag>}
                </Space>
              ),
            },
            { title: 'Level asked', dataIndex: 'required_level', width: 100, align: 'center' },
            { title: 'Avg level (recorded)', dataIndex: 'avg_level', width: 150, align: 'center', render: (v: number, g) => (g.students_recorded ? v : '—') },
            {
              title: 'Students meeting it',
              width: 260,
              render: (_, g) => (
                <Space style={{ width: '100%' }}>
                  <Progress percent={g.coverage_percent} size="small" strokeColor={scaleColor(g.coverage_percent)} style={{ width: 140, margin: 0 }} />
                  <Typography.Text type="secondary" style={{ whiteSpace: 'nowrap' }}>
                    {g.students_meeting}/{g.students_base}
                  </Typography.Text>
                </Space>
              ),
            },
          ]}
        />
      </Card>

      <Row gutter={[16, 16]}>
        <Col xs={24} xl={12}>
          <Card title="Offers per month" style={{ height: '100%' }}>
            <Columns
              empty="No offers in the last 12 months"
              data={d.placement_by_month.map((m) => ({
                key: m.month,
                label: dayjs(m.month + '-01').format('MMM YY'),
                value: m.offers,
                tooltip: m.offers ? `${m.offers} offer${m.offers > 1 ? 's' : ''} · average ${m.average_package} LPA` : 'No offers',
              }))}
            />
          </Card>
        </Col>
        <Col xs={24} xl={12}>
          <Card title="Placement by batch" style={{ height: '100%' }}>
            <Table
              size="small"
              rowKey="batch"
              pagination={false}
              dataSource={[...d.placement_by_batch].reverse()}
              scroll={{ x: 480 }}
              columns={[
                { title: 'Batch', dataIndex: 'batch' },
                {
                  title: 'Placed',
                  width: 170,
                  render: (_, b) => (
                    <Space>
                      <Progress percent={b.placed_percent} size="small" style={{ width: 90, margin: 0 }} showInfo={false} />
                      <span style={{ whiteSpace: 'nowrap' }}>{b.placed}/{b.students}</span>
                    </Space>
                  ),
                },
                { title: 'Offers', dataIndex: 'offers', align: 'right', width: 70 },
                { title: 'Highest', dataIndex: 'highest_package', align: 'right', render: (v) => (v != null ? `${v} LPA` : '—') },
                { title: 'Median', dataIndex: 'median_package', align: 'right', render: (v) => (v != null ? `${v} LPA` : '—') },
              ]}
            />
          </Card>
        </Col>
      </Row>
    </Space>
  );
}
