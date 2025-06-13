package com.example.flutter_media_screen

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MyAccessibilityService : AccessibilityService() {

  companion object {
    /** Daftar paket aplikasi yang ingin dipantau (whitelist) */
    val whitelist = setOf(
      "com.instagram.android",
      "com.tiktok.android",
      "com.youtube.android"
    )
  }

  // Nama channel yang sama dengan ScreenCapture
  private val CHANNEL = "screen_capture"
  private var flutterChannel: MethodChannel? = null

  override fun onServiceConnected() {
    super.onServiceConnected()

    val engine = MainActivity.flutterEngineInstance
    if (engine != null) {
        val messenger = engine.dartExecutor.binaryMessenger
        flutterChannel = MethodChannel(messenger, CHANNEL)
    }
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    event ?: return

    // Kita hanya tangani perubahan window (paket aplikasi baru)
    if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
      val pkg = event.packageName?.toString() ?: return

        Log.d("ACCESSIBILITY", "Aplikasi aktif: $pkg")

      if (pkg in whitelist) {
        // Jika paket termasuk whitelist → aktifkan capture
        flutterChannel?.invokeMethod("enableCapture", null)
      } else {
        // Pakai diluar whitelist → matikan capture
        flutterChannel?.invokeMethod("disableCapture", null)
      }
    }
  }

  override fun onInterrupt() {
    // Tidak digunakan
  }
}
