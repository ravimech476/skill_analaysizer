import 'package:dio/dio.dart';

import 'client.dart';
import 'models.dart';

/// Document types the knowledge base accepts, with the label shown to people.
const kbDocTypes = <String, String>{
  'syllabus': 'Syllabus',
  'notes': 'Notes',
  'question_paper': 'Question paper',
  'placement': 'Placement',
  'resume': 'Resume tips',
  'roadmap': 'Career roadmap',
  'other': 'Other',
};

/// Documents the AI assistant can answer from.
class KbApi {
  Future<List<Map<String, dynamic>>> list() async => maps(await api.get('/kb/documents'));

  Future<Map<String, dynamic>> upload(MultipartFile file, {required String docType, String? title, int? departmentId, int? subjectId}) async =>
      (await api.upload('/kb/documents', 'file', file, fields: {
        'doc_type': docType,
        'title': title,
        'department_id': departmentId,
        'subject_id': subjectId,
      })) as Map<String, dynamic>;

  Future<void> remove(int id) => api.delete('/kb/documents/$id');

  Future<List<Map<String, dynamic>>> search(String query) async =>
      maps(await api.post('/kb/search', {'query': query}, const Duration(minutes: 1)));
}

/// Skill levels the marks support (to accept or dismiss) and AI-proposed subject mappings.
class SkillSuggestApi {
  Future<List<Map<String, dynamic>>> pending(int studentId) async => maps(await api.get('/students/$studentId/skill-suggestions'));

  Future<Map<String, dynamic>> generate(int studentId) async =>
      (await api.post('/students/$studentId/skill-suggestions/generate')) as Map<String, dynamic>;

  Future<void> accept(int id) => api.post('/skill-suggestions/$id/accept');
  Future<void> dismiss(int id) => api.post('/skill-suggestions/$id/dismiss');

  Future<Map<String, dynamic>> suggestMapping(int subjectId) async =>
      (await api.post('/subjects/$subjectId/skill-mapping/suggest', null, const Duration(minutes: 2))) as Map<String, dynamic>;
}

final kbApi = KbApi();
final skillSuggestApi = SkillSuggestApi();
