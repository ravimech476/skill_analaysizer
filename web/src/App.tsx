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
const DepartmentsPage = lazy(() => import('./pages/DepartmentsPage'));
const SubjectsPage = lazy(() => import('./pages/SubjectsPage'));
const ExamTypesPage = lazy(() => import('./pages/ExamTypesPage'));
const AcademicYearsPage = lazy(() => import('./pages/AcademicYearsPage'));
const ClassesPage = lazy(() => import('./pages/ClassesPage'));
const StaffPage = lazy(() => import('./pages/StaffPage'));
const StudentsPage = lazy(() => import('./pages/StudentsPage'));
const MarksPage = lazy(() => import('./pages/MarksPage'));
const SkillMasterPage = lazy(() => import('./pages/SkillMasterPage'));
const CompaniesPage = lazy(() => import('./pages/CompaniesPage'));
const PlacementDrivesPage = lazy(() => import('./pages/PlacementPage'));
const PlacementHistoryPage = lazy(() => import('./pages/PlacementHistoryPage'));
const StudentAnalysisPage = lazy(() => import('./pages/StudentAnalysisPage'));
const ClassAnalysisPage = lazy(() => import('./pages/ClassAnalysisPage'));
const DeptAnalysisPage = lazy(() => import('./pages/DeptAnalysisPage'));
const NotificationsPage = lazy(() => import('./pages/NotificationsPage'));
const ReportsPage = lazy(() => import('./pages/ReportsPage'));
const ThresholdPage = lazy(() => import('./pages/ThresholdPage'));

const PAGES: Record<string, ReactNode> = {
  users: <UsersPage />,
  roles: <RolesPage />,
  departments: <DepartmentsPage />,
  subjects: <SubjectsPage />,
  examtypes: <ExamTypesPage />,
  academicyears: <AcademicYearsPage />,
  classes: <ClassesPage />,
  staff: <StaffPage />,
  students: <StudentsPage />,
  marks: <MarksPage />,
  skillmaster: <SkillMasterPage />,
  companies: <CompaniesPage />,
  drives: <PlacementDrivesPage />,
  history: <PlacementHistoryPage />,
  studentanalysis: <StudentAnalysisPage />,
  classanalysis: <ClassAnalysisPage />,
  deptanalysis: <DeptAnalysisPage />,
  notifications: <NotificationsPage />,
  reports: <ReportsPage />,
  threshold: <ThresholdPage />,
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
