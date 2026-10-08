package app.convoy.convoy

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Offline convoy mesh over Google Nearby Connections.
 *
 * P2P_CLUSTER lets every phone advertise and discover at once and hold
 * several connections (M-to-N), which is what a line of cars needs. Nearby
 * picks Bluetooth Classic, BLE or Wi-Fi Direct/hotspot on its own and
 * upgrades bandwidth when it can. No internet or cell signal is involved.
 *
 * Only endpoints advertising the same trip tag are connected; frames are
 * additionally authenticated in Dart with the trip's HMAC key.
 */
class ConvoyMeshPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    private var client: ConnectionsClient? = null
    private var tripTag: String = ""
    private var endpointName: String = ""
    private val connected = linkedSetOf<String>()
    private val pending = mutableSetOf<String>()

    companion object {
        const val SERVICE_ID = "app.convoy.mesh"
        val STRATEGY: Strategy = Strategy.P2P_CLUSTER
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "convoy/mesh").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "convoy/mesh/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                tripTag = call.argument<String>("tripTag") ?: ""
                endpointName = call.argument<String>("endpointName") ?: tripTag
                start()
                result.success(null)
            }
            "broadcast" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes != null && connected.isNotEmpty()) {
                    client?.sendPayload(connected.toList(), Payload.fromBytes(bytes))
                }
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start() {
        stop()
        val c = Nearby.getConnectionsClient(context)
        client = c
        c.startAdvertising(
            endpointName, SERVICE_ID, lifecycle,
            AdvertisingOptions.Builder().setStrategy(STRATEGY).build()
        )
        c.startDiscovery(
            SERVICE_ID, discovery,
            DiscoveryOptions.Builder().setStrategy(STRATEGY).build()
        )
    }

    private fun stop() {
        client?.apply {
            stopAdvertising()
            stopDiscovery()
            stopAllEndpoints()
        }
        client = null
        connected.clear()
        pending.clear()
        emitPeers()
    }

    private fun sameTrip(name: String) = tripTag.isNotEmpty() && name.substringBefore('|') == tripTag

    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            if (!sameTrip(info.endpointName)) return
            if (connected.contains(endpointId) || !pending.add(endpointId)) return
            // Both sides discover each other; the lexically smaller name
            // initiates so we do not race two connection requests.
            if (endpointName > info.endpointName) {
                pending.remove(endpointId)
                return
            }
            client?.requestConnection(endpointName, endpointId, lifecycle)
                ?.addOnFailureListener { pending.remove(endpointId) }
        }

        override fun onEndpointLost(endpointId: String) {
            pending.remove(endpointId)
        }
    }

    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            if (sameTrip(info.endpointName)) {
                client?.acceptConnection(endpointId, payloads)
            } else {
                client?.rejectConnection(endpointId)
            }
        }

        override fun onConnectionResult(endpointId: String, resolution: ConnectionResolution) {
            pending.remove(endpointId)
            if (resolution.status.statusCode == ConnectionsStatusCodes.STATUS_OK) {
                connected.add(endpointId)
            }
            emitPeers()
        }

        override fun onDisconnected(endpointId: String) {
            connected.remove(endpointId)
            emitPeers()
        }
    }

    private val payloads = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            val bytes = payload.asBytes() ?: return
            main.post { sink?.success(mapOf("type" to "payload", "bytes" to bytes)) }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {}
    }

    private fun emitPeers() {
        val n = connected.size
        main.post { sink?.success(mapOf("type" to "peers", "count" to n)) }
    }
}
