package com.example.flutter_media_screen

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
  private val CHANNEL = "screen_capture"
  private val STREAM = "screen_stream"
  private val OVERLAY = "overlay_control" 
  private val REQUEST_CODE = 1001
  private lateinit var mediaProjectionManager: MediaProjectionManager
  private var pendingResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    mediaProjectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

    // 1) MethodChannel untuk requestPermission
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "requestPermission" -> {
            pendingResult = result
            val intent = mediaProjectionManager.createScreenCaptureIntent()
            startActivityForResult(intent, REQUEST_CODE)
          }
          else -> result.notImplemented()
        }
      }

    // 2) EventChannel untuk streaming frame
    EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM)
      .setStreamHandler(object: EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
          // Assign sink ke service static variable
          ScreenCaptureService.eventSink = sink
        }
        override fun onCancel(arguments: Any?) {
          // Clear sink dan stop projection
          ScreenCaptureService.eventSink = null
          ScreenCaptureService.stopProjection()
        }
      })

    // 3) MethodChannel untuk overlay control
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "showOverlay" -> {
            // Panggil fungsi statis di service
            ScreenCaptureService.serviceInstance?.showOverlay()
            result.success(null)
          }
          "removeOverlay" -> {
            ScreenCaptureService.serviceInstance?.removeOverlay()
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == REQUEST_CODE && data != null) {
      pendingResult?.success(true)
      // Start service with the permission data
      val svc = Intent(this, ScreenCaptureService::class.java).apply {
        putExtra("code", resultCode)
        putExtra("data", data)
      }
      startForegroundService(svc)
    } else {
      pendingResult?.success(false)
    }
    pendingResult = null
  }
}
