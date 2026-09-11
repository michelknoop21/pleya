package nl.michelknoop.pleya.exoplayer

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class LoudnessDspTest {

  private val rate = 48_000
  private fun programme(gain: Double, drc: Boolean = false) = LoudnessDsp.Params(LoudnessDsp.Mode.PROGRAMME, gain, drc, LoudnessDsp.PROFILE_VERSION)
  private val realtime = LoudnessDsp.Params(LoudnessDsp.Mode.REALTIME, 0.0, false, LoudnessDsp.PROFILE_VERSION)

  private fun tone(seconds: Double, amplitude: Double, freq: Double = 1000.0, phase: Double = 0.0, channels: Int = 2): FloatArray {
    val frames = (seconds * rate).toInt()
    return FloatArray(frames * channels) { i -> (amplitude * sin(2 * PI * freq * (i / channels) / rate + phase)).toFloat() }
  }

  private fun rms(buf: FloatArray, from: Int = 0): Double {
    var s = 0.0
    for (i in from until buf.size) s += buf[i].toDouble() * buf[i]
    return sqrt(s / (buf.size - from))
  }

  @Test
  fun planMatchesTheDartPolicy() {
    assertEquals(8.0, LoudnessDsp.planGainDb(-30.0, -20.0)!!, 1e-9)
    assertEquals(-4.0, LoudnessDsp.planGainDb(-18.0, -5.0)!!, 1e-9)
    assertEquals(12.0, LoudnessDsp.planGainDb(-40.0, -30.0)!!, 1e-9)
    // +8 would load the limiter 9,5 dB; the gain gives way to a load of 6.
    assertEquals(4.5, LoudnessDsp.planGainDb(-30.0, -0.5)!!, 1e-9)
    // DEC-111 (6): without a true peak a boost is held at 0, a cut passes.
    assertEquals(0.0, LoudnessDsp.planGainDb(-28.0, null)!!, 1e-9)
    assertEquals(-4.0, LoudnessDsp.planGainDb(-18.0, null)!!, 1e-9)
    assertNull(LoudnessDsp.planGainDb(-70.0, -60.0))
    assertNull(LoudnessDsp.planGainDb(Double.NaN, -10.0))
    assertNull(LoudnessDsp.planGainDb(-20.0, 3.5))
  }

  @Test
  fun programmeGainIsApplied() {
    val dsp = LoudnessDsp(rate, 2)
    val buf = tone(1.0, 0.05)
    val before = rms(buf)
    dsp.process(buf, buf.size / 2, programme(6.0))
    // Skip the limiter's delay line, which starts out silent.
    val ratio = rms(buf, 2 * 1000) / before
    assertEquals(LoudnessDsp.dbToLin(6.0), ratio, 0.01)
  }

  @Test
  fun ceilingHoldsOnIntersamplePeaks() {
    // fs/4 at 45 degrees: every sample sits at 0,707 of the waveform peak, so
    // a sample-peak limiter would let the true peak through 3 dB high. For a
    // pure fs/4 tone the true peak is exactly sqrt(2) times the sample peak.
    val dsp = LoudnessDsp(rate, 2)
    val buf = tone(2.0, 0.9, freq = rate / 4.0, phase = PI / 4)
    dsp.process(buf, buf.size / 2, programme(6.0))
    var samplePeak = 0.0
    for (i in rate until buf.size) samplePeak = max(samplePeak, abs(buf[i].toDouble()))
    val truePeak = samplePeak * sqrt(2.0)
    assertTrue("true peak $truePeak over the ceiling", truePeak <= LoudnessDsp.dbToLin(-2.0) * 1.02)
  }

  @Test
  fun notANumberBecomesSilenceNotNoise() {
    val dsp = LoudnessDsp(rate, 2)
    val buf = FloatArray(4800) {
      if (it % 7 == 0) {
        Float.NaN
      } else if (it % 11 == 0) {
        Float.POSITIVE_INFINITY
      } else {
        0.1f
      }
    }
    dsp.process(buf, buf.size / 2, programme(3.0))
    dsp.process(buf, buf.size / 2, realtime)
    assertTrue(buf.all { it.isFinite() && abs(it) <= 1f })
  }

  @Test
  fun silenceFreezesTheRealtimeGain() {
    val dsp = LoudnessDsp(rate, 2)
    val buf = FloatArray(10 * rate * 2)
    dsp.process(buf, buf.size / 2, realtime)
    assertEquals(0.0, dsp.status(realtime)["appliedGainDb"] as Double, 1e-9)
  }

  @Test
  fun realtimeGainRisesSlowly() {
    val dsp = LoudnessDsp(rate, 2)
    val buf = tone(5.0, 0.01)
    dsp.process(buf, buf.size / 2, realtime)
    val gain = dsp.status(realtime)["appliedGainDb"] as Double
    assertTrue("gain $gain should have started rising", gain > 1.0)
    assertTrue("gain $gain rose faster than 0,5 dB/s", gain <= 0.5 * 5.0 + 1e-6)
  }

  @Test
  fun aJumpFreezesTheRealtimeGain() {
    val dsp = LoudnessDsp(rate, 2)
    val steady = tone(10.0, 0.05)
    dsp.process(steady, steady.size / 2, realtime)
    val before = dsp.status(realtime)["appliedGainDb"] as Double
    val loud = tone(1.5, 0.5)
    dsp.process(loud, loud.size / 2, realtime)
    val after = dsp.status(realtime)["appliedGainDb"] as Double
    // Unfrozen it would have fallen 1,5 dB; frozen it moves at most for the
    // 400 ms block in which the jump is detected.
    assertTrue("gain moved ${before - after} dB during the hold", abs(before - after) <= 0.45)
  }

  @Test
  fun resetClearsState() {
    val dsp = LoudnessDsp(rate, 2)
    val buf = tone(1.0, 0.9)
    dsp.process(buf, buf.size / 2, programme(12.0))
    assertTrue((dsp.status(programme(12.0))["maxLimiterReductionDb"] as Double) > 1.0)
    dsp.reset()
    val status = dsp.status(realtime)
    assertEquals(0.0, status["maxLimiterReductionDb"] as Double, 0.0)
    assertEquals(0.0, status["appliedGainDb"] as Double, 0.0)
    assertNull(status["shortTermLufs"])
  }

  /**
   * Renders every programme fixture from `scripts/loudness/fixtures.sh` through
   * the DSP and writes `<fixture>.android.wav` for `prove.sh --android`, which
   * measures them with the same independent meter as the mpv row. The `drc`
   * fixture runs with reduce-loud-sounds on, for the D row. The output keeps
   * the limiter latency, as a device plays it; `latency_frames` tells prove.sh
   * how far to shift it back before comparing in time. (Shifting here would
   * put the isp fixture's first burst on sample 0, where the meter's resampler
   * mirrors it into a peak that is not there.) Skipped when the fixtures have
   * not been generated.
   */
  @Test
  fun exportFixturesForProve() {
    val root = File(System.getenv("LOUDNESS_FIXTURES") ?: "../../build/loudness/fixtures")
    val manifest = File(root, "manifest.txt")
    assumeTrue("run scripts/loudness/fixtures.sh first", manifest.exists())
    val outDir = File(root, "../android").apply { mkdirs() }
    val line = Regex("""^(\S+)\.wav I=(\S+) TP=(\S+)""")
    var written = 0
    for (entry in manifest.readLines()) {
      val m = line.find(entry) ?: continue
      val (name, i, tp) = m.destructured
      val gain = LoudnessDsp.planGainDb(i.toDoubleOrNull(), tp.toDoubleOrNull()) ?: continue
      val wav = Wav.read(File(root, "$name.wav"))
      val dsp = LoudnessDsp(wav.rate, wav.channels)
      val buf = FloatArray(wav.samples.size) { wav.samples[it] / 32768f }
      dsp.process(buf, buf.size / wav.channels, programme(gain, drc = name == "drc"))
      Wav.write(File(outDir, "$name.android.wav"), wav.rate, wav.channels, ShortArray(buf.size) { LoudnessDsp.toPcm16(buf[it]) })
      File(outDir, "latency_frames").writeText("${dsp.latencyFrames}\n")
      written++
    }
    assertTrue("no programme fixtures found", written > 0)
  }

  private class Wav(val rate: Int, val channels: Int, val samples: ShortArray) {
    companion object {
      fun read(file: File): Wav {
        val b = ByteBuffer.wrap(file.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
        b.position(12)
        var rate = 0
        var channels = 0
        while (b.remaining() >= 8) {
          val id = String(ByteArray(4).also { b.get(it) })
          val size = b.int
          if (id == "fmt ") {
            val start = b.position()
            b.short // format tag
            channels = b.short.toInt()
            rate = b.int
            b.position(start + size)
          } else if (id == "data") {
            // A truncated file still claims its full length; read what is there.
            val n = minOf(size, b.remaining()) / 2
            return Wav(rate, channels, ShortArray(n) { b.short })
          } else {
            b.position(minOf(b.limit(), b.position() + size))
          }
        }
        error("no data chunk in $file")
      }

      fun write(file: File, rate: Int, channels: Int, samples: ShortArray) {
        val data = samples.size * 2
        val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(channels.toShort())
          .putInt(rate).putInt(rate * channels * 2).putShort((channels * 2).toShort()).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        samples.forEach { b.putShort(it) }
        file.writeBytes(b.array())
      }
    }
  }
}
