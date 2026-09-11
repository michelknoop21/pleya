package nl.michelknoop.pleya.exoplayer

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.tan

/**
 * Pleya's loudness chain for Media3, in float and without Android imports so
 * the JVM tests can drive it with the same fixtures `scripts/loudness/prove.sh`
 * measures.
 *
 * Programme mode is the canonical path: one fixed gain, planned in Dart from
 * stored evidence (`loudness_planner.dart`), then the optional reduce-loud-sounds
 * compressor, then a true-peak limiter at -2 dBTP. That is the same chain mpv
 * runs, which is what makes Android and Apple land on the same level.
 *
 * Realtime mode is the emergency fallback for titles without evidence, and it
 * is an estimator, not a meter: K-weighted short-term loudness over 3 s, a gain
 * that moves at most 0,5 dB/s up and 1 dB/s down, frozen in silence and for
 * 2 s after a jump of more than 8 LU.
 *
 * Interleaved frames, any channel count up to 8, any sample rate.
 */
class LoudnessDsp(val sampleRate: Int, val channels: Int) {

  enum class Mode(val wire: String) {
    OFF("off"),
    PROGRAMME("programme"),
    REALTIME("realtime");

    companion object {
      fun parse(value: String?): Mode = entries.firstOrNull { it.wire == value } ?: OFF
    }
  }

  data class Params(val mode: Mode, val gainDb: Double, val drc: Boolean, val profileVersion: Int) {
    companion object {
      val OFF = Params(Mode.OFF, 0.0, false, PROFILE_VERSION)
    }
  }

  companion object {
    /** Must match `AudioLoudness.profileVersion` in Dart. */
    const val PROFILE_VERSION = 1

    // The canonical policy, mirrored from `LoudnessPolicy` in Dart.
    const val TARGET_LUFS = -22.0
    const val CEILING_DBTP = -2.0
    const val MAX_GAIN_DB = 12.0
    const val MIN_GAIN_DB = -30.0
    const val MAX_LIMITER_LOAD_DB = 6.0
    const val MIN_VALID_LUFS = -60.0
    const val MAX_VALID_TRUE_PEAK_DBTP = 3.0

    // Limiter: same attack and release as mpv's alimiter.
    const val LOOKAHEAD_MS = 5.0
    const val RELEASE_MS = 50.0

    // Reduce-loud-sounds compressor, as mpv's
    // acompressor=threshold=-18dB:ratio=8:attack=5:release=250 (knee 2,83 = 9 dB).
    const val COMP_THRESHOLD_DB = -18.0
    const val COMP_RATIO = 8.0
    const val COMP_ATTACK_MS = 5.0
    const val COMP_RELEASE_MS = 250.0
    const val COMP_KNEE_DB = 9.03

    // Realtime estimator.
    const val SUB_BLOCK_MS = 100
    const val SHORT_TERM_SUB_BLOCKS = 30
    const val UPDATE_SUB_BLOCKS = 4
    const val UP_DB_PER_S = 0.5
    const val DOWN_DB_PER_S = 1.0
    const val SILENCE_LUFS = -50.0
    const val TRANSIENT_LU = 8.0
    const val TRANSIENT_HOLD_S = 2.0

    /**
     * The canonical programme gain, identical to `planProgrammeGain` in Dart.
     * Used by the tests to prove both sides agree; at runtime Dart sends it.
     */
    fun planGainDb(integratedLufs: Double?, truePeakDbtp: Double?): Double? {
      if (integratedLufs == null || !integratedLufs.isFinite() || integratedLufs < MIN_VALID_LUFS) return null
      if (truePeakDbtp != null && (!truePeakDbtp.isFinite() || truePeakDbtp > MAX_VALID_TRUE_PEAK_DBTP)) return null
      var gain = (TARGET_LUFS - integratedLufs).coerceIn(MIN_GAIN_DB, MAX_GAIN_DB)
      if (truePeakDbtp != null) {
        val load = (truePeakDbtp + gain) - CEILING_DBTP
        if (load > MAX_LIMITER_LOAD_DB) gain -= load - MAX_LIMITER_LOAD_DB
      } else if (gain > 0.0) {
        // DEC-111 (6): no true peak, no limiter load to check, so no boost.
        gain = 0.0
      }
      return gain
    }

    fun dbToLin(db: Double): Double = 10.0.pow(db / 20.0)

    fun toPcm16(x: Float): Short {
      if (!x.isFinite()) return 0
      return (x * 32768f).coerceIn(-32768f, 32767f).toInt().toShort()
    }

    /** ITU-R BS.1770-4 Annex 2: 4x oversampling interpolation, 12 taps per phase. */
    private val TRUE_PEAK_PHASES = arrayOf(
      doubleArrayOf(0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000, -0.0594482421875, 0.1373291015625, 0.9721679687500, -0.1022949218750, 0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500),
      doubleArrayOf(-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250, -0.1665039062500, 0.4650878906250, 0.7797851562500, -0.2003173828125, 0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375),
      doubleArrayOf(-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000, -0.2003173828125, 0.7797851562500, 0.4650878906250, -0.1665039062500, 0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875),
      doubleArrayOf(-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750, -0.1022949218750, 0.9721679687500, 0.1373291015625, -0.0594482421875, 0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750)
    )
    private const val TAPS = 12
  }

