class FaceMatchResult {
  const FaceMatchResult({
    required this.matched,
    required this.cosineSimilarity,
    required this.euclideanDistance,
    required this.threshold,
  });

  final bool matched;
  final double cosineSimilarity;
  final double euclideanDistance;
  final double threshold;
}
