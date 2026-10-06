import type { ReactNode } from 'react';
import { BarChartOutlined, SafetyCertificateOutlined, TrophyOutlined } from '@ant-design/icons';
import { Brand } from './Brand';

const POINTS = [
  { icon: <BarChartOutlined />, text: 'Marks, CGPA and attendance of every semester in one place' },
  { icon: <TrophyOutlined />, text: 'Placement drives matched to each student by skills and results' },
  { icon: <SafetyCertificateOutlined />, text: 'One login for students, parents, staff and administrators' },
];

/** Two-panel sign-in layout: brand story on the left, the form on the right. */
export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <div className="auth-split">
      <aside className="auth-aside">
        <Brand subtitle="Campus placements" size="large" />
        <div>
          <h2 className="auth-headline">
            From first semester
            <br />
            to first offer.
          </h2>
          <p className="auth-lede">
            The college platform that keeps academics, skills and placements together, so every student knows exactly where they
            stand and what to work on next.
          </p>
          <ul className="auth-points">
            {POINTS.map((p) => (
              <li key={p.text}>
                <span className="dot">{p.icon}</span>
                <span>{p.text}</span>
              </li>
            ))}
          </ul>
        </div>
        <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.75)' }}>Need help signing in? Ask your class incharge or the placement office.</div>
      </aside>
      <main className="auth-main">
        <div className="auth-card">
          <div className="auth-mobile-brand">
            <Brand />
          </div>
          {children}
        </div>
      </main>
    </div>
  );
}
