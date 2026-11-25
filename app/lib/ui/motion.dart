import 'package:flutter/widgets.dart';
import 'dart:math' as math;

/// Motion that follows the finger and carries on from it (the way Apple's fluid interfaces do): a spring that keeps the
/// velocity of the release, the place a flick would come to rest, and a soft edge that resists more the further it is
/// pulled.

/// Set from the system's "remove animations": the swipes and slides then just happen.
bool reduceMotionNow = false;

/// Set by the shell: the VPN is off, so the moving backgrounds stand still (and the screen is grey, see [GreyWhenOff]).
bool backdropFrozenNow = false;

/// Set by the shell: runs [change] in the middle of the screen's own motion (the screen goes away, [change] is made
/// while it cannot be seen, the screen comes back as it now is). While [work] goes on (the core being restarted, at most
/// ten seconds) the screen stays away and a ring turns in its place. Used to go in and out of Superlight.
Future<void> Function(void Function() change, {Future<void> Function()? work})?
swapMotion;

/// One motion for everything that opens over the screen (pages, sheets, dialogs), so that nothing is quicker or slower
/// than the rest: the same time and the same curve in and out.
const kOpenMotion = Duration(milliseconds: 380);
const kCloseMotion = Duration(milliseconds: 340);

/// The pages of the settings take a little longer than the sheets: they are big, and the step of a frame is the smaller the longer
/// the slide is, so a frame that comes late is not seen
const kPageOpenMotion = Duration(milliseconds: 520);
const kPageCloseMotion = Duration(milliseconds: 440);
const kOpenCurve = Cubic(0.32, 0.72, 0, 1);
const kCloseCurve = Cubic(0.4, 0, 0.6, 1);

/// The page that is open comes from above (the settings from the home screen), not from the right: the screen under it
/// moves down a little instead of left.
bool pageFromTop = false;

/// A tick on the finger's choices (the Feedback setting).
bool hapticsNow = true;

/// A spring of Apple's two parameters: the damping ratio (1: no overshoot, below 1: it swings past) and the response,
/// in seconds (how quickly it comes to its place; not a duration).
SpringDescription fluidSpring({double damping = 1, double response = .4}) {
  const mass = 1.0;
  final stiffness = math.pow(2 * math.pi / response, 2).toDouble();
  return SpringDescription(
    mass: mass,
    stiffness: stiffness,
    damping: 4 * math.pi * damping * mass / response,
  );
}

/// Where a flick of [velocity] (pixels a second) would come to rest, as the scroll's own slowing down: the distance it
/// still travels beyond the release point. [rate] is how slowly it slows (.998 the scroll's, lower is snappier).
double projectedTravel(double velocity, {double rate = .996}) =>
    (velocity / 1000) * rate / (1 - rate);

/// A pull of [overshoot] past an edge, as far as it shows ([dimension]: the size it is pulled across): the further past,
/// the less it follows, so it never stops dead.
double rubberBand(double overshoot, double dimension, {double constant = .55}) {
  final over = overshoot.abs();
  final shown = (over * dimension * constant) / (dimension + constant * over);
  return overshoot < 0 ? -shown : shown;
}

/// While [frozen], [child] is shown as a picture of itself taken once (a fading, scaling page drawn anew at every frame
/// of its motion cost 12 to 20 ms a frame: the motion ran at 50 frames a second instead of 120). At rest it is the live
/// child. The wrapping stays the same either way, so nothing is built anew when the motion begins or ends.
class Frozen extends StatefulWidget {
  const Frozen({super.key, required this.frozen, required this.child});

  final bool frozen;
  final Widget child;

  @override
  State<Frozen> createState() => _FrozenState();
}

class _FrozenState extends State<Frozen> {
  late final _controller = SnapshotController(allowSnapshotting: widget.frozen);

  @override
  void didUpdateWidget(Frozen old) {
    super.didUpdateWidget(old);
    _controller.allowSnapshotting = widget.frozen;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _controller,
    mode: SnapshotMode.permissive,
    autoresize: true,
    child: widget.child,
  );
}
