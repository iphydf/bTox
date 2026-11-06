import 'dart:typed_data';

import 'package:toxcore/tox.dart';
import 'package:toxcore/tox_av.dart';

final class FakeToxAv extends ToxAv {
  final events = <AvEvent>[];

  /// (friend number, audio bit rate), for calls and answers.
  final calls = <(int, int)>[];
  final answers = <(int, int)>[];
  final controls = <(int, AvCallControl)>[];
  final frames = <(int, Int16List)>[];
  final videoBitRates = <(int, int)>[];
  final videoFrames = <(int, int, int)>[];
  ApiException? error;

  void _check() {
    if (error case final error?) {
      throw error;
    }
  }

  @override
  List<AvEvent> iterate() {
    final iterated = [...events];
    events.clear();
    return iterated;
  }

  @override
  int iterationInterval() => 20;

  @override
  void call(
    FriendNumber friendNumber,
    AvBitRate audioBitRate,
    AvBitRate videoBitRate,
  ) {
    _check();
    calls.add((friendNumber.value, audioBitRate.value));
  }

  @override
  void answer(
    FriendNumber friendNumber,
    AvBitRate audioBitRate,
    AvBitRate videoBitRate,
  ) => answers.add((friendNumber.value, audioBitRate.value));

  @override
  void callControl(FriendNumber friendNumber, AvCallControl control) {
    _check();
    controls.add((friendNumber.value, control));
  }

  @override
  void audioSendFrame(
    FriendNumber friendNumber,
    Int16List pcm,
    int sampleCount,
    AvChannels channels,
    AvSamplingRate samplingRate,
  ) {
    _check();
    frames.add((friendNumber.value, pcm));
  }

  @override
  void videoSendFrame(
    FriendNumber friendNumber,
    AvWidth width,
    AvHeight height,
    Uint8List y,
    Uint8List u,
    Uint8List v,
  ) {
    _check();
    videoFrames.add((friendNumber.value, width.value, height.value));
  }

  @override
  void videoSetBitRate(FriendNumber friendNumber, AvBitRate bitRate) {
    _check();
    videoBitRates.add((friendNumber.value, bitRate.value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
