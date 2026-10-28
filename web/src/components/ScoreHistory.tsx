import dayjs from 'dayjs';
import { Empty, Spin, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { api } from '../api/client';
import type { Envelope } from '../api/types';

export interface HistoryPoint {
  date: string;
  readiness: number;
  cgpa: number;
  aptitude: number | null;
  coding: number | null;
  communication: number | null;
  attendance: number | null;
  skill_count: number;
  risk_level: 'none' | 'medium' | 'high';
}

export const scoreHistoryApi = {
  get: (studentId: number, days = 365) =>
    api.get<Envelope<HistoryPoint[]>>(`/students/${studentId}/score-history`, { params: { days } }).then((r) => r.data.data),
};

const W = 520;
const H = 150;
const PAD = { l: 32, r: 10, t: 10, b: 22 };

/** Placement readiness over time, one point per daily snapshot. */
export default function ScoreHistory({ studentId }: { studentId: number }) {
  const { data, isLoading } = useQuery({ queryKey: ['score-history', studentId], queryFn: () => scoreHistoryApi.get(studentId) });
  if (isLoading) return <Spin size="small" />;
  if (!data || data.length < 2) {
    return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="History builds up as daily snapshots are taken" styles={{ image: { height: 36 } }} />;
  }
  const t0 = dayjs(data[0].date).valueOf();
  const t1 = dayjs(data[data.length - 1].date).valueOf();
  const x = (d: string) => PAD.l + ((dayjs(d).valueOf() - t0) / Math.max(t1 - t0, 1)) * (W - PAD.l - PAD.r);
  const y = (v: number) => PAD.t + (1 - v / 100) * (H - PAD.t - PAD.b);
  const path = data.map((p, i) => `${i ? 'L' : 'M'}${x(p.date).toFixed(1)},${y(p.readiness).toFixed(1)}`).join(' ');
  const first = data[0].readiness;
  const last = data[data.length - 1].readiness;
  const delta = Math.round((last - first) * 10) / 10;

  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ maxWidth: W }} role="img" aria-label="Placement readiness over time">
        {[0, 50, 100].map((v) => (
          <g key={v}>
            <line x1={PAD.l} x2={W - PAD.r} y1={y(v)} y2={y(v)} stroke="currentColor" opacity={0.12} />
            <text x={PAD.l - 6} y={y(v) + 4} fontSize="10" textAnchor="end" fill="currentColor" opacity={0.6}>{v}</text>
          </g>
        ))}
        <path d={path} fill="none" stroke="#2563eb" strokeWidth={2} />
        {data.map((p) => (
          <circle key={p.date} cx={x(p.date)} cy={y(p.readiness)} r={3} fill={p.risk_level === 'high' ? '#dc2626' : p.risk_level === 'medium' ? '#d97706' : '#2563eb'}>
            <title>{`${dayjs(p.date).format('DD MMM')}: ${p.readiness}`}</title>
          </circle>
        ))}
        <text x={PAD.l} y={H - 6} fontSize="10" fill="currentColor" opacity={0.6}>{dayjs(data[0].date).format('DD MMM')}</text>
        <text x={W - PAD.r} y={H - 6} fontSize="10" textAnchor="end" fill="currentColor" opacity={0.6}>{dayjs(data[data.length - 1].date).format('DD MMM')}</text>
      </svg>
      <Typography.Text type="secondary" style={{ fontSize: 12 }}>
        Readiness {first} to {last} ({delta >= 0 ? '+' : ''}{delta}) since {dayjs(data[0].date).format('DD MMM YYYY')}. Red and amber dots mark days the student was at risk.
      </Typography.Text>
    </div>
  );
}
