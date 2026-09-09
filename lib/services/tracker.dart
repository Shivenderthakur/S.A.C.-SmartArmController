import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/hand.dart';

enum TrackerStage { idle, needsPermission, starting, running, failed }

/// Owns the camera and the native MediaPipe bridge.
///
/// Per-frame results are [ValueNotifier]s rather than plain fields on a
/// [State]: rebuilding the widget tree at frame rate cost more than the
/// inference did.
class Tracker {
  Tracker(this.onAngles);

  static const _channel = MethodChannel('smartarm/hands');

  static const _rotations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final void Function(List<int>) onAngles;

  final hand = ValueNotifier<Hand?>(null);
  final fps = ValueNotifier<double>(0);
  final stage = ValueNotifier<TrackerStage>(TrackerStage.idle);
  final message = ValueNotifier<String>('starting…');
  final controller = ValueNotifier<CameraController?>(null);

  List<CameraDescription> _cameras = const [];
  int _index = 0;
  int _inFlight = 0;
  bool _disposed = false;

  final _stopwatch = Stopwatch()..start();
  int _framesSinceTick = 0;

  bool get isFrontFacing =>
      _cameras.isNotEmpty &&
      _cameras[_index].lensDirection == CameraLensDirection.front;
  bool get canFlip => _cameras.length > 1;

  Future<void> start() async {
    stage.value = TrackerStage.starting;

    final status = await Permission.camera.request();
    if (_disposed) return;
    if (!status.isGranted) {
      stage.value = TrackerStage.needsPermission;
      message.value = 'Camera access is required for hand tracking.';
      return;
    }

    try {
      await _channel.invokeMethod<bool>('start');
    } catch (e) {
      stage.value = TrackerStage.failed;
      message.value = 'Hand model failed to load: $e';
      return;
    }

    try {
      _cameras = await availableCameras();
    } catch (e) {
      stage.value = TrackerStage.failed;
      message.value = 'No camera available: $e';
      return;
    }
    if (_cameras.isEmpty) {
      stage.value = TrackerStage.failed;
      message.value = 'No camera found on this device.';
      return;
    }

    final front =
        _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _index = front == -1 ? 0 : front;
    await _open();
  }

  Future<void> _open() async {
    final cam = CameraController(
      _cameras[_index],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await cam.initialize();
      await cam.startImageStream(_onFrame);
    } catch (e) {
      stage.value = TrackerStage.failed;
      message.value = 'Camera error: $e';
      return;
    }
    if (_disposed) {
      await cam.dispose();
      return;
    }
    controller.value = cam;
    stage.value = TrackerStage.running;
    message.value = 'tracking';
  }

  Future<void> flip() async {
    if (!canFlip) return;
    final old = controller.value;
    controller.value = null;
    hand.value = null;
    _index = (_index + 1) % _cameras.length;
    await old?.dispose();
    if (_disposed) return;
    await _open();
  }

  Future<void> suspend() async {
    final cam = controller.value;
    if (cam == null) return;
    controller.value = null;
    hand.value = null;
    await cam.dispose();
  }

  Future<void> resume() async {
    if (_disposed || controller.value != null) return;
    if (stage.value == TrackerStage.needsPermission ||
        stage.value == TrackerStage.idle) {
      await start();
    } else if (_cameras.isNotEmpty) {
      await _open();
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    // Two frames in flight: the native worker is single-threaded, so the queued
    // frame starts converting the instant the previous one leaves MediaPipe
    // instead of after a full channel round trip.
    if (_inFlight >= 2 || _disposed) return;
    final cam = controller.value;
    if (cam == null || image.planes.length != 1) return;

    final description = _cameras[_index];
    final deviceRotation = _rotations[cam.value.deviceOrientation];
    if (deviceRotation == null) return;
    final rotation = description.lensDirection == CameraLensDirection.front
        ? (description.sensorOrientation + deviceRotation) % 360
        : (description.sensorOrientation - deviceRotation + 360) % 360;

    _inFlight++;
    try {
      final raw = await _channel.invokeMethod<Float64List>('detect', {
        'bytes': image.planes.first.bytes,
        'width': image.width,
        'height': image.height,
        'rotation': rotation,
      });
      if (_disposed) return;

      final found = raw == null ? null : Hand(raw);
      // The desktop script holds the last angles when the hand leaves frame.
      if (found != null) onAngles(landmarkToServoAngle(found));
      hand.value = found;

      _framesSinceTick++;
      final elapsed = _stopwatch.elapsedMilliseconds;
      if (elapsed >= 1000) {
        fps.value = _framesSinceTick * 1000 / elapsed;
        _framesSinceTick = 0;
        _stopwatch.reset();
      }
    } catch (e) {
      message.value = 'detect failed: $e';
    } finally {
      _inFlight--;
    }
  }

  void dispose() {
    _disposed = true;
    controller.value?.dispose();
    hand.dispose();
    fps.dispose();
    stage.dispose();
    message.dispose();
    controller.dispose();
  }
}
