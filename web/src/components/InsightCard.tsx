import dayjs from 'dayjs';
import { Alert, Button, Card, Skeleton, Tag, Typography } from 'antd';
import { ReloadOutlined } from '@ant-design/icons';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { api, errorMessage } from '../api/client';
import type { Envelope } from '../api/types';

interface Insight {
  summary: string;
  strengths: string[];
  focus_areas: string[];
  next_steps: string[];
  source: 'llm' | 'rules';
}

async function fetchInsight(studentId: number, refresh: boolean) {
  const r = await api.get<Envelope<{ insight: Insight; generated_at: string }>>(`/students/${studentId}/insight`, {
    params: refresh ? { refresh: true } : undefined,
    timeout: 120000,
  });
  return r.data.data;
}

function List({ title, items, color }: { title: string; items: string[]; color: string }) {
  if (!items.length) return null;
  return (
    <div style={{ marginTop: 12 }}>
      <Typography.Text strong style={{ color }}>{title}</Typography.Text>
      <ul style={{ margin: '4px 0 0', paddingLeft: 20 }}>
        {items.map((s) => (
          <li key={s}>{s}</li>
        ))}
      </ul>
    </div>
  );
}

/** A short plain-language reading of the student's record. The facts come from the database; a local model only words them. */
export default function InsightCard({ studentId }: { studentId: number }) {
  const qc = useQueryClient();
  const { data, isLoading, isFetching, error } = useQuery({
    queryKey: ['insight', studentId],
    queryFn: () => fetchInsight(studentId, false),
    staleTime: 60_000,
  });
  const refresh = async () => {
    const fresh = await fetchInsight(studentId, true);
    qc.setQueryData(['insight', studentId], fresh);
  };
  return (
    <Card
      title="Overall reading"
      style={{ marginTop: 16 }}
      extra={
        <Button size="small" icon={<ReloadOutlined />} loading={isFetching && !isLoading} onClick={refresh}>
          Refresh
        </Button>
      }
    >
      {isLoading ? (
        <Skeleton active paragraph={{ rows: 3 }} />
      ) : error || !data ? (
        <Alert type="error" showIcon title={errorMessage(error)} />
      ) : (
        <>
          <Typography.Paragraph style={{ marginBottom: 0 }}>{data.insight.summary}</Typography.Paragraph>
          <List title="Strengths" items={data.insight.strengths} color="#16a34a" />
          <List title="Needs attention" items={data.insight.focus_areas} color="#d97706" />
          <List title="Next steps" items={data.insight.next_steps} color="#2563eb" />
          <Typography.Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 12 }}>
            <Tag style={{ marginRight: 6 }}>{data.insight.source === 'llm' ? 'Worded by the local AI model' : 'Written from the record'}</Tag>
            Every figure comes from the student's record. Updated {dayjs(data.generated_at).format('DD MMM YYYY, HH:mm')}.
          </Typography.Text>
        </>
      )}
    </Card>
  );
}
