/// One recorded pose, and how to get there.
///
/// The angles are the whole of the arm's state - there is no easing, no
/// per-joint enable - so a step is just a pose with a name and a pace.
class ArmStep {
  const ArmStep({
    required this.id,
    required this.name,
    required this.angles,
    this.speed = 60,
    this.dwell = const Duration(milliseconds: 400),
  });

  /// Degrees per second, for every joint together. The firmware ramps at about
  /// 66 a second of its own accord, so anything faster than that is the arm's
  /// ceiling rather than this number.
  static const maxSpeed = 120;
  static const minSpeed = 5;

  final String id;
  final String name;
  final List<int> angles;
  final int speed;

  /// How long to hold this pose before the next step is started.
  final Duration dwell;

  ArmStep copyWith({String? name, List<int>? angles, int? speed, Duration? dwell}) =>
      ArmStep(
        id: id,
        name: name ?? this.name,
        angles: angles ?? this.angles,
        speed: speed ?? this.speed,
        dwell: dwell ?? this.dwell,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'angles': angles,
        'speed': speed,
        'dwell_ms': dwell.inMilliseconds,
      };

  static ArmStep fromJson(Map<String, Object?> json) => ArmStep(
        id: json['id'] as String? ?? newId(),
        name: json['name'] as String? ?? 'Step',
        angles: [
          for (final a in (json['angles'] as List<Object?>? ?? [])) a as int,
        ],
        speed: (json['speed'] as int? ?? 60).clamp(minSpeed, maxSpeed),
        dwell: Duration(milliseconds: json['dwell_ms'] as int? ?? 400),
      );

  /// Enough to tell two steps apart in a list; nothing depends on the shape.
  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

/// A named run of steps.
class ArmSequence {
  const ArmSequence({
    required this.id,
    required this.name,
    required this.steps,
    this.gap = const Duration(milliseconds: 500),
    this.loop = false,
  });

  final String id;
  final String name;
  final List<ArmStep> steps;

  /// Dead time between one step finishing its dwell and the next one starting.
  final Duration gap;

  final bool loop;

  ArmSequence copyWith({
    String? name,
    List<ArmStep>? steps,
    Duration? gap,
    bool? loop,
  }) =>
      ArmSequence(
        id: id,
        name: name ?? this.name,
        steps: steps ?? this.steps,
        gap: gap ?? this.gap,
        loop: loop ?? this.loop,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'gap_ms': gap.inMilliseconds,
        'loop': loop,
        'steps': [for (final s in steps) s.toJson()],
      };

  static ArmSequence fromJson(Map<String, Object?> json) => ArmSequence(
        id: json['id'] as String? ?? ArmStep.newId(),
        name: json['name'] as String? ?? 'Sequence',
        gap: Duration(milliseconds: json['gap_ms'] as int? ?? 500),
        loop: json['loop'] as bool? ?? false,
        steps: [
          for (final s in (json['steps'] as List<Object?>? ?? []))
            ArmStep.fromJson(s as Map<String, Object?>),
        ],
      );

  static ArmSequence empty() => ArmSequence(
        id: ArmStep.newId(),
        name: 'Sequence',
        steps: const [],
      );
}
