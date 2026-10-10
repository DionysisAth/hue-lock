import '../core/seeded_random.dart';

/// Run perks: after every boss round the player picks one of three. They
/// last until the run ends (a continue keeps them).
enum Perk {
  steady('Steady Hand', 'Perfect window 35% wider', maxStacks: 2),
  shield('Shield', 'Absorbs your next miss', maxStacks: 99),
  chill('Chill', 'Pointer 8% slower', maxStacks: 2),
  wide('Wide Zones', 'All zones 12% wider', maxStacks: 2),
  magnet('Coin Magnet', '+50% coins this run', maxStacks: 2),
  quick('Quick Combo', 'Combo grows every 2 Perfects, not 3', maxStacks: 1),
  keeper('Combo Saver', 'A Good only drops your combo one step', maxStacks: 1),
  greed('Greed', '+50% points, but zones 10% smaller', maxStacks: 2);

  const Perk(this.title, this.description, {required this.maxStacks});

  final String title;
  final String description;
  final int maxStacks;
}

/// The perks a run has picked, with stack counts.
class PerkSet {
  final _counts = <Perk, int>{};

  int operator [](Perk p) => _counts[p] ?? 0;

  bool get isEmpty => _counts.isEmpty;

  /// Picked perks in the order of [Perk.values], with their counts.
  Iterable<(Perk, int)> get entries => [
    for (final p in Perk.values)
      if (this[p] > 0) (p, this[p]),
  ];

  void add(Perk p) => _counts[p] = this[p] + 1;
  void clear() => _counts.clear();

  /// Multiplier on the Perfect window.
  double get perfectScale => 1 + 0.35 * this[Perk.steady];

  /// Multiplier on the pointer speed.
  double get speedScale => 1 - 0.08 * this[Perk.chill];

  /// Multiplier on zone sizes.
  double get sizeScale =>
      (1 + 0.12 * this[Perk.wide]) * (1 - 0.1 * this[Perk.greed]);

  double get pointsScale => 1 + 0.5 * this[Perk.greed];
  double get coinScale => 1 + 0.5 * this[Perk.magnet];

  /// Perfects in a row per combo step, never below 2.
  int comboStep(int base) =>
      this[Perk.quick] > 0 ? (base - 1).clamp(2, base) : base;

  /// Three different perks to choose from (fewer if most are maxed out),
  /// the same for everyone with the same [seed] and boss count.
  List<Perk> offer(int seed, int bossNumber, {required bool hasShield}) {
    final rng = SeededRandom(seed ^ (bossNumber * 0x9E3779B1));
    final pool = [
      for (final p in Perk.values)
        if (this[p] < p.maxStacks && !(p == Perk.shield && hasShield)) p,
    ];
    final out = <Perk>[];
    while (out.length < 3 && pool.isNotEmpty) {
      out.add(pool.removeAt(rng.nextInt(pool.length)));
    }
    return out;
  }
}
