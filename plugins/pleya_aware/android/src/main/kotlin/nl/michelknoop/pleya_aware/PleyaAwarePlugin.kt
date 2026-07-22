package nl.michelknoop.pleya_aware

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.aware.AttachCallback
import android.net.wifi.aware.DiscoverySessionCallback
import android.net.wifi.aware.PeerHandle
import android.net.wifi.aware.PublishConfig
import android.net.wifi.aware.PublishDiscoverySession
import android.net.wifi.aware.SubscribeConfig
import android.net.wifi.aware.SubscribeDiscoverySession
import android.net.wifi.aware.WifiAwareManager
import android.net.wifi.aware.WifiAwareNetworkInfo
import android.net.wifi.aware.WifiAwareNetworkSpecifier
import android.net.wifi.aware.WifiAwareSession
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Wi-Fi Aware byte-stream transport for Pleya Share.
 *
 * Host: publish + local ServerSocket; when a subscriber messages us we open a
 * responder network with the socket's port; accepted sockets are pumped to
 * Dart as byte streams. Guest: subscribe, discover peers, connect by
 * requesting the peer network and dialing its (ipv6, port).
 */
class PleyaAwarePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()

    private var awareSession: WifiAwareSession? = null
    private var publishSession: PublishDiscoverySession? = null
    private var subscribeSession: SubscribeDiscoverySession? = null
    private var serverSocket: ServerSocket? = null
    private var serviceInfo: String = ""

    private val nextId = AtomicInteger(1)
    private val streams = ConcurrentHashMap<Int, Socket>()
    private val peers = ConcurrentHashMap<Int, PeerHandle>()
    private val networkCallbacks = mutableListOf<ConnectivityManager.NetworkCallback>()

    companion object {
        const val SERVICE_NAME = "pleya-share"
        const val PASSPHRASE_PREFIX = "pleya-aware-"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pleya_aware")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "pleya_aware/events")
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, s: EventChannel.EventSink?) { sink = s }
            override fun onCancel(args: Any?) { sink = null }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        teardown()
    }

    private fun emit(event: Map<String, Any?>) = main.post { sink?.success(event) }

    private val awareManager: WifiAwareManager?
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE)
        ) context.getSystemService(Context.WIFI_AWARE_SERVICE) as? WifiAwareManager else null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(awareManager?.isAvailable == true)
            "startPublishing" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) { result.success(null); return }
                serviceInfo = call.argument<String>("serviceInfo") ?: ""
                startPublishing(result)
            }
            "stopPublishing" -> { stopPublishing(); result.success(null) }
            "startDiscovery" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) { result.success(null); return }
                startDiscovery(result)
            }
            "stopDiscovery" -> { stopDiscovery(); result.success(null) }
            "connect" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) { result.error("unsupported", null, null); return }
                connect(call.argument<Int>("peerId")!!, result)
            }
            "write" -> {
                val id = call.argument<Int>("streamId")!!
                val bytes = call.argument<ByteArray>("bytes")!!
                executor.execute {
                    try { streams[id]?.getOutputStream()?.let { it.write(bytes); it.flush() } } catch (_: Exception) { closeStream(id) }
                }
                result.success(null)
            }
            "closeStream" -> { closeStream(call.argument<Int>("streamId")!!); result.success(null) }
            "presentPairing" -> result.success(null) // Android has no pairing requirement.
            else -> result.notImplemented()
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun withSession(onReady: (WifiAwareSession) -> Unit, onError: () -> Unit) {
        awareSession?.let { onReady(it); return }
        val manager = awareManager ?: run { onError(); return }
        manager.attach(object : AttachCallback() {
            override fun onAttached(session: WifiAwareSession) { awareSession = session; onReady(session) }
            override fun onAttachFailed() = onError()
        }, main)
    }

    // ── Host ──

    @RequiresApi(Build.VERSION_CODES.O)
    private fun startPublishing(result: MethodChannel.Result) {
        withSession(onReady = { session ->
            try {
                val server = ServerSocket(0)
                serverSocket = server
                val config = PublishConfig.Builder()
                    .setServiceName(SERVICE_NAME)
                    .setServiceSpecificInfo(serviceInfo.toByteArray())
                    .build()
                session.publish(config, object : DiscoverySessionCallback() {
                    override fun onPublishStarted(s: PublishDiscoverySession) { publishSession = s }
                    override fun onMessageReceived(peer: PeerHandle, message: ByteArray) {
                        // Subscriber asks to connect: open a responder network
                        // carrying our server port.
                        val publish = publishSession ?: return
                        val specifier = WifiAwareNetworkSpecifier.Builder(publish, peer)
                            .setPskPassphrase(PASSPHRASE_PREFIX + serviceInfo)
                            .setPort(server.localPort)
                            .build()
                        requestAwareNetwork(specifier) { _, _ -> /* responder side: nothing to dial */ }
                        // Accept exactly one socket per request on a worker.
                        executor.execute {
                            try {
                                val socket = server.accept()
                                registerStream(socket, accepted = true)
                            } catch (_: Exception) {}
                        }
                    }
                }, main)
                result.success(null)
            } catch (e: Exception) {
                result.error("publish_failed", e.message, null)
            }
        }, onError = { result.error("attach_failed", null, null) })
    }

    private fun stopPublishing() {
        publishSession?.close(); publishSession = null
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
    }

    // ── Guest ──

    @RequiresApi(Build.VERSION_CODES.O)
    private fun startDiscovery(result: MethodChannel.Result) {
        withSession(onReady = { session ->
            try {
                val config = SubscribeConfig.Builder().setServiceName(SERVICE_NAME).build()
                session.subscribe(config, object : DiscoverySessionCallback() {
                    override fun onSubscribeStarted(s: SubscribeDiscoverySession) { subscribeSession = s }
                    override fun onServiceDiscovered(peer: PeerHandle, info: ByteArray?, filter: List<ByteArray>?) {
                        val id = peer.hashCode()
                        peers[id] = peer
                        discoveredInfo[id] = String(info ?: ByteArray(0))
                        emit(mapOf("type" to "discovered", "peerId" to id, "serviceInfo" to discoveredInfo[id]))
                    }
                }, main)
                result.success(null)
            } catch (e: Exception) {
                result.error("subscribe_failed", e.message, null)
            }
        }, onError = { result.error("attach_failed", null, null) })
    }

    private fun stopDiscovery() {
        subscribeSession?.close(); subscribeSession = null
        peers.clear()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun connect(peerId: Int, result: MethodChannel.Result) {
        val subscribe = subscribeSession
        val peer = peers[peerId]
        if (subscribe == null || peer == null) { result.error("no_peer", null, null); return }
        // The discovered serviceInfo doubles as the PSK suffix; the host set
        // the same. HTTP-level auth still applies on top.
        var replied = false
        subscribe.sendMessage(peer, 0, "c".toByteArray())
        val specifier = WifiAwareNetworkSpecifier.Builder(subscribe, peer)
            .setPskPassphrase(PASSPHRASE_PREFIX + (lastInfoFor(peerId) ?: ""))
            .build()
        requestAwareNetwork(specifier) { network, info ->
            if (replied) return@requestAwareNetwork
            replied = true
            executor.execute {
                try {
                    val socket = network.socketFactory.createSocket(info.peerIpv6Addr, info.port)
                    val id = registerStream(socket, accepted = false)
                    main.post { result.success(id) }
                } catch (e: Exception) {
                    main.post { result.error("connect_failed", e.message, null) }
                }
            }
        }
        // Timeout guard so the Dart future never hangs.
        main.postDelayed({ if (!replied) { replied = true; result.error("timeout", null, null) } }, 15000)
    }

    private val discoveredInfo = ConcurrentHashMap<Int, String>()
    private fun lastInfoFor(peerId: Int): String? = discoveredInfo[peerId]

    @RequiresApi(Build.VERSION_CODES.O)
    private fun requestAwareNetwork(
        specifier: WifiAwareNetworkSpecifier,
        onAvailable: (Network, WifiAwareNetworkInfo) -> Unit,
    ) {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
            .setNetworkSpecifier(specifier)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                val info = caps.transportInfo as? WifiAwareNetworkInfo ?: return
                onAvailable(network, info)
            }
        }
        synchronized(networkCallbacks) { networkCallbacks.add(callback) }
        cm.requestNetwork(request, callback)
    }

    // ── Byte pump ──

    private fun registerStream(socket: Socket, accepted: Boolean): Int {
        val id = nextId.getAndIncrement()
        streams[id] = socket
        if (accepted) emit(mapOf("type" to "accepted", "streamId" to id))
        executor.execute {
            val buffer = ByteArray(64 * 1024)
            try {
                val input = socket.getInputStream()
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    emit(mapOf("type" to "data", "streamId" to id, "bytes" to buffer.copyOf(n)))
                }
            } catch (_: Exception) {
            } finally {
                closeStream(id)
            }
        }
        return id
    }

    private fun closeStream(id: Int) {
        streams.remove(id)?.let {
            try { it.close() } catch (_: Exception) {}
            emit(mapOf("type" to "closed", "streamId" to id))
        }
    }

    private fun teardown() {
        stopPublishing()
        stopDiscovery()
        streams.keys.toList().forEach(::closeStream)
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        synchronized(networkCallbacks) {
            networkCallbacks.forEach { try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {} }
            networkCallbacks.clear()
        }
        awareSession?.close(); awareSession = null
    }
}
