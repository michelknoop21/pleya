package nl.michelknoop.pleya.exoplayer

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

/**
 * Runs [LoudnessDsp] inside Media3's PCM pipeline, the one place where decoded
 * audio is in the app's own hands (DefaultAudioSink, int16 path; float output
 * stays off because the sink skips user processors on the float path).
 *
 * Always active for 16-bit PCM, including in [LoudnessDsp.Mode.OFF], where it
 * copies: whether a processor is active is decided at configure time, and the
 * user can switch loudness on mid-title without the sink reconfiguring. The
 * compressed paths (tunneling, passthrough, offload) never reach it; the core
 * forces decoded non-tunneled output while loudness is on.
 */
@OptIn(UnstableApi::class)
class LoudnessAudioProcessor : BaseAudioProcessor() {

  /** Written from the main thread, read per buffer on the playback thread. */
  @Volatile var params: LoudnessDsp.Params = LoudnessDsp.Params.OFF

  private var dsp: LoudnessDsp? = null
  private var scratch = FloatArray(0)
  private var lastMode = LoudnessDsp.Mode.OFF

  override fun onConfigure(inputAudioFormat: AudioFormat): AudioFormat {
    if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT || inputAudioFormat.channelCount !in 1..8) {
      return AudioFormat.NOT_SET
    }
    return inputAudioFormat
  }

  override fun queueInput(inputBuffer: ByteBuffer) {
    val bytes = inputBuffer.remaining()
    if (bytes == 0) return
    val out = replaceOutputBuffer(bytes)
    val p = params
    val d = dsp
    if (p.mode == LoudnessDsp.Mode.OFF || d == null) {
      lastMode = p.mode
      out.put(inputBuffer)
      out.flip()
      return
    }
    // Coming back on: the delay line still holds audio from before it was off.
    if (lastMode == LoudnessDsp.Mode.OFF) d.flush()
    lastMode = p.mode

    val samples = bytes / 2
    if (scratch.size < samples) scratch = FloatArray(samples)
    for (i in 0 until samples) scratch[i] = inputBuffer.getShort() / 32768f
    d.process(scratch, samples / d.channels, p)
    for (i in 0 until samples) out.putShort(LoudnessDsp.toPcm16(scratch[i]))
    out.flip()
  }

  override fun onFlush() {
    val format = inputAudioFormat
    val current = dsp
    dsp = if (current != null && current.sampleRate == format.sampleRate && current.channels == format.channelCount) {
      current.also { it.flush() }
    } else if (format.encoding == C.ENCODING_PCM_16BIT) {
      LoudnessDsp(format.sampleRate, format.channelCount)
    } else {
      null
    }
  }

  override fun onReset() {
    dsp = null
    lastMode = LoudnessDsp.Mode.OFF
  }

  /** For `getStats()`: what the chain is doing right now. */
  fun status(): Map<String, Any?> = dsp?.status(params) ?: mapOf("mode" to params.mode.wire, "active" to false)
}
