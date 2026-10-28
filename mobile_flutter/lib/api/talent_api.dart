import 'client.dart';
import 'models.dart';

/// Psychometric questionnaires, coding platforms and projects (the "talent profile" of a student).
class TalentApi {
  Future<Map<String, dynamic>> profile(int studentId) async =>
      (await api.get('/students/$studentId/talent-profile')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> questionnaire(String kind) async =>
      (await api.get('/assessments/questionnaires/$kind')) as Map<String, dynamic>;

  Future<void> submit(int studentId, String kind, Map<String, int> answers) =>
      api.post('/students/$studentId/assessments/$kind', {'answers': answers});

  Future<void> addPlatform(int studentId, Map<String, dynamic> body) => api.post('/students/$studentId/coding-profiles', body);
  Future<void> updatePlatform(int id, Map<String, dynamic> body) => api.put('/coding-profiles/$id', body);
  Future<void> removePlatform(int id) => api.delete('/coding-profiles/$id');
  Future<void> verifyPlatform(int id, bool verified) => api.put('/coding-profiles/$id/verify', {'verified': verified});

  Future<void> addProject(int studentId, Map<String, dynamic> body) => api.post('/students/$studentId/projects', body);
  Future<void> updateProject(int id, Map<String, dynamic> body) => api.put('/projects/$id', body);
  Future<void> removeProject(int id) => api.delete('/projects/$id');
  Future<void> reviewProject(int id, Map<String, dynamic> body) => api.put('/projects/$id/review', body);

  Future<void> reviewCommunication(int studentId, Map<String, int> rubric, String notes) =>
      api.post('/students/$studentId/communication-review', {'rubric': rubric, 'notes': notes});

  Future<Map<String, dynamic>> aptitude(int studentId) async =>
      (await api.get('/students/$studentId/aptitude')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> startAptitude(int studentId) async =>
      (await api.post('/students/$studentId/aptitude/start')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> submitAptitude(int attemptId, Map<String, String> answers) async =>
      (await api.post('/aptitude/attempts/$attemptId/submit', {'answers': answers})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> prepPlan(int studentId, {int? careerId, int? hours}) async => (await api.get(
        '/students/$studentId/prep-plan',
        query: {if (careerId != null) 'career_id': careerId, if (hours != null) 'hours': hours},
      )) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> scoreHistory(int studentId) async => maps(await api.get('/students/$studentId/score-history'));

  Future<Map<String, dynamic>> insight(int studentId, {bool refresh = false}) async =>
      (await api.get('/students/$studentId/insight', query: refresh ? {'refresh': 'true'} : null)) as Map<String, dynamic>;

  /// Rows of a list in the profile, as maps.
  static List<Map<String, dynamic>> rows(dynamic v) => maps(v);
}

final talentApi = TalentApi();

const platforms = <String, String>{
  'leetcode': 'LeetCode',
  'hackerrank': 'HackerRank',
  'codechef': 'CodeChef',
  'codeforces': 'Codeforces',
  'geeksforgeeks': 'GeeksforGeeks',
  'hackerearth': 'HackerEarth',
  'other': 'Other',
};

const communicationCriteria = <String, String>{
  'speaking': 'Speaking',
  'writing': 'Writing',
  'listening': 'Listening',
  'teamwork': 'Teamwork',
};

const aptitudeSections = <String, String>{
  'quantitative': 'Quantitative',
  'logical': 'Logical reasoning',
  'verbal': 'Verbal',
};

const rubricCriteria = <String, String>{
  'readability': 'Readability',
  'structure': 'Structure',
  'testing': 'Testing',
  'documentation': 'Documentation',
};
