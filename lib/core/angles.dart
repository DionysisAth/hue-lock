import 'dart:math' as math;

const tau = math.pi * 2;

/// Wraps [a] into [0, tau).
double wrapAngle(double a) {
  final r = a % tau;
  return r < 0 ? r + tau : r;
}

/// Signed shortest difference `a - b`, in (-pi, pi].
double angleDiff(double a, double b) {
  var d = wrapAngle(a - b);
  if (d > math.pi) d -= tau;
  return d;
}

/// Distance travelled from [from] to [to] moving in direction [dir]
/// (+1 clockwise, -1 counter-clockwise), in [0, tau).
double travelDistance(double from, double to, int dir) =>
    wrapAngle(dir > 0 ? to - from : from - to);

/// Converts degrees to radians.
double deg(double degrees) => degrees * math.pi / 180;
