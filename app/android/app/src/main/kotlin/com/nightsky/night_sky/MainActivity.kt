package com.nightsky.night_sky

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
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
    private var observingChannel: MethodChannel? = null
    private var askingPermission: MethodChannel.Result? = null

    override fun onResume() {
        super.onResume()
        Observing.restore(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        observingChannel?.invokeMethod("destinationReady", null)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 8162) {
            askingPermission?.success(Observing.permitted(this))
            askingPermission = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        observingChannel = MethodChannel(messenger, "night_sky/observing").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val id = call.arguments as? String ?: ""
                when (call.method) {
                    "destination" -> {
                        val page = intent.action?.removePrefix("night_sky.open.")
                        result.success(page?.takeIf { it in listOf("events", "moon", "sky") })
                        if (intent.action?.startsWith("night_sky.open.") == true) intent.action = null
                    }
                    "status" -> result.success(Observing.status(this, id))
                    "permission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (askingPermission != null) result.success(false) else {
                                askingPermission = result
                                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 8162)
                            }
                        } else result.success(Observing.permitted(this))
                    }
                    "schedule" -> result.success(Observing.events(this).find { it.id == id }
                        ?.let { Observing.schedule(this, it) } ?: false)
                    "cancel" -> { Observing.cancel(this, id); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager

        MethodChannel(messenger, "night_sky/image_cache").setMethodCallHandler { call, result ->
            if (call.method == "directory") {
                result.success(java.io.File(cacheDir, "viewed_images_v1").absolutePath)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, "night_sky/sensors").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> {
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
                "displayRotation" -> result.success(currentDisplayRotationDeg().toInt())
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "night_sky/sensor_events").setStreamHandler(
            SensorStreamHandler(sensorManager, displayManager, ::currentDisplayRotationDeg)
        )

        MethodChannel(messenger, "night_sky/settings").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("night_sky", Context.MODE_PRIVATE)
            when (call.method) {
                "load" -> result.success(prefs.getString("settings", null))
                "save" -> {
                    prefs.edit().putString("settings", call.arguments as? String).apply()
                    Observing.refresh(this)
                    result.success(null)
                }
                // Keyed strings for caches (e.g. the curated-highlights index).
                "loadKey" -> result.success(
                    prefs.getString("cache_" + (call.arguments as String), null))
                "saveKey" -> {
                    val args = call.arguments as Map<*, *>
                    prefs.edit().putString("cache_" + args["key"], args["value"] as? String).apply()
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

    private fun currentDisplayRotationDeg(): Double {
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                display?.rotation
            } catch (_: UnsupportedOperationException) {
                null
            }
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay?.rotation
        }
        return when (rotation) {
            Surface.ROTATION_90 -> 90.0
            Surface.ROTATION_180 -> 180.0
            Surface.ROTATION_270 -> 270.0
            else -> 0.0
        }
    }
}

/**
 * Streams raw readings as [kind, v0, v1, v2, v3, accuracy, timestampNanos, displayRotationDeg]
 * (v3 = NaN if absent).
 * kind: 0 = accelerometer, 1 = magnetic field, 2 = rotation vector, 3 = accuracy, 4 = display rotation.
 *
 * Listen arguments: {"mode": "compass"} -> accelerometer + magnetometer only (no gyroscope);
 * {"mode": "gyro"} -> Android's rotation vector, which fuses the gyroscope with both.
 */
private class SensorStreamHandler(
    private val manager: SensorManager,
    private val displayManager: DisplayManager?,
    private val rotationDeg: () -> Double,
) : EventChannel.StreamHandler {
    private var listener: SensorEventListener? = null
    private var displayListener: DisplayManager.DisplayListener? = null

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
        var lastDisplayDeg = rotationDeg()
        events.success(
            listOf(
                4.0, lastDisplayDeg, 0.0, 0.0,
                Double.NaN, -1.0, System.nanoTime().toDouble(), lastDisplayDeg,
            )
        )

        val dl = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) = Unit
            override fun onDisplayRemoved(displayId: Int) = Unit
            override fun onDisplayChanged(displayId: Int) {
                val deg = rotationDeg()
                if (deg != lastDisplayDeg) {
                    lastDisplayDeg = deg
                    events.success(
                        listOf(
                            4.0, deg, 0.0, 0.0,
                            Double.NaN, -1.0, System.nanoTime().toDouble(), deg,
                        )
                    )
                }
            }
        }
        displayManager?.registerDisplayListener(dl, Handler(Looper.getMainLooper()))
        displayListener = dl

        val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val kind = when (e.sensor.type) {
                    Sensor.TYPE_ACCELEROMETER -> 0.0
                    Sensor.TYPE_MAGNETIC_FIELD -> 1.0
                    else -> 2.0
                }
                val v = e.values
                val deg = rotationDeg()
                lastDisplayDeg = deg
                events.success(
                    listOf(
                        kind, v[0].toDouble(), v[1].toDouble(), v[2].toDouble(),
                        if (v.size > 3) v[3].toDouble() else Double.NaN,
                        e.accuracy.toDouble(), e.timestamp.toDouble(), deg,
                    )
                )
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
                // kind 3 = accuracy-only update [3, sensorKind, accuracy, 0, NaN, accuracy, now, deg]
                val sensorKind = when (sensor.type) {
                    Sensor.TYPE_ACCELEROMETER -> 0.0
                    Sensor.TYPE_MAGNETIC_FIELD -> 1.0
                    else -> 2.0
                }
                val deg = rotationDeg()
                lastDisplayDeg = deg
                events.success(
                    listOf(
                        3.0, sensorKind, accuracy.toDouble(), 0.0,
                        Double.NaN, accuracy.toDouble(), System.nanoTime().toDouble(), deg,
                    )
                )
            }
        }
        sensors.forEach { manager.registerListener(l, it, SensorManager.SENSOR_DELAY_GAME) }
        listener = l
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { manager.unregisterListener(it) }
        listener = null
        displayListener?.let { displayManager?.unregisterDisplayListener(it) }
        displayListener = null
    }
}
