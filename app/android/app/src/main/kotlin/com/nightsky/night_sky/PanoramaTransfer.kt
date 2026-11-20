package com.nightsky.night_sky

import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLongArray

internal data class PanoramaTile(val name: String, val bytes: Long, val sha256: String)

/** Portable download engine: bounded concurrency, exact checksums and atomic tile publication. */
internal class PanoramaTransfer {
    private val cancelled = AtomicBoolean(false)
    private val connections = ConcurrentHashMap.newKeySet<HttpURLConnection>()
    private val pool = Executors.newFixedThreadPool(4)

    fun cancel() {
        cancelled.set(true)
        connections.forEach { it.disconnect() }
        pool.shutdownNow()
    }

    private fun checkRunning() {
        if (cancelled.get() || Thread.currentThread().isInterrupted) throw InterruptedException("Download stopped")
    }

    fun fetch(url: String, limit: Long, consume: (ByteArray, Int) -> Unit) {
        checkRunning()
        val connection = URL(url).openConnection() as HttpURLConnection
        connections.add(connection)
        try {
            checkRunning()
            connection.connectTimeout = 30_000
            connection.readTimeout = 120_000
            connection.setRequestProperty("User-Agent", "NightSky-Panorama/1")
            connection.instanceFollowRedirects = true
            if (connection.responseCode != 200) throw IOException("Download HTTP ${connection.responseCode}")
            connection.inputStream.use { input ->
                val buffer = ByteArray(64 * 1024)
                var received = 0L
                while (true) {
                    checkRunning()
                    val size = input.read(buffer)
                    if (size < 0) break
                    received += size
                    if (received > limit) throw IOException("Download exceeds expected size")
                    consume(buffer, size)
                }
            }
        } finally {
            connections.remove(connection)
            connection.disconnect()
        }
    }

    fun install(folder: File, tiles: List<PanoramaTile>, url: (String) -> String,
                progress: (Long, Long) -> Unit) {
        if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Storage unavailable")
        val total = tiles.sumOf { it.bytes }
        val received = AtomicLongArray(tiles.size)
        val progressLock = Any()
        var lastProgress = 0L
        fun report(force: Boolean = false) = synchronized(progressLock) {
            val now = System.nanoTime()
            if (force || now - lastProgress >= 250_000_000) {
                lastProgress = now
                progress((0 until tiles.size).sumOf { received.get(it) }, total)
            }
        }
        val completion = ExecutorCompletionService<Unit>(pool)
        try {
            tiles.forEachIndexed { index, tile ->
                require(Regex("\\d{1,2}_\\d{1,2}\\.webp").matches(tile.name))
                completion.submit(java.util.concurrent.Callable {
                    checkRunning()
                    val target = File(folder, tile.name)
                    if (!matches(target, tile)) {
                        val temporary = File(folder, "${tile.name}.part")
                        try {
                            var count = 0L
                            temporary.outputStream().use { output ->
                                fetch(url(tile.name), tile.bytes) { bytes, size ->
                                    output.write(bytes, 0, size)
                                    count += size
                                    received.set(index, count)
                                    report()
                                }
                                output.fd.sync()
                            }
                            if (!matches(temporary, tile)) throw IOException("Download checksum mismatch")
                            checkRunning()
                            if (target.exists() && !target.delete()) throw IOException("Cannot replace damaged tile")
                            if (!temporary.renameTo(target)) throw IOException("Cannot save tile")
                        } finally { temporary.delete() }
                    }
                    received.set(index, tile.bytes)
                    report()
                    Unit
                })
            }
            var finished = 0
            while (finished < tiles.size) {
                checkRunning()
                val task = completion.poll(500, TimeUnit.MILLISECONDS) ?: continue
                task.get()
                finished++
            }
            checkRunning()
            report(true)
        } finally {
            cancel()
            pool.awaitTermination(130, TimeUnit.SECONDS)
        }
    }

    companion object {
        fun matches(file: File, tile: PanoramaTile): Boolean {
            if (!file.isFile || file.length() != tile.bytes) return false
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val size = input.read(buffer)
                    if (size < 0) break
                    digest.update(buffer, 0, size)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) } == tile.sha256
        }
    }
}
