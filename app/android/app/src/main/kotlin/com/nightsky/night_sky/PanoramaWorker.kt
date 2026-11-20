package com.nightsky.night_sky

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.AtomicFile
import androidx.core.app.NotificationCompat
import androidx.work.*
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

/** OS-owned work survives leaving the Activity and resumes verified tiles on retry. */
class PanoramaWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    private val transfer = PanoramaTransfer()

    override fun doWork(): Result {
        val k = inputData.getInt("resolution", 0)
        if (k != 16 && k != 32) return Result.failure()
        try {
            setForegroundAsync(notification(k, 0)).get()
            val root = File(applicationContext.filesDir, "nasa2020-v1")
            val folder = File(root, "${k}k")
            val bytes = ByteArrayOutputStream()
            transfer.fetch(assetUrl(k, "manifest.json"), 256 * 1024L) { buffer, size -> bytes.write(buffer, 0, size) }
            val manifestText = bytes.toString("UTF-8")
            val manifest = JSONObject(manifestText)
            val tiles = parseManifest(k, manifest)
            transfer.install(folder, tiles, { assetUrl(k, it) }) { received, total ->
                if (isStopped) { transfer.cancel(); throw InterruptedException("Stopped") }
                val fraction = (received.toDouble() / total).coerceIn(0.0, 0.999)
                setProgressAsync(Data.Builder().putDouble("progress", fraction).build()).get()
                setForegroundAsync(notification(k, (fraction * 100).toInt())).get()
            }
            if (isStopped) return Result.failure()
            atomicWrite(File(folder, "manifest.json"), manifestText)
            atomicWrite(File(root, "active.txt"), if (k == 16) "sixteenK" else "thirtyTwoK")
            runCatching {
                val ready = NotificationCompat.Builder(applicationContext, "panorama_downloads")
                    .setSmallIcon(R.drawable.ic_observing).setContentTitle("${k}K sky map ready")
                    .setContentText("Installed and available offline").setAutoCancel(true)
                    .setContentIntent(Observing.destination(applicationContext, "sky")).build()
                applicationContext.getSystemService(NotificationManager::class.java).notify(4872, ready)
            }
            return Result.success()
        } catch (_: Exception) {
            if (isStopped) return Result.failure()
            return if (runAttemptCount < 5) Result.retry() else Result.failure(
                Data.Builder().putString("error", "Download failed. Check your connection and storage, then retry.").build())
        } finally { transfer.cancel() }
    }

    override fun onStopped() { transfer.cancel(); super.onStopped() }

    private fun notification(k: Int, progress: Int): ForegroundInfo {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel("panorama_downloads", "Sky map downloads", NotificationManager.IMPORTANCE_LOW))
        val notification = NotificationCompat.Builder(applicationContext, "panorama_downloads")
            .setSmallIcon(R.drawable.ic_observing)
            .setContentTitle("Downloading ${k}K sky map")
            .setContentText("$progress% — continues in the background")
            .setProgress(100, progress, false).setOngoing(true).setOnlyAlertOnce(true)
            .setContentIntent(Observing.destination(applicationContext, "sky"))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel",
                WorkManager.getInstance(applicationContext).createCancelPendingIntent(id))
            .build()
        return ForegroundInfo(4871, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    }

    companion object {
        const val JOB = "nasa_panorama_download"
        const val RELEASE = "https://github.com/HSAlpha-Code/NightSky/releases/download/panorama-nasa2020-v1"
        private fun assetUrl(k: Int, name: String) = "$RELEASE/nasa2020-${k}k-$name"

        internal fun parseManifest(k: Int, json: JSONObject): List<PanoramaTile> {
            require(json.getInt("version") == 1 && json.getInt("width") == k * 1024 &&
                json.getInt("height") == k * 512 && json.getInt("tileSize") == 2048 && json.getInt("gutter") == 1)
            val entries = json.getJSONArray("tiles")
            require(entries.length() == k * k / 8)
            val tiles = (0 until entries.length()).map { index ->
                val tile = entries.getJSONObject(index)
                val name = tile.getString("file")
                val bytes = tile.getLong("bytes")
                val hash = tile.getString("sha256")
                require(Regex("\\d{1,2}_\\d{1,2}\\.webp").matches(name) && bytes in 1..(32 * 1024 * 1024L) &&
                    Regex("[a-f0-9]{64}").matches(hash))
                PanoramaTile(name, bytes, hash)
            }
            val names = tiles.map { it.name }.toSet()
            require(names.size == tiles.size)
            for (y in 0 until k / 4) for (x in 0 until k / 2) require("${x}_$y.webp" in names)
            return tiles
        }

        private fun atomicWrite(file: File, text: String) {
            file.parentFile?.mkdirs()
            val atomic = AtomicFile(file)
            val output = atomic.startWrite()
            try { output.write(text.toByteArray(Charsets.UTF_8)); atomic.finishWrite(output) }
            catch (error: Exception) { atomic.failWrite(output); throw error }
        }

        fun start(context: Context, k: Int, directory: String): Map<String, Any?> {
            require(k == 16 || k == 32)
            require(File(directory).canonicalFile == File(context.filesDir, "nasa2020-v1").canonicalFile)
            val existing = status(context)
            if (existing?.get("status") in listOf("RUNNING", "ENQUEUED", "BLOCKED")) return existing!!
            val work = OneTimeWorkRequestBuilder<PanoramaWorker>()
                .setInputData(Data.Builder().putInt("resolution", k).build())
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED)
                    .setRequiresStorageNotLow(true).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS).build()
            WorkManager.getInstance(context).enqueueUniqueWork(JOB, ExistingWorkPolicy.KEEP, work).result.get()
            context.getSharedPreferences(JOB, Context.MODE_PRIVATE).edit()
                .putString("id", work.id.toString()).putInt("resolution", k).commit()
            return status(context)!!
        }

        fun status(context: Context): Map<String, Any?>? {
            val prefs = context.getSharedPreferences(JOB, Context.MODE_PRIVATE)
            val id = prefs.getString("id", null) ?: return null
            val info = WorkManager.getInstance(context).getWorkInfoById(UUID.fromString(id)).get() ?: return null
            return mapOf("id" to id, "resolution" to prefs.getInt("resolution", 0),
                "status" to info.state.name, "progress" to info.progress.getDouble("progress", 0.0),
                "error" to info.outputData.getString("error"))
        }

        fun cancel(context: Context) { WorkManager.getInstance(context).cancelUniqueWork(JOB).result.get() }
    }
}
