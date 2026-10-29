package com.nightsky.night_sky

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Exposes the camera's focal length and physical sensor size so Dart can compute the FOV. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "night_sky/camera")
            .setMethodCallHandler { call, result ->
                if (call.method != "getCameraOptics") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId = call.argument<String>("cameraId")
                        ?: manager.cameraIdList.first {
                            manager.getCameraCharacteristics(it)
                                .get(CameraCharacteristics.LENS_FACING) ==
                                CameraCharacteristics.LENS_FACING_BACK
                        }
                    val chars = manager.getCameraCharacteristics(cameraId)
                    val focal = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                        ?.firstOrNull()
                    val size = chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                    if (focal == null || size == null) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "focalLength" to focal.toDouble(),
                                "sensorWidth" to size.width.toDouble(),
                                "sensorHeight" to size.height.toDouble(),
                            )
                        )
                    }
                } catch (e: Exception) {
                    result.success(null) // FOV is optional; the backend falls back to a default
                }
            }
    }
}
