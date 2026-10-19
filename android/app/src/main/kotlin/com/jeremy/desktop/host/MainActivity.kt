package com.jeremy.desktop.host

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.jeremy.desktop/screen_stream"
    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    
    private val CAPTURE_REQ_CODE = 1001
    private val PERM_REQ_CODE = 1002

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestScreenCapture" -> {
                    checkAndRequestLocalNetworkPermissions()
                    startMediaProjectionService()
                    
                    val intent = projectionManager?.createScreenCaptureIntent()
                    startActivityForResult(intent, CAPTURE_REQ_CODE)
                    result.success(true)
                }
                "stopScreenCapture" -> {
                    stopMediaProjectionService()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkAndRequestLocalNetworkPermissions() {
        val permissionsToRequest = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= 33) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.POST_NOTIFICATIONS)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.NEARBY_WIFI_DEVICES)
            }
        }

        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissionsToRequest.toTypedArray(), PERM_REQ_CODE)
        }
    }

    private fun startMediaProjectionService() {
        val serviceIntent = Intent(this, MediaProjectionService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopMediaProjectionService() {
        val serviceIntent = Intent(this, MediaProjectionService::class.java)
        stopService(serviceIntent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CAPTURE_REQ_CODE && resultCode == Activity.RESULT_OK && data != null) {
            mediaProjection = projectionManager?.getMediaProjection(resultCode, data)
        }
    }
}
