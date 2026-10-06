import { useEffect, useState } from 'react';
import { Alert, Button, Card, Col, Empty, Row, Select, Space, Statistic, Switch, Table, Tag, Tooltip, Typography, message } from 'antd';
import { DownloadOutlined, ThunderboltOutlined, UsergroupAddOutlined } from '@ant-design/icons';
import { exportsApi } from '../api/reports';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { useSearchParams } from 'react-router-dom';
import { errorMessage } from '../api/client';
import { lpa, placementApi, pretty, STATUS_COLORS, type Match, type Ranking } from '../api/placement';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { OpportunitiesView, RoleSkillsTags, StudentPicker } from './PlacementPage';

function Ranker() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const [params, setParams] = useSearchParams();
  const roleId = params.get('role') ? Number(params.get('role')) : undefined;
  const [eligibleOnly, setEligibleOnly] = useState(false);
  const [selected, setSelected] = useState<number[]>([]);
  const [ranking, setRanking] = useState<Ranking | null>(null);

  const { data: roles } = useQuery({ queryKey: ['job-roles', 'analyzer'], queryFn: () => placementApi.roles({}) });
  const role = roles?.find((r) => r.id === roleId);
  const cached = useQuery({ queryKey: ['ranking', roleId], queryFn: () => placementApi.matches(roleId!), enabled: !!roleId });

  useEffect(() => {
    setRanking(cached.data ?? null);
    setSelected([]);
  }, [cached.data]);

  const run = useMutation({
    mutationFn: () => placementApi.analyze(roleId!),
    onSuccess: (r) => {
      setRanking(r);
      setSelected([]);
      qc.setQueryData(['ranking', roleId], r);
      qc.invalidateQueries({ queryKey: ['job-roles'] });
      message.success(`Ranked ${r.total} students · ${r.eligible} eligible`);
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const shortlist = useMutation({
    mutationFn: () => placementApi.shortlist(roleId!, selected),
    onSuccess: (r) => {
      if (r.skipped.length) message.warning(`Shortlisted ${r.added}; skipped ${r.skipped.length}: ${r.skipped.map((s) => `${s.name}: ${s.reason}`).join('; ')}`, 8);
      else message.success(`Shortlisted ${r.added} student(s)`);
      qc.invalidateQueries({ queryKey: ['ranking', roleId] });
      qc.invalidateQueries({ queryKey: ['job-roles'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  const rows = (ranking?.matches ?? []).filter((m) => !eligibleOnly || m.is_eligible);
  const canShortlist = can('placement.create') && role && (role.status === 'open' || role.status === 'upcoming');

  return (
    <Space orientation="vertical" size="middle" style={{ width: '100%' }}>
      <Select
        showSearch
        optionFilterProp="label"
        style={{ width: '100%', maxWidth: 520 }}
        placeholder="Pick a job role / drive"
        value={roleId}
        onChange={(v) => setParams({ role: String(v) })}
        options={(roles ?? []).map((r) => ({ value: r.id, label: `${r.company_name} · ${r.title} · ${lpa(r.package_lpa)} (${pretty(r.status)})` }))}
      />
      {!role ? (
        <Empty description="Pick a job role to rank students against its required skills and eligibility" />
      ) : (
        <>
          <Card size="small">
            <Row gutter={[16, 12]} align="middle">
              <Col xs={24} md={14}>
                <Typography.Text strong>{role.title}</Typography.Text> <Typography.Text type="secondary">· {role.company_name} · {lpa(role.package_lpa)}</Typography.Text>
                <div style={{ margin: '6px 0' }}><RoleSkillsTags role={role} /></div>
                <Typography.Text type="secondary">
                  CGPA ≥ {role.min_cgpa} · ≤ {role.max_backlogs} backlogs · {role.eligible_batch ?? 'any batch'} · {role.departments.length ? role.departments.map((d) => d.code).join(', ') : 'all departments'}
                </Typography.Text>
              </Col>
              <Col xs={24} md={10} style={{ textAlign: 'right' }}>
                <Space wrap style={{ justifyContent: 'flex-end' }}>
                  {ranking?.analyzed_at && <Typography.Text type="secondary">Last run {dayjs(ranking.analyzed_at).format('DD MMM, HH:mm')}</Typography.Text>}
                  {ranking?.analyzed_at && (
                    <Button icon={<DownloadOutlined />} onClick={() => exportsApi.ranking(roleId!, eligibleOnly)}>
                      Ranking (.xlsx)
                    </Button>
                  )}
                  {can('skill_analyzer.create') && (
                    <Button type="primary" icon={<ThunderboltOutlined />} loading={run.isPending} onClick={() => run.mutate()}>
                      {ranking?.analyzed_at ? 'Re-run analyzer' : 'Run analyzer'}
                    </Button>
                  )}
                </Space>
              </Col>
            </Row>
          </Card>
          <Alert
            type="info"
            showIcon
            title="How the score works"
            description="Skill match = weighted share of each required skill the student has, measured on their blended skill score — what staff recorded plus verified certificates, assessments and marks in mapped subjects. Academic = CGPA × 10. The split between the two is set under Student Skills → Scoring weights. Students must also pass department, batch, CGPA, backlog and mandatory-skill checks; students already placed are only eligible for higher packages."
          />
          {!!ranking?.stale && (
            <Alert
              type="warning"
              showIcon
              title={`${ranking.stale} student${ranking.stale === 1 ? "'s" : "s'"} skills have changed since this ranking was run`}
              description="Re-run the analyzer so the shortlist reflects the latest skills, certificates and marks."
              action={
                can('skill_analyzer.create') && (
                  <Button size="small" loading={run.isPending} onClick={() => run.mutate()}>
                    Re-run
                  </Button>
                )
              }
            />
          )}
          {!ranking?.analyzed_at ? (
            <Empty description={cached.isLoading ? 'Loading…' : 'Not analysed yet. Run the analyzer to rank students.'} />
          ) : (
            <>
              <Row gutter={16}>
                <Col xs={8}><Statistic title="Ranked" value={ranking.total} /></Col>
                <Col xs={8}><Statistic title="Eligible" value={ranking.eligible} styles={{ content: { color: '#16a34a' } }} /></Col>
                <Col xs={8}><Statistic title="Selected to shortlist" value={selected.length} /></Col>
              </Row>
              <Space wrap style={{ justifyContent: 'space-between', width: '100%' }}>
                <Space>
                  <Switch checked={eligibleOnly} onChange={setEligibleOnly} /> Eligible only
                </Space>
                {canShortlist && (
                  <Button type="primary" icon={<UsergroupAddOutlined />} disabled={!selected.length} loading={shortlist.isPending} onClick={() => shortlist.mutate()}>
                    Shortlist selected ({selected.length})
                  </Button>
                )}
              </Space>
              <Table<Match>
                rowKey="student_id"
                size="small"
                dataSource={rows}
                pagination={{ pageSize: 50, hideOnSinglePage: true }}
                scroll={{ x: 1000 }}
                rowSelection={
                  canShortlist
                    ? {
                        selectedRowKeys: selected,
                        onChange: (keys) => setSelected(keys as number[]),
                        getCheckboxProps: (m) => ({ disabled: !m.is_eligible || !!m.application_status }),
                      }
                    : undefined
                }
                columns={[
                  { title: '#', width: 50, render: (_, __, i) => i + 1 },
                  {
                    title: 'Student',
                    render: (_, m) => (
                      <div>
                        <b>{m.name}</b>
                        {m.is_stale && (
                          <Tooltip title="This student's skills changed after the ranking was run">
                            <Tag color="orange" style={{ marginLeft: 6 }}>stale</Tag>
                          </Tooltip>
                        )}
                        <br />
                        <Typography.Text type="secondary">{m.register_no} · {m.class_label ?? m.department_code}</Typography.Text>
                      </div>
                    ),
                  },
                  { title: 'CGPA', dataIndex: 'cgpa', width: 70, render: (v, m) => <span>{v}{m.backlog_count ? <Tag color="red" style={{ marginLeft: 4 }}>{m.backlog_count} BL</Tag> : null}</span> },
                  { title: 'Skill match', dataIndex: 'skill_score', width: 100, render: (v) => `${v}%` },
                  { title: 'Score', dataIndex: 'final_score', width: 80, render: (v) => <b>{v}</b> },
                  {
                    title: 'Eligibility',
                    width: 130,
                    render: (_, m) =>
                      m.is_eligible ? (
                        <Tag color="green">Eligible</Tag>
                      ) : (
                        <Tooltip title={<ul style={{ margin: 0, paddingLeft: 16 }}>{m.ineligible_reasons.map((r) => <li key={r}>{r}</li>)}</ul>}>
                          <Tag color="red">Not eligible ({m.ineligible_reasons.length})</Tag>
                        </Tooltip>
                      ),
                  },
                  {
                    title: 'Missing skills',
                    render: (_, m) =>
                      m.missing_skills.length ? (
                        <Space size={[4, 4]} wrap>
                          {m.missing_skills.map((g) => (
                            <Tooltip key={g.skill_id} title={`Blended score ${g.student_score} of the ${g.required_score} needed`}>
                              <Tag color={g.is_mandatory ? 'red' : 'orange'}>{g.name} {g.student_level}/{g.required_level}</Tag>
                            </Tooltip>
                          ))}
                        </Space>
                      ) : (
                        <Typography.Text type="success">None</Typography.Text>
                      ),
                  },
                  { title: 'Status', dataIndex: 'application_status', width: 110, render: (v) => (v ? <Tag color={STATUS_COLORS[v]}>{pretty(v)}</Tag> : '') },
                ]}
              />
            </>
          )}
        </>
      )}
    </Space>
  );
}

export default function AnalyzerPage() {
  const { user } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  if (audience === 'student' || audience === 'parent') {
    return (
      <Card>
        <Typography.Paragraph type="secondary">How your skills compare with what each company needs. Improve the red ones to become eligible.</Typography.Paragraph>
        <StudentPicker parent={audience === 'parent'}>{(id) => <OpportunitiesView studentId={id} mode="gap" />}</StudentPicker>
      </Card>
    );
  }
  return (
    <Card>
      <Ranker />
    </Card>
  );
}
