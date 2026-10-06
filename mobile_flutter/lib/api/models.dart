// Data the API returns. Only the shapes the screens actually read are typed; the
// config-driven master screens keep working with plain maps.

String? str(dynamic v) => v?.toString();
String text(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;
int asInt(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
int? asIntOrNull(dynamic v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));
double asDouble(dynamic v, [double fallback = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
double? asDoubleOrNull(dynamic v) => v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
bool asBool(dynamic v) => v == true;
List<Map<String, dynamic>> maps(dynamic v) =>
    ((v ?? []) as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

/// A stored file. `url` is signed, relative to the API root, and expires after 1–2 hours.
class FileLink {
  FileLink({required this.url, required this.name, required this.type, required this.size, this.id});
  final String url;
  final String name;
  final String type;
  final int size;
  final int? id;

  static FileLink? from(dynamic j) {
    if (j is! Map) return null;
    return FileLink(
      url: text(j['url']),
      name: text(j['name']),
      type: text(j['type']),
      size: asInt(j['size']),
      id: asIntOrNull(j['id']),
    );
  }

  bool get isImage => type.startsWith('image/');
  String get sizeLabel => size > 1024 * 1024
      ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(size / 1024).toStringAsFixed(0)} KB';
}

class SessionUser {
  SessionUser({
    required this.id,
    required this.name,
    required this.username,
    required this.roles,
    required this.permissions,
    this.photo,
  });
  final int id;
  final String name;
  final String username;
  final List<String> roles;
  final List<String> permissions;
  final FileLink? photo;

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        id: asInt(j['id']),
        name: text(j['name']),
        username: text(j['username']),
        roles: ((j['roles'] ?? []) as List).map((e) => e.toString()).toList(),
        permissions: ((j['permissions'] ?? []) as List).map((e) => e.toString()).toList(),
        photo: FileLink.from(j['photo']),
      );
}

class ParentRef {
  ParentRef(this.id, this.name, this.username, this.mobile, this.relation, this.isPrimary);
  final int id;
  final String name;
  final String username;
  final String? mobile;
  final String relation;
  final bool isPrimary;

  factory ParentRef.fromJson(Map<String, dynamic> j) => ParentRef(
        asInt(j['id']),
        text(j['name']),
        text(j['username']),
        str(j['mobile']),
        text(j['relation']),
        asBool(j['is_primary']),
      );
}

class Student {
  Student(this.raw);
  final Map<String, dynamic> raw;

  int get id => asInt(raw['id']);
  String get name => text(raw['name']);
  String get username => text(raw['username']);
  String get registerNo => text(raw['register_no']);
  String? get mobile => str(raw['mobile']);
  String? get email => str(raw['email']);
  String? get gender => str(raw['gender']);
  String? get dob => str(raw['dob']);
  int? get departmentId => asIntOrNull(raw['department_id']);
  String? get departmentName => str(raw['department_name']);
  String? get departmentCode => str(raw['department_code']);
  int get admissionYear => asInt(raw['admission_year']);
  String get batch => text(raw['batch']);
  int? get classId => asIntOrNull(raw['class_id']);
  String? get classLabel => str(raw['class_label']);
  String? get inchargeName => str(raw['class_incharge_name']);
  double get cgpa => asDouble(raw['cgpa']);
  int get backlogCount => asInt(raw['backlog_count']);
  String? get bloodGroup => str(raw['blood_group']);
  String? get address => str(raw['address']);
  bool get isActive => asBool(raw['is_active']);
  String get lifecycle => text(raw['lifecycle_status'], 'studying');
  int? get passedOutYear => asIntOrNull(raw['passed_out_year']);
  String? get statusRemarks => str(raw['status_remarks']);
  FileLink? get photo => FileLink.from(raw['photo']);
  FileLink? get resume => FileLink.from(raw['resume']);
  List<ParentRef> get parents => maps(raw['parents']).map(ParentRef.fromJson).toList();

  String get subtitle => [registerNo, classLabel ?? departmentCode].whereType<String>().join(' · ');
}

class Staff {
  Staff(this.raw);
  final Map<String, dynamic> raw;

  int get id => asInt(raw['id']);
  String get name => text(raw['name']);
  String get username => text(raw['username']);
  String? get employeeCode => str(raw['employee_code']);
  String? get mobile => str(raw['mobile']);
  String? get email => str(raw['email']);
  int? get departmentId => asIntOrNull(raw['department_id']);
  String? get departmentName => str(raw['department_name']);
  String? get designation => str(raw['designation']);
  String? get qualification => str(raw['qualification']);
  String? get joinedOn => str(raw['joined_on']);
  String? get inchargeOf => str(raw['incharge_of']);
  bool get isActive => asBool(raw['is_active']);
  List<String> get roles => ((raw['roles'] ?? []) as List).map((e) => e.toString()).toList();
  FileLink? get photo => FileLink.from(raw['photo']);
}

class ClassRow {
  ClassRow(this.raw);
  final Map<String, dynamic> raw;

  int get id => asInt(raw['id']);
  String get label => text(raw['label']);
  int get departmentId => asInt(raw['department_id']);
  String get departmentCode => text(raw['department_code']);
  int get academicYearId => asInt(raw['academic_year_id']);
  String get academicYearName => text(raw['academic_year_name']);
  bool get isCurrentYear => asBool(raw['is_current_year']);
  int get yearLevelId => asInt(raw['year_level_id']);
  String get yearLevelName => text(raw['year_level_name']);
  String get section => text(raw['section']);
  int? get inchargeId => asIntOrNull(raw['class_incharge_id']);
  String? get inchargeName => str(raw['class_incharge_name']);
  int? get currentSemesterId => asIntOrNull(raw['current_semester_id']);
  String? get currentSemesterName => str(raw['current_semester_name']);
  int? get currentSemNo => asIntOrNull(raw['current_sem_no']);
  int get studentCount => asInt(raw['student_count']);
}

/// Any simple master row (department, subject, skill, course…): the screens that
/// render them are config-driven, so a map plus id/label is all they need.
class MasterRow {
  MasterRow(this.raw);
  final Map<String, dynamic> raw;
  int get id => asInt(raw['id']);
  bool get isActive => asBool(raw['is_active']);
  dynamic operator [](String key) => raw[key];
}

/// id + label, for dropdowns.
class Ref {
  Ref(this.id, this.label, [this.extra]);
  final int id;
  final String label;
  final Map<String, dynamic>? extra;
}

// ---------- skills ----------

class StudentSkill {
  StudentSkill(this.raw);
  final Map<String, dynamic> raw;

  int get skillId => asInt(raw['skill_id']);
  String get name => text(raw['name']);
  String get category => text(raw['category']);
  int get proficiency => asInt(raw['proficiency']);
  String get source => text(raw['source']);
  String? get certificateUrl => str(raw['certificate_url']);
  String? get remarks => str(raw['remarks']);
  String? get recordedBy => str(raw['recorded_by']);
  String? get updatedAt => str(raw['updated_at']);
  FileLink? get certificate => FileLink.from(raw['certificate']);
  bool get verified => asBool(raw['certificate_verified']);
  String? get verifiedBy => str(raw['certificate_verified_by']);
  String? get verifiedAt => str(raw['certificate_verified_at']);
  double? get score => asDoubleOrNull(raw['score']);
  bool get hasProof => certificate != null || (certificateUrl?.isNotEmpty ?? false);
}

/// One source's contribution to a blended skill score, with the evidence behind it.
class SourceScore {
  SourceScore(this.source, this.score, this.weight, this.detail);
  final String source;
  final double score;
  final double weight;
  final Map<String, dynamic> detail;

  factory SourceScore.fromJson(Map<String, dynamic> j) => SourceScore(
        text(j['source']),
        asDouble(j['score']),
        asDouble(j['weight']),
        (j['detail'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

class SkillScore {
  SkillScore(this.skillId, this.name, this.category, this.score, this.level, this.breakdown);
  final int skillId;
  final String name;
  final String category;
  final double score;
  final int level;
  final List<SourceScore> breakdown;

  factory SkillScore.fromJson(Map<String, dynamic> j) => SkillScore(
        asInt(j['skill_id']),
        text(j['name']),
        text(j['category']),
        asDouble(j['score']),
        asInt(j['level']),
        maps(j['breakdown']).map(SourceScore.fromJson).toList(),
      );
}

class SkillScores {
  SkillScores(this.computedAt, this.weights, this.scores);
  final String? computedAt;
  final Map<String, double> weights;
  final List<SkillScore> scores;

  factory SkillScores.fromJson(Map<String, dynamic> j) => SkillScores(
        str(j['computed_at']),
        ((j['weights'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), asDouble(v))),
        maps(j['scores']).map(SkillScore.fromJson).toList(),
      );
}

/// Human wording for a skill-score source, shared by every screen that shows one.
const sourceLabels = {
  'declared': 'Recorded by staff',
  'test': 'Assessment',
  'cert': 'Verified certificate',
  'academic': 'Subject marks',
};

const levelNames = ['', 'Beginner', 'Basic', 'Intermediate', 'Advanced', 'Expert'];

// ---------- placement ----------

class RoleSkill {
  RoleSkill(this.skillId, this.name, this.requiredLevel, this.isMandatory, this.weight);
  final int skillId;
  final String name;
  final int requiredLevel;
  final bool isMandatory;
  final double weight;

  factory RoleSkill.fromJson(Map<String, dynamic> j) => RoleSkill(
        asInt(j['skill_id']),
        text(j['skill_name']),
        asInt(j['required_level']),
        asBool(j['is_mandatory']),
        asDouble(j['weight'], 1),
      );
}

class JobRole {
  JobRole(this.raw);
  final Map<String, dynamic> raw;

  int get id => asInt(raw['id']);
  int get companyId => asInt(raw['company_id']);
  String get companyName => text(raw['company_name']);
  String get title => text(raw['title']);
  String? get description => str(raw['description']);
  double get packageLpa => asDouble(raw['package_lpa']);
  String? get driveDate => str(raw['drive_date']);
  String? get lastApplyDate => str(raw['last_apply_date']);
  double get minCgpa => asDouble(raw['min_cgpa']);
  int get maxBacklogs => asInt(raw['max_backlogs']);
  String? get eligibleBatch => str(raw['eligible_batch']);
  int? get openings => asIntOrNull(raw['openings']);
  String get status => text(raw['status']);
  int get applicationCount => asInt(raw['application_count']);
  int get selectedCount => asInt(raw['selected_count']);
  String? get analyzedAt => str(raw['analyzed_at']);
  List<RoleSkill> get skills => maps(raw['skills']).map(RoleSkill.fromJson).toList();
  List<Ref> get departments =>
      maps(raw['departments']).map((d) => Ref(asInt(d['id']), text(d['code']))).toList();
  FileLink? get logo => FileLink.from(raw['company_logo']);
  FileLink? get jd => FileLink.from(raw['jd']);
}

/// One required skill measured against what a student has, for a drive or a career.
class Gap {
  Gap(this.skillId, this.name, this.requiredLevel, this.studentLevel, this.studentScore,
      this.requiredScore, this.isMandatory);
  final int skillId;
  final String name;
  final int requiredLevel;
  final int studentLevel;
  final double studentScore;
  final double requiredScore;
  final bool isMandatory;

  factory Gap.fromJson(Map<String, dynamic> j) => Gap(
        asInt(j['skill_id']),
        text(j['name']),
        asInt(j['required_level']),
        asInt(j['student_level']),
        asDouble(j['student_score']),
        asDouble(j['required_score'], asInt(j['required_level']) * 20),
        asBool(j['is_mandatory']),
      );

  bool get met => studentScore >= requiredScore;
  double get progress => requiredScore <= 0 ? 1 : (studentScore / requiredScore).clamp(0, 1);
}

class Match {
  Match(this.raw);
  final Map<String, dynamic> raw;

  int get studentId => asInt(raw['student_id']);
  String get name => text(raw['name']);
  String get registerNo => text(raw['register_no']);
  String? get classLabel => str(raw['class_label']);
  String? get departmentCode => str(raw['department_code']);
  double get cgpa => asDouble(raw['cgpa']);
  int get backlogCount => asInt(raw['backlog_count']);
  double get skillScore => asDouble(raw['skill_score']);
  double get academicScore => asDouble(raw['academic_score']);
  double get finalScore => asDouble(raw['final_score']);
  bool get isEligible => asBool(raw['is_eligible']);
  bool get isStale => asBool(raw['is_stale']);
  String? get applicationStatus => str(raw['application_status']);
  List<String> get reasons => ((raw['ineligible_reasons'] ?? []) as List).map((e) => e.toString()).toList();
  List<Gap> get matched => maps(raw['matched_skills']).map(Gap.fromJson).toList();
  List<Gap> get missing => maps(raw['missing_skills']).map(Gap.fromJson).toList();
}

class Ranking {
  Ranking(this.analyzedAt, this.total, this.eligible, this.stale, this.matches);
  final String? analyzedAt;
  final int total;
  final int eligible;
  final int stale;
  final List<Match> matches;

  factory Ranking.fromJson(Map<String, dynamic> j) => Ranking(
        str(j['analyzed_at']),
        asInt(j['total']),
        asInt(j['eligible']),
        asInt(j['stale']),
        maps(j['matches']).map(Match.new).toList(),
      );
}

class Application {
  Application(this.raw);
  final Map<String, dynamic> raw;
  int get id => asInt(raw['id']);
  int get jobRoleId => asInt(raw['job_role_id']);
  String get jobTitle => text(raw['job_title']);
  String get companyName => text(raw['company_name']);
  double get packageLpa => asDouble(raw['package_lpa']);
  int get studentId => asInt(raw['student_id']);
  String get studentName => text(raw['student_name']);
  String get registerNo => text(raw['register_no']);
  double get cgpa => asDouble(raw['cgpa']);
  double? get matchScore => asDoubleOrNull(raw['match_score']);
  String get status => text(raw['status']);
  String? get remarks => str(raw['remarks']);
  String? get offerDate => str(raw['offer_date']);
}

class Placement {
  Placement(this.raw);
  final Map<String, dynamic> raw;
  int get id => asInt(raw['id']);
  String get studentName => text(raw['student_name']);
  String get registerNo => text(raw['register_no']);
  String? get departmentCode => str(raw['department_code']);
  String get batch => text(raw['batch']);
  String get companyName => text(raw['company_name']);
  String get jobTitle => text(raw['job_title']);
  double get packageLpa => asDouble(raw['package_lpa']);
  String? get offerDate => str(raw['offer_date']);
  FileLink? get offerLetter => FileLink.from(raw['offer_letter']);
}

class Opportunity {
  Opportunity(this.raw);
  final Map<String, dynamic> raw;
  JobRole get role => JobRole((raw['job_role'] as Map).cast<String, dynamic>());
  bool get isEligible => asBool(raw['is_eligible']);
  List<String> get reasons => ((raw['ineligible_reasons'] ?? []) as List).map((e) => e.toString()).toList();
  double get skillScore => asDouble(raw['skill_score']);
  double get finalScore => asDouble(raw['final_score']);
  List<Gap> get matched => maps(raw['matched_skills']).map(Gap.fromJson).toList();
  List<Gap> get missing => maps(raw['missing_skills']).map(Gap.fromJson).toList();
  String? get applicationStatus => str(raw['application_status']);
}

// ---------- careers ----------

class CareerSkill {
  CareerSkill(this.skillId, this.name, this.requiredLevel, this.weight, this.isCore);
  final int skillId;
  final String name;
  final int requiredLevel;
  final double weight;
  final bool isCore;

  factory CareerSkill.fromJson(Map<String, dynamic> j) => CareerSkill(
        asInt(j['skill_id']),
        text(j['skill_name']),
        asInt(j['required_level']),
        asDouble(j['weight'], 1),
        asBool(j['is_core']),
      );
}

class Career {
  Career(this.raw);
  final Map<String, dynamic> raw;
  int get id => asInt(raw['id']);
  String get code => text(raw['code']);
  String get name => text(raw['name']);
  String? get domain => str(raw['domain']);
  String? get description => str(raw['description']);
  double? get avgPackage => asDoubleOrNull(raw['avg_package']);
  double get minCgpa => asDouble(raw['min_cgpa']);
  int get courseCount => asInt(raw['course_count']);
  List<CareerSkill> get skills => maps(raw['skills']).map(CareerSkill.fromJson).toList();
}

class CourseRef {
  CourseRef(this.id, this.title, this.provider, this.url, this.level, this.hours, this.isFree);
  final int id;
  final String title;
  final String? provider;
  final String? url;
  final int level;
  final int? hours;
  final bool isFree;

  factory CourseRef.fromJson(Map<String, dynamic> j) => CourseRef(
        asInt(j['id']),
        text(j['title']),
        str(j['provider']),
        str(j['url']),
        asInt(j['level']),
        asIntOrNull(j['duration_hours']),
        asBool(j['is_free']),
      );
}

/// One required skill of a career, measured against the student's blended score.
class SkillStanding {
  SkillStanding(this.raw);
  final Map<String, dynamic> raw;
  int get skillId => asInt(raw['skill_id']);
  String get name => text(raw['name']);
  double get score => asDouble(raw['score']);
  int get level => asInt(raw['level']);
  int get requiredLevel => asInt(raw['required_level']);
  double get requiredScore => asDouble(raw['required_score']);
  double get gap => asDouble(raw['gap']);
  bool get isCore => asBool(raw['is_core']);
  List<CourseRef> get courses => maps(raw['courses']).map(CourseRef.fromJson).toList();
  double get progress => requiredScore <= 0 ? 1 : (score / requiredScore).clamp(0, 1);
}

class CareerMatch {
  CareerMatch(this.raw);
  final Map<String, dynamic> raw;
  int get careerId => asInt(raw['career_id']);
  String get code => text(raw['code']);
  String get name => text(raw['name']);
  String? get domain => str(raw['domain']);
  double? get avgPackage => asDoubleOrNull(raw['avg_package']);
  double get minCgpa => asDouble(raw['min_cgpa']);
  int get rank => asInt(raw['rank']);
  double get skillScore => asDouble(raw['skill_score']);
  double get academicScore => asDouble(raw['academic_score']);
  double get finalScore => asDouble(raw['final_score']);
  String get readiness => text(raw['readiness'], 'explore');
  String get explanation => text(raw['explanation']);
  bool get isStale => asBool(raw['is_stale']);
  List<SkillStanding> get strengths => maps(raw['strengths']).map(SkillStanding.new).toList();
  List<SkillStanding> get gaps => maps(raw['gaps']).map(SkillStanding.new).toList();
  int? get rating => asIntOrNull((raw['feedback'] as Map?)?['rating']);
}

class CareerMatches {
  CareerMatches(this.computedAt, this.isStale, this.counts, this.total, this.matches);
  final String? computedAt;
  final bool isStale;
  final Map<String, int> counts;
  final int total;
  final List<CareerMatch> matches;

  factory CareerMatches.fromJson(Map<String, dynamic> j) => CareerMatches(
        str(j['computed_at']),
        asBool(j['is_stale']),
        ((j['counts'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), asInt(v))),
        asInt(j['total']),
        maps(j['matches']).map(CareerMatch.new).toList(),
      );
}

// ---------- marks ----------

class MarkTarget {
  MarkTarget(this.raw);
  final Map<String, dynamic> raw;
  int get classId => asInt(raw['class_id']);
  String get classLabel => text(raw['class_label']);
  int get semesterId => asInt(raw['semester_id']);
  int get semNo => asInt(raw['sem_no']);
  int get subjectId => asInt(raw['subject_id']);
  String get subjectCode => text(raw['subject_code']);
  String get subjectName => text(raw['subject_name']);
  String get reason => text(raw['reason']);
}

class EntryRow {
  EntryRow(this.raw);
  final Map<String, dynamic> raw;
  int get studentId => asInt(raw['student_id']);
  String get registerNo => text(raw['register_no']);
  String get name => text(raw['name']);
  double? get marks => asDoubleOrNull(raw['marks_obtained']);
  bool get isAbsent => asBool(raw['is_absent']);
  String? get grade => str(raw['grade']);
  String? get result => str(raw['result']);
  bool get inClass => asBool(raw['in_class']);
}

class EntrySheet {
  EntrySheet(this.raw);
  final Map<String, dynamic> raw;
  String get classLabel => text(raw['class_label']);
  int get semNo => asInt(raw['sem_no']);
  String get subjectCode => text(raw['subject_code']);
  String get subjectName => text(raw['subject_name']);
  String get examName => text(raw['exam_name']);
  double get maxMarks => asDouble(raw['max_marks']);
  bool get isFinal => asBool(raw['is_final']);
  bool get canEdit => asBool(raw['can_edit']);
  int get attemptNo => asInt(raw['attempt_no'], 1);
  List<EntryRow> get rows => maps(raw['rows']).map(EntryRow.new).toList();
  Map<String, dynamic> get stats => (raw['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
}

class MarkHistory {
  MarkHistory(this.raw);
  final Map<String, dynamic> raw;
  String get name => text(raw['name']);
  String get registerNo => text(raw['register_no']);
  String? get classLabel => str(raw['class_label']);
  double get cgpa => asDouble(raw['cgpa']);
  int get backlogCount => asInt(raw['backlog_count']);
  List<Map<String, dynamic>> get semesters => maps(raw['semesters']);
}

// ---------- notifications ----------

class Notice {
  Notice(this.raw);
  final Map<String, dynamic> raw;
  int get id => asInt(raw['id']);
  String get title => text(raw['title']);
  String get body => text(raw['body']);
  String get type => text(raw['type'], 'general');
  String? get referenceType => str(raw['reference_type']);
  int? get referenceId => asIntOrNull(raw['reference_id']);
  String? get senderName => str(raw['sender_name']);
  bool get isRead => asBool(raw['is_read']);
  String get createdAt => text(raw['created_at']);
  FileLink? get attachment => FileLink.from(raw['attachment']);
}

// ---------- documents ----------

class StudentDocument {
  StudentDocument(this.raw);
  final Map<String, dynamic> raw;
  int get id => asInt(raw['id']);
  int get studentId => asInt(raw['student_id']);
  String get studentName => text(raw['student_name']);
  String get registerNo => text(raw['register_no']);
  String? get classLabel => str(raw['class_label']);
  String get docType => text(raw['doc_type']);
  String get docTypeLabel => text(raw['doc_type_label'], text(raw['doc_type']));
  String get title => text(raw['title']);
  String get status => text(raw['status'], 'pending');
  String? get remarks => str(raw['remarks']);
  String? get verifiedBy => str(raw['verified_by']);
  String? get uploadedBy => str(raw['uploaded_by']);
  String get createdAt => text(raw['created_at']);
  FileLink? get file => FileLink.from(raw['file']);
}

// ---------- bulk upload ----------

class UploadJob {
  UploadJob(this.raw);
  final Map<String, dynamic> raw;
  int get id => asInt(raw['id']);
  String get uploadType => text(raw['upload_type']);
  String get fileName => text(raw['file_name']);
  int get totalRows => asInt(raw['total_rows']);
  int get successRows => asInt(raw['success_rows']);
  int get failedRows => asInt(raw['failed_rows']);
  bool get dryRun => asBool(raw['dry_run']);
  String get status => text(raw['status']);
  String? get createdByName => str(raw['created_by_name']);
  String get createdAt => text(raw['created_at']);
  List<Map<String, dynamic>> get errors => maps(raw['errors']);
}
