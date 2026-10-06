import { lazy, Suspense, type ReactNode } from 'react';
import { Result, Spin } from 'antd';
import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { useAuth } from './auth/AuthContext';
import { audienceOf, FEATURES, type Feature } from './auth/access';
import AppLayout from './components/AppLayout';
import LoginPage from './pages/LoginPage';
const ForgotPasswordPage = lazy(() => import('./pages/ForgotPasswordPage'));
import DashboardPage from './pages/DashboardPage';
const UsersPage = lazy(() => import('./pages/UsersPage'));
const RolesPage = lazy(() => import('./pages/RolesPage'));
const ProfilePage = lazy(() => import('./pages/ProfilePage'));
import ComingSoonPage from './pages/ComingSoonPage';
const AcademicPage = lazy(() => import('./pages/AcademicPage'));
const ClassesPage = lazy(() => import('./pages/ClassesPage'));
const StaffPage = lazy(() => import('./pages/StaffPage'));
const StudentsPage = lazy(() => import('./pages/StudentsPage'));
const BulkUploadPage = lazy(() => import('./pages/BulkUploadPage'));
const MarksPage = lazy(() => import('./pages/MarksPage'));
const SkillsPage = lazy(() => import('./pages/SkillsPage'));
const PlacementPage = lazy(() => import('./pages/PlacementPage'));
const AnalyzerPage = lazy(() => import('./pages/AnalyzerPage'));
const CareersPage = lazy(() => import('./pages/CareersPage'));
const NotificationsPage = lazy(() => import('./pages/NotificationsPage'));
const YearEndPage = lazy(() => import('./pages/YearEndPage'));
const ReportsPage = lazy(() => import('./pages/ReportsPage'));
const DocumentsPage = lazy(() => import('./pages/DocumentsPage'));

const PAGES: Record<string, ReactNode> = {
  users: <UsersPage />,
  roles: <RolesPage />,
  academic: <AcademicPage />,
  classes: <ClassesPage />,
  staff: <StaffPage />,
  students: <StudentsPage />,
  bulk: <BulkUploadPage />,
  marks: <MarksPage />,
  skills: <SkillsPage />,
  placement: <PlacementPage />,
  analyzer: <AnalyzerPage />,
  careers: <CareersPage />,
  notifications: <NotificationsPage />,
  yearend: <YearEndPage />,
  reports: <ReportsPage />,
  documents: <DocumentsPage />,
};

/** Shown while a page's code chunk is loading. */
function PageLoader() {
  return (
    <div style={{ display: 'grid', placeItems: 'center', minHeight: 240, padding: 48 }}>
      <Spin size="large" />
    </div>
  );
}

function RequireAuth({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth();
  const location = useLocation();
  if (loading) {
    return (
      <div style={{ display: 'grid', placeItems: 'center', height: '100vh' }}>
        <Spin size="large" />
      </div>
    );
  }
  if (!user) return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  return children;
}

function Guard({ feature }: { feature: Feature }) {
  const { can, user } = useAuth();
  const allowedAudience = !feature.audiences || feature.audiences.includes(audienceOf(user?.roles ?? []));
  if ((feature.permissions !== 'any' && !can(...feature.permissions)) || !allowedAudience) {
    return <Result status="403" title="Not allowed" subTitle="Your role does not have access to this page." />;
  }
  return feature.ready ? PAGES[feature.key] : <ComingSoonPage feature={feature} />;
}

export default function App() {
  return (
    <BrowserRouter>
      <Suspense fallback={<PageLoader />}>
        <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/forgot-password" element={<ForgotPasswordPage />} />
        <Route
          element={
            <RequireAuth>
              <AppLayout />
            </RequireAuth>
          }
        >
          <Route index element={<DashboardPage />} />
          <Route path="profile" element={<ProfilePage />} />
          {FEATURES.filter((f) => f.path !== '/').map((f) => (
            <Route key={f.key} path={f.path.slice(1)} element={<Guard feature={f} />} />
          ))}
          <Route path="*" element={<Result status="404" title="Page not found" />} />
        </Route>
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}
