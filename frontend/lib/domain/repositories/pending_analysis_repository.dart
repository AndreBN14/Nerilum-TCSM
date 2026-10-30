import '../models/pending_analysis.dart';
import '../models/selected_image.dart';

abstract class PendingAnalysisRepository {
  Future<PendingAnalysis> enqueue(String ownerId, SelectedImage image);
  Future<List<PendingAnalysis>> list(String ownerId);
  Future<PendingAnalysis?> find(String ownerId, String id);
  Future<SelectedImage> image(String ownerId, String id);
  Future<void> discard(String ownerId, String id);
  Future<void> resetPreview(String ownerId, String id);
  Future<void> releaseExpiredSave(String ownerId, String id);
  Future<void> beginSave(
    String ownerId,
    String id, {
    required String previewId,
    required String proof,
    required DateTime expiresAt,
    required String name,
  });
  Future<void> complete(String ownerId, String id);
}
