package com.nightsky.night_sky

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channels:
 * - night_sky/camera: the camera's focal length and physical sensor size (Dart computes the FOV).
 * - night_sky/sensors + night_sky/sensor_events: raw motion-sensor readings. The orientation
 *   maths is done in Dart (sky_math.dart), so it is the same for both sensor modes and testable.
 * - night_sky/settings: app settings stored as one JSON string in SharedPreferences.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager

        MethodChannel(messenger, "night_sky/sensors").setMethodCallHandler { call, result ->
            if (call.method != "available") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            fun has(type: Int) = sensorManager.getDefaultSensor(type) != null
            result.success(
                mapOf(
                    "accelerometer" to has(Sensor.TYPE_ACCELEROMETER),
                    "magnetometer" to has(Sensor.TYPE_MAGNETIC_FIELD),
                    "gyroscope" to has(Sensor.TYPE_GYROSCOPE),
                    "rotationVector" to has(Sensor.TYPE_ROTATION_VECTOR),
                )
            )
        }
        EventChannel(messenger, "night_sky/sensor_events")
            .setStreamHandler(SensorStreamHandler(sensorManager))

        MethodChannel(messenger, "night_sky/settings").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("night_sky", Context.MODE_PRIVATE)
            when (call.method) {
                "load" -> result.success(prefs.getString("settings", null))
                "save" -> {
                    prefs.edit().putString("settings", call.arguments as? String).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "night_sky/camera")
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

/**
 * Streams raw readings as [kind, v0, v1, v2, v3, accuracy, timestampNanos] (v3 = NaN if absent).
 * kind: 0 = accelerometer, 1 = magnetic field, 2 = rotation vector.
 *
 * Listen arguments: {"mode": "compass"} -> accelerometer + magnetometer only (no gyroscope);
 * {"mode": "gyro"} -> Android's rotation vector, which fuses the gyroscope with both.
 */
private class SensorStreamHandler(private val manager: SensorManager) : EventChannel.StreamHandler {
    private var listener: SensorEventListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        val mode = (arguments as? Map<*, *>)?.get("mode") as? String ?: "compass"
        val types = if (mode == "gyro") listOf(Sensor.TYPE_ROTATION_VECTOR)
        else listOf(Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_MAGNETIC_FIELD)
        val sensors = types.mapNotNull { manager.getDefaultSensor(it) }
        if (sensors.size != types.size) {
            events.error("NO_SENSOR", "This phone lacks the sensors for mode '$mode'.", mode)
            return
        }
        val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val kind = when (e.sensor.type) {
                    Sensor.TYPE_ACCELEROMETER -> 0.0
                    Sensor.TYPE_MAGNETIC_FIELD -> 1.0
                    else -> 2.0
                }
                val v = e.values
                events.success(
                    listOf(
                        kind, v[0].toDouble(), v[1].toDouble(), v[2].toDouble(),
                        if (v.size > 3) v[3].toDouble() else Double.NaN,
                        e.accuracy.toDouble(), e.timestamp.toDouble(),
                    )
                )
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
        }
        sensors.forEach { manager.registerListener(l, it, SensorManager.SENSOR_DELAY_GAME) }
        listener = l
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { manager.unregisterListener(it) }
        listener = null
    }
}
