import { useEffect, useState } from 'react';
import { Alert, Button, Col, Empty, Input, InputNumber, Modal, Popover, Progress, Row, Segmented, Select, Space, Spin, Table, Tag, Tooltip, Typography, message } from 'antd';
import { PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { SOURCE_LABELS, scoresApi, type ScoreSource, type SkillScore, type SubjectMapping } from '../api/careers';
import { placementApi } from '../api/placement';
import { useAuth } from '../auth/AuthContext';

/** The blended score as a number plus a popover saying where it came from. */
export function ScoreBadge({ row }: { row: SkillScore | undefined }) {
  if (!row) return <Typography.Text type="secondary">—</Typography.Text>;
  const colour = row.score >= 80 ? 'var(--success)' : row.score >= 50 ? 'var(--accent)' : 'var(--warning)';
  return (
    <Popover
      title={`${row.name}: ${row.score} of 100`}
      content={
        <div style={{ maxWidth: 320 }}>
          {row.breakdown.map((p) => (
            <Row key={p.source} gutter={8} align="middle" style={{ marginBottom: 4 }}>
              <Col flex="130px">
                <Typography.Text>{SOURCE_LABELS[p.source]}</Typography.Text>
              </Col>
              <Col flex="auto">
                <Progress percent={p.score} size="small" showInfo={false} />
              </Col>
              <Col flex="86px" style={{ textAlign: 'right' }}>
                <Typography.Text type="secondary">
                  {p.score} × {p.weight}
                </Typography.Text>
              </Col>
            </Row>
          ))}
          {!row.breakdown.length && <Typography.Text type="secondary">No evidence recorded yet.</Typography.Text>}
          <Typography.Paragraph type="secondary" style={{ marginTop: 8, marginBottom: 0, fontSize: 12 }}>
            The score is the weighted average of the sources that have data; a source with nothing recorded is left out
            rather than counted as zero.
          </Typography.Paragraph>
        </div>
      }
    >
      <Typography.Text strong style={{ color: colour, cursor: 'help' }}>
        {row.score}
      </Typography.Text>
    </Popover>
  );
}

/** A student's blended scores, used on the skills screen and the student drawer. */
export function useSkillScores(studentId: number) {
  return useQuery({ queryKey: ['skill-scores', studentId], queryFn: () => scoresApi.of(studentId) });
}

/** Which skills each subject teaches — the link that makes marks move skill scores. */
export function SubjectSkillMapping() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<'all' | 'true' | 'false'>('all');
  const [editing, setEditing] = useState<{ row: SubjectMapping; skills: { skill_id: number; weight: number }[] } | null>(null);
  const { data, isLoading } = useQuery({
    queryKey: ['subject-skills', search, filter],
    queryFn: () => scoresApi.subjectMappings({ search, mapped: filter === 'all' ? undefined : filter }),
  });
  const { data: skills } = useQuery({ queryKey: ['lookup', 'skills'], queryFn: placementApi.skills, staleTime: 5 * 60_000 });
  const canEdit = can('subject.update');

  const save = useMutation({
    mutationFn: () => scoresApi.setSubjectSkills(editing!.row.subject_id, editing!.skills.filter((s) => s.skill_id)),
    onSuccess: () => {
      message.success('Mapping saved — scores for students with marks in this subject were recomputed');
      qc.invalidateQueries({ queryKey: ['subject-skills'] });
      qc.invalidateQueries({ queryKey: ['skill-scores'] });
      setEditing(null);
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  return (
    <>
      <Alert
        type="info"
        showIcon
        style={{ marginBottom: 16 }}
        title="Marks only count towards a skill once the subject is mapped to it"
        description="Map a subject to the skills it teaches and every student's score for those skills starts taking their marks in that subject into account. Weight decides how much the subject counts when several subjects feed one skill."
      />
      <Space wrap style={{ width: '100%', justifyContent: 'space-between', marginBottom: 12 }}>
        <Space wrap>
          <Input.Search allowClear placeholder="Search subjects" style={{ width: 240 }} onSearch={setSearch} />
          <Segmented
            value={filter}
            onChange={(v) => setFilter(v as 'all' | 'true' | 'false')}
            options={[
              { value: 'all', label: 'All' },
              { value: 'true', label: 'Mapped' },
              { value: 'false', label: 'Not mapped' },
            ]}
          />
        </Space>
        {data && (
          <Typography.Text type="secondary">
            {data.mapped} of {data.total} subjects mapped
          </Typography.Text>
        )}
      </Space>
      <Table<SubjectMapping>
        rowKey="subject_id"
        size="small"
        loading={isLoading}
        dataSource={data?.subjects}
        pagination={{ pageSize: 20, hideOnSinglePage: true }}
        scroll={{ x: 760 }}
        columns={[
          {
            title: 'Subject',
            width: 260,
            render: (_, s) => (
              <div>
                <b>{s.subject_code}</b>
                <br />
                <Typography.Text type="secondary">{s.subject_name}</Typography.Text>
              </div>
            ),
          },
          {
            title: 'Skills it teaches',
            render: (_, s) =>
              s.skills.length ? (
                <Space size={[4, 4]} wrap>
                  {s.skills.map((k) => (
                    <Tag key={k.skill_id}>
                      {k.name}
                      {k.weight !== 1 ? ` × ${k.weight}` : ''}
                    </Tag>
                  ))}
                </Space>
              ) : (
                <Typography.Text type="secondary">Not mapped — its marks do not count towards any skill</Typography.Text>
              ),
          },
          ...(canEdit
            ? [
                {
                  title: '',
                  key: 'x',
                  width: 90,
                  align: 'right' as const,
                  render: (_: unknown, s: SubjectMapping) => (
                    <Button size="small" onClick={() => setEditing({ row: s, skills: s.skills.map((k) => ({ skill_id: k.skill_id, weight: k.weight })) })}>
                      {s.skills.length ? 'Edit' : 'Map'}
                    </Button>
                  ),
                },
              ]
            : []),
        ]}
      />

      {editing && (
        <Modal
          open
          title={`${editing.row.subject_code} · ${editing.row.subject_name}`}
          onCancel={() => setEditing(null)}
          onOk={() => save.mutate()}
          okText="Save mapping"
          okButtonProps={{ loading: save.isPending }}
        >
          <Typography.Paragraph type="secondary">
            Marks in this subject will count towards each skill below, weighted as shown.
          </Typography.Paragraph>
          {editing.skills.map((s, i) => (
            <Row key={i} gutter={8} align="middle" style={{ marginBottom: 8 }}>
              <Col flex="auto">
                <Select
                  showSearch
                  optionFilterProp="label"
                  style={{ width: '100%' }}
                  placeholder="Skill"
                  value={s.skill_id || undefined}
                  onChange={(v) => setEditing({ ...editing, skills: editing.skills.map((x, j) => (j === i ? { ...x, skill_id: v } : x)) })}
                  options={(skills ?? []).map((k) => ({ value: k.id, label: k.name }))}
                />
              </Col>
              <Col flex="130px">
                <Tooltip title="How much this subject counts towards the skill">
                  <InputNumber
                    min={0.1}
                    max={10}
                    step={0.5}
                    style={{ width: '100%' }}
                    prefix="weight"
                    value={s.weight}
                    onChange={(v) => setEditing({ ...editing, skills: editing.skills.map((x, j) => (j === i ? { ...x, weight: v ?? 1 } : x)) })}
                  />
                </Tooltip>
              </Col>
              <Col flex="40px">
                <Button size="small" danger onClick={() => setEditing({ ...editing, skills: editing.skills.filter((_, j) => j !== i) })}>
                  ✕
                </Button>
              </Col>
            </Row>
          ))}
          <Button size="small" icon={<PlusOutlined />} onClick={() => setEditing({ ...editing, skills: [...editing.skills, { skill_id: 0, weight: 1 }] })}>
            Add a skill
          </Button>
        </Modal>
      )}
    </>
  );
}

/** Admin screen for the weights behind every blended score and match score. */
export function ScoringWeights() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['scoring'], queryFn: scoresApi.scoring });
  const [blend, setBlend] = useState<Record<string, number>>({});
  const [match, setMatch] = useState<Record<string, number>>({});
  const canEdit = can('config.update');

  useEffect(() => {
    if (!data) return;
    const by = Object.fromEntries(data.settings.map((s) => [s.key, s.value]));
    setBlend({ ...by.skill_score_weights });
    setMatch({ ...by.match_weights });
  }, [data]);

  const save = useMutation({
    mutationFn: () => scoresApi.saveScoring({ skill_score_weights: blend, match_weights: match }),
    onSuccess: (d) => {
      qc.setQueryData(['scoring'], d);
      qc.invalidateQueries({ queryKey: ['skill-scores'] });
      message.success('Weights saved. Every student’s scores are being recomputed in the background.');
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  if (isLoading) return <Spin />;
  if (!data) return <Empty />;
  const blendTotal = Object.values(blend).reduce((a, b) => a + b, 0);
  const matchTotal = Object.values(match).reduce((a, b) => a + b, 0);

  return (
    <Space orientation="vertical" size="large" style={{ width: '100%', maxWidth: 680 }}>
      <Alert
        type="info"
        showIcon
        title="These weights decide every score in the app"
        description="A skill score blends the four sources below. Sources with nothing recorded for a student are left out and the rest are scaled back up, so the weights are a ratio rather than a budget."
      />
      <div>
        <Typography.Title level={5}>What a skill score is made of</Typography.Title>
        {data.skill_sources.map((s: ScoreSource) => (
          <Row key={s} gutter={12} align="middle" style={{ marginBottom: 8 }}>
            <Col flex="170px">
              <Typography.Text>{SOURCE_LABELS[s]}</Typography.Text>
            </Col>
            <Col flex="120px">
              <InputNumber
                min={0}
                max={1}
                step={0.05}
                style={{ width: '100%' }}
                disabled={!canEdit}
                value={blend[s] ?? 0}
                onChange={(v) => setBlend({ ...blend, [s]: v ?? 0 })}
              />
            </Col>
            <Col flex="auto">
              <Progress percent={blendTotal ? Math.round(((blend[s] ?? 0) / blendTotal) * 100) : 0} size="small" />
            </Col>
          </Row>
        ))}
        <Typography.Text type={blendTotal > 0 ? 'secondary' : 'danger'}>
          {blendTotal > 0 ? `Adds up to ${blendTotal.toFixed(2)}` : 'At least one weight must be above zero'}
        </Typography.Text>
      </div>
      <div>
        <Typography.Title level={5}>What a match score is made of</Typography.Title>
        <Typography.Paragraph type="secondary">
          Used for both placement drives and career matches: how much the skill match counts against the academic
          record.
        </Typography.Paragraph>
        {(['skill', 'academic'] as const).map((k) => (
          <Row key={k} gutter={12} align="middle" style={{ marginBottom: 8 }}>
            <Col flex="170px">
              <Typography.Text>{k === 'skill' ? 'Skill match' : 'Academic record (CGPA)'}</Typography.Text>
            </Col>
            <Col flex="120px">
              <InputNumber
                min={0}
                max={1}
                step={0.05}
                style={{ width: '100%' }}
                disabled={!canEdit}
                value={match[k] ?? 0}
                onChange={(v) => setMatch({ ...match, [k]: v ?? 0 })}
              />
            </Col>
            <Col flex="auto">
              <Progress percent={matchTotal ? Math.round(((match[k] ?? 0) / matchTotal) * 100) : 0} size="small" />
            </Col>
          </Row>
        ))}
      </div>
      {canEdit && (
        <Space>
          <Button type="primary" loading={save.isPending} disabled={blendTotal <= 0 || matchTotal <= 0} onClick={() => save.mutate()}>
            Save weights
          </Button>
          <Tooltip title="Recompute every student's scores now, without changing the weights">
            <Button
              onClick={() =>
                scoresApi
                  .recompute({ all: true })
                  .then((r) => message.success(r.message))
                  .catch((e) => message.error(errorMessage(e)))
              }
            >
              Recompute all scores
            </Button>
          </Tooltip>
        </Space>
      )}
      <Typography.Text type="secondary">
        Last changed{' '}
        {data.settings
          .map((s) => `${s.key.replace(/_/g, ' ')} by ${s.updated_by ?? 'the system'}`)
          .join(' · ')}
      </Typography.Text>
    </Space>
  );
}
