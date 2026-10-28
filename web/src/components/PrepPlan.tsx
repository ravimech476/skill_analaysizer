import { useState } from 'react';
import { Alert, Card, Col, InputNumber, List, Row, Select, Space, Spin, Tag, Timeline, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { careersApi, prepApi } from '../api/careers';
import { errorMessage } from '../api/client';

function Block({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Card size="small" title={title} style={{ height: '100%' }}>
      {children}
    </Card>
  );
}

/** A placement preparation plan for one student: skills to build, what to practise, projects, habits and a weekly schedule. */
export default function PrepPlan({ studentId }: { studentId: number }) {
  const [careerId, setCareerId] = useState<number>();
  const [hours, setHours] = useState(6);
  const matches = useQuery({ queryKey: ['career-matches', studentId], queryFn: () => careersApi.matches(studentId) });
  const { data, isLoading, error } = useQuery({
    queryKey: ['prep-plan', studentId, careerId, hours],
    queryFn: () => prepApi.plan(studentId, { career_id: careerId, hours }),
  });

  return (
    <Space direction="vertical" size="middle" style={{ width: '100%' }}>
      <Space wrap>
        <Typography.Text>Plan for</Typography.Text>
        <Select
          style={{ minWidth: 260 }}
          value={careerId ?? data?.career_id}
          onChange={setCareerId}
          loading={matches.isLoading}
          options={(matches.data?.matches ?? []).map((m) => ({ value: m.career_id, label: `#${m.rank} ${m.name}` }))}
        />
        <Typography.Text>with</Typography.Text>
        <InputNumber min={2} max={30} value={hours} onChange={(v) => setHours(v ?? 6)} style={{ width: 70 }} />
        <Typography.Text>study hours a week</Typography.Text>
      </Space>

      {isLoading ? (
        <Spin />
      ) : error || !data ? (
        <Alert type="error" showIcon title={errorMessage(error)} />
      ) : (
        <>
          {data.alternatives.length > 0 && (
            <Alert
              type="info"
              showIcon
              title={`Your interests point more towards ${data.alternatives.map((a) => a.career).join(' or ')}. You may want to plan for ${data.alternatives.length > 1 ? 'one of them' : 'it'} as well.`}
            />
          )}
          <Row gutter={[12, 12]}>
            <Col xs={24} lg={12}>
              <Block title="Skills to build">
                {data.skills.length === 0 ? (
                  <Typography.Text type="secondary">You meet every skill requirement for {data.career}.</Typography.Text>
                ) : (
                  <List
                    size="small"
                    dataSource={data.skills}
                    renderItem={(s) => (
                      <List.Item>
                        <div>
                          <Typography.Text strong>{s.skill}</Typography.Text> {s.is_core && <Tag color="red">core</Tag>}
                          <Typography.Text type="secondary"> level {s.level} of {s.needed} needed</Typography.Text>
                          <div>
                            {s.courses.length === 0 ? (
                              <Typography.Text type="secondary">No course in the catalogue yet</Typography.Text>
                            ) : (
                              s.courses.slice(0, 2).map((c) => (
                                <div key={c.id}>
                                  {c.url ? <a href={c.url} target="_blank" rel="noreferrer">{c.title}</a> : c.title}
                                  <Typography.Text type="secondary"> {c.provider ?? ''}{c.duration_hours ? `, ${c.duration_hours}h` : ''}</Typography.Text>
                                  {c.is_free && <Tag color="green" style={{ marginLeft: 6 }}>Free</Tag>}
                                </div>
                              ))
                            )}
                          </div>
                        </div>
                      </List.Item>
                    )}
                  />
                )}
              </Block>
            </Col>
            <Col xs={24} lg={12}>
              <Block title="Weekly schedule">
                {data.weeks.length === 0 ? (
                  <Typography.Text type="secondary">Nothing to schedule.</Typography.Text>
                ) : (
                  <>
                    <Timeline
                      items={data.weeks.map((w) => ({
                        children: (
                          <>
                            <Typography.Text strong>Week {w.number}</Typography.Text> <Typography.Text type="secondary">{w.hours}h</Typography.Text>
                            {w.study.map((x) => <div key={x}>{x}</div>)}
                          </>
                        ),
                      }))}
                    />
                    <Typography.Text type="secondary">
                      About {data.total_hours} hours of courses at {data.hours_per_week} hours a week.
                      {data.more_courses > 0 ? ` ${data.more_courses} more course(s) follow after these weeks.` : ''}
                    </Typography.Text>
                  </>
                )}
              </Block>
            </Col>
            <Col xs={24} lg={12}>
              <Block title="Practice">
                <Items items={data.practice} empty="Nothing urgent. Keep up your practice." />
              </Block>
            </Col>
            <Col xs={24} lg={12}>
              <Block title="Study habits">
                <Items items={data.habits} empty="Your study habits look strong." />
              </Block>
            </Col>
            <Col span={24}>
              <Block title="Projects to build">
                {data.projects.length === 0 ? (
                  <Typography.Text type="secondary">No project ideas for this career yet.</Typography.Text>
                ) : (
                  <List
                    size="small"
                    dataSource={data.projects}
                    renderItem={(p) => (
                      <List.Item>
                        <div>
                          <Typography.Text strong>{p.title}</Typography.Text> <Tag>{['Starter', 'Intermediate', 'Advanced'][p.level - 1]}</Tag>
                          <div><Typography.Text type="secondary">{p.description}</Typography.Text></div>
                        </div>
                      </List.Item>
                    )}
                  />
                )}
              </Block>
            </Col>
          </Row>
        </>
      )}
    </Space>
  );
}

function Items({ items, empty }: { items: { area: string; why: string; do: string }[]; empty: string }) {
  if (!items.length) return <Typography.Text type="secondary">{empty}</Typography.Text>;
  return (
    <List
      size="small"
      dataSource={items}
      renderItem={(a) => (
        <List.Item>
          <div>
            <Typography.Text strong>{a.area}</Typography.Text>
            <div><Typography.Text type="secondary">{a.why}</Typography.Text></div>
            <div>{a.do}</div>
          </div>
        </List.Item>
      )}
    />
  );
}
