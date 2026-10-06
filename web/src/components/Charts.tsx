import { Empty, Tooltip, Typography, theme } from 'antd';
import type { ReactNode } from 'react';
import { status } from '../theme';

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