  private val ceilingLin = dbToLin(CEILING_DBTP)

  // --- Limiter state ---------------------------------------------------------
  // The peak of frame n is known at n, but the interpolated peaks it reveals
  // sit up to TAPS frames back, so the gain is held TAPS frames longer than
  // the lookahead and the audio is delayed by that much extra. Held min over
  // [holdLen] frames, then a box average over [lookahead] frames, guarantees
  // the averaged gain covers every audio frame the peak touches.
  private val lookahead = max(1, (LOOKAHEAD_MS * sampleRate / 1000.0).toInt())
  private val holdLen = lookahead + TAPS
  private val delayFrames = lookahead - 1 + TAPS

  /** Frames the output lags the input, from the limiter's lookahead. */
  val latencyFrames: Int get() = delayFrames
  private val releaseCoef = 1.0 - exp(-1.0 / (RELEASE_MS * sampleRate / 1000.0))

  private val history = Array(channels) { DoubleArray(TAPS) }
  private var historyPos = 0

  private val minIdx = LongArray(holdLen + 1)
  private val minVal = DoubleArray(holdLen + 1)
  private var minHead = 0
  private var minSize = 0
  private var frameCounter = 0L

  private var released = 1.0
  private val avgRing = DoubleArray(lookahead) { 1.0 }
  private var avgPos = 0
  private var avgSum = lookahead.toDouble()

  private val delay = FloatArray(max(1, delayFrames) * channels)
  private var delayPos = 0

  // --- Compressor state -------------------------------------------------------
  // FFmpeg's acompressor coefficients, FFMIN(1., 1. / (ms * rate / 4000.)):
  // a one-pole step that covers the attack or release time four times over.
  private val compAttack = min(1.0, 4000.0 / (COMP_ATTACK_MS * sampleRate))
  private val compRelease = min(1.0, 4000.0 / (COMP_RELEASE_MS * sampleRate))
  private var compEnv = 0.0

  // --- Realtime estimator state ----------------------------------------------
  private val weights = DoubleArray(channels) { c ->
    when {
      channels >= 6 && c == 3 -> 0.0 // LFE
      channels >= 6 && c >= 4 -> 1.41 // surrounds, +1,5 dB
      else -> 1.0
    }
  }
  private val kShelf = shelfCoefficients(sampleRate)
  private val kHighPass = highPassCoefficients(sampleRate)
  private val kState = Array(channels) { DoubleArray(4) }
  private val subLen = max(1, sampleRate * SUB_BLOCK_MS / 1000)
  private var subAcc = 0.0
  private var subCount = 0
  private val subEnergies = DoubleArray(SHORT_TERM_SUB_BLOCKS)
  private var subFilled = 0
  private var subPos = 0
  private var subsSinceUpdate = 0
  private var previousShortTerm = Double.NaN
  private var holdFrames = 0L
  private var gated = true
  private var realtimeGainDb = 0.0
  private var realtimeTargetDb = 0.0
  private val upStep = UP_DB_PER_S / sampleRate
  private val downStep = DOWN_DB_PER_S / sampleRate

  // --- Status -----------------------------------------------------------------
  @Volatile private var appliedGainDb = 0.0

  @Volatile private var limiterReductionDb = 0.0

  @Volatile private var maxLimiterReductionDb = 0.0

  @Volatile private var shortTermLufs: Double? = null

