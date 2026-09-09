package com.roboticdroid.smartcontroller

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/// MediaPipe Hands, running on-device from the bundled `hand_landmarker.task`.
///
/// Dart hands over the raw NV21 camera frame; this rotates it upright, hands it
/// to the landmarker and returns 21 normalised x/y/z triples. Nothing but the
/// 63 doubles crosses back over the channel.
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "smartarm/hands"
        const val LANDMARKS = 21
        const val TAG = "SmartArm"
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var landmarker: HandLandmarker? = null
    private var delegateName = "?"
    private var argb: IntArray? = null
    private var bitmap: Bitmap? = null
    private var lastTimestamp = -1L

    private var frames = 0L
    private var hits = 0L
    private var convertMs = 0L
    private var detectMs = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> worker.execute {
                        val error = start()
                        main.post {
                            if (error == null) result.success(true)
                            else result.error("init", error, null)
                        }
                    }
                    "detect" -> {
                        val bytes = call.argument<ByteArray>("bytes")!!
                        val width = call.argument<Int>("width")!!
                        val height = call.argument<Int>("height")!!
                        val rotation = call.argument<Int>("rotation")!!
                        worker.execute {
                            val landmarks = detect(bytes, width, height, rotation)
                            main.post { result.success(landmarks) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        worker.execute { landmarker?.close() }
        worker.shutdown()
        super.onDestroy()
    }

    private fun start(): String? {
        if (landmarker != null) return null
        var failure: Throwable? = null
        // GPU roughly halves inference; not every driver takes it, so fall back.
        for (delegate in listOf(Delegate.GPU, Delegate.CPU)) {
            try {
                landmarker = HandLandmarker.createFromOptions(
                    this,
                    HandLandmarker.HandLandmarkerOptions.builder()
                        .setBaseOptions(
                            BaseOptions.builder()
                                .setModelAssetPath("hand_landmarker.task")
                                .setDelegate(delegate)
                                .build(),
                        )
                        .setRunningMode(RunningMode.VIDEO)
                        .setNumHands(1)
                        .setMinHandDetectionConfidence(0.5f)
                        .setMinTrackingConfidence(0.5f)
                        .setMinHandPresenceConfidence(0.5f)
                        .build(),
                )
                delegateName = delegate.name
                Log.i(TAG, "landmarker ready on $delegate")
                return null
            } catch (e: Throwable) {
                Log.e(TAG, "landmarker init failed on $delegate", e)
                failure = e
            }
        }
        return failure?.message ?: failure?.toString() ?: "unknown"
    }

    private fun detect(nv21: ByteArray, width: Int, height: Int, rotation: Int): DoubleArray? {
        val hands = landmarker ?: return null

        // Detection runs at half resolution. The landmarker rescales to 192x192
        // internally, so the detail is thrown away anyway, and this cuts the
        // colour conversion to a quarter. The preview is a separate camera
        // texture and stays sharp.
        val sw = width / 2
        val sh = height / 2
        val swap = rotation == 90 || rotation == 270
        val outW = if (swap) sh else sw
        val outH = if (swap) sw else sh

        val t0 = SystemClock.elapsedRealtime()
        val pixels = argb?.takeIf { it.size == outW * outH } ?: IntArray(outW * outH).also { argb = it }
        nv21ToArgb(nv21, width, height, rotation, pixels)

        val image = bitmap?.takeIf { it.width == outW && it.height == outH }
            ?: Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888).also { bitmap = it }
        image.setPixels(pixels, 0, outW, 0, 0, outW, outH)
        val t1 = SystemClock.elapsedRealtime()

        // VIDEO mode insists on strictly increasing timestamps.
        val ts = System.currentTimeMillis().let { if (it <= lastTimestamp) lastTimestamp + 1 else it }
        lastTimestamp = ts

        return try {
            val result = hands.detectForVideo(BitmapImageBuilder(image).build(), ts)

            frames++
            if (result.landmarks().isNotEmpty()) hits++
            convertMs += t1 - t0
            detectMs += SystemClock.elapsedRealtime() - t1
            if (frames % 30L == 0L) {
                Log.i(
                    TAG,
                    "frames=$frames hands=$hits ${outW}x$outH on $delegateName " +
                        "convert=${convertMs / 30}ms detect=${detectMs / 30}ms",
                )
                convertMs = 0
                detectMs = 0
            }

            val hand = result.landmarks().firstOrNull() ?: return null
            DoubleArray(LANDMARKS * 3).also { out ->
                for (i in 0 until LANDMARKS) {
                    out[i * 3] = hand[i].x().toDouble()
                    out[i * 3 + 1] = hand[i].y().toDouble()
                    out[i * 3 + 2] = hand[i].z().toDouble()
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "detectForVideo failed", e)
            null
        }
    }

    /// NV21 -> ARGB_8888 at half resolution, rotating [rotation] degrees
    /// clockwise on the way so the result is already upright and no second pass
    /// is needed. Chroma is sampled per 2x2 block, so dropping every other pixel
    /// costs no colour accuracy.
    private fun nv21ToArgb(nv21: ByteArray, w: Int, h: Int, rotation: Int, out: IntArray) {
        val frameSize = w * h
        val sw = w / 2
        val sh = h / 2
        for (sj in 0 until sh) {
            val j = sj * 2
            val uvRow = frameSize + sj * w
            val yRow = j * w
            for (si in 0 until sw) {
                val i = si * 2
                val y = (nv21[yRow + i].toInt() and 0xff).let { if (it < 16) 16 else it }
                val uvIndex = uvRow + i
                val v = (nv21[uvIndex].toInt() and 0xff) - 128
                val u = (nv21[uvIndex + 1].toInt() and 0xff) - 128

                val y1192 = 1192 * (y - 16)
                var r = (y1192 + 1634 * v) shr 10
                var g = (y1192 - 833 * v - 400 * u) shr 10
                var b = (y1192 + 2066 * u) shr 10
                r = if (r < 0) 0 else if (r > 255) 255 else r
                g = if (g < 0) 0 else if (g > 255) 255 else g
                b = if (b < 0) 0 else if (b > 255) 255 else b

                val dst = when (rotation) {
                    90 -> si * sh + (sh - 1 - sj)
                    180 -> (sh - 1 - sj) * sw + (sw - 1 - si)
                    270 -> (sw - 1 - si) * sh + sj
                    else -> sj * sw + si
                }
                out[dst] = (0xff shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
    }
}
