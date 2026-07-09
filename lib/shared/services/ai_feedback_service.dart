import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';

class AiFeedbackService {
  bool get cloudReady =>
      AppConfig.hasRealSupabase &&
      InRangeSupabase.clientOrNull?.auth.currentUser != null;

  Future<int> submitFeedback({
    int? eventId,
    String feedbackType = 'quality',
    int? rating,
    String? label,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    if (!cloudReady) {
      throw StateError('Cloud feedback unavailable');
    }
    final id = await InRangeSupabase.client.rpc('submit_ai_feedback', params: {
      'p_event_id': eventId,
      'p_feedback_type': feedbackType,
      'p_rating': rating,
      'p_label': label,
      'p_notes': notes,
      'p_metadata': metadata ?? const <String, dynamic>{},
    });
    final parsed = id is int ? id : int.tryParse('$id');
    if (parsed == null) {
      throw StateError('submit_ai_feedback returned no id');
    }
    return parsed;
  }
}
