// Single source of truth for "which roles see which screens", kept in step with
// web/src/auth/access.ts. A feature is visible when the user holds ANY of its
// permissions; labels adapt so a parent reads "My Children" where staff read "Students".

import 'package:flutter/material.dart';

enum Audience { admin, staff, student, parent }

class Feature {
  const Feature({
    required this.key,
    required this.icon,
    required this.permissions,
    required this.label,
    required this.description,
    this.audiences,
  });

  final String key;
  final IconData icon;

  /// Empty means "any signed-in user".
  final List<String> permissions;
  final Map<Audience, String> label;
  final Map<Audience, String> description;

  /// Limit to these audiences even when the permission is held (parents can read
  /// classes, but a Classes menu would only confuse them).
  final List<Audience>? audiences;

  String labelFor(Audience a) => label[a] ?? label[Audience.staff] ?? key;
  String descriptionFor(Audience a) => description[a] ?? description[Audience.staff] ?? '';
}

const features = <Feature>[
  Feature(
    key: 'dashboard',
    icon: Icons.space_dashboard_outlined,
    permissions: [],
    label: {Audience.admin: 'Dashboard', Audience.staff: 'Dashboard', Audience.student: 'Home', Audience.parent: 'Home'},
    description: {
      Audience.admin: 'Overview',
      Audience.staff: 'Overview',
      Audience.student: 'Your marks, skills and drives at a glance',
      Audience.parent: "Your children at a glance",
    },
  ),
  Feature(
    key: 'students',
    icon: Icons.school_outlined,
    permissions: ['student.view'],
    label: {
      Audience.admin: 'Students',
      Audience.staff: 'Students',
      Audience.student: 'My Profile',
      Audience.parent: 'My Children'
    },
    description: {
      Audience.admin: 'Student profiles, classes and parent links',
      Audience.staff: 'Students in your classes',
      Audience.student: 'Your academic profile',
      Audience.parent: "Your children's profiles and classes",
    },
  ),
  Feature(
    key: 'marks',
    icon: Icons.menu_book_outlined,
    permissions: ['marks.view'],
    label: {
      Audience.admin: 'Marks',
      Audience.staff: 'Marks',
      Audience.student: 'My Marks',
      Audience.parent: "Children's Marks"
    },
    description: {
      Audience.admin: 'Semester-wise mark history and CGPA',
      Audience.staff: 'Enter and review marks for your classes',
      Audience.student: 'Your semester-wise marks and CGPA',
      Audience.parent: "Your children's semester-wise marks",
    },
  ),
  Feature(
    key: 'skills',
    icon: Icons.star_outline,
    permissions: ['student_skill.view'],
    label: {
      Audience.admin: 'Student Skills',
      Audience.staff: 'Student Skills',
      Audience.student: 'My Skills',
      Audience.parent: "Children's Skills"
    },
    description: {
      Audience.admin: 'Skill master, blended scores and the subject mapping',
      Audience.staff: 'Record and verify student skills',
      Audience.student: 'Skills recorded for you and what they score',
      Audience.parent: "Skills recorded for your children",
    },
  ),
  Feature(
    key: 'careers',
    icon: Icons.explore_outlined,
    permissions: ['career.view'],
    label: {
      Audience.admin: 'Careers',
      Audience.staff: 'Careers',
      Audience.student: 'My Careers',
      Audience.parent: 'Career Guidance'
    },
    description: {
      Audience.admin: 'Career catalogue, required skills, courses and student matches',
      Audience.staff: 'Which careers fit a student, what is missing and what to study',
      Audience.student: 'Careers that fit your skills and marks, and what to learn next',
      Audience.parent: "Careers that fit your child, and what they could study next",
    },
  ),
  Feature(
    key: 'placement',
    icon: Icons.emoji_events_outlined,
    permissions: ['job_role.view', 'placement.view'],
    label: {
      Audience.admin: 'Placement',
      Audience.staff: 'Placement',
      Audience.student: 'Placement Drives',
      Audience.parent: 'Placement Status'
    },
    description: {
      Audience.admin: 'Companies, job roles and placement records',
      Audience.staff: 'Upcoming drives and placement results',
      Audience.student: 'Drives you are eligible for and your applications',
      Audience.parent: "Your children's placement status",
    },
  ),
  Feature(
    key: 'analyzer',
    icon: Icons.insights_outlined,
    permissions: ['skill_analyzer.view'],
    label: {
      Audience.admin: 'Skill Analyzer',
      Audience.staff: 'Skill Analyzer',
      Audience.student: 'Skill Gap',
      Audience.parent: 'Skill Gap'
    },
    description: {
      Audience.admin: 'Rank students against a job role and shortlist',
      Audience.staff: 'Rank students against a job role',
      Audience.student: 'Skills you need for each company',
      Audience.parent: 'Skills your child needs for each company',
    },
  ),
  Feature(
    key: 'classes',
    icon: Icons.account_tree_outlined,
    permissions: ['class.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Classes', Audience.staff: 'Classes'},
    description: {
      Audience.admin: 'Classes, sections and class incharges',
      Audience.staff: 'Classes and their incharges',
    },
  ),
  Feature(
    key: 'staff',
    icon: Icons.badge_outlined,
    permissions: ['staff.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Staff', Audience.staff: 'Staff'},
    description: {Audience.admin: 'Staff profiles, departments and roles', Audience.staff: 'Staff directory'},
  ),
  Feature(
    key: 'documents',
    icon: Icons.folder_open_outlined,
    permissions: ['document.verify'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Documents', Audience.staff: 'Documents'},
    description: {
      Audience.admin: 'Verify the documents students upload',
      Audience.staff: 'Verify documents uploaded by your students',
    },
  ),
  Feature(
    key: 'reports',
    icon: Icons.pie_chart_outline,
    permissions: ['report.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Reports', Audience.staff: 'Reports'},
    description: {
      Audience.admin: 'Pass %, CGPA spread, skill gaps and the placement trend',
      Audience.staff: 'Results, skill gaps and placement for your department',
    },
  ),
  Feature(
    key: 'yearend',
    icon: Icons.event_repeat_outlined,
    permissions: ['promotion.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Year-end', Audience.staff: 'Year-end'},
    description: {
      Audience.admin: 'Semester change, year promotion, alumni and student history',
      Audience.staff: 'Semester change for your department and alumni',
    },
  ),
  Feature(
    key: 'bulk',
    icon: Icons.cloud_upload_outlined,
    permissions: ['bulk_upload.create', 'staff.create', 'student_skill.create'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Bulk Upload', Audience.staff: 'Bulk Upload'},
    description: {
      Audience.admin: 'Import students, staff and student skills from Excel',
      Audience.staff: 'Import student skill levels from Excel',
    },
  ),
  Feature(
    key: 'academic',
    icon: Icons.account_balance_outlined,
    permissions: ['department.create', 'department.update', 'subject.create', 'academic_year.create'],
    label: _staffOnlyLabel,
    description: {
      Audience.admin: 'Departments, academic years, subjects, curriculum and exam types',
      Audience.staff: 'Departments, subjects and exam types',
    },
    audiences: [Audience.admin, Audience.staff],
  ),
  Feature(
    key: 'users',
    icon: Icons.group_outlined,
    permissions: ['user.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Users', Audience.staff: 'Users'},
    description: {
      Audience.admin: 'Create and manage student, staff, parent and admin accounts',
      Audience.staff: 'User accounts',
    },
  ),
  Feature(
    key: 'roles',
    icon: Icons.verified_user_outlined,
    permissions: ['role.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Roles & Permissions', Audience.staff: 'Roles & Permissions'},
    description: {
      Audience.admin: 'Define roles and what each role can do',
      Audience.staff: 'Roles and permissions',
    },
  ),
  Feature(
    key: 'notifications',
    icon: Icons.notifications_none,
    permissions: ['notification.view'],
    label: {},
    description: {},
  ),
];

const _staffOnlyLabel = {Audience.admin: 'Academic Setup', Audience.staff: 'Academic Setup'};

/// Sidebar sections, in order. Anything not listed falls into "More".
const menuGroups = <String, List<String>>{
  'Overview': ['dashboard', 'reports'],
  'Academics': ['classes', 'marks', 'documents', 'yearend'],
  'People': ['students', 'staff', 'users', 'roles'],
  'Placement': ['skills', 'careers', 'placement', 'analyzer'],
  'Setup & tools': ['academic', 'bulk', 'notifications'],
};

/// Most privileged audience wins for labels (staff + parent reads as staff).
Audience audienceOf(List<String> roles) {
  if (roles.contains('admin')) return Audience.admin;
  if (roles.any((r) => r == 'staff' || r == 'hod' || r == 'placement_officer')) return Audience.staff;
  if (roles.contains('student')) return Audience.student;
  if (roles.contains('parent')) return Audience.parent;
  return Audience.staff;
}

const roleColors = <String, Color>{
  'admin': Color(0xFFBE123C),
  'staff': Color(0xFF0369A1),
  'hod': Color(0xFF6D28D9),
  'placement_officer': Color(0xFF0D9488),
  'student': Color(0xFF15803D),
  'parent': Color(0xFFB45309),
};

/// The notifications feature has no label map above; give it one here so the menu
/// and the title bar always have something to show.
String featureLabel(Feature f, Audience a) {
  if (f.key == 'notifications') return 'Notifications';
  return f.labelFor(a);
}

String featureDescription(Feature f, Audience a) {
  if (f.key == 'notifications') return 'Announcements and alerts';
  return f.descriptionFor(a);
}
