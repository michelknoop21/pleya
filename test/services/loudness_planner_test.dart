import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/loudness_evidence.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/services/loudness/loudness_planner.dart';

double? programmeGainDb(LoudnessEvidence? evidence) => planProgrammeGain(evidence)?.gainDb;

LoudnessEvidence _scan(
  double? lufs, {
  double? peak = -20,
  int version = 1,
  String basis = LoudnessPolicy.clientBasis,
  LoudnessQuality quality = LoudnessQuality.measuredFull,
  bool complete = true,
  LoudnessSource source = LoudnessSource.serverScan,
}) => LoudnessEvidence(
  source: source,
  method: 'ffmpeg-loudnorm-1',
  methodVersion: version,
  integratedLufs: lufs,
  truePeakDbtp: peak,
  quality: quality,
  coverageComplete: complete,
  basis: basis,
);

void main() {
  // DEC-111 (6): plan() in prove.sh judges the proof, so it has to plan what
  // Dart and LoudnessDsp.planGainDb plan. measure.sh reports a missing true
  // peak as TP=nan, which is the null here.
  group('prove.sh plan() agrees with planProgrammeGain', () {
    const cases = <(double, double?, String, double)>[
      (-30, null, '', 0),
      (-30, null, 'nan', 0),
      (-30, null, 'NaN', 0),
      (-18, null, 'nan', -4),
      (-30, -20, '-20', 8),
      (-30, -0.5, '-0.5', 4.5),
      (-40, -30, '-30', 12),
    ];
    for (final (lufs, peak, tp, want) in cases) {
      test('I=$lufs TP="$tp" -> $want dB', () async {
        final r = await Process.run('bash', ['scripts/loudness/prove.sh', '--plan', '$lufs', tp]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        final shell = double.parse((r.stdout as String).trim().split(' ').first);
        expect(shell, closeTo(want, 0.005), reason: 'prove.sh');
        expect(programmeGainDb(_scan(lufs, peak: peak)), closeTo(want, 1e-9), reason: 'Dart');
      });
    }
  });

  group('programme gain', () {
    test('lands the programme on -22', () {
      expect(programmeGainDb(_scan(-30)), 8.0);
      expect(programmeGainDb(_scan(-18)), -4.0);
      expect(programmeGainDb(_scan(-22)), 0.0);
    });

    test('caps the boost at +12 and the cut at -30', () {
      expect(programmeGainDb(_scan(-40)), 12.0);
      expect(programmeGainDb(_scan(10, peak: 2)), -30.0);
    });

    test('gives way when the limiter would work more than 6 dB', () {
      // -30 LUFS with a true peak of -0,5: +8 would put the peak 9,5 dB over
      // the -2 ceiling, so the gain drops by 3,5 and the load ends at 6.
      final gain = programmeGainDb(_scan(-30, peak: -0.5))!;
      expect(gain, closeTo(4.5, 1e-9));
      expect((-0.5 + gain) - LoudnessPolicy.ceilingDbtp, closeTo(6, 1e-9));
    });

    test('DEC-111 (6): a positive gain without true peak is capped at 0 dB', () {
      // -30 LUFS wants +8 dB, but there's no true peak to vouch for the limiter load.
      expect(programmeGainDb(_scan(-30, peak: null)), 0.0);
      // Negative gain needs no true peak backstop and passes through unchanged.
      expect(programmeGainDb(_scan(-18, peak: null)), -4.0);
    });

    test('the plan names what held the gain down', () {
      expect(planProgrammeGain(_scan(-30))!.limit, ProgrammeGainLimit.none);
      expect(planProgrammeGain(_scan(-30, peak: -0.5))!.limit, ProgrammeGainLimit.truePeakLoad);
      expect(planProgrammeGain(_scan(-30, peak: null))!.limit, ProgrammeGainLimit.missingTruePeak);
      expect(planProgrammeGain(_scan(-18, peak: null))!.limit, ProgrammeGainLimit.none, reason: 'a cut needs no peak');

      final capped = planLoudness(const AudioLoudness(levelVolume: true), _scan(-30, peak: null));
      expect(capped.programmeGainDb, 0.0);
      expect(capped.gainLimit, ProgrammeGainLimit.missingTruePeak);
      expect(capped.toString(), contains('limit: missingTruePeak'));
      final off = planLoudness(const AudioLoudness(reduceLoudSounds: true), _scan(-30, peak: null));
      expect(off.gainLimit, ProgrammeGainLimit.none, reason: 'no levelling, no gain, nothing held down');
    });

    test('a tag without a peak still gets its gain', () {
      const opus = LoudnessEvidence(
        source: LoudnessSource.opusR128,
        method: 'tag-opus-r128-1',
        methodVersion: 1,
        gainDb: -3,
        referenceLufs: -23,
        quality: LoudnessQuality.tagTrusted,
        coverageComplete: true,
        basis: LoudnessPolicy.clientBasis,
      );
      // -23 reference minus a -3 dB gain: the programme sits at -20.
      expect(programmeGainDb(opus), -2.0);
    });

    test('refuses anything it cannot vouch for', () {
      expect(programmeGainDb(null), isNull);
      expect(programmeGainDb(_scan(double.nan)), isNull);
      expect(programmeGainDb(_scan(double.infinity)), isNull);
      expect(programmeGainDb(_scan(null)), isNull);
      expect(programmeGainDb(_scan(-70)), isNull, reason: 'silence');
      expect(programmeGainDb(_scan(-20, peak: 3.5)), isNull, reason: 'impossible peak');
      expect(programmeGainDb(_scan(-20, peak: double.nan)), isNull);
      expect(programmeGainDb(_scan(-20, version: 2)), isNull, reason: 'unknown method version');
      expect(programmeGainDb(_scan(-20, basis: 'pcm-native-tl31-drc1')), isNull, reason: 'other decode basis');
      expect(programmeGainDb(_scan(-20, complete: false)), isNull, reason: 'partial coverage');
      expect(programmeGainDb(_scan(-20, quality: LoudnessQuality.tagHint)), isNull, reason: 'ReplayGain stays a hint');
      expect(programmeGainDb(_scan(-20, quality: LoudnessQuality.estimated)), isNull);
      expect(programmeGainDb(_scan(-20, source: LoudnessSource.realtimeEstimator)), isNull);
    });
  });

  group('planLoudness', () {
    test('carries the gain only while levelling is on', () {
      final on = planLoudness(const AudioLoudness(levelVolume: true), _scan(-30));
      expect(on.mode, LoudnessMode.programme);
      expect(on.programmeGainDb, 8.0);

      final off = planLoudness(const AudioLoudness(reduceLoudSounds: true), _scan(-30));
      expect(off.programmeGainDb, isNull);
    });

    test('falls back to realtime without usable evidence', () {
      final plan = planLoudness(const AudioLoudness(levelVolume: true), _scan(-70));
      expect(plan.mode, LoudnessMode.realtime);
      expect(plan.mpvFilter, 'loudnorm=I=-22:TP=-2:LRA=9');
    });

    test('off stays off and carries no gain from a previous track', () {
      final plan = planLoudness(AudioLoudness.none, _scan(-30));
      expect(plan, AudioLoudness.none);
      expect(plan.mpvFilter, '');
    });
  });

  group('evidence wire shape', () {
    test('round-trips and keeps missing metrics null', () {
      final json = {
        'source': 'server_scan',
        'method': 'ffmpeg-loudnorm-1',
        'method_version': 1,
        'integrated_lufs': -24.3,
        'true_peak_dbtp': -1.2,
        'quality': 'measured_full',
        'coverage_complete': true,
        'basis': 'pcm-native-tl31-drc0',
        'stream': {'file_id': 'f1', 'stream_index': 1, 'generation': 3},
        'measured_at': '2026-09-11T10:00:00.000Z',
      };
      final e = LoudnessEvidence.fromJson(json)!;
      expect(e.lraLu, isNull);
      expect(e.stream!.generation, 3);
      expect(e.toJson(), json);
    });

    test('an unknown source is kept apart, not guessed', () {
      final e = LoudnessEvidence.fromJson({
        'source': 'dialog_detector',
        'method': 'x',
        'method_version': 1,
        'quality': 'measured_full',
        'coverage_complete': true,
        'basis': LoudnessPolicy.clientBasis,
        'integrated_lufs': -20,
      })!;
      expect(e.source, LoudnessSource.unknown);
      expect(programmeGainDb(e), isNull);
    });

    test('not evidence at all parses to null', () {
      expect(LoudnessEvidence.fromJson({'source': 'server_scan'}), isNull);
      expect(LoudnessEvidence.fromJson('nope'), isNull);
    });
  });
}
