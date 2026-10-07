// Single source of truth for "which roles see which screens".
// A feature is visible when the user has ANY of its permissions; labels adapt to the
// user's audience so a parent sees "My Children" where staff see "Students".

export type Audience = 'admin' | 'staff' | 'student' | 'parent';

export interface Feature {
  key: string;
  path: string;
  permissions: string[] | 'any';
  label: Record<Audience, string>;
  description: Record<Audience, string>;
  ready: boolean; // false → "coming soon" page
  /** Limit to these audiences even if the permission is held (e.g. parents can read classes but get no Classes menu). */
  audiences?: Audience[];
}

const same = (s: string): Record<Audience, string> => ({ admin: s, staff: s, student: s, parent: s });

export const FEATURES: Feature[] = [
  {
    key: 'dashboard',
    path: '/',
    permissions: 'any',
    label: same('Dashboard'),
    description: same('Overview'),
    ready: true,
  },
  {
    key: 'users',
    path: '/users',
    permissions: ['user.view'],
    label: same('Users'),
    description: same('Create and manage student, staff, parent and admin accounts'),
    ready: true,
  },
  {
    key: 'roles',
    path: '/roles',
    permissions: ['role.view'],
    label: same('Roles & Permissions'),
    description: same('Define roles and what each role can do'),
    ready: true,
  },
  {
    key: 'threshold',
    path: '/threshold',
    permissions: ['config.view'],
    audiences: ['admin', 'staff'],
    label: same('Skill Analysis Config'),
    description: { admin: 'Global mark threshold and skill scoring weights', staff: 'View skill scoring configuration', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'subjects',
    path: '/subjects',
    permissions: ['subject.view'],
    audiences: ['admin', 'staff'],
    label: same('Subjects'),
    description: { admin: 'Subject codes, names, credits and types', staff: 'Subject directory', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'examtypes',
    path: '/exam-types',
    permissions: ['exam_type.view'],
    audiences: ['admin', 'staff'],
    label: same('Exams'),
    description: { admin: 'Exam configuration, max marks and pass percentages', staff: 'Exam directory', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'academicyears',
    path: '/academic-years',
    permissions: ['academic_year.view'],
    audiences: ['admin', 'staff'],
    label: same('Academic Years'),
    description: { admin: 'Academic year periods and current year setting', staff: 'Academic year directory', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'classes',
    path: '/classes',
    permissions: ['class.view'],
    audiences: ['admin', 'staff'],
    label: same('Classes'),
    description: { admin: 'Classes, sections and class incharges', staff: 'Classes and their incharges', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'staff',
    path: '/staff',
    permissions: ['staff.view'],
    audiences: ['admin', 'staff'],
    label: same('Staff'),
    description: { admin: 'Staff profiles, departments and roles', staff: 'Staff directory', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'departments',
    path: '/departments',
    permissions: ['department.view'],
    audiences: ['admin', 'staff'],
    label: same('Departments'),
    description: { admin: 'Manage departments and HODs', staff: 'Department directory', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'students',
    path: '/students',
    permissions: ['student.view'],
    label: { admin: 'Students', staff: 'Students', student: 'My Profile', parent: 'My Children' },
    description: {
      admin: 'Student profiles, classes and parent links',
      staff: 'Students in your classes',
      student: 'Your academic profile',
      parent: "Your children's profiles and classes",
    },
    ready: true,
  },
  {
    key: 'marks',
    path: '/marks',
    permissions: ['marks.view'],
    label: { admin: 'Marks', staff: 'Marks', student: 'My Marks', parent: "Children's Marks" },
    description: {
      admin: 'Semester-wise mark history and CGPA',
      staff: 'Enter and review marks for your classes',
      student: 'Your semester-wise marks and CGPA',
      parent: "Your children's semester-wise marks",
    },
    ready: true,
  },
  {
    key: 'skillmaster',
    path: '/skill-master',
    permissions: ['skill.view'],
    audiences: ['admin', 'staff'],
    label: same('Skills'),
    description: { admin: 'Manage the catalogue of skills', staff: 'Skill directory', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'companies',
    path: '/companies',
    permissions: ['company.view'],
    audiences: ['admin', 'staff'],
    label: same('Companies'),
    description: { admin: 'Company directory for placement drives', staff: 'Company directory', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'drives',
    path: '/drives',
    permissions: ['job_role.view'],
    label: { admin: 'Placement Drives', staff: 'Placement Drives', student: 'Placement Drives', parent: 'Placement Status' },
    description: {
      admin: 'Create drives with required skills and manage applications',
      staff: 'Upcoming drives and student applications',
      student: 'Drives you are eligible for',
      parent: "Your children's placement status",
    },
    ready: true,
  },
  {
    key: 'history',
    path: '/placement-history',
    permissions: ['placement.view'],
    label: { admin: 'Placement History', staff: 'Placement History', student: 'My Placements', parent: 'Placement Results' },
    description: {
      admin: 'Confirmed placements, packages and offer letters',
      staff: 'Placement records and statistics',
      student: 'Your placement offers',
      parent: "Your children's placement results",
    },
    ready: true,
  },
  {
    key: 'studentanalysis',
    path: '/student-analysis',
    permissions: ['student.view'],
    label: { admin: 'Student Analysis', staff: 'Student Analysis', student: 'My Analysis', parent: "Child's Analysis" },
    description: {
      admin: 'Individual student skill analysis from mark history',
      staff: 'Student skill analysis from marks',
      student: 'Your skill analysis based on your marks',
      parent: "Your child's skill analysis",
    },
    ready: true,
  },
  {
    key: 'classanalysis',
    path: '/class-analysis',
    permissions: ['class.view'],
    audiences: ['admin', 'staff'],
    label: same('Class Analysis'),
    description: { admin: 'Class-wide skill overview and performance', staff: 'Class performance analysis', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'deptanalysis',
    path: '/department-analysis',
    permissions: ['report.view'],
    audiences: ['admin', 'staff'],
    label: same('Department Analysis'),
    description: { admin: 'Department-wide analytics and comparisons', staff: 'Department performance analysis', student: '', parent: '' },
    ready: true,
  },
  {
    key: 'reports',
    path: '/reports',
    permissions: ['report.view'],
    audiences: ['admin', 'staff'],
    label: same('Reports'),
    description: {
      admin: 'Pass %, CGPA spread, skill gaps, placement trend and Excel exports',
      staff: 'Results, skill gaps and placement for your department',
      student: '',
      parent: '',
    },
    ready: true,
  },
  {
    key: 'notifications',
    path: '/notifications',
    permissions: ['notification.view'],
    label: same('Notifications'),
    description: same('Announcements and alerts'),
    ready: true,
  },
];

/** Most privileged audience wins for labels (staff+parent → staff wording). */
export function audienceOf(roles: string[]): Audience {
  if (roles.includes('admin')) return 'admin';
  if (roles.some((r) => r === 'staff' || r === 'hod' || r === 'placement_officer')) return 'staff';
  if (roles.includes('student')) return 'student';
  if (roles.includes('parent')) return 'parent';
  return 'staff';
}

export function visibleFeatures(can: (...p: string[]) => boolean, audience: Audience): Feature[] {
  return FEATURES.filter(
    (f) => (f.permissions === 'any' || can(...f.permissions)) && (!f.audiences || f.audiences.includes(audience)),
  );
}

export const ROLE_COLORS: Record<string, string> = {
  admin: 'red',
  staff: 'blue',
  hod: 'geekblue',
  placement_officer: 'purple',
  student: 'green',
  parent: 'orange',
};
