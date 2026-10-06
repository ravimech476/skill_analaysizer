import { RadarChartOutlined } from '@ant-design/icons';

/** Product mark: gradient tile + wordmark. Used in the sidebar and on the sign-in screens. */
export function Brand({ subtitle, size = 'default' }: { subtitle?: string; size?: 'default' | 'large' }) {
  const mark = size === 'large' ? { width: 44, height: 44, fontSize: 23, borderRadius: 13 } : undefined;
  return (
    <div className="sider-brand" style={{ height: 'auto', padding: 0 }}>
      <span className="brand-mark" style={mark}>
        <RadarChartOutlined />
      </span>
      <span>
        <div className="brand-name" style={size === 'large' ? { fontSize: 20 } : undefined}>
          Skills Analyzer
        </div>
        {subtitle && <div className="brand-sub">{subtitle}</div>}
      </span>
    </div>
  );
}
