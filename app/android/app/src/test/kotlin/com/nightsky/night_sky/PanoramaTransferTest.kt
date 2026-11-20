package com.nightsky.night_sky

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class PanoramaTransferTest {
    private val payload = ByteArray(32 * 1024) { (it % 251).toByte() }
    private fun tile(name: String) = PanoramaTile(name, payload.size.toLong(),
        MessageDigest.getInstance("SHA-256").digest(payload).joinToString("") { "%02x".format(it.toInt() and 255) })

    @Test fun fourDownloadsRunInParallelAndVerifiedFilesAreReused() {
        val folder = Files.createTempDirectory("panorama-transfer-").toFile()
        val active = AtomicInteger()
        val peak = AtomicInteger()
        val requests = AtomicInteger()
        val fourStarted = CountDownLatch(4)
        val threads = Executors.newCachedThreadPool()
        val server = LocalHttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.executor = threads
        server.createContext("/") { exchange ->
            requests.incrementAndGet()
            val current = active.incrementAndGet()
            peak.updateAndGet { previous -> maxOf(previous, current) }
            fourStarted.countDown()
            fourStarted.await(3, TimeUnit.SECONDS)
            Thread.sleep(30)
            try {
                exchange.sendResponseHeaders(200, payload.size.toLong())
                exchange.responseBody.use { it.write(payload) }
            } finally { active.decrementAndGet(); exchange.close() }
        }
        server.start()
        try {
            val tiles = (0 until 12).map { tile("${it % 4}_${it / 4}.webp") }
            val progress = mutableListOf<Long>()
            val url = { name: String -> "http://127.0.0.1:${server.address.port}/$name" }
            PanoramaTransfer().install(folder, tiles, url) { received, total ->
                assertTrue(received in 0..total)
                progress.add(received)
            }
            assertEquals(4, peak.get())
            assertEquals(12, requests.get())
            assertTrue(progress.zipWithNext().all { (a, b) -> b >= a })
            tiles.forEach { assertTrue(PanoramaTransfer.matches(File(folder, it.name), it)) }
            PanoramaTransfer().install(folder, tiles, url) { _, _ -> }
            assertEquals(12, requests.get())
            assertTrue(folder.listFiles()!!.none { it.name.endsWith(".part") })
        } finally { server.stop(0); threads.shutdownNow(); folder.deleteRecursively() }
    }

    @Test fun cancellationClosesTransfersAndRemovesPartialFiles() {
        val folder = Files.createTempDirectory("panorama-cancel-").toFile()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val threads = Executors.newCachedThreadPool()
        val server = LocalHttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.executor = threads
        server.createContext("/") { exchange ->
            try {
                exchange.sendResponseHeaders(200, payload.size.toLong())
                exchange.responseBody.write(payload, 0, 100)
                exchange.responseBody.flush()
                started.countDown()
                release.await(5, TimeUnit.SECONDS)
            } finally { exchange.close() }
        }
        server.start()
        val transfer = PanoramaTransfer()
        val failure = AtomicReference<Throwable>()
        val caller = Thread {
            try { transfer.install(folder, listOf(tile("0_0.webp")),
                { "http://127.0.0.1:${server.address.port}/$it" }) { _, _ -> } }
            catch (error: Throwable) { failure.set(error) }
        }
        try {
            caller.start()
            assertTrue(started.await(5, TimeUnit.SECONDS))
            transfer.cancel()
            release.countDown()
            caller.join(5_000)
            assertFalse(caller.isAlive)
            assertNotNull(failure.get())
            assertFalse(File(folder, "0_0.webp").exists())
            assertFalse(File(folder, "0_0.webp.part").exists())
        } finally { release.countDown(); server.stop(0); threads.shutdownNow(); folder.deleteRecursively() }
    }

    @Test fun checksumFailureNeverPublishesCorruptTile() {
        val folder = Files.createTempDirectory("panorama-corrupt-").toFile()
        val server = LocalHttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            val bad = payload.clone().also { it[0] = 127 }
            exchange.sendResponseHeaders(200, bad.size.toLong())
            exchange.responseBody.use { it.write(bad) }
            exchange.close()
        }
        server.start()
        try {
            try {
                PanoramaTransfer().install(folder, listOf(tile("0_0.webp")),
                    { "http://127.0.0.1:${server.address.port}/$it" }) { _, _ -> }
                fail("Expected checksum failure")
            } catch (_: java.util.concurrent.ExecutionException) { }
            assertFalse(File(folder, "0_0.webp").exists())
            assertFalse(File(folder, "0_0.webp.part").exists())
        } finally { server.stop(0); folder.deleteRecursively() }
    }
}


/** Tiny real HTTP endpoint using APIs available on the Android unit-test compile path. */
private class LocalHttpServer private constructor(address: InetSocketAddress) {
    private val socket = java.net.ServerSocket().apply { bind(address) }
    private val ownThreads = Executors.newCachedThreadPool()
    var executor: java.util.concurrent.Executor = ownThreads
    val address: InetSocketAddress get() = socket.localSocketAddress as InetSocketAddress
    private var handler: ((Exchange) -> Unit)? = null
    private val clients = java.util.concurrent.ConcurrentHashMap.newKeySet<java.net.Socket>()
    fun createContext(path: String, callback: (Exchange) -> Unit) { handler = callback }
    fun start() {
        ownThreads.execute {
            while (!socket.isClosed) {
                try {
                    val client = socket.accept()
                    clients.add(client)
                    executor.execute {
                        try {
                            client.getInputStream().bufferedReader().let { input ->
                                while (true) { val line = input.readLine() ?: break; if (line.isEmpty()) break }
                            }
                            handler!!(Exchange(client))
                        } catch (_: Exception) { }
                        finally { clients.remove(client); client.close() }
                    }
                } catch (_: java.io.IOException) { break }
            }
        }
    }
    fun stop(delay: Int) {
        socket.close()
        clients.forEach { it.close() }
        ownThreads.shutdownNow()
    }
    class Exchange(private val client: java.net.Socket) {
        val responseBody: java.io.OutputStream get() = client.getOutputStream()
        fun sendResponseHeaders(status: Int, size: Long) {
            responseBody.write(("HTTP/1.1 $status OK\r\nContent-Length: $size\r\nConnection: close\r\n\r\n").toByteArray())
            responseBody.flush()
        }
        fun close() { client.close() }
    }
    companion object {
        fun create(address: InetSocketAddress, backlog: Int) = LocalHttpServer(address)
    }
}
