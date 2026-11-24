package app.avet

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import app.avet.R
import app.avet.libbox.BridgeOptions
import app.avet.libbox.BridgeSession
import app.avet.libbox.CommandServer
import app.avet.libbox.CommandServerHandler
import app.avet.libbox.ConnectionOwner
import app.avet.libbox.ExchangeContext
import app.avet.libbox.InterfaceUpdateListener
import app.avet.libbox.Libbox
import app.avet.libbox.LocalDNSTransport
import app.avet.libbox.NeighborUpdateListener
import app.avet.libbox.NetworkInterface
import app.avet.libbox.NetworkInterfaceIterator
import app.avet.libbox.Notification as BoxNotification
import app.avet.libbox.OverrideOptions
import app.avet.libbox.PlatformInterface
import app.avet.libbox.PlatformUser
import app.avet.libbox.SetupOptions
import app.avet.libbox.ShellSession
import app.avet.libbox.StringIterator
import app.avet.libbox.SystemProxyStatus
import app.avet.libbox.TunOptions
import app.avet.libbox.WIFIState
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * AVET's VPN on the phone: the sing-box core (libbox) runs here, the device's traffic comes to it through a TUN, and
 * the core's own sockets are kept out of the VPN.
 */
class AvetService : VpnService(), PlatformInterface, CommandServerHandler {
    companion object {
        const val ACTION_START = "app.avet.START"
        const val ACTION_STOP = "app.avet.STOP"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_SECRET = "secret"
        private const val TAG = "AvetService"
        private const val CHANNEL = "vpn_quiet"
        private const val NOTICE_ID = 1

        @Volatile var running = false

        /** whether the app's screen is in front: then it keeps the statistics itself, else the collector does */
        @Volatile var uiForeground = false

        /** the service while it runs: the app sends it the text of the notification */
        @Volatile var instance: AvetService? = null
        @Volatile var lastError: String? = null

        /** The network the core's servers are for now: "wifi" or "mobile". */
        @Volatile var network = ""

        /** How many times the servers were switched to the other network since the start. */
        @Volatile var switches = 0

        /** How long the new network has to hold before the servers follow it (a short drop doesn't switch). */
        private const val SETTLE_MS = 300L
        private var setUp = false
        private var memoryMb = 450
    }

    private var server: CommandServer? = null
    private var tun: ParcelFileDescriptor? = null
    private val connectivity by lazy { getSystemService(ConnectivityManager::class.java) }
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // the config (both networks' servers in it) and the key of the core's local control
    private var config = ""
    private var secret = ""
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private val reloads = Executors.newSingleThreadExecutor()
    private var pendingSwitch: Runnable? = null

    /** The last start, kept while the VPN is wanted: the system starts the service again from it if it killed the process. */
    private val resumeFile by lazy { File(filesDir, "resume.json") }
    @Volatile private var userStop = false
    private val restarts = ArrayDeque<Long>()

    private fun saveResume(config: String, secret: String, memory: Int) {
        try {
            resumeFile.writeText(
                org.json.JSONObject().put("config", config).put("secret", secret).put("memoryMb", memory).toString(),
            )
        } catch (_: Exception) {}
    }

    private fun clearResume() {
        try { resumeFile.delete() } catch (_: Exception) {}
    }

    /** A line of the logcat and of the diagnostic log. */
    private fun note(level: String, text: String, e: Throwable? = null) {
        when (level) {
            "E" -> Log.e(TAG, text, e)
            "W" -> Log.w(TAG, text, e)
            else -> Log.i(TAG, text)
        }
        Diag.log("$level service: $text" + (e?.let { " (" + it.javaClass.simpleName + ": " + it.message + ")" } ?: ""))
    }

    private var startedAt = System.currentTimeMillis()

    /** whether the Superlight mode is on (read from the settings file the app keeps) */
    private fun superLight(): Boolean = try {
        org.json.JSONObject(File(filesDir, "rules.json").readText()).optBoolean("superLight", false)
    } catch (_: Exception) {
        false
    }

