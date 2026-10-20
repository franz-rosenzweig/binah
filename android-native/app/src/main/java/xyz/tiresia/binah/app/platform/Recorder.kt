package xyz.tiresia.binah.app.platform

import android.content.Context
import android.media.MediaRecorder
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import kotlin.math.sqrt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * A spoken answer: AAC in an .m4a (audio/mp4), which Binah's /api/audio takes as it is, with a time
 * limit, the time left and the microphone's level for the screen.
 */
class Recorder(private val context: Context, val limit: Float = 60f) {
    enum class State { Idle, Recording, Done }
    var state by mutableStateOf(State.Idle)
    var left by mutableFloatStateOf(limit)
    /** The last few levels, 0–1, newest last. */
    val levels = mutableStateListOf<Float>().apply { repeat(BARS) { add(0f) } }
    /** Told with the recording and how long it ran (ms) when it stops, by hand or at the limit. */
    var onFinish: ((ByteArray, Long) -> Unit)? = null

    private var mr: MediaRecorder? = null
    private var ticker: Job? = null
    private var began = 0L
    private val file get() = File(context.cacheDir, "answer.m4a")

    fun start(scope: CoroutineScope) {
        file.delete()
        val r = MediaRecorder(context)
        r.setAudioSource(MediaRecorder.AudioSource.MIC)
        r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioChannels(1)
        r.setAudioSamplingRate(44_100)
        r.setAudioEncodingBitRate(96_000)
        r.setMaxDuration((limit * 1000).toInt())
        r.setOutputFile(file)
        r.setOnInfoListener { _, what, _ -> if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) stop() }
        try { r.prepare(); r.start() } catch (e: Exception) { r.release(); throw e }
        mr = r
        began = System.currentTimeMillis()
        left = limit
        state = State.Recording
        ticker = scope.launch {
            while (isActive && state == State.Recording) {
                left = (limit - (System.currentTimeMillis() - began) / 1000f).coerceAtLeast(0f)
                val amp = runCatching { mr?.maxAmplitude ?: 0 }.getOrDefault(0)
                levels.removeAt(0)
                levels.add(sqrt(amp / 32767f).coerceIn(0f, 1f))
                delay(100)
            }
        }
    }

    fun stop() {
        val r = mr ?: return
        mr = null
        ticker?.cancel()
        val took = System.currentTimeMillis() - began
        val ok = runCatching { r.stop() }.isSuccess
        r.release()
        state = State.Done
        if (ok && file.exists()) onFinish?.invoke(file.readBytes(), took) else state = State.Idle
        file.delete()
    }

    fun cancel() {
        val r = mr ?: return
        mr = null
        ticker?.cancel()
        runCatching { r.stop() }
        r.release()
        file.delete()
        state = State.Idle
        left = limit
    }

    companion object { const val BARS = 28 }
}
