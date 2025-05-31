package com.example.flutter_media_screen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper  
import android.os.IBinder
import android.util.Log 
import android.hardware.display.DisplayManager
import io.flutter.plugin.common.EventChannel

class ScreenCaptureService: Service() {
  companion object {
    private const val NOTIF_ID = 1001
    /** Static sink untuk mengirim frame ke Dart */
    var eventSink: EventChannel.EventSink? = null
    /** Hentikan projection jika dipanggil dari cancel */
    fun stopProjection() {
      // Nunggu instance mediaProjection valid dan stop
      instance?.mediaProjection?.stop()
    }
    private var instance: ScreenCaptureService? = null
  }

    private lateinit var mediaProjection: MediaProjection
    private lateinit var imageReader: ImageReader
    private lateinit var handlerThread: HandlerThread
    private var isSendingFrame = false


    override fun onCreate() {
    super.onCreate()
    instance = this
    createNotificationChannel()
    startForeground(NOTIF_ID, makeNotification())
    handlerThread = HandlerThread("CaptureThread").apply { start() }


    // Siapkan ImageReader untuk capture frame
    val metrics = resources.displayMetrics
    imageReader = ImageReader.newInstance(
      metrics.widthPixels,
      metrics.heightPixels,
      PixelFormat.RGBA_8888,
      3
    )
    val handler = Handler(handlerThread.looper)
    imageReader.setOnImageAvailableListener({ reader ->
      val image = try {
          reader.acquireNextImage() // Ganti dengan acquireNextImage()
      } catch (e: IllegalStateException) {
          Log.e("ScreenCapture", "Gagal mengambil gambar: ${e.message}")
          return@setOnImageAvailableListener
      }

      if (image == null) return@setOnImageAvailableListener

        try {
            if (isSendingFrame) {
                image.close()
                return@setOnImageAvailableListener
            }
            isSendingFrame = true

            val plane = image.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val width = image.width
            val height = image.height

            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)

            Handler(Looper.getMainLooper()).post {
                eventSink?.success(
                    hashMapOf(
                        "bytes" to bytes,
                        "metadata" to mapOf("width" to width, "height" to height)
                    )
                )
                isSendingFrame = false
            }
        } catch (e: Exception) {
            Log.e("ScreenCapture", "Error saat proses frame: ${e.message}")
            isSendingFrame = false
        } finally {
            image.close()
        }
    }, Handler(handlerThread.looper))
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    // Ambil permission data dari intent
    val code = intent?.getIntExtra("code", -1) ?: return START_NOT_STICKY
    val data = intent.getParcelableExtra<Intent>("data") ?: return START_NOT_STICKY

    val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    mediaProjection = mgr.getMediaProjection(code, data)

    // 1. Daftarkan MediaProjection.Callback untuk menangani lifecycle
    mediaProjection.registerCallback(object : MediaProjection.Callback() {
        override fun onStop() {
            Log.e("ScreenCapture", "MediaProjection dihentikan!")
            eventSink?.endOfStream()  // Tutup event channel agar tidak error di Dart
            stopSelf()
        }
    }, Handler(Looper.getMainLooper())) // Handler null untuk default
    
    // 2. Panggil createVirtualDisplay dengan parameter yang benar
    val virtualDisplay = mediaProjection.createVirtualDisplay(
        "ScreenCapture",
        resources.displayMetrics.widthPixels,
        resources.displayMetrics.heightPixels,
        resources.displayMetrics.densityDpi,
        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
        imageReader.surface,
        null, // VirtualDisplay.Callback (opsional)
        null  // Handler (null untuk default)
    )

    if (virtualDisplay == null) {
      Log.e("ScreenCapture", "Gagal membuat VirtualDisplay!")
      stopSelf()
    }
    return START_STICKY
  }

  override fun onBind(intent: Intent?): IBinder? = null

  private fun createNotificationChannel() {
    val channel = NotificationChannel(
      "screen_capture",
      "Screen Capture Service",
      NotificationManager.IMPORTANCE_LOW
    )
    getSystemService(NotificationManager::class.java)
      .createNotificationChannel(channel)
  }

    override fun onDestroy() {
        handlerThread.quitSafely()
        try {
            mediaProjection.stop()
        } catch (e: Exception) {
            Log.e("ScreenCapture", "Error stopping projection: ${e.message}")
        }
        imageReader.close()
        eventSink = null
        super.onDestroy()
    }


    private fun makeNotification(): Notification =
    Notification.Builder(this, "screen_capture")
      .setContentTitle("Parental Control")
      .setContentText("Screen capture aktif")
      .setSmallIcon(android.R.drawable.ic_menu_camera)
      .build()
}