    /** Every few minutes while the VPN runs: the memory, the battery, the state of the system, the network. */
    private val sampler = object : Runnable {
        override fun run() {
            if (!running) return
            try {
                val rt = Runtime.getRuntime()
                val status = File("/proc/self/status").readLines()
                val rss = status.firstOrNull { it.startsWith("VmRSS") }?.filter { it.isDigit() }?.toLongOrNull()?.div(1024)
                val threads = status.firstOrNull { it.startsWith("Threads") }?.filter { it.isDigit() }
                val battery = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val level = battery?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val charging = (battery?.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
                val power = getSystemService(android.os.PowerManager::class.java)
                Diag.log(
                    "I sample: up=${(System.currentTimeMillis() - startedAt) / 60000}min rss=${rss}MB " +
                        "heap=${(rt.totalMemory() - rt.freeMemory()) / 1048576}MB threads=$threads battery=$level% " +
                        "charging=$charging idle=${power.isDeviceIdleMode} saver=${power.isPowerSaveMode} " +
                        "free=${power.isIgnoringBatteryOptimizations(packageName)} net=$network switches=$switches " +
                        "collector=${collector != null} ui=$uiForeground",
                )
                // the tail of the core's own log, copied where it can be read after a long run
                val box = File(filesDir, "box.log")
                val dir = Diag.dir()
                if (box.exists() && dir != null) {
                    File(dir, "box-tail.log").writeText(box.readLines().takeLast(300).joinToString("\n"))
                }
            } catch (e: Exception) {
                Diag.log("W sample failed: ${e.message}")
            }
            // (Superlight: less often)
            main.postDelayed(this, if (superLight()) 20 * 60_000L else 5 * 60_000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Diag.init(this)
        Diag.log("I service: onStartCommand action=${intent?.action} restart=${intent == null}")
        if (intent?.action == ACTION_STOP) {
            userStop = true
            clearResume()
            stopCore()
            stopSelf()
            return START_NOT_STICKY
        }
        userStop = false
        var cfg = intent?.getStringExtra(EXTRA_CONFIG)
        var key = intent?.getStringExtra(EXTRA_SECRET) ?: ""
        var memory = intent?.getIntExtra("memoryMb", 450) ?: 450
        if (cfg == null) {
            // started again by the system after it ended the process: the last start, if the VPN was still wanted
            try {
                val last = org.json.JSONObject(resumeFile.readText())
                cfg = last.getString("config")
                key = last.optString("secret", "")
                memory = last.optInt("memoryMb", 450)
                note("W", "started again by the system: resuming the VPN")
            } catch (_: Exception) {
                return START_NOT_STICKY
            }
        } else {
            saveResume(cfg, key, memory)
        }
        memoryMb = memory
        config = withMemoryLimit(cfg!!)
        secret = key
        switches = 0
        val kind = kindOf(currentUnderlying())
        showNotice(kind)
        reloads.execute { startCore(kind) }
        return START_STICKY
    }

    override fun onRevoke() {
        Diag.log("W service: the VPN permission was revoked")
        userStop = true
        clearResume()
        stopCore()
        stopSelf()
    }

    override fun onDestroy() {
        Diag.log("I service: onDestroy (userStop=$userStop)")
        instance = null
        stopCore()
        super.onDestroy()
    }

    /** "mobile" for cellular data, "wifi" for the rest (Wi-Fi, Ethernet, unknown). */
    private fun kindOf(network: Network?): String {
        val caps = network?.let { connectivity.getNetworkCapabilities(it) } ?: return "wifi"
        return if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        ) "mobile" else "wifi"
    }

    /**
     * The device moved to another network: once it holds for [SETTLE_MS], the choice is pointed at that network's own
     * automatic group. The core is not restarted: the TUN and the core stay, only the way out changes (connections
     * made through the old network are interrupted so they come back through the new one).
     */
    private fun onNetwork(kind: String) {
        pendingSwitch?.let { main.removeCallbacks(it) }
        pendingSwitch = null
        if (!running || kind == network) return
        val task = Runnable {
            pendingSwitch = null
            if (!running || kind == network || kindOf(currentUnderlying()) != kind) return@Runnable
            reloads.execute {
                try {
                    choose("auto-$kind")
                    network = kind
                    switches++
                    note("I", "servers switched to $kind")
                    main.post { showNotice(kind) }
                    // the new network's servers measured at once, so Auto takes the best of them
                    testGroup("auto-$kind")
                } catch (e: Exception) {
                    note("E", "switch to $kind failed", e)
                    lastError = e.message ?: e.toString()
                }
            }
        }
        pendingSwitch = task
        main.postDelayed(task, SETTLE_MS)
    }

    /** Every 10 s while running: the servers follow the network even if a change was not reported. */
    private val watch = object : Runnable {
        override fun run() {
            if (!running) return
            val kind = kindOf(currentUnderlying())
            if (kind != network && pendingSwitch == null) {
                note("I", "check: network is $kind, servers are for $network")
                onNetwork(kind)
            }
            main.postDelayed(this, 10_000)
        }
    }

    /** The core's local control (127.0.0.1, with the key): one request, its HTTP code. */
    private fun control(method: String, path: String, body: String? = null, timeoutMs: Int = 3000): Int {
        val c = java.net.URL("http://127.0.0.1:9090$path").openConnection() as java.net.HttpURLConnection
        try {
            c.requestMethod = method
            c.connectTimeout = timeoutMs
            c.readTimeout = timeoutMs
            c.setRequestProperty("Authorization", "Bearer $secret")
            if (body != null) {
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                c.outputStream.use { it.write(body.toByteArray()) }
            }
            return c.responseCode
        } finally {
            c.disconnect()
        }
    }

    /** Points the choice by hand at [tag]; tried a few times, the control comes up with the core. */
    private fun choose(tag: String) {
        var last: Exception? = null
        repeat(10) {
            try {
                val code = control("PUT", "/proxies/select", org.json.JSONObject().put("name", tag).toString())
                if (code in 200..299) {
                    // the core's own connections (its DNS client keeps one open) made through the old way are dropped
                    // so they come back through the new one
                    try { server?.resetNetwork() } catch (_: Exception) {}
                    return
                }
                last = Exception("HTTP $code")
            } catch (e: Exception) {
                last = e
            }
            Thread.sleep(200)
        }
        throw last ?: Exception("no answer")
    }

    /** Measures a group's servers now (in the background). */
    private fun testGroup(tag: String) {
        Thread {
            try {
                control(
                    "GET", "/group/$tag/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000",
                    timeoutMs = 15000,
                )
            } catch (_: Exception) {}
        }.start()
    }

    /**
     * The memory the core may use: a quarter of the device's (but not under 600 MB), as a soft limit for Go's collector (it
     * collects harder near it, and never kills anything). With no limit a weak phone or a TV box could let the heap grow
     * until the system ended the process; a limit that is too low makes every connection wait for the collector (the lag).
     * The setting "memory limit" off (0) leaves the core free.
     */
    private fun withMemoryLimit(cfg: String): String {
        if (memoryMb <= 0) return cfg
        return try {
            val info = android.app.ActivityManager.MemoryInfo()
            (getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager).getMemoryInfo(info)
            val limit = maxOf(info.totalMem / 4, 600L * 1024 * 1024)
            val json = org.json.JSONObject(cfg)
            // (the debug options of the core are in "experimental")
            val experimental = json.optJSONObject("experimental") ?: org.json.JSONObject()
            val debug = experimental.optJSONObject("debug") ?: org.json.JSONObject()
            if (!debug.has("memory_limit")) debug.put("memory_limit", limit)
            experimental.put("debug", debug)
            json.put("experimental", experimental)
            Diag.log("I service: core memory limit ${limit / 1048576} MB (device ${info.totalMem / 1048576} MB)")
            json.toString()
        } catch (e: Exception) {
            note("W", "memory limit not set", e)
            cfg
        }
    }

    private fun startCore(kind: String) {
        try {
            if (!setUp) {
                val options = SetupOptions()
                options.basePath = filesDir.path
                options.workingPath = File(filesDir, "core").apply { mkdirs() }.path
                options.tempPath = cacheDir.path
                options.fixAndroidStack = true
                Libbox.setup(options)
                setUp = true
            }
            val s = server ?: Libbox.newCommandServer(this, this).also {
                it.start()
                server = it
            }
            s.startOrReloadService(config, OverrideOptions())
            // the network's own automatic group from the start
            try {
                choose("auto-$kind")
            } catch (e: Exception) {
                note("E", "first choice failed", e)
            }
            testGroup("auto-$kind")
            network = kind
            running = true
            startedAt = System.currentTimeMillis()
            Diag.log("I service: core is up ($kind)")
            main.removeCallbacks(sampler)
            main.postDelayed(sampler, 60_000L)
            // started with no screen (the phone's boot, the tile, a restart by the system): the statistics run all the same
            if (!uiForeground) startCollector()
            main.removeCallbacks(watch)
            main.postDelayed(watch, 10_000)
            lastError = null
        } catch (e: Exception) {
            note("E", "start failed", e)
            lastError = e.message ?: e.toString()
            stopCore()
            stopSelf()
        }
    }

    private var collector: io.flutter.embedding.engine.FlutterEngine? = null
    private var collectorChannel: io.flutter.plugin.common.MethodChannel? = null

    /**
     * The statistics while the app is closed or out of sight: a Flutter engine of its own runs the collector
     * (lib/collector.dart), which keeps the session's files as the screen does. Stopped (after saving) when the
     * screen comes back, and with the VPN.
     */
    fun startCollector() {
        main.post {
            if (collector != null || !running) return@post
            // Superlight: switch on and forget, the least memory and CPU: no statistics are kept, no second engine runs
            if (superLight()) return@post
            Diag.log("I collector: starts")
            try {
                val loader = io.flutter.FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val engine = io.flutter.embedding.engine.FlutterEngine(applicationContext, null, false)
                collectorChannel = io.flutter.plugin.common.MethodChannel(engine.dartExecutor.binaryMessenger, "avet/collector")
                collectorChannel?.setMethodCallHandler { call, result ->
                    if (call.method == "diag") Diag.log("I collector: " + (call.argument<String>("text") ?: ""))
                    result.success(null)
                }
                engine.dartExecutor.executeDartEntrypoint(
                    io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "package:avet/collector.dart",
                        "collectorMain",
                    ),
                    listOf(filesDir.path),
                )
                collector = engine
            } catch (e: Exception) {
                note("E", "collector start failed", e)
            }
        }
    }

    /** Asks the collector to save what it has, then stops it; [done] is called when it is gone (at most after 3 s). */
    fun stopCollector(done: (() -> Unit)? = null) {
        main.post {
            val engine = collector
            if (engine == null) {
                done?.invoke()
                return@post
            }
            collector = null
            Diag.log("I collector: stops")
            val channel = collectorChannel
            collectorChannel = null
            var finished = false
            fun end() {
                if (finished) return
                finished = true
                try { engine.destroy() } catch (_: Exception) {}
                done?.invoke()
            }
            main.postDelayed({ end() }, 3000)
            try {
                channel?.invokeMethod("flush", null, object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) = end()
                    override fun error(code: String, message: String?, details: Any?) = end()
                    override fun notImplemented() = end()
                }) ?: end()
            } catch (_: Exception) {
                end()
            }
        }
    }

    /** The screen came in front (the collector hands over) or went out of sight (the collector takes over). */
    fun setUi(foreground: Boolean, done: (() -> Unit)? = null) {
        uiForeground = foreground
        if (foreground) {
            stopCollector(done)
        } else {
            startCollector()
            done?.invoke()
        }
    }

    private fun stopCore() {
        Diag.log("I service: core goes down (userStop=$userStop)")
        main.removeCallbacks(sampler)
        stopCollector()
        main.removeCallbacks(watch)
        pendingSwitch?.let { main.removeCallbacks(it) }
        pendingSwitch = null
        try { server?.closeService() } catch (_: Exception) {}
        try { server?.close() } catch (_: Exception) {}
        server = null
        try { tun?.close() } catch (_: Exception) {}
        tun = null
        networkCallback?.let { try { connectivity.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        networkCallback = null
        running = false
        network = ""
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private var noticeKind = "wifi"
    private var noticeExtra: String? = null

    /** What the notification says besides the network: the server, the ping, the losses (sent by the app every few seconds). */
    fun setNoticeText(text: String) {
        if (noticeExtra == text) return
        noticeExtra = text
        main.post { if (running) showNotice(noticeKind) }
    }

    private fun showNotice(kind: String) {
        noticeKind = kind
        instance = this
        val nm = getSystemService(NotificationManager::class.java)
        // the old channel showed a number on the app's icon all the time; a channel keeps its settings, so a new one
        nm.deleteNotificationChannel("vpn")
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) },
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val notice = Notification.Builder(this, CHANNEL)
            .setContentTitle("AVET")
            .setContentText(noticeExtra ?: (if (kind == "mobile") "VPN включён · LTE" else "VPN включён · Wi-Fi"))
            .addAction(
                Notification.Action.Builder(
                    null,
                    "Выключить",
                    PendingIntent.getService(
                        this, 1, Intent(this, AvetService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE,
                    ),
                ).build(),
            )
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTICE_ID, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTICE_ID, notice)
        }
    }

    // ------------------------------------------------------------------------------------------- the TUN and sockets

    override fun openTun(options: TunOptions): Int {
        val builder = Builder().setSession("AVET").setMtu(options.mtu)
        val v4 = options.inet4Address
        while (v4.hasNext()) v4.next().let { builder.addAddress(it.address(), it.prefix()) }
        val v6 = options.inet6Address
        var hasV6 = false
        while (v6.hasNext()) v6.next().let { builder.addAddress(it.address(), it.prefix()); hasV6 = true }
        if (options.autoRoute) {
            val dns = options.dnsServerAddress
            while (dns.hasNext()) builder.addDnsServer(dns.next())
            val r4 = options.inet4RouteAddress
            if (r4.hasNext()) {
                while (r4.hasNext()) r4.next().let { builder.addRoute(it.address(), it.prefix()) }
            } else {
                builder.addRoute("0.0.0.0", 0)
            }
            val r6 = options.inet6RouteAddress
            if (r6.hasNext()) {
                while (r6.hasNext()) r6.next().let { builder.addRoute(it.address(), it.prefix()) }
            } else if (hasV6) {
                builder.addRoute("::", 0)
            }
        }
        // the app is not left out of its own VPN: the core's TCP stack answers the device's connections through the
        // TUN; the core's own sockets are kept out by protect() (autoDetectInterfaceControl)
        val fd = builder.establish() ?: throw Exception("no VPN permission")
        // a reload for the other network opens a new TUN: the old one is let go once the new one is up
        val old = tun
        tun = fd
        try { old?.close() } catch (_: Exception) {}
        return fd.fd
    }

    override fun usePlatformAutoDetectInterfaceControl() = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    // ------------------------------------------------------------------------------------------- the device's network

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = report(network, listener)
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = report(network, listener)
            override fun onLinkPropertiesChanged(network: Network, link: android.net.LinkProperties) =
                report(network, listener)
            override fun onLost(network: Network) = listener.updateDefaultInterface("", -1, false, false)
        }
        networkCallback?.let { old -> try { connectivity.unregisterNetworkCallback(old) } catch (_: Exception) {} }
        networkCallback = callback
        note("I", "network monitor started")
        // the core needs the network at once, not on the first callback: the one the device uses now (not a VPN)
        currentUnderlying()?.let { report(it, listener) }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        if (Build.VERSION.SDK_INT >= 31) {
            connectivity.registerBestMatchingNetworkCallback(request, callback, android.os.Handler(mainLooper))
        } else {
            connectivity.requestNetwork(request, callback)
        }
    }

    /** The network the device's traffic goes out by: the active one when it is not a VPN, else Wi-Fi, else any. */
    private fun currentUnderlying(): Network? {
        fun ok(n: Network): Boolean {
            val caps = connectivity.getNetworkCapabilities(n) ?: return false
            return !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        }
        connectivity.activeNetwork?.let { if (ok(it)) return it }
        @Suppress("DEPRECATION")
        val all = connectivity.allNetworks.filter(::ok)
        return all.firstOrNull {
            connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } ?: all.firstOrNull()
    }

    private fun report(network: Network, listener: InterfaceUpdateListener) {
        val name = connectivity.getLinkProperties(network)?.interfaceName ?: return
        val index = try { java.net.NetworkInterface.getByName(name)?.index ?: -1 } catch (_: Exception) { -1 }
        val caps = connectivity.getNetworkCapabilities(network)
        val metered = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true
        listener.updateDefaultInterface(name, index, metered, false)
        note("I", "network now: $name (${kindOf(network)})")
        onNetwork(kindOf(network))
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        note("I", "network monitor closed")
        networkCallback?.let { try { connectivity.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        networkCallback = null
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val list = mutableListOf<NetworkInterface>()
        @Suppress("DEPRECATION")
        for (network in connectivity.allNetworks) {
            val caps = connectivity.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            val link = connectivity.getLinkProperties(network) ?: continue
            val name = link.interfaceName ?: continue
            val sys = try { java.net.NetworkInterface.getByName(name) } catch (_: Exception) { null } ?: continue
            list += NetworkInterface().apply {
                this.name = name
                index = sys.index
                mtu = sys.mtu
                addresses = Strings(link.linkAddresses.map { "${it.address.hostAddress}/${it.prefixLength}" })
                // IFF_UP | IFF_BROADCAST | IFF_RUNNING | IFF_MULTICAST
                flags = 0x1 or 0x2 or 0x40 or 0x1000
                type = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                dnsServer = Strings(link.dnsServers.mapNotNull { it.hostAddress })
                metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            }
        }
        return object : NetworkInterfaceIterator {
            private val it = list.iterator()
            override fun hasNext() = it.hasNext()
            override fun next() = it.next()
        }
    }

    override fun findConnectionOwner(
        ipProtocol: Int, sourceAddress: String, sourcePort: Int, destinationAddress: String, destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < 29) throw Exception("not supported")
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol, InetSocketAddress(sourceAddress, sourcePort), InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid < 0) throw Exception("not found")
        return ConnectionOwner().apply {
            userId = uid
            setAndroidPackageNames(Strings(packageManager.getPackagesForUid(uid)?.toList() ?: emptyList()))
        }
    }

    /**
     * The device's own DNS, asked on the network the traffic goes out by (not through the VPN): the core finds the
     * servers' addresses with it.
     */
    private val dnsExecutor = Executors.newCachedThreadPool()
    private val systemDns = object : LocalDNSTransport {
        override fun raw() = Build.VERSION.SDK_INT >= 29

        override fun exchange(ctx: ExchangeContext, message: ByteArray) {
            val done = CountDownLatch(1)
            val cancel = android.os.CancellationSignal()
            android.net.DnsResolver.getInstance().rawQuery(
                currentUnderlying(), message, android.net.DnsResolver.FLAG_NO_RETRY, dnsExecutor, cancel,
                object : android.net.DnsResolver.Callback<ByteArray> {
                    override fun onAnswer(answer: ByteArray, rcode: Int) {
                        ctx.rawSuccess(answer)
                        done.countDown()
                    }

                    override fun onError(error: android.net.DnsResolver.DnsException) {
                        ctx.errorCode(error.code)
                        done.countDown()
                    }
                },
            )
            if (!done.await(10, TimeUnit.SECONDS)) {
                cancel.cancel()
                throw Exception("DNS timeout")
            }
        }

        override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
            val found = (currentUnderlying()?.getAllByName(domain) ?: InetAddress.getAllByName(domain)).filter {
                when (network) {
                    "ip4" -> it is java.net.Inet4Address
                    "ip6" -> it is java.net.Inet6Address
                    else -> true
                }
            }
            if (found.isEmpty()) throw Exception("no address for $domain")
            ctx.success(found.joinToString("\n") { it.hostAddress ?: "" })
        }
    }

    override fun underNetworkExtension() = false
    override fun includeAllNetworks() = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun localDNSTransport(): LocalDNSTransport = systemDns
    override fun registerMyInterface(name: String) {}

    // ------------------------------------------------------------------------------------------- not used by AVET

    override fun sendNotification(notification: BoxNotification) {}
    override fun cancelNotification(identifier: String, typeID: Int) {}
    override fun startNeighborMonitor(listener: NeighborUpdateListener) {}
    override fun closeNeighborMonitor(listener: NeighborUpdateListener) {}
    override fun usePlatformShell() = false
    override fun checkPlatformShell(): Unit = throw Exception("not supported")
    override fun openShellSession(
        user: PlatformUser, command: String, environ: StringIterator, term: String, rows: Int, cols: Int,
    ): ShellSession = throw Exception("not supported")
    override fun lookupUser(username: String): PlatformUser = throw Exception("not supported")
    override fun lookupSFTPServer(): String = throw Exception("not supported")
    override fun readSystemSSHHostKey(): String = throw Exception("not supported")
    override fun tailscaleHostname() = ""
    override fun usePlatformBridge() = false
    override fun createBridge(options: BridgeOptions): BridgeSession = throw Exception("not supported")

    // CommandServerHandler
    override fun serviceStop() {
        // the core stopped by itself (it reached its memory limit, or failed): started again, unless the user switched
        // it off, and not more than three times in ten minutes (a core that keeps failing is left stopped)
        val now = System.currentTimeMillis()
        synchronized(restarts) {
            while (restarts.isNotEmpty() && now - restarts.first() > 10 * 60_000L) restarts.removeFirst()
            if (!userStop && running && restarts.size < 3) {
                restarts.addLast(now)
                note("W", "the core stopped by itself: starting it again")
                main.post {
                    stopCore()
                    val kind = kindOf(currentUnderlying())
                    showNotice(kind)
                    reloads.execute {
                        try { Thread.sleep(1500) } catch (_: Exception) {}
                        startCore(kind)
                    }
                }
                return
            }
        }
        clearResume()
        stopCore()
        stopSelf()
    }
    override fun serviceReload() {}
    override fun getSystemProxyStatus() = SystemProxyStatus()
    override fun setSystemProxyEnabled(enabled: Boolean) {}
    override fun triggerNativeCrash() {}
    override fun writeDebugMessage(message: String) { Log.d(TAG, message) }
    override fun connectSSHAgent(): Int = throw Exception("not supported")
}

/** A list of strings as the core reads them. */
class Strings(private val items: List<String>) : StringIterator {
    private var i = 0
    override fun hasNext() = i < items.size
    override fun len() = items.size
    override fun next() = items[i++]
}
