import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/joint.dart';

/// Why a pin could not be taken.
enum AssignResult { ok, taken, notAllowed }

/// The arm's shape: how many joints it has, what they are called and which pin
/// each one drives.
///
/// Deliberately not part of [AppSettings]: every change there re-pushes the
/// link settings, and dragging a joint across pins would tear the socket down
/// on every frame of the drag.
class JointConfig extends ChangeNotifier {
  JointConfig._(this._prefs, this._joints);

  static const _key = 'joints_v1';

  final SharedPreferences _prefs;
  final List<Joint> _joints;

  static Future<JointConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return JointConfig._(prefs, _read(prefs));
  }

  @visibleForTesting
  static JointConfig forTest(SharedPreferences prefs) =>
      JointConfig._(prefs, _read(prefs));

  static List<Joint> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return List<Joint>.of(defaultJoints);
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final list = (decoded['joints'] as List<Object?>? ?? [])
          .map((e) => Joint.fromJson(e as Map<String, Object?>))
          .toList();
      return list.isEmpty ? List<Joint>.of(defaultJoints) : list;
    } catch (_) {
      // Anything unreadable - half-written, hand-edited, or from a future
      // version - is not worth failing a launch over.
      return List<Joint>.of(defaultJoints);
    }
  }

  List<Joint> get joints => List<Joint>.unmodifiable(_joints);

  /// How many joints there are - one slider, one recorded angle each.
  int get channels => _joints.length;

  /// The joints that make up the arm itself, which is what a DOF count means.
  /// The gripper on the end is not one of them.
  int get armJoints => _joints.where((j) => !j.isGripper).length;

  bool get hasGripper => _joints.any((j) => j.isGripper);

  /// How many servos those joints drive. A claw is two.
  int get servos => channels + _joints.where((j) => j.twoServos).length;

  /// The pin per wire channel, in channel order: every joint first, then the
  /// second servo of each mirrored joint, in joint order.
  ///
  /// That ordering is the whole contract with the board - it is told this map,
  /// and every command is numbered against it.
  List<int> get pinMap => [
        for (final j in _joints) j.gpio,
        for (final j in _joints)
          if (j.twoServos) j.mirrorGpio,
      ];

  List<int> get restPose => _joints.map((j) => j.rest).toList();

  /// One angle per joint becomes one angle per servo: the mirrored half of a
  /// claw closes toward the first, so it is given the opposite angle on a
  /// channel of its own.
  List<int> wireAngles(List<int> angles) => [
        ...angles,
        for (var i = 0; i < _joints.length && i < angles.length; i++)
          if (_joints[i].twoServos) 180 - angles[i],
      ];

  /// Tracking yields three joints and a claw and nothing more, so a larger arm
  /// cannot be driven by the camera at all.
  bool get trackingUsable => _joints.length <= 4;

  /// Which joint a pin belongs to, or null if it is free. A joint's second
  /// servo counts: two things cannot drive one pin.
  int? ownerOf(int gpio) {
    for (var i = 0; i < _joints.length; i++) {
      final j = _joints[i];
      if (j.gpio == gpio || (j.twoServos && j.mirrorGpio == gpio)) return i;
    }
    return null;
  }

  /// Whether [gpio] is the second servo of the joint that owns it.
  bool isMirrorPin(int gpio) =>
      _joints.any((j) => j.twoServos && j.mirrorGpio == gpio);

  /// Give a joint a second servo, or take it away. Turning it off unwires the
  /// pin with it; turning it on leaves the pin to be assigned, exactly like a
  /// joint that has never been wired.
  void setTwoServos(int channel, bool on) {
    if (_joints[channel].twoServos == on) return;
    _joints[channel] = _joints[channel].copyWith(
      twoServos: on,
      mirrorGpio: Joint.unassigned,
    );
    _save();
  }

  AssignResult assign(int channel, int gpio, {bool mirror = false}) {
    if (!allowedPins.contains(gpio)) return AssignResult.notAllowed;

    // One pin, one servo - and a joint's two halves are two servos, so a claw
    // cannot put both of its own on the same pin either. Re-assigning a pin to
    // the slot that already holds it is the one harmless case.
    final owner = ownerOf(gpio);
    final alreadyHere = owner == channel && isMirrorPin(gpio) == mirror;
    if (owner != null && !alreadyHere) return AssignResult.taken;

    // Wiring a second servo is also declaring there is one.
    _joints[channel] = mirror
        ? _joints[channel].copyWith(twoServos: true, mirrorGpio: gpio)
        : _joints[channel].copyWith(gpio: gpio);
    _save();
    return AssignResult.ok;
  }

  void unassign(int channel, {bool mirror = false}) {
    final joint = _joints[channel];
    if (mirror ? !joint.mirrorAssigned : !joint.assigned) return;

    _joints[channel] = mirror
        ? joint.copyWith(mirrorGpio: Joint.unassigned)
        : joint.copyWith(gpio: Joint.unassigned);
    _save();
  }

  void rename(int channel, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _joints[channel].name) return;
    _joints[channel] = _joints[channel].copyWith(name: trimmed);
    _save();
  }

  /// Sets how many joints the arm has, keeping the ones that survive exactly as
  /// they were — resizing is not a reason to lose someone's pin assignments.
  ///
  /// The gripper is never one of them. Asking for three joints gives three and
  /// the gripper still on the end, because dropping the thing that grips is
  /// never what "fewer joints" meant.
  void resize(int count) {
    final gripper = _joints.where((j) => j.isGripper).toList();
    final arm = _joints.where((j) => !j.isGripper).toList();
    final wanted = count.clamp(1, maxJoints - gripper.length);
    if (wanted == arm.length) return;

    if (wanted < arm.length) {
      arm.removeRange(wanted, arm.length);
    } else {
      for (var i = arm.length; i < wanted; i++) {
        final free = allowedPins.firstWhere(
          (p) => _ownerIn([...arm, ...gripper], p) == null,
          orElse: () => Joint.unassigned,
        );
        arm.add(spareJoint(i).copyWith(gpio: free));
      }
    }

    _joints
      ..clear()
      ..addAll(arm)
      ..addAll(gripper);
    _save();
  }

  int? _ownerIn(List<Joint> joints, int gpio) {
    for (var i = 0; i < joints.length; i++) {
      final j = joints[i];
      if (j.gpio == gpio || (j.twoServos && j.mirrorGpio == gpio)) return i;
    }
    return null;
  }

  void _save() {
    _prefs.setString(
      _key,
      jsonEncode({'v': 1, 'joints': _joints.map((j) => j.toJson()).toList()}),
    );
    notifyListeners();
  }
}
