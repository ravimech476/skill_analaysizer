import { useState } from 'react';
import { Alert, Button, Card, Empty, Popconfirm, Space, Table, Tag, Typography, message } from 'antd';
import { CheckOutlined, CloseOutlined, ThunderboltOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { errorMessage } from '../api/client';
import { skillSuggestApi, type GenerateResult, type SkillSuggestion } from '../api/skillsuggest';

const levelColor = (n: number) => (n >= 4 ? 'success' : n >= 3 ? 'processing' : 'default');

/** Staff panel on a student's analysis: skill levels the marks support, to accept or dismiss one by one. */
export default function SkillSuggestions({ studentId }: { studentId: number }) {
  const qc = useQueryClient();
  const [note, setNote] = useState<Pick<GenerateResult, 'summary' | 'unmapped_subjects'> | null>(null);
  const key = ['skill-suggestions', studentId];
  const { data, isLoading } = useQuery({ queryKey: key, queryFn: () => skillSuggestApi.pending(studentId) });

  const generate = useMutation({
    mutationFn: () => skillSuggestApi.generate(studentId),
    onSuccess: (r) => {
      qc.setQueryData(key, r.suggestions);
      setNote({ summary: r.summary, unmapped_subjects: r.unmapped_subjects });
    },
    onError: (e) => message.error(errorMessage(e)),
  });

  // An accepted skill changes the student's skills, scores and analysis, so refresh everything that shows them.
  const accept = useMutation({
    mutationFn: (s: SkillSuggestion) => skillSuggestApi.accept(s.id),
    onSuccess: () => {
      message.success('Skill recorded');
      qc.invalidateQueries({ queryKey: key });
      qc.invalidateQueries({ queryKey: ['skill-scores'] });
      qc.invalidateQueries({ queryKey: ['analyzer'] });
      qc.invalidateQueries({ queryKey: ['student-skills'] });
    },
    onError: (e) => message.error(errorMessage(e)),
  });
  const dismiss = useMutation({
    mutationFn: (s: SkillSuggestion) => skillSuggestApi.dismiss(s.id),
    onSuccess: () => qc.invalidateQueries({ queryKey: key }),
    onError: (e) => message.error(errorMessage(e)),
  });
  const busy = accept.isPending || dismiss.isPending;

  return (
    <Card
      title="Skills noticed from marks"
      extra={
        <Button icon={<ThunderboltOutlined />} loading={generate.isPending} onClick={() => generate.mutate()}>
          Check marks
        </Button>
      }
    >
      <Typography.Paragraph type="secondary">
        Levels are worked out from the student&rsquo;s marks in the subjects that build each skill. Nothing is recorded until you accept it, and a level that is already higher is never lowered.
      </Typography.Paragraph>
      {note?.summary && <Alert type="info" showIcon style={{ marginBottom: 12 }} title={note.summary} />}
      {note && note.unmapped_subjects.length > 0 && (
        <Alert
          type="warning"
          showIcon
          style={{ marginBottom: 12 }}
          title={`No skill mapping for: ${note.unmapped_subjects.join(', ')}`}
          description="Marks in these subjects cannot produce suggestions. Map them under Skill Analysis Config."
        />
      )}
      <Table<SkillSuggestion>
        rowKey="id"
        size="small"
        loading={isLoading}
        dataSource={data ?? []}
        pagination={false}
        locale={{ emptyText: <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={note ? 'No new skill levels are supported by the marks.' : 'Press “Check marks” to look for skills the marks support.'} /> }}
        columns={[
          { title: 'Skill', dataIndex: 'skill', width: 200, render: (v: string) => <b>{v}</b> },
          {
            title: 'Level',
            width: 150,
            render: (_, s) => (
              <Space size={4}>
                {s.current_level ? <Tag>{s.current_level}</Tag> : <Typography.Text type="secondary">none</Typography.Text>}
                <span>→</span>
                <Tag color={levelColor(s.suggested_level)}>{s.suggested_level}</Tag>
              </Space>
            ),
          },
          {
            title: 'Why',
            render: (_, s) => (
              <div style={{ fontSize: 13 }}>
                <b>{s.percent}%</b> across{' '}
                {s.evidence.map((e, i) => (
                  <span key={e.subject_id}>
                    {i > 0 && ', '}
                    {e.subject} ({e.percent}%{e.weight !== 1 ? `, weight ${e.weight}` : ''})
                  </span>
                ))}
              </div>
            ),
          },
          {
            title: '',
            width: 170,
            align: 'right',
            render: (_, s) => (
              <Space>
                <Button size="small" type="primary" icon={<CheckOutlined />} disabled={busy} onClick={() => accept.mutate(s)}>
                  Accept
                </Button>
                <Popconfirm title="Dismiss this suggestion?" description="It will not be suggested again unless the marks support a higher level." okText="Dismiss" onConfirm={() => dismiss.mutate(s)}>
                  <Button size="small" icon={<CloseOutlined />} disabled={busy} aria-label={`Dismiss ${s.skill}`} />
                </Popconfirm>
              </Space>
            ),
          },
        ]}
      />
    </Card>
  );
}