  /** Processes [frames] interleaved frames of [buf] in place. */
  fun process(buf: FloatArray, frames: Int, params: Params) {
    if (params.mode == Mode.OFF) return
    val fixedLin = dbToLin(params.gainDb)
    for (f in 0 until frames) {
      val base = f * channels

      if (params.mode == Mode.REALTIME) estimate(buf, base)
      val gainLin = if (params.mode == Mode.REALTIME) {
        stepRealtimeGain()
        dbToLin(realtimeGainDb)
      } else {
        fixedLin
      }

      var power = 0.0
      for (c in 0 until channels) {
        var x = buf[base + c].toDouble()
        if (!x.isFinite()) x = 0.0
        x *= gainLin
        buf[base + c] = x.toFloat()
        power += x * x
      }

      if (params.drc) {
        power /= channels
        compEnv += (if (power > compEnv) compAttack else compRelease) * (power - compEnv)
        val reduction = dbToLin(compressorGainDb(10.0 * log10(compEnv + 1e-20)))
        for (c in 0 until channels) buf[base + c] = (buf[base + c] * reduction).toFloat()
      }

      limit(buf, base)
    }
    appliedGainDb = if (params.mode == Mode.REALTIME) realtimeGainDb else params.gainDb
  }

  /** Clears filters and delay lines, keeping the realtime gain so a seek does not restart the level. */
  fun flush() {
    history.forEach { it.fill(0.0) }
    historyPos = 0
    minHead = 0
    minSize = 0
    frameCounter = 0
    released = 1.0
    avgRing.fill(1.0)
    avgPos = 0
    avgSum = lookahead.toDouble()
    delay.fill(0f)
    delayPos = 0
    compEnv = 0.0
    kState.forEach { it.fill(0.0) }
    subAcc = 0.0
    subCount = 0
    subFilled = 0
    subPos = 0
    subsSinceUpdate = 0
    previousShortTerm = Double.NaN
    holdFrames = 0
    gated = true
    limiterReductionDb = 0.0
  }

  fun reset() {
    flush()
    realtimeGainDb = 0.0
    realtimeTargetDb = 0.0
    appliedGainDb = 0.0
    maxLimiterReductionDb = 0.0
    shortTermLufs = null
  }

  fun status(params: Params): Map<String, Any?> = mapOf(
    "mode" to params.mode.wire,
    "profileVersion" to params.profileVersion,
    "gainDb" to if (params.mode == Mode.REALTIME) realtimeTargetDb else params.gainDb,
    "appliedGainDb" to appliedGainDb,
    "drc" to params.drc,
    "limiterReductionDb" to limiterReductionDb,
    "maxLimiterReductionDb" to maxLimiterReductionDb,
    "shortTermLufs" to shortTermLufs,
    "estimated" to (params.mode == Mode.REALTIME)
  )

  // --- Limiter ----------------------------------------------------------------

  private fun limit(buf: FloatArray, base: Int) {
    var peak = 0.0
    for (c in 0 until channels) {
      val x = buf[base + c].toDouble()
      val h = history[c]
      h[historyPos] = x
      peak = max(peak, abs(x))
      for (phase in TRUE_PEAK_PHASES) {
        var y = 0.0
        var idx = historyPos
        for (k in 0 until TAPS) {
          y += phase[k] * h[idx]
          idx = if (idx == 0) TAPS - 1 else idx - 1
        }
        peak = max(peak, abs(y))
      }
    }
    historyPos = (historyPos + 1) % TAPS

    val required = if (peak > ceilingLin) ceilingLin / peak else 1.0

    // Sliding minimum of the required gain over the last [holdLen] frames.
    while (minSize > 0 && minVal[(minHead + minSize - 1) % minVal.size] >= required) minSize--
    minIdx[(minHead + minSize) % minIdx.size] = frameCounter
    minVal[(minHead + minSize) % minVal.size] = required
    minSize++
    if (minIdx[minHead] <= frameCounter - holdLen) {
      minHead = (minHead + 1) % minIdx.size
      minSize--
    }
    frameCounter++
    val held = minVal[minHead]

    released = min(held, released + (1.0 - released) * releaseCoef)
    avgSum += released - avgRing[avgPos]
    avgRing[avgPos] = released
    avgPos = (avgPos + 1) % lookahead
    val gain = min(1.0, avgSum / lookahead)

    val reduction = -20.0 * log10(max(gain, 1e-9))
    limiterReductionDb = reduction
    if (reduction > maxLimiterReductionDb) maxLimiterReductionDb = reduction

    if (delayFrames <= 0) {
      for (c in 0 until channels) buf[base + c] = (buf[base + c] * gain).toFloat()
      return
    }
    val d = delayPos * channels
    for (c in 0 until channels) {
      val delayed = delay[d + c]
      delay[d + c] = buf[base + c]
      val out = (delayed * gain).toFloat()
      buf[base + c] = if (out.isFinite()) out else 0f
    }
    delayPos = (delayPos + 1) % delayFrames
  }

