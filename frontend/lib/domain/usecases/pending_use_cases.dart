import '../models/pending_analysis.dart';
import '../models/selected_image.dart';
import '../repositories/pending_analysis_repository.dart';

class ListPending {
  const ListPending(this.repository);
  final PendingAnalysisRepository repository;
  Future<List<PendingAnalysis>> call(String ownerId) =>
      repository.list(ownerId);
}

class EnqueuePending {
  const EnqueuePending(this.repository);
  final PendingAnalysisRepository repository;
  Future<PendingAnalysis> call(String ownerId, SelectedImage image) =>
      repository.enqueue(ownerId, image);
}

class FindPending {
  const FindPending(this.repository);
  final PendingAnalysisRepository repository;
  Future<PendingAnalysis?> call(String ownerId, String id) =>
      repository.find(ownerId, id);
}

class GetPendingImage {
  const GetPendingImage(this.repository);
  final PendingAnalysisRepository repository;
  Future<SelectedImage> call(String ownerId, String id) =>
      repository.image(ownerId, id);
}

class DiscardPending {
  const DiscardPending(this.repository);
  final PendingAnalysisRepository repository;
  Future<void> call(String ownerId, String id) =>
      repository.discard(ownerId, id);
}

class BeginPendingSave {
  const BeginPendingSave(this.repository);
  final PendingAnalysisRepository repository;
  Future<void> call(
    String ownerId,
    String id, {
    required String previewId,
    required String proof,
    required DateTime expiresAt,
    required String name,
  }) => repository.beginSave(
        ownerId,
        id,
        previewId: previewId,
        proof: proof,
        expiresAt: expiresAt,
        name: name,
      );
}

class CompletePendingSave {
  const CompletePendingSave(this.repository);
  final PendingAnalysisRepository repository;
  Future<void> call(String ownerId, String id) =>
      repository.complete(ownerId, id);
}

class ReleaseExpiredPendingSave {
  const ReleaseExpiredPendingSave(this.repository);
  final PendingAnalysisRepository repository;
  Future<void> call(String ownerId, String id) =>
      repository.releaseExpiredSave(ownerId, id);
}
