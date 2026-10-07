import { Empty, Tooltip, Typography, theme } from 'antd';
import type { ReactNode } from 'react';
import { series, status } from '../theme';

/**
 * Categorical chart palette — starts from the theme `series` array and extends
 * it with two extra hues so eight categories can be shown without cycling.
 */
export const CHART_COLORS: readonly string[] = [
  ...series,
  '#0284c7', // sky-600
  '#c2410c', // orange-700
];

// Small dependency-free charts for the reports dashboard.


export interface BarDatum {
  key: string | number;
  label: ReactNode;
  value: number;
  /** Text shown at the end of the bar (defaults to the value). */
  display?: ReactNode;
  tooltip?: ReactNode;
  color?: string;
}

/** Horizontal bars, one per row, scaled to `max` (default: the largest value). */
export function HBars({ data, max, labelWidth = 110, empty = 'No data' }: { data: BarDatum[]; max?: number; labelWidth?: number; empty?: string }) {
  const { token } = theme.useToken();
  if (!data.length) return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={empty} />;
  const top = max ?? Math.max(...data.map((d) => d.value), 1);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {data.map((d) => (
        <Tooltip key={d.key} title={d.tooltip} placement="topLeft">
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
            <div style={{ width: labelWidth, flex: 'none', fontSize: 13, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{d.label}</div>
            <div style={{ flex: 1, background: token.colorFillSecondary, borderRadius: 4, height: 18, minWidth: 40 }}>
              <div
                style={{
                  width: `${Math.max((d.value / top) * 100, d.value > 0 ? 1.5 : 0)}%`,
                  height: '100%',
                  borderRadius: 4,
                  background: d.color ?? token.colorPrimary,
                  transition: 'width .3s',
                }}
              />
            </div>
            <div style={{ width: 64, flex: 'none', textAlign: 'right', fontVariantNumeric: 'tabular-nums', fontSize: 13 }}>{d.display ?? d.value}</div>
          </div>
        </Tooltip>
      ))}
    </div>
  );
}

/** Vertical columns with labels underneath. */
export function Columns({ data, height = 160, empty = 'No data' }: { data: BarDatum[]; height?: number; empty?: string }) {
  const { token } = theme.useToken();
  if (!data.length || data.every((d) => d.value === 0)) return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={empty} />;
  const top = Math.max(...data.map((d) => d.value), 1);
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 6, height: height + 40, overflowX: 'auto' }}>
      {data.map((d) => (
        <Tooltip key={d.key} title={d.tooltip}>
          <div style={{ flex: '1 0 28px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
            <Typography.Text style={{ fontSize: 12, fontVariantNumeric: 'tabular-nums' }}>{d.value > 0 ? (d.display ?? d.value) : ''}</Typography.Text>
            <div
              style={{
                width: '70%',
                maxWidth: 44,
                height: Math.max((d.value / top) * height, d.value > 0 ? 3 : 1),
                background: d.value > 0 ? (d.color ?? token.colorPrimary) : token.colorBorderSecondary,
                borderRadius: '4px 4px 0 0',
              }}
            />
            <Typography.Text type="secondary" style={{ fontSize: 11, whiteSpace: 'nowrap' }}>{d.label}</Typography.Text>
          </div>
        </Tooltip>
      ))}
    </div>
  );
}

/** Pass/coverage colour scale: red below 50, amber below 75, green above. Always paired
 * with the number itself, so the colour is never the only thing carrying the meaning. */
export function scaleColor(pct: number) {
  if (pct < 50) return status.critical;
  if (pct < 75) return status.warning;
  return status.good;
}

/* ── Donut / pie chart ──────────────────────────────────────────────── */

export interface DonutSegment {
  key: string;
  label: string;
  value: number;
  color: string;
}

/** Simple SVG donut chart with an optional center label. */
export function DonutChart({
  data,
  size = 180,
  label,
  sublabel,
}: {
  data: DonutSegment[];
  size?: number;
  label?: ReactNode;
  sublabel?: ReactNode;
}) {
  if (!data.length || data.every((d) => d.value === 0))
    return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="No data" />;

  const total = data.reduce((s, d) => s + d.value, 0);
  const r = size / 2 - 10;
  const cx = size / 2;
  const cy = size / 2;
  const circumference = 2 * Math.PI * r;
  let offset = -circumference / 4; // start at 12 o'clock

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        {data.map((d) => {
          const pct = total > 0 ? d.value / total : 0;
          const dash = pct * circumference;
          const currentOffset = offset;
          offset += dash;
          return (
            <circle
              key={d.key}
              cx={cx}
              cy={cy}
              r={r}
              fill="none"
              stroke={d.color}
              strokeWidth={28}
              strokeDasharray={`${dash} ${circumference - dash}`}
              strokeDashoffset={-currentOffset}
              style={{ transition: 'stroke-dasharray 0.5s' }}
            />
          );
        })}
        {label != null && (
          <>
            <text x={cx} y={cy - 6} textAnchor="middle" fontSize="22" fontWeight="600" fill="currentColor">
              {label}
            </text>
            {sublabel && (
              <text x={cx} y={cy + 14} textAnchor="middle" fontSize="12" fill="#888">
                {sublabel}
              </text>
            )}
          </>
        )}
      </svg>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px 16px', justifyContent: 'center' }}>
        {data.map((d) => (
          <div key={d.key} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 12 }}>
            <span style={{ width: 10, height: 10, borderRadius: '50%', background: d.color, flexShrink: 0 }} />
            {d.label}: {d.value}
          </div>
        ))}
      </div>
    </div>
  );
}