  private fun compressorGainDb(levelDb: Double): Double {
    val over = levelDb - COMP_THRESHOLD_DB
    val slope = 1.0 / COMP_RATIO - 1.0
    return when {
      over <= -COMP_KNEE_DB / 2 -> 0.0
      over >= COMP_KNEE_DB / 2 -> slope * over
      else -> slope * (over + COMP_KNEE_DB / 2).pow(2) / (2 * COMP_KNEE_DB)
    }
  }

  // --- Realtime estimator -------------------------------------------------------

  // ponytail: short-term estimator with fixed gates, not integrated BS.1770
  // gating. The upgrade is a real BS.1770 tracker behind the same Params.
  private fun estimate(buf: FloatArray, base: Int) {
    var energy = 0.0
    for (c in 0 until channels) {
      val w = weights[c]
      if (w == 0.0) continue
      var x = buf[base + c].toDouble()
      if (!x.isFinite()) x = 0.0
      val s = kState[c]
      val y1 = kShelf[0] * x + s[0]
      s[0] = kShelf[1] * x - kShelf[4] * y1 + s[1]
      s[1] = kShelf[2] * x - kShelf[5] * y1
      val y2 = kHighPass[0] * y1 + s[2]
      s[2] = kHighPass[1] * y1 - kHighPass[4] * y2 + s[3]
      s[3] = kHighPass[2] * y1 - kHighPass[5] * y2
      energy += w * y2 * y2
    }
    subAcc += energy
    if (++subCount < subLen) return

    subEnergies[subPos] = subAcc / subLen
    subPos = (subPos + 1) % SHORT_TERM_SUB_BLOCKS
    if (subFilled < SHORT_TERM_SUB_BLOCKS) subFilled++
    subAcc = 0.0
    subCount = 0
    if (++subsSinceUpdate < UPDATE_SUB_BLOCKS) return
    subsSinceUpdate = 0

    var sum = 0.0
    for (i in 0 until subFilled) sum += subEnergies[i]
    val shortTerm = lufs(sum / subFilled)
    var block = 0.0
    for (i in 1..UPDATE_SUB_BLOCKS) block += subEnergies[(subPos - i + SHORT_TERM_SUB_BLOCKS) % SHORT_TERM_SUB_BLOCKS]
    val blockLufs = lufs(block / UPDATE_SUB_BLOCKS)
    shortTermLufs = shortTerm

    val jumped = previousShortTerm.isFinite() && blockLufs - previousShortTerm > TRANSIENT_LU
    if (jumped) holdFrames = (TRANSIENT_HOLD_S * sampleRate).toLong()
    gated = shortTerm < SILENCE_LUFS || holdFrames > 0
    if (!gated) realtimeTargetDb = (TARGET_LUFS - shortTerm).coerceIn(MIN_GAIN_DB, MAX_GAIN_DB)
    previousShortTerm = shortTerm
  }

  private fun stepRealtimeGain() {
    if (holdFrames > 0) {
      holdFrames--
      if (holdFrames == 0L) gated = false
    }
    if (gated) return
    val diff = realtimeTargetDb - realtimeGainDb
    realtimeGainDb += if (diff > 0) min(diff, upStep) else max(diff, -downStep)
  }

  private fun lufs(meanSquare: Double): Double = -0.691 + 10.0 * log10(meanSquare + 1e-20)

  /** BS.1770 pre-filter (high shelf), as libebur128 derives it for any rate: b0 b1 b2 a0 a1 a2. */
  private fun shelfCoefficients(rate: Int): DoubleArray {
    val f0 = 1681.974450955533
    val g = 3.999843853973347
    val q = 1.7072244193
    val k = tan(Math.PI * f0 / rate)
    val vh = 10.0.pow(g / 20.0)
    val vb = vh.pow(0.4996667741545416)
    val a0 = 1.0 + k / q + k * k
    return doubleArrayOf(
      (vh + vb * k / q + k * k) / a0,
      2.0 * (k * k - vh) / a0,
      (vh - vb * k / q + k * k) / a0,
      1.0,
      2.0 * (k * k - 1.0) / a0,
      (1.0 - k / q + k * k) / a0
    )
  }

  /** BS.1770 RLB high-pass. */
  private fun highPassCoefficients(rate: Int): DoubleArray {
    val f0 = 38.13547087602444
    val q = 0.5003270373238773
    val k = tan(Math.PI * f0 / rate)
    val a0 = 1.0 + k / q + k * k
    return doubleArrayOf(1.0, -2.0, 1.0, 1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0)
  }
}
