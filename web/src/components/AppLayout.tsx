import { useEffect, useState } from 'react';
import { Button, Drawer, Dropdown, Grid, Layout, Menu, Space, Tag, Typography } from 'antd';
import {
  ApartmentOutlined,
  BankOutlined,
  BarChartOutlined,
  BellOutlined,
  BookOutlined,
  CalendarOutlined,
  CloudUploadOutlined,
  CompassOutlined,
  DashboardOutlined,
  FolderOpenOutlined,
  IdcardOutlined,
  LogoutOutlined,
  MenuOutlined,
  PieChartOutlined,
  SafetyOutlined,
  SolutionOutlined,
  StarOutlined,
  TeamOutlined,
  TrophyOutlined,
  UserOutlined,
} from '@ant-design/icons';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { audienceOf, ROLE_COLORS, visibleFeatures, type Feature } from '../auth/access';
import NotificationBell from './NotificationBell';
import { UserAvatar } from './Files';
import { moduleColor } from '../auth/moduleColors';
import { Brand } from './Brand';

const ICONS: Record<string, React.ReactNode> = {
  dashboard: <DashboardOutlined />,
  users: <TeamOutlined />,
  roles: <SafetyOutlined />,
  academic: <BankOutlined />,
  classes: <ApartmentOutlined />,
  staff: <IdcardOutlined />,
  students: <SolutionOutlined />,
  marks: <BookOutlined />,
  skills: <StarOutlined />,
  placement: <TrophyOutlined />,
  analyzer: <BarChartOutlined />,
  careers: <CompassOutlined />,
  bulk: <CloudUploadOutlined />,
  notifications: <BellOutlined />,
  yearend: <CalendarOutlined />,
  reports: <PieChartOutlined />,
  documents: <FolderOpenOutlined />,
};

/** Sidebar sections, in order. Features not listed fall into "More". */
const GROUPS: { title: string; keys: string[] }[] = [
  { title: 'Overview', keys: ['dashboard', 'reports'] },
  { title: 'Academics', keys: ['classes', 'marks', 'documents', 'yearend'] },
  { title: 'People', keys: ['students', 'staff', 'users', 'roles'] },
  { title: 'Placement', keys: ['skills', 'careers', 'placement', 'analyzer'] },
  { title: 'Setup & tools', keys: ['academic', 'bulk', 'notifications'] },
];

export default function AppLayout() {
  const { user, can, logout } = useAuth();
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const screens = Grid.useBreakpoint();
  const isMobile = !screens.lg;
  const [drawerOpen, setDrawerOpen] = useState(false);

  const audience = audienceOf(user?.roles ?? []);
  const features = visibleFeatures(can, audience);
  const current = features
    .filter((f) => (f.path === '/' ? pathname === '/' : pathname.startsWith(f.path)))
    .at(-1);
  const selected = current ? [current.key] : [];
  const pageTitle = pathname.startsWith('/profile') ? 'My profile' : (current?.label[audience] ?? 'Skills Analyzer');

  // Keep the browser tab in step with the page.
  useEffect(() => {
    document.title = `${pageTitle} · Skills Analyzer`;
  }, [pageTitle]);

  const open = (f: Feature) => {
    navigate(f.path);
    setDrawerOpen(false);
  };
  // --tone drives the icon colour, the hover tint and the selected pill in index.css,
  // so each row only needs the one value.
  const item = (f: Feature) => ({
    key: f.key,
    icon: <span className="nav-icon">{ICONS[f.key]}</span>,
    label: f.label[audience],
    className: 'nav-item',
    style: { '--tone': moduleColor(f.key, 'dark') } as React.CSSProperties,
  });

  // Students and parents see only a handful of screens: a plain list reads better for them.
  const grouped = features.length > 8;
  const byKey = new Map(features.map((f) => [f.key, f]));
  const used = new Set<string>();
  const sections = GROUPS.map((g) => {
    const items = g.keys.filter((k) => byKey.has(k));
    items.forEach((k) => used.add(k));
    return { title: g.title, items: items.map((k) => byKey.get(k)!) };
  }).filter((g) => g.items.length > 0);
  const rest = features.filter((f) => !used.has(f.key));
  if (rest.length) sections.push({ title: 'More', items: rest });

  const menu = (
    <Menu
      mode="inline"
      theme="dark"
      selectedKeys={selected}
      items={
        grouped
          ? sections.map((s) => ({ key: s.title, type: 'group' as const, label: s.title, children: s.items.map(item) }))
          : features.map(item)
      }
      onClick={({ key }) => {
        const f = features.find((x) => x.key === key);
        if (f) open(f);
      }}
      style={{ borderInlineEnd: 0, paddingBottom: 24 }}
    />
  );

  const sidebar = (
    <>
      <div className="sider-brand">
        <Brand subtitle="Campus placements" />
      </div>
      {menu}
    </>
  );

  return (
    <Layout style={{ minHeight: '100vh' }}>
      {isMobile ? (
        <Drawer placement="left" open={drawerOpen} onClose={() => setDrawerOpen(false)} size={272} className="app-drawer"
          styles={{ body: { padding: 0 }, header: { display: 'none' } }}>
          {sidebar}
        </Drawer>
      ) : (
        <Layout.Sider width={248} theme="dark" className="app-sider">
          {sidebar}
        </Layout.Sider>
      )}
      <Layout style={{ background: 'transparent' }}>
        <Layout.Header className="app-header">
          <Space size={12} style={{ minWidth: 0 }}>
            {isMobile && <Button type="text" icon={<MenuOutlined />} onClick={() => setDrawerOpen(true)} aria-label="Open menu" />}
            <h1 className="page-title">{pageTitle}</h1>
          </Space>
          <Space size={8}>
            <NotificationBell />
            <Dropdown
              trigger={['click']}
              menu={{
                items: [
                  { key: 'profile', icon: <UserOutlined />, label: 'My profile' },
                  { type: 'divider' },
                  { key: 'logout', icon: <LogoutOutlined />, label: 'Log out', danger: true },
                ],
                onClick: async ({ key }) => {
                  if (key === 'profile') navigate('/profile');
                  if (key === 'logout') {
                    await logout();
                    navigate('/login', { replace: true });
                  }
                },
              }}
            >
              <div className="user-chip">
                <UserAvatar name={user?.name} photo={user?.photo} />
                {!isMobile && (
                  <Space orientation="vertical" size={0} style={{ lineHeight: 1.25 }}>
                    <Typography.Text strong style={{ fontSize: 13.5 }}>
                      {user?.name}
                    </Typography.Text>
                    <span>
                      {user?.roles.map((r) => (
                        <Tag key={r} color={ROLE_COLORS[r]} style={{ marginInlineEnd: 4, fontSize: 10.5, lineHeight: '16px', padding: '0 6px' }}>
                          {r.replace('_', ' ')}
                        </Tag>
                      ))}
                    </span>
                  </Space>
                )}
              </div>
            </Dropdown>
          </Space>
        </Layout.Header>
        <Layout.Content className="app-content">
          <Outlet />
        </Layout.Content>
      </Layout>
    </Layout>
  );
}
