import { Card, Col, Row, Space, Tag, Typography } from 'antd';
import {
  ApartmentOutlined,
  ArrowRightOutlined,
  BankOutlined,
  BarChartOutlined,
  BellOutlined,
  BookOutlined,
  CalendarOutlined,
  CloudUploadOutlined,
  CompassOutlined,
  FolderOpenOutlined,
  IdcardOutlined,
  PieChartOutlined,
  SafetyOutlined,
  SendOutlined,
  SolutionOutlined,
  StarOutlined,
  TeamOutlined,
  TrophyOutlined,
} from '@ant-design/icons';
import { useQueries, useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import dayjs from 'dayjs';
import { usersApi } from '../api/endpoints';
import { studentsApi } from '../api/phase2';
import { placementApi } from '../api/placement';
import { useAuth } from '../auth/AuthContext';
import { audienceOf, visibleFeatures } from '../auth/access';
import { moduleColor } from '../auth/moduleColors';

const COUNT_ROLES = [
  { slug: 'student', label: 'Students', icon: <SolutionOutlined /> },
  { slug: 'staff', label: 'Staff', icon: <IdcardOutlined /> },
  { slug: 'parent', label: 'Parents', icon: <TeamOutlined /> },
  { slug: 'admin', label: 'Admins', icon: <SafetyOutlined /> },
];

const TILE_ICONS: Record<string, React.ReactNode> = {
  users: <TeamOutlined />,
  roles: <SafetyOutlined />,
  academic: <BankOutlined />,
  classes: <ApartmentOutlined />,
  staff: <IdcardOutlined />,
  students: <SolutionOutlined />,
  marks: <BookOutlined />,
  skills: <StarOutlined />,
  careers: <CompassOutlined />,
  placement: <TrophyOutlined />,
  analyzer: <BarChartOutlined />,
  bulk: <CloudUploadOutlined />,
  reports: <PieChartOutlined />,
  documents: <FolderOpenOutlined />,
  yearend: <CalendarOutlined />,
  notifications: <BellOutlined />,
};

/** The four account-count cards, which are not modules and so pick their own hues. */
const TONES = ['var(--c-teal)', 'var(--c-blue)', 'var(--c-violet)', 'var(--c-amber)'];

/** One figure with its icon — the dashboard's basic unit. */
function Stat({
  label,
  value,
  caption,
  icon,
  tone,
}: {
  label: string;
  value: React.ReactNode;
  caption?: string;
  icon: React.ReactNode;
  tone: string;
}) {
  return (
    <Card className="stat-card toned" style={{ '--tone': tone } as React.CSSProperties} styles={{ body: { padding: 18 } }}>
      <Space size={13} align="start">
        <span className="icon-chip toned">{icon}</span>
        <span>
          <div className="stat-label">{label}</div>
          <div className="stat-value">{value}</div>
          {caption && <div className="stat-caption">{caption}</div>}
        </span>
      </Space>
    </Card>
  );
}

/** Admin view: how many accounts of each kind exist. */
function UserCounts() {
  const results = useQueries({
    queries: COUNT_ROLES.map((r) => ({
      queryKey: ['users', 'count', r.slug],
      queryFn: () => usersApi.list({ role: r.slug, page: 1, page_size: 1 }).then((d) => d.meta.total),
    })),
  });
  return (
    <Row gutter={[16, 16]}>
      {COUNT_ROLES.map((r, i) => (
        <Col xs={12} md={6} key={r.slug}>
          <Stat label={r.label} value={results[i].isLoading ? '—' : (results[i].data ?? 0)} icon={r.icon} tone={TONES[i]} />
        </Col>
      ))}
    </Row>
  );
}

/**
 * Student and parent view: the numbers they actually came for, so the first screen
 * answers "how am I doing" before they navigate anywhere.
 */
function MyNumbers() {
  const { data: me } = useQuery({
    queryKey: ['students', 'dashboard', 'self'],
    queryFn: () => studentsApi.list({ page: 1, page_size: 1 }).then((d) => d.data[0]),
  });
  const { data: ops } = useQuery({
    queryKey: ['opportunities', me?.id],
    queryFn: () => placementApi.opportunities(me!.id),
    enabled: !!me?.id,
  });

  if (!me) return null;
  const eligible = ops?.opportunities.filter((o) => o.is_eligible).length;
  const offers = ops?.applications.filter((a) => a.status === 'selected') ?? [];

  return (
    <Row gutter={[16, 16]}>
      <Col xs={12} md={6}>
        <Stat
          label="CGPA"
          value={me.cgpa.toFixed(2)}
          caption={me.class_label ?? me.department_code ?? undefined}
          icon={<BookOutlined />}
          tone="var(--c-teal)"
        />
      </Col>
      <Col xs={12} md={6}>
        <Stat
          label="Backlogs"
          value={me.backlog_count}
          caption={me.backlog_count === 0 ? 'All clear' : 'Subjects to clear'}
          icon={<SolutionOutlined />}
          tone={me.backlog_count === 0 ? 'var(--c-green)' : 'var(--c-rose)'}
        />
      </Col>
      <Col xs={12} md={6}>
        <Stat
          label="Skills recorded"
          value={ops ? ops.skills.length : '—'}
          caption={ops ? `${ops.skills.filter((s) => s.proficiency >= 4).length} at level 4+` : undefined}
          icon={<StarOutlined />}
          tone="var(--c-violet)"
        />
      </Col>
      <Col xs={12} md={6}>
        <Stat
          label="Drives open to you"
          value={eligible ?? '—'}
          caption={offers.length > 0 ? `Placed at ${offers[0].company_name}` : `${ops?.opportunities.length ?? 0} drives live`}
          icon={<TrophyOutlined />}
          tone="var(--c-amber)"
        />
      </Col>
    </Row>
  );
}

/** Staff view: what is waiting for them rather than college-wide totals. */
function StaffNumbers() {
  const { data: students } = useQuery({
    queryKey: ['students', 'dashboard', 'scope'],
    queryFn: () => studentsApi.list({ page: 1, page_size: 1 }).then((d) => d.meta.total),
  });
  const { data: open } = useQuery({
    queryKey: ['job-roles', 'dashboard', 'open'],
    queryFn: () => placementApi.roles({ status: 'open' }),
  });

  return (
    <Row gutter={[16, 16]}>
      <Col xs={12} md={8}>
        <Stat label="Students in your scope" value={students ?? '—'} icon={<SolutionOutlined />} tone="var(--c-teal)" />
      </Col>
      <Col xs={12} md={8}>
        <Stat
          label="Drives open now"
          value={open?.length ?? '—'}
          caption={open?.length ? open[0].company_name : undefined}
          icon={<TrophyOutlined />}
          tone="var(--c-amber)"
        />
      </Col>
      <Col xs={12} md={8}>
        <Stat
          label="Students applied"
          value={open?.reduce((a, r) => a + r.application_count, 0) ?? '—'}
          caption="Across the open drives"
          icon={<SendOutlined />}
          tone="var(--c-blue)"
        />
      </Col>
    </Row>
  );
}

const GREETING: Record<string, string> = {
  admin: 'Everything across the college, from academics to placements.',
  staff: 'Your classes, marks entry and placement tools.',
  student: 'Your marks, skills and placement opportunities.',
  parent: "Follow your children's progress and placement.",
};

const ROLE_LABEL: Record<string, string> = { admin: 'Administrator', staff: 'Staff', student: 'Student', parent: 'Parent' };

function hello() {
  const h = dayjs().hour();
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

export default function DashboardPage() {
  const { user, can } = useAuth();
  const navigate = useNavigate();
  const audience = audienceOf(user?.roles ?? []);
  const tiles = visibleFeatures(can, audience).filter((f) => f.key !== 'dashboard');
  const isStudentSide = audience === 'student' || audience === 'parent';

  return (
    <Space orientation="vertical" size="large" style={{ width: '100%' }}>
      <div className="hero page-intro">
        <div style={{ position: 'relative', zIndex: 1 }}>
          <div className="eyebrow">{dayjs().format('dddd, DD MMMM YYYY')}</div>
          <h2>
            {hello()}, {user?.name?.split(' ')[0]}
          </h2>
          <p>{GREETING[audience]}</p>
        </div>
        <span className="hero-badge">{ROLE_LABEL[audience]}</span>
      </div>

      {isStudentSide ? <MyNumbers /> : can('user.view') ? <UserCounts /> : <StaffNumbers />}

      <div>
        <h3 className="section-title">{isStudentSide ? 'Your sections' : 'Modules'}</h3>
        <Row gutter={[16, 16]}>
          {tiles.map((f) => (
            <Col xs={24} sm={12} xl={8} key={f.key}>
              <Card
                className="tile toned"
                onClick={() => navigate(f.path)}
                style={{ height: '100%', '--tone': moduleColor(f.key, 'light') } as React.CSSProperties}
                styles={{ body: { padding: 18 } }}
              >
                <Space align="start" size={13} style={{ width: '100%' }}>
                  <span className="icon-chip toned">{TILE_ICONS[f.key] ?? <ApartmentOutlined />}</span>
                  <span style={{ flex: 1 }}>
                    <Space size={8} style={{ marginBottom: 2 }}>
                      <Typography.Text strong style={{ fontSize: 14.5 }}>
                        {f.label[audience]}
                      </Typography.Text>
                      {!f.ready && <Tag>Coming soon</Tag>}
                    </Space>
                    <div style={{ color: 'var(--text-soft)', fontSize: 13, lineHeight: 1.5 }}>{f.description[audience]}</div>
                  </span>
                  <ArrowRightOutlined className="tile-go toned" />
                </Space>
              </Card>
            </Col>
          ))}
        </Row>
      </div>
    </Space>
  );
}
