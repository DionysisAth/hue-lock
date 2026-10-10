import 'game_engine.dart';

enum GoalType { perfects, streak, ratio, greedy, fevers, powerUps, shield }

/// One star challenge of a level ("Hit 5 Perfects", "Finish with a shield").
/// Clearing a level is the first star; each goal met is one more.
class StarGoal {
  const StarGoal(this.type, [this.target = 1]);

  /// "perfects:5", "streak:4", "ratio:60", "greedy:2", "fevers:1",
  /// "powerUps:2" or "shield".
  factory StarGoal.parse(String source) {
    final parts = source.split(':');
    final type = GoalType.values.firstWhere(
      (t) => t.name == parts.first,
      orElse: () => throw FormatException('Unknown star goal: $source'),
    );
    return StarGoal(type, parts.length > 1 ? int.parse(parts[1]) : 1);
  }

  final GoalType type;
  final int target;

  String get text => switch (type) {
    GoalType.perfects => 'Hit $target Perfects',
    GoalType.streak => '$target Perfects in a row',
    GoalType.ratio => '$target% Perfect hits',
    GoalType.greedy =>
      target == 1 ? 'Hit a gold zone' : 'Hit $target gold zones',
    GoalType.fevers =>
      target == 1 ? 'Trigger Fever' : 'Trigger Fever $target times',
    GoalType.powerUps =>
      target == 1 ? 'Collect a power-up' : 'Collect $target power-ups',
    GoalType.shield => 'Finish with a shield',
  };

  /// A few words for the in-run HUD.
  String get shortText => switch (type) {
    GoalType.perfects => 'PERFECTS',
    GoalType.streak => 'IN A ROW',
    GoalType.ratio => 'PERFECT %',
    GoalType.greedy => 'GOLD',
    GoalType.fevers => 'FEVER',
    GoalType.powerUps => 'POWER-UPS',
    GoalType.shield => 'SHIELD',
  };

  /// Progress so far in [s] (compare with [target]).
  int value(RunSummary s) => switch (type) {
    GoalType.perfects => s.perfects,
    GoalType.streak => s.bestPerfectStreak,
    GoalType.ratio => (s.perfectRatio * 100).floor(),
    GoalType.greedy => s.greedyHits,
    GoalType.fevers => s.fevers,
    GoalType.powerUps => s.powerUps,
    GoalType.shield => s.shieldLeft ? 1 : 0,
  };

  bool met(RunSummary s) => value(s) >= target;

  @override
  String toString() =>
      type == GoalType.shield ? type.name : '${type.name}:$target';
}

/// Bit 0 = level cleared, bit i+1 = goal i met.
int goalMask(RunSummary s, List<StarGoal> goals) {
  if (!s.completed) return 0;
  var mask = 1;
  for (var i = 0; i < goals.length; i++) {
    if (goals[i].met(s)) mask |= 1 << (i + 1);
  }
  return mask;
}

int starCount(int mask) {
  var n = 0;
  for (var m = mask; m > 0; m >>= 1) {
    n += m & 1;
  }
  return n;
}
