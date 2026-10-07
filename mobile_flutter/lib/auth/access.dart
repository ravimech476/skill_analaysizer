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
    key: 'departments',
    icon: Icons.business_outlined,
    permissions: ['department.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Departments', Audience.staff: 'Departments'},
    description: {
      Audience.admin: 'Manage departments and HODs',
      Audience.staff: 'Department directory',
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
    key: 'skillmaster',
    icon: Icons.category_outlined,
    permissions: ['skill.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Skills', Audience.staff: 'Skills'},
    description: {
      Audience.admin: 'Manage the catalogue of skills',
      Audience.staff: 'Skill directory',
    },
  ),
  Feature(
    key: 'companies',
    icon: Icons.store_outlined,
    permissions: ['company.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Companies', Audience.staff: 'Companies'},
    description: {
      Audience.admin: 'Company directory for placement drives',
      Audience.staff: 'Company directory',
    },
  ),
  Feature(
    key: 'drives',
    icon: Icons.emoji_events_outlined,
    permissions: ['job_role.view'],
    label: {
      Audience.admin: 'Placement Drives',
      Audience.staff: 'Placement Drives',
      Audience.student: 'Placement Drives',
      Audience.parent: 'Placement Status'
    },
    description: {
      Audience.admin: 'Create drives with required skills and manage applications',
      Audience.staff: 'Upcoming drives and student applications',
      Audience.student: 'Drives you are eligible for',
      Audience.parent: "Your children's placement status",
    },
  ),
  Feature(
    key: 'history',
    icon: Icons.history_outlined,
    permissions: ['placement.view'],
    label: {
      Audience.admin: 'Placement History',
      Audience.staff: 'Placement History',
      Audience.student: 'My Placements',
      Audience.parent: 'Placement Results'
    },
    description: {
      Audience.admin: 'Confirmed placements, packages and offer letters',
      Audience.staff: 'Placement records and statistics',
      Audience.student: 'Your placement offers',
      Audience.parent: "Your children's placement results",
    },
  ),
  Feature(
    key: 'studentanalysis',
    icon: Icons.person_search_outlined,
    permissions: ['student.view'],
    label: {Audience.admin: 'Student Analysis', Audience.staff: 'Student Analysis', Audience.student: 'My Analysis', Audience.parent: "Child's Analysis"},
    description: {
      Audience.admin: 'Individual student skill analysis from mark history',
      Audience.staff: 'Student skill analysis from marks',
      Audience.student: 'Your skill analysis based on your marks',
      Audience.parent: "Your child's skill analysis",
    },
  ),
  Feature(
    key: 'classanalysis',
    icon: Icons.analytics_outlined,
    permissions: ['class.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Class Analysis', Audience.staff: 'Class Analysis'},
    description: {
      Audience.admin: 'Class-wide skill overview and performance',
      Audience.staff: 'Class performance analysis',
    },
  ),
  Feature(
    key: 'deptanalysis',
    icon: Icons.assessment_outlined,
    permissions: ['report.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Dept Analysis', Audience.staff: 'Dept Analysis'},
    description: {
      Audience.admin: 'Department-wide analytics and comparisons',
      Audience.staff: 'Department performance analysis',
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
    key: 'subjects',
    icon: Icons.menu_book_outlined,
    permissions: ['subject.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Subjects', Audience.staff: 'Subjects'},
    description: {
      Audience.admin: 'Subject codes, names, credits and types',
      Audience.staff: 'Subject directory',
    },
  ),
  Feature(
    key: 'examtypes',
    icon: Icons.assignment_outlined,
    permissions: ['exam_type.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Exams', Audience.staff: 'Exams'},
    description: {
      Audience.admin: 'Exam configuration, max marks and pass percentages',
      Audience.staff: 'Exam directory',
    },
  ),
  Feature(
    key: 'academicyears',
    icon: Icons.date_range_outlined,
    permissions: ['academic_year.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Academic Years', Audience.staff: 'Academic Years'},
    description: {
      Audience.admin: 'Academic year periods and current year',
      Audience.staff: 'Academic year directory',
    },
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
    key: 'threshold',
    icon: Icons.tune_outlined,
    permissions: ['config.view'],
    audiences: [Audience.admin, Audience.staff],
    label: {Audience.admin: 'Skill Analysis Config', Audience.staff: 'Skill Analysis Config'},
    description: {
      Audience.admin: 'Global mark threshold and skill scoring weights',
      Audience.staff: 'View skill scoring configuration',
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

/// Sidebar sections, in order. Anything not listed falls into "More".
const menuGroups = <String, List<String>>{
  'Overview': ['dashboard', 'reports'],
  'Academics': ['departments', 'academicyears', 'classes', 'subjects', 'examtypes', 'marks'],
  'People': ['students', 'staff'],
  'Skill Analyzer': ['studentanalysis', 'classanalysis', 'deptanalysis'],
  'Placement': ['companies', 'drives', 'history'],
  'Settings': ['users', 'roles', 'skillmaster', 'threshold', 'notifications'],
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
