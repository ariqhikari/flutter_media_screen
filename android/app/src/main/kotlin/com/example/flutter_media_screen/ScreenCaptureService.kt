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
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper  
import android.os.IBinder
import android.util.Log 
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.hardware.display.DisplayManager
import io.flutter.plugin.common.EventChannel

class ScreenCaptureService: Service() {
  companion object {
    private const val NOTIF_ID = 1001
    /** Static sink untuk mengirim frame ke Dart */
    var eventSink: EventChannel.EventSink? = null
    var serviceInstance: ScreenCaptureService? = null
    /** Hentikan projection jika dipanggil dari cancel */
    fun stopProjection() {
      // Nunggu instance mediaProjection valid dan stop
      serviceInstance?.mediaProjection?.stop()
    }
  }

    private lateinit var mediaProjection: MediaProjection
    private lateinit var imageReader: ImageReader
    private lateinit var handlerThread: HandlerThread
    private var isSendingFrame = false

    // 🌟 Tambahan untuk overlay
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null

    override fun onCreate() {
      super.onCreate()
      serviceInstance = this

      // Inisialisasi WindowManager untuk overlay
      windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

      // Pre-inflate overlay satu kali
      overlayView = LayoutInflater.from(this)
        .inflate(R.layout.overlay_layout, null)

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

              // Jika ada padding, salin per baris:
              if (rowStride != width * pixelStride) {
                  for (y in 0 until height) {
                      val rowStart = y * rowStride
                      buffer.position(rowStart)
                      buffer.get(bytes, y * width * pixelStride, width * pixelStride)
                  }
              }

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
      // Hapus overlay jika masih terpasang
      removeOverlay()

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

    // --------------------
    // 🌟 Overlay Methods
    // --------------------

    /** Tampilkan overlay full‐screen menutupi aplikasi lain */
    fun showOverlay() {
      // Jika sudah terpasang, tidak perlu ulang
      if (overlayView?.parent != null) return

      val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.MATCH_PARENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
          WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
          WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
          WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
          WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT
      ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = 0
        y = 0
      }

      windowManager.addView(overlayView, params)
    }

    /** Hapus overlay jika ada */
    fun removeOverlay() {
      overlayView?.let {
        if (it.parent != null) {
          windowManager.removeView(it)
          overlayView = null
        }
      }
    }
}
