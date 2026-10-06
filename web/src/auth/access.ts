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
    key: 'academic',
    path: '/academic',
    permissions: ['department.create', 'department.update', 'subject.create', 'academic_year.create'],
    label: same('Academic Setup'),
    description: same('Departments, academic years, subjects, curriculum and exam types'),
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
    key: 'skills',
    path: '/skills',
    permissions: ['student_skill.view'],
    label: { admin: 'Student Skills', staff: 'Student Skills', student: 'My Skills', parent: "Children's Skills" },
    description: {
      admin: 'Skill master and student skill levels',
      staff: 'Record and verify student skills',
      student: 'Skills recorded by your staff',
      parent: "Skills recorded for your children",
    },
    ready: true,
  },
  {
    key: 'placement',
    path: '/placement',
    permissions: ['job_role.view', 'placement.view'],
    label: { admin: 'Placement', staff: 'Placement', student: 'Placement Drives', parent: 'Placement Status' },
    description: {
      admin: 'Companies, job roles and placement records',
      staff: 'Upcoming drives and placement results',
      student: 'Drives you are eligible for and your applications',
      parent: "Your children's placement status",
    },
    ready: true,
  },
  {
    key: 'analyzer',
    path: '/skill-analyzer',
    permissions: ['skill_analyzer.view'],
    label: { admin: 'Skill Analyzer', staff: 'Skill Analyzer', student: 'Skill Gap', parent: 'Skill Gap' },
    description: {
      admin: 'Rank students against a job role and shortlist',
      staff: 'Rank students against a job role',
      student: 'Skills you need for each company',
      parent: 'Skills your child needs for each company',
    },
    ready: true,
  },
  {
    key: 'careers',
    path: '/careers',
    permissions: ['career.view'],
    label: { admin: 'Careers', staff: 'Careers', student: 'My Careers', parent: 'Career Guidance' },
    description: {
      admin: 'Career catalogue, required skills, courses and student career matches',
      staff: 'Which careers fit a student, what is missing and what they could study',
      student: 'Careers that fit your skills and marks, and what to learn next',
      parent: "Careers that fit your child, and what they could study next",
    },
    ready: true,
  },
  {
    key: 'bulk',
    path: '/bulk-upload',
    permissions: ['bulk_upload.create', 'staff.create', 'student_skill.create'],
    audiences: ['admin', 'staff'],
    label: same('Bulk Upload'),
    description: { admin: 'Import students, staff and student skills from Excel', staff: 'Import student skill levels from Excel', student: '', parent: '' },
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
    key: 'yearend',
    path: '/year-end',
    permissions: ['promotion.view'],
    audiences: ['admin', 'staff'],
    label: same('Year-end'),
    description: {
      admin: 'Semester change, year promotion, alumni and student history',
      staff: 'Semester change for your department and alumni',
      student: '',
      parent: '',
    },
    ready: true,
  },
  {
    key: 'documents',
    path: '/documents',
    permissions: ['document.verify'],
    audiences: ['admin', 'staff'],
    label: same('Documents'),
    description: {
      admin: 'Verify the documents students upload',
      staff: 'Verify documents uploaded by your students',
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
