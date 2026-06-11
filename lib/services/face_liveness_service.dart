import 'dart:math' as math;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum FaceLivenessPrompt { blink, turnHeadLeft, turnHeadRight }

class FaceLivenessResult {
  const FaceLivenessResult({
    required this.passed,
    required this.prompt,
    required this.message,
  });

  final bool passed;
  final FaceLivenessPrompt prompt;
  final String message;
}

class FaceLivenessService {
  FaceLivenessService({FaceLivenessPrompt? prompt})
    : prompt = prompt ?? _randomPrompt();

  final FaceLivenessPrompt prompt;
  bool _seenEyesOpen = false;
  bool _passed = false;

  String get promptText {
    switch (prompt) {
      case FaceLivenessPrompt.blink:
        return 'Blink once';
      case FaceLivenessPrompt.turnHeadLeft:
        return 'Turn head left';
      case FaceLivenessPrompt.turnHeadRight:
        return 'Turn head right';
    }
  }

  FaceLivenessResult update(Face face) {
    if (_passed) {
      return FaceLivenessResult(
        passed: true,
        prompt: prompt,
        message: 'Liveness passed.',
      );
    }

    switch (prompt) {
      case FaceLivenessPrompt.blink:
        return _updateBlink(face);
      case FaceLivenessPrompt.turnHeadLeft:
        return _updateTurn(face, left: true);
      case FaceLivenessPrompt.turnHeadRight:
        return _updateTurn(face, left: false);
    }
  }

  FaceLivenessResult fail(String reason) {
    return FaceLivenessResult(passed: false, prompt: prompt, message: reason);
  }

  FaceLivenessResult _updateBlink(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null || right == null) {
      return const FaceLivenessResult(
        passed: false,
        prompt: FaceLivenessPrompt.blink,
        message: 'Blink detection unavailable. Keep your face well lit.',
      );
    }
    final eyeOpen = (left + right) / 2;
    if (eyeOpen > 0.68) _seenEyesOpen = true;
    if (_seenEyesOpen && eyeOpen < 0.36) _passed = true;
    return FaceLivenessResult(
      passed: _passed,
      prompt: prompt,
      message: _passed ? 'Liveness passed.' : 'Blink once to continue.',
    );
  }

  FaceLivenessResult _updateTurn(Face face, {required bool left}) {
    final yaw = face.headEulerAngleY ?? 0;
    final passed = left ? yaw > 12 : yaw < -12;
    if (passed) _passed = true;
    return FaceLivenessResult(
      passed: _passed,
      prompt: prompt,
      message: _passed
          ? 'Liveness passed.'
          : left
          ? 'Turn your head left.'
          : 'Turn your head right.',
    );
  }

  static FaceLivenessPrompt _randomPrompt() {
    const prompts = FaceLivenessPrompt.values;
    return prompts[math.Random().nextInt(prompts.length)];
  }
}
