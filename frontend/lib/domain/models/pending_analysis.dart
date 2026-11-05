class PendingAnalysis {
  const PendingAnalysis({
    required this.id,
    required this.ownerId,
    required this.filename,
    required this.extension,
    required this.createdAt,
    required this.status,
    this.previewId,
    this.saveProof,
    this.proofExpiresAt,
    this.displayName,
  });

  final String id;
  final String ownerId;
  final String filename;
  final String extension;
  final DateTime createdAt;
  final String status;
  final String? previewId;
  final String? saveProof;
  final DateTime? proofExpiresAt;
  final String? displayName;
}
