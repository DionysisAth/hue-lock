import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../render/ball_skins.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import '../services/feedback.dart';
import 'widgets.dart';

/// Cosmetics bought with coins. Nothing here affects timing or difficulty.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return ListenableBuilder(
      listenable: s.profile,
      builder: (context, _) {
        final p = s.profile.profile;
        final theme = ringThemeById(p.theme);
        final palette = HuePalette.of(colorblind: p.colorblind);
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: theme.bgBottom,
            appBar: AppBar(
              backgroundColor: theme.bgTop,
              foregroundColor: theme.text,
              title: const Text(
                'SHOP',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: CoinCount(coins: p.coins, color: theme.text),
                ),
              ],
              bottom: TabBar(
                labelColor: theme.text,
                unselectedLabelColor: theme.subtleText,
                indicatorColor: theme.text,
                tabs: const [
                  Tab(text: 'BALLS'),
                  Tab(text: 'RINGS'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _grid(
                  context,
                  theme: theme,
                  items: [
                    for (final skin in ballSkins)
                      _ShopItem(
                        id: skin.id,
                        name: skin.name,
                        price: skin.price,
                        owned: p.ownedBalls.contains(skin.id),
                        equipped: p.ball == skin.id,
                        preview: _BallPreview(
                          skin: skin,
                          color: palette[ballSkins.indexOf(skin) % 4],
                        ),
                      ),
                  ],
                  onBuy: (id, price) => s.profile.update((p) {
                    p.coins -= price;
                    p.ownedBalls.add(id);
                    p.ball = id;
                  }),
                  onEquip: (id) => s.profile.update((p) => p.ball = id),
                ),
                _grid(
                  context,
                  theme: theme,
                  items: [
                    for (final t in ringThemes)
                      _ShopItem(
                        id: t.id,
                        name: t.name,
                        price: t.price,
                        owned: p.ownedThemes.contains(t.id),
                        equipped: p.theme == t.id,
                        preview: _ThemePreview(theme: t, palette: palette),
                      ),
                  ],
                  onBuy: (id, price) => s.profile.update((p) {
                    p.coins -= price;
                    p.ownedThemes.add(id);
                    p.theme = id;
                  }),
                  onEquip: (id) => s.profile.update((p) => p.theme = id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _grid(
    BuildContext context, {
    required RingTheme theme,
    required List<_ShopItem> items,
    required void Function(String id, int price) onBuy,
    required void Function(String id) onEquip,
  }) {
    final s = Services.of(context);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final coins = s.profile.profile.coins;
        final affordable = coins >= item.price;
        return Material(
          color: theme.text.withValues(alpha: item.equipped ? 0.16 : 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: item.equipped
                ? BorderSide(color: theme.text, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              if (item.owned) {
                s.audio.play(Sfx.ui);
                onEquip(item.id);
              } else if (affordable) {
                final ok = await _confirm(context, theme, item);
                if (ok) {
                  s.audio.play(Sfx.coin);
                  onBuy(item.id, item.price);
                  s.analytics.log('shop_buy', {
                    'item': item.id,
                    'price': item.price,
                  });
                }
              } else {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        'You need ${item.price - coins} more coins. '
                        'Play runs to earn them!',
                      ),
                    ),
                  );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(child: item.preview),
                  const SizedBox(height: 8),
                  Text(
                    item.name,
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 22,
                    child: item.equipped
                        ? Text('EQUIPPED', style: _tag(theme))
                        : item.owned
                        ? Text('OWNED', style: _tag(theme))
                        : Opacity(
                            opacity: affordable ? 1 : 0.5,
                            child: CoinCount(
                              coins: item.price,
                              color: theme.text,
                              size: 16,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _tag(RingTheme theme) => TextStyle(
    color: theme.subtleText,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
    fontSize: 13,
  );

  Future<bool> _confirm(
    BuildContext context,
    RingTheme theme,
    _ShopItem item,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Buy ${item.name}?'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Price: '),
                CoinCount(coins: item.price, color: Colors.white, size: 16),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Buy'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _ShopItem {
  const _ShopItem({
    required this.id,
    required this.name,
    required this.price,
    required this.owned,
    required this.equipped,
    required this.preview,
  });

  final String id;
  final String name;
  final int price;
  final bool owned;
  final bool equipped;
  final Widget preview;
}

class _BallPreview extends StatefulWidget {
  const _BallPreview({required this.skin, required this.color});

  final BallSkin skin;
  final Color color;

  @override
  State<_BallPreview> createState() => _BallPreviewState();
}

class _BallPreviewState extends State<_BallPreview>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _BallPainter(widget.skin, widget.color, _anim),
    );
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter(this.skin, this.color, this.anim) : super(repaint: anim);

  final BallSkin skin;
  final Color color;
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) * 0.3;
    skin.paint(canvas, size.center(Offset.zero), r, color, anim.value * 60);
  }

  @override
  bool shouldRepaint(_BallPainter old) =>
      old.skin != skin || old.color != color;
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.theme, required this.palette});

  final RingTheme theme;
  final HuePalette palette;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        size: Size.infinite,
        painter: _ThemePainter(theme, palette),
      ),
    );
  }
}

class _ThemePainter extends CustomPainter {
  _ThemePainter(this.theme, this.palette);

  final RingTheme theme;
  final HuePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.bgTop, theme.bgBottom],
        ).createShader(rect),
    );
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * 0.32;
    final w = r * theme.ringWidth * 1.4;
    final ring = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = theme.ringNeutral,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(
        ring,
        -math.pi / 2 + i * 2.1,
        0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = palette[i],
      );
    }
    canvas.drawLine(
      c + Offset(0, -r - w),
      c + Offset(0, -r + w),
      Paint()
        ..strokeWidth = w * 0.35
        ..strokeCap = StrokeCap.round
        ..color = theme.pointer,
    );
    canvas.drawCircle(c, r * 0.3, Paint()..color = palette[1]);
  }

  @override
  bool shouldRepaint(_ThemePainter old) =>
      old.theme != theme || old.palette != palette;
}
