// Every call the app makes, grouped by module and mirroring the web app's api/ folder
// so the two clients stay recognisably the same.

import 'package:dio/dio.dart';

import 'client.dart';
import 'models.dart';

// ---------- auth ----------

class AuthApi {
  Future<Map<String, dynamic>> login(String username, String password) async =>
      (await api.post('/auth/login', {'username': username, 'password': password})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> requestOtp(String identifier) async =>
      (await api.post('/auth/otp/request', {'identifier': identifier})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> verifyOtp(String identifier, String otp) async =>
      (await api.post('/auth/otp/verify', {'identifier': identifier, 'otp': otp})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> forgotPassword(String identifier) async =>
      (await api.post('/auth/password/forgot', {'identifier': identifier})) as Map<String, dynamic>;

  Future<void> resetPassword(String identifier, String otp, String newPassword) =>
      api.post('/auth/password/reset', {'identifier': identifier, 'otp': otp, 'new_password': newPassword});

  Future<SessionUser> me() async => SessionUser.fromJson((await api.get('/auth/me')) as Map<String, dynamic>);

  Future<void> changePassword(String current, String next) =>
      api.post('/auth/password/change', {'current_password': current, 'new_password': next});

  Future<void> logout(String refreshToken) => api.post('/auth/logout', {'refresh_token': refreshToken});
}

// ---------- users, roles, permissions ----------

class UsersApi {
  Future<Paged<Map<String, dynamic>>> list({String? search, String? role, String? status, int page = 1, int pageSize = 25}) =>
      api.list('/users', query: {'search': search, 'role': role, 'status': status, 'page': page, 'page_size': pageSize});

  Future<Map<String, dynamic>> get(int id) async => (await api.get('/users/$id')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async => (await api.post('/users', body)) as Map<String, dynamic>;
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> body) async => (await api.put('/users/$id', body)) as Map<String, dynamic>;
  Future<void> setStatus(int id, bool active) => api.patch('/users/$id/status', {'is_active': active});
  Future<void> setRoles(int id, List<int> roleIds) => api.put('/users/$id/roles', {'role_ids': roleIds});
  Future<void> setPassword(int id, String password) => api.put('/users/$id/password', {'password': password});
}

class RolesApi {
  Future<List<Map<String, dynamic>>> list() async => maps(await api.get('/roles'));
  Future<Map<String, dynamic>> get(int id) async => (await api.get('/roles/$id')) as Map<String, dynamic>;
  Future<void> create(Map<String, dynamic> body) => api.post('/roles', body);
  Future<void> update(int id, Map<String, dynamic> body) => api.put('/roles/$id', body);
  Future<void> remove(int id) => api.delete('/roles/$id');
  Future<void> setPermissions(int id, List<int> ids) => api.put('/roles/$id/permissions', {'permission_ids': ids});
  Future<List<Map<String, dynamic>>> permissionGroups() async => maps(await api.get('/permissions'));
}

// ---------- masters ----------

/// The config-driven lookup tables: departments, academic years, subjects, exam types,
/// grade scales, skills, companies and courses all share these endpoints.
class MastersApi {
  Future<List<MasterRow>> all(String path, {Map<String, dynamic>? query}) async {
    final r = await api.list('/$path', query: {'all': true, ...?query});
    return r.rows.map(MasterRow.new).toList();
  }

  Future<Paged<Map<String, dynamic>>> list(String path, {Map<String, dynamic>? query}) =>
      api.list('/$path', query: query ?? {'all': true});

  Future<Map<String, dynamic>> create(String path, Map<String, dynamic> body) async =>
      (await api.post('/$path', body)) as Map<String, dynamic>;
  Future<Map<String, dynamic>> update(String path, int id, Map<String, dynamic> body) async =>
      (await api.put('/$path/$id', body)) as Map<String, dynamic>;
  Future<void> remove(String path, int id) => api.delete('/$path/$id');
  Future<void> setStatus(String path, int id, bool active) => api.patch('/$path/$id/status', {'is_active': active});
}

class CurriculumApi {
  Future<List<Map<String, dynamic>>> list(int departmentId, [int? semesterId]) async =>
      maps(await api.get('/curriculum', query: {'department_id': departmentId, 'semester_id': semesterId}));
  Future<void> add(int departmentId, int semesterId, List<int> subjectIds, {String? regulation}) =>
      api.post('/curriculum', {
        'department_id': departmentId,
        'semester_id': semesterId,
        'subject_ids': subjectIds,
        if (regulation != null && regulation.isNotEmpty) 'regulation': regulation,
      });
  Future<void> remove(int id) => api.delete('/curriculum/$id');
}

// ---------- classes, staff, students ----------

class ClassesApi {
  Future<List<ClassRow>> list({int? departmentId, dynamic academicYearId, String? search}) async => maps(
        await api.get('/classes',
            query: {'department_id': departmentId, 'academic_year_id': academicYearId, 'search': search}),
      ).map(ClassRow.new).toList();

  Future<ClassRow> get(int id) async => ClassRow((await api.get('/classes/$id')) as Map<String, dynamic>);
  Future<ClassRow> create(Map<String, dynamic> body) async => ClassRow((await api.post('/classes', body)) as Map<String, dynamic>);
  Future<ClassRow> update(int id, Map<String, dynamic> body) async => ClassRow((await api.put('/classes/$id', body)) as Map<String, dynamic>);
  Future<void> remove(int id) => api.delete('/classes/$id');
}

class StaffApi {
  Future<Paged<Map<String, dynamic>>> list({String? search, int? departmentId, String? role, String? status, int page = 1, int pageSize = 25}) =>
      api.list('/staff', query: {
        'search': search,
        'department_id': departmentId,
        'role': role,
        'status': status,
        'page': page,
        'page_size': pageSize,
      });

  Future<List<Staff>> options() async =>
      (await api.list('/staff', query: {'page': 1, 'page_size': 500, 'all': true})).rows.map(Staff.new).toList();

  Future<Staff> get(int id) async => Staff((await api.get('/staff/$id')) as Map<String, dynamic>);
  Future<Staff> create(Map<String, dynamic> body) async => Staff((await api.post('/staff', body)) as Map<String, dynamic>);
  Future<Staff> update(int id, Map<String, dynamic> body) async => Staff((await api.put('/staff/$id', body)) as Map<String, dynamic>);
  Future<void> setStatus(int id, bool active) => api.patch('/staff/$id/status', {'is_active': active});
}

class StudentsApi {
  Future<Paged<Map<String, dynamic>>> list({
    String? search,
    int? departmentId,
    int? classId,
    String? batch,
    String? lifecycle,
    String? status,
    int page = 1,
    int pageSize = 25,
  }) =>
      api.list('/students', query: {
        'search': search,
        'department_id': departmentId,
        'class_id': classId,
        'batch': batch,
        'lifecycle': lifecycle,
        'status': status,
        'page': page,
        'page_size': pageSize,
      });

  Future<Student> get(int id) async => Student((await api.get('/students/$id')) as Map<String, dynamic>);
  Future<Student> create(Map<String, dynamic> body) async => Student((await api.post('/students', body)) as Map<String, dynamic>);
  Future<Student> update(int id, Map<String, dynamic> body) async => Student((await api.put('/students/$id', body)) as Map<String, dynamic>);
  Future<void> setStatus(int id, bool active) => api.patch('/students/$id/status', {'is_active': active});
  Future<Student> addParent(int id, Map<String, dynamic> body) async =>
      Student((await api.post('/students/$id/parents', body)) as Map<String, dynamic>);
  Future<Student> removeParent(int id, int parentId) async =>
      Student((await api.delete('/students/$id/parents/$parentId')) as Map<String, dynamic>);
  Future<List<Map<String, dynamic>>> parents(String search) async =>
      maps(await api.get('/parents', query: {'search': search, 'page_size': 20}));
}

// ---------- marks ----------

class MarksApi {
  Future<List<MarkTarget>> mySubjects() async => maps(await api.get('/marks/my-subjects')).map(MarkTarget.new).toList();

  Future<EntrySheet> entry(Map<String, dynamic> key) async =>
      EntrySheet((await api.get('/marks/entry', query: key)) as Map<String, dynamic>);

  Future<EntrySheet> save(Map<String, dynamic> key, List<Map<String, dynamic>> entries) async =>
      EntrySheet((await api.put('/marks/entry', {...key, 'entries': entries})) as Map<String, dynamic>);

  Future<Map<String, dynamic>> sheet(Map<String, dynamic> query) async =>
      (await api.get('/marks/sheet', query: query)) as Map<String, dynamic>;

  Future<MarkHistory> history(int studentId) async =>
      MarkHistory((await api.get('/marks/students/$studentId')) as Map<String, dynamic>);

  Future<Map<String, dynamic>> uploadEntry(Map<String, dynamic> key, MultipartFile file, bool dryRun) async =>
      (await api.upload('/marks/entry/upload', 'file', file, fields: {...key, 'dry_run': dryRun})) as Map<String, dynamic>;
}

class AllocationsApi {
  Future<List<Map<String, dynamic>>> list({int? classId, int? staffId, int? departmentId}) async =>
      maps(await api.get('/subject-allocations',
          query: {'class_id': classId, 'staff_id': staffId, 'department_id': departmentId}));
  Future<void> create(Map<String, dynamic> body) => api.post('/subject-allocations', body);
  Future<void> remove(int id) => api.delete('/subject-allocations/$id');
}

// ---------- student skills, scores, careers ----------

class SkillsApi {
  Future<List<StudentSkill>> of(int studentId) async =>
      maps(await api.get('/students/$studentId/skills')).map(StudentSkill.new).toList();

  Future<List<StudentSkill>> save(int studentId, Map<String, dynamic> body) async =>
      maps(await api.put('/students/$studentId/skills', body)).map(StudentSkill.new).toList();

  Future<List<StudentSkill>> remove(int studentId, int skillId) async =>
      maps(await api.delete('/students/$studentId/skills/$skillId')).map(StudentSkill.new).toList();

  /// Marks a certificate as checked — verified certificates count as their own source
  /// in the blended skill score.
  Future<List<StudentSkill>> verify(int studentId, int skillId, bool verified) async =>
      maps(await api.put('/students/$studentId/skills/$skillId/verify', {'verified': verified}))
          .map(StudentSkill.new)
          .toList();

  Future<Map<String, dynamic>> matrix(int classId) async =>
      (await api.get('/student-skills/matrix', query: {'class_id': classId})) as Map<String, dynamic>;
}

class ScoresApi {
  Future<SkillScores> of(int studentId) async =>
      SkillScores.fromJson((await api.get('/students/$studentId/skill-scores')) as Map<String, dynamic>);

  Future<Map<String, dynamic>> recompute(Map<String, dynamic> body) async =>
      (await api.post('/skill-scores/recompute', body)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> scoring() async => (await api.get('/config/scoring')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> saveScoring(Map<String, dynamic> body) async =>
      (await api.put('/config/scoring', body)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> subjectMappings({String? search, String? mapped}) async =>
      (await api.get('/subject-skills', query: {'search': search, 'mapped': mapped})) as Map<String, dynamic>;

  Future<void> setSubjectSkills(int subjectId, List<Map<String, dynamic>> skills) =>
      api.put('/subjects/$subjectId/skills', {'skills': skills});
}

class CareersApi {
  Future<List<Career>> list({String? search, String? domain}) async =>
      maps(await api.get('/careers', query: {'search': search, 'domain': domain})).map(Career.new).toList();

  Future<Career> get(int id) async => Career((await api.get('/careers/$id')) as Map<String, dynamic>);
  Future<List<String>> domains() async =>
      ((await api.get('/careers/domains')) as List).map((e) => e.toString()).toList();
  Future<Career> create(Map<String, dynamic> body) async => Career((await api.post('/careers', body)) as Map<String, dynamic>);
  Future<Career> update(int id, Map<String, dynamic> body) async => Career((await api.put('/careers/$id', body)) as Map<String, dynamic>);
  Future<void> remove(int id) => api.delete('/careers/$id');
  Future<List<CourseRef>> courses(int id) async =>
      maps(await api.get('/careers/$id/courses')).map(CourseRef.fromJson).toList();

  Future<CareerMatches> matches(int studentId, {bool refresh = false}) async => CareerMatches.fromJson(
      (await api.get('/students/$studentId/career-matches', query: {if (refresh) 'refresh': 'true'}))
          as Map<String, dynamic>);

  Future<CareerMatches> run(int studentId) async =>
      CareerMatches.fromJson((await api.post('/students/$studentId/career-matches')) as Map<String, dynamic>);

  Future<CareerMatches> feedback(int studentId, int careerId, int rating, {String? comment}) async =>
      CareerMatches.fromJson((await api.post('/students/$studentId/career-matches/$careerId/feedback',
          {'rating': rating, if (comment != null && comment.isNotEmpty) 'comment': comment})) as Map<String, dynamic>);
}

// ---------- placement ----------

class PlacementApi {
  Future<List<JobRole>> roles({String? search, String? status, int? companyId}) async => maps(
        await api.get('/job-roles', query: {'search': search, 'status': status, 'company_id': companyId}),
      ).map(JobRole.new).toList();

  Future<JobRole> role(int id) async => JobRole((await api.get('/job-roles/$id')) as Map<String, dynamic>);
  Future<JobRole> createRole(Map<String, dynamic> body) async => JobRole((await api.post('/job-roles', body)) as Map<String, dynamic>);
  Future<JobRole> updateRole(int id, Map<String, dynamic> body) async => JobRole((await api.put('/job-roles/$id', body)) as Map<String, dynamic>);
  Future<void> setRoleStatus(int id, String status) => api.patch('/job-roles/$id/status', {'status': status});
  Future<void> deleteRole(int id) => api.delete('/job-roles/$id');

  Future<Ranking> analyze(int id) async => Ranking.fromJson((await api.post('/job-roles/$id/analyze')) as Map<String, dynamic>);
  Future<Ranking> matches(int id) async => Ranking.fromJson((await api.get('/job-roles/$id/matches')) as Map<String, dynamic>);
  Future<Map<String, dynamic>> shortlist(int id, List<int> studentIds) async =>
      (await api.post('/job-roles/$id/shortlist', {'student_ids': studentIds})) as Map<String, dynamic>;

  Future<List<Application>> applications(int roleId) async =>
      maps(await api.get('/job-roles/$roleId/applications')).map(Application.new).toList();
  Future<void> updateApplication(int id, String status, {String? remarks}) =>
      api.patch('/applications/$id', {'status': status, if (remarks != null) 'remarks': remarks});

  Future<List<Placement>> placements({String? search, int? departmentId, int? companyId, String? batch}) async => maps(
        await api.get('/placements',
            query: {'search': search, 'department_id': departmentId, 'company_id': companyId, 'batch': batch}),
      ).map(Placement.new).toList();

  Future<Map<String, dynamic>> stats({String? batch}) async =>
      (await api.get('/placements/stats', query: {'batch': batch})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> opportunities(int studentId) async =>
      (await api.get('/students/$studentId/opportunities')) as Map<String, dynamic>;
}

// ---------- lifecycle (year-end) ----------

class LifecycleApi {
  Future<Map<String, dynamic>> semesterChange(List<int> classIds, String direction) async =>
      (await api.post('/lifecycle/semester-change', {'class_ids': classIds, 'direction': direction}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> preview(int fromYearId, int toYearId) async =>
      (await api.post('/lifecycle/promotion/preview', {'from_year_id': fromYearId, 'to_year_id': toYearId}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> promote(Map<String, dynamic> body) async =>
      (await api.post('/lifecycle/promotion', body)) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> runs() async => maps(await api.get('/lifecycle/promotions'));

  Future<void> studentAction(int id, Map<String, dynamic> body) => api.post('/students/$id/lifecycle', body);

  Future<List<Map<String, dynamic>>> history(int id) async => maps(await api.get('/students/$id/history'));
}

// ---------- notifications ----------

class NotificationsApi {
  Future<Paged<Map<String, dynamic>>> inbox({int page = 1, int pageSize = 20, bool unreadOnly = false, String? type}) =>
      api.list('/notifications', query: {
        'page': page,
        'page_size': pageSize,
        if (unreadOnly) 'unread_only': true,
        'type': type,
      });

  Future<int> unreadCount() async => asInt(((await api.get('/notifications/unread-count')) as Map)['unread']);
  Future<void> markRead(int id) => api.post('/notifications/$id/read');
  Future<void> readAll() => api.post('/notifications/read-all');
  Future<void> hide(int id) => api.delete('/notifications/$id');
  Future<Map<String, dynamic>> send(Map<String, dynamic> body) async => (await api.post('/notifications', body)) as Map<String, dynamic>;
  Future<List<Map<String, dynamic>>> sent() async => maps(await api.get('/notifications/sent'));
}

// ---------- reports ----------

class ReportsApi {
  Future<Map<String, dynamic>> dashboard({int? departmentId, int? examTypeId}) async =>
      (await api.get('/reports/dashboard', query: {'department_id': departmentId, 'exam_type_id': examTypeId}))
          as Map<String, dynamic>;
}

// ---------- files & documents ----------

class FilesApi {
  Future<FileLink> upload(String category, MultipartFile file) async {
    final data = await api.upload('/files', 'file', file, fields: {'category': category});
    return FileLink.from(data)!;
  }

  Future<FileLink?> setMyPhoto(int? fileId) async =>
      FileLink.from(((await api.put('/users/me/photo', {'file_id': fileId})) as Map)['photo']);
  Future<FileLink?> setUserPhoto(int userId, int? fileId) async =>
      FileLink.from(((await api.put('/users/$userId/photo', {'file_id': fileId})) as Map)['photo']);
  Future<FileLink?> setResume(int studentId, int? fileId) async =>
      FileLink.from(((await api.put('/students/$studentId/resume', {'file_id': fileId})) as Map)['resume']);
  Future<void> setCompanyLogo(int companyId, int? fileId) => api.put('/companies/$companyId/logo', {'file_id': fileId});
  Future<void> setJobDescription(int roleId, int? fileId) => api.put('/job-roles/$roleId/jd', {'file_id': fileId});
  Future<void> setOfferLetter(int placementId, int? fileId) =>
      api.put('/placements/$placementId/offer-letter', {'file_id': fileId});
}

class DocumentsApi {
  Future<Map<String, dynamic>> of(int studentId) async =>
      (await api.get('/students/$studentId/documents')) as Map<String, dynamic>;

  Future<void> add(int studentId, String docType, String title, int fileId) =>
      api.post('/students/$studentId/documents', {'doc_type': docType, 'title': title, 'file_id': fileId});

  Future<void> review(int studentId, int docId, String status, {String? remarks}) =>
      api.patch('/students/$studentId/documents/$docId', {'status': status, if (remarks != null) 'remarks': remarks});

  Future<void> remove(int studentId, int docId) => api.delete('/students/$studentId/documents/$docId');

  Future<Paged<Map<String, dynamic>>> queue({String? status, int? classId, int page = 1, int pageSize = 25}) =>
      api.list('/documents/pending',
          query: {'status': status, 'class_id': classId, 'page': page, 'page_size': pageSize});
}

// ---------- bulk upload ----------

class BulkApi {
  Future<UploadJob> students(MultipartFile file, {required bool dryRun, bool createMissingClasses = false, String? defaultPassword}) async =>
      UploadJob((await api.upload('/bulk-upload/students', 'file', file, fields: {
        'dry_run': dryRun,
        'create_missing_classes': createMissingClasses,
        'default_password': defaultPassword,
      })) as Map<String, dynamic>);

  Future<UploadJob> staff(MultipartFile file, {required bool dryRun, String? defaultPassword}) async =>
      UploadJob((await api.upload('/bulk-upload/staff', 'file', file,
          fields: {'dry_run': dryRun, 'default_password': defaultPassword})) as Map<String, dynamic>);

  Future<UploadJob> skills(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/skills', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<UploadJob> departments(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/departments', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<UploadJob> subjects(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/subjects', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<UploadJob> companies(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/companies', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<UploadJob> examTypes(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/exam-types', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<UploadJob> academicYears(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/academic-years', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<UploadJob> skillMaster(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/skill-master', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<UploadJob> placementDrives(MultipartFile file, {required bool dryRun}) async =>
      UploadJob((await api.upload('/bulk-upload/placement-drives', 'file', file, fields: {'dry_run': dryRun}))
          as Map<String, dynamic>);

  Future<Paged<Map<String, dynamic>>> jobs({int page = 1, int pageSize = 20, String? uploadType}) =>
      api.list('/bulk-upload/jobs', query: {'page': page, 'page_size': pageSize, 'upload_type': uploadType});

  Future<UploadJob> job(int id) async => UploadJob((await api.get('/bulk-upload/jobs/$id')) as Map<String, dynamic>);
}

// Single instances, imported by the screens.
final authApi = AuthApi();
final usersApi = UsersApi();
final rolesApi = RolesApi();
final mastersApi = MastersApi();
final curriculumApi = CurriculumApi();
final classesApi = ClassesApi();
final staffApi = StaffApi();
final studentsApi = StudentsApi();
final marksApi = MarksApi();
final allocationsApi = AllocationsApi();
final skillsApi = SkillsApi();
final scoresApi = ScoresApi();
final careersApi = CareersApi();
final placementApi = PlacementApi();
final lifecycleApi = LifecycleApi();
final notificationsApi = NotificationsApi();
final reportsApi = ReportsApi();
final filesApi = FilesApi();
final documentsApi = DocumentsApi();
final bulkApi = BulkApi();
