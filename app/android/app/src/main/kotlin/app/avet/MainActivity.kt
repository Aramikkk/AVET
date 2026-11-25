package app.avet

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The app's screen; the Dart side asks the VPN service to start and stop through the "avet/vpn" channel. */
class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    /** the tile (or a shortcut) asked to connect: the Dart side takes it once */
    private var wantConnect = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        Diag.init(this)
        Diag.log("I app: screen created")
        if (intent?.getBooleanExtra("connect", false) == true) wantConnect = true
        // the notification of the running VPN needs the user's leave on Android 13 and later
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 2)
        }
    }

    /**
     * The screen left the sight (swiped away from the recent apps, or hidden): the service's collector takes the statistics
     * over whatever the Dart side managed to tell (a destroyed screen sends nothing, and the flag stayed "in front").
     */
    override fun onStop() {
        super.onStop()
        val service = AvetService.instance
        if (service == null) AvetService.uiForeground = false else service.setUi(false)
        // the launcher icon asked for while the app was open is changed now that it is out of sight: switching the entry
        // the app was started from while it is in front closes it (the system ends the task of a disabled entry)
        pendingIcon?.let {
            pendingIcon = null
            setLauncherIcon(it)
        }
    }

    /** the launcher icon to show once the app leaves the screen (null: nothing to change) */
    private var pendingIcon: Int? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("connect", false)) wantConnect = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "avet/vpn").setMethodCallHandler { call, result ->
            when (call.method) {
                "dir" -> result.success(filesDir.path)
                // the self-update: where the APK is downloaded to, the installed build, its SHA-256, the system installer
                // the launcher icon: -1 the usual one, else the one tinted in the accent of that palette place
                "setIcon" -> {
                    val index = call.argument<Int>("index") ?: -1
                    // (not at once: when the app leaves the screen, see onStop)
                    pendingIcon = index
                    result.success(true)
                }
                "updateDir" -> {
                    val d = java.io.File(cacheDir, "avet_update")
                    d.mkdirs()
                    result.success(d.path)
                }
                "version" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success(mapOf("name" to (info.versionName ?: ""), "code" to code))
                }
                "sha256" -> {
                    val path = call.argument<String>("path")
                    Thread {
                        val hex = try {
                            val md = java.security.MessageDigest.getInstance("SHA-256")
                            java.io.File(path!!).inputStream().use { input ->
                                val buf = ByteArray(1 shl 16)
                                while (true) {
                                    val n = input.read(buf)
                                    if (n < 0) break
                                    md.update(buf, 0, n)
                                }
                            }
                            md.digest().joinToString("") { "%02x".format(it) }
                        } catch (e: Exception) {
                            ""
                        }
                        runOnUiThread { result.success(hex) }
                    }.start()
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    val allowSettings = call.argument<Boolean>("allowSettings") ?: true
                    result.success(if (path == null) "error" else try { installApk(path, allowSettings) } catch (e: Exception) { "error" })
                }
                // the names of the apps by their uids (the core names a connection's app by its uid)
                "appLabels" -> {
                    val out = HashMap<String, String>()
                    for (uid in call.argument<List<Int>>("uids").orEmpty()) {
                        val pkg = packageManager.getPackagesForUid(uid)?.firstOrNull()
                        if (pkg == null) {
                            // the system's own uids (below 10000) have no package
                            if (uid < 10000) out[uid.toString()] = "Система"
                            continue
                        }
                        out[uid.toString()] = try {
                            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
                        } catch (e: Exception) {
                            pkg
                        }
                    }
                    result.success(out)
                }
                // the apps' icons by their uids, as small PNGs
                "appIcons" -> {
                    val out = HashMap<String, ByteArray>()
                    for (uid in call.argument<List<Int>>("uids").orEmpty()) {
                        val pkg = packageManager.getPackagesForUid(uid)?.firstOrNull() ?: continue
                        try {
                            val d = packageManager.getApplicationIcon(pkg)
                            val size = 96
                            val bmp = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
                            d.setBounds(0, 0, size, size)
                            d.draw(android.graphics.Canvas(bmp))
                            val bytes = java.io.ByteArrayOutputStream()
                            bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, bytes)
                            out[uid.toString()] = bytes.toByteArray()
                        } catch (e: Exception) {
                        }
                    }
                    result.success(out)
                }
                // the launchable apps: package, name and a small icon
                "installedApps" -> {
                    Thread {
                        val list = ArrayList<HashMap<String, Any>>()
                        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        for (info in packageManager.queryIntentActivities(intent, 0)) {
                            val pkg = info.activityInfo.packageName
                            if (pkg == packageName) continue
                            try {
                                val d = info.loadIcon(packageManager)
                                val size = 72
                                val bmp = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
                                d.setBounds(0, 0, size, size)
                                d.draw(android.graphics.Canvas(bmp))
                                val bytes = java.io.ByteArrayOutputStream()
                                bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, bytes)
                                list.add(hashMapOf("pkg" to pkg, "label" to info.loadLabel(packageManager).toString(), "icon" to bytes.toByteArray()))
                            } catch (e: Exception) {
                            }
                        }
                        runOnUiThread { result.success(list) }
                    }.start()
                }
                "notice" -> {
                    AvetService.instance?.setNoticeText(call.argument<String>("text") ?: "")
                    result.success(null)
                }
                // the screen in front or out of sight: out of sight, the service's collector keeps the statistics going
                "uiForeground" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    val service = AvetService.instance
                    if (service == null) {
                        AvetService.uiForeground = on
                        result.success(true)
                    } else {
                        service.setUi(on) { runOnUiThread { result.success(true) } }
                    }
                }
                // whether the app works with no battery limits, and the system's window asking for that
                "batteryFree" -> {
                    val power = getSystemService(android.os.PowerManager::class.java)
                    result.success(power.isIgnoringBatteryOptimizations(packageName))
                }
                "askBattery" -> {
                    try {
                        startActivity(
                            Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(android.net.Uri.parse("package:$packageName")),
                        )
                    } catch (e: Exception) {
                        startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    }
                    result.success(true)
                }
                // a line from the Dart side for the diagnostic log
                "diag" -> {
                    Diag.log("I app: " + (call.argument<String>("text") ?: ""))
                    result.success(null)
                }
                // the country the phone is in (the network's, else the SIM's, else the language's): where what goes direct leaves from
                "homeCountry" -> {
                    val tm = getSystemService(android.telephony.TelephonyManager::class.java)
                    var c = tm?.networkCountryIso ?: ""
                    if (c.isEmpty()) c = tm?.simCountryIso ?: ""
                    if (c.isEmpty()) c = java.util.Locale.getDefault().country
                    result.success(c.uppercase())
                }
                "takeConnect" -> {
                    val want = wantConnect
                    wantConnect = false
                    result.success(want)
                }
                // the gateway of the Wi-Fi the phone is on (a home network is known by its router: no location permission needed)
                "gateway" -> {
                    val cm = getSystemService(android.net.ConnectivityManager::class.java)
                    var gw = ""
                    for (n in cm.allNetworks) {
                        val caps = cm.getNetworkCapabilities(n) ?: continue
                        if (!caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) continue
                        if (caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)) continue
                        val lp = cm.getLinkProperties(n) ?: continue
                        for (r in lp.routes) {
                            if (r.isDefaultRoute && r.gateway != null) gw = r.gateway!!.hostAddress ?: ""
                        }
                    }
                    result.success(gw)
                }
                "prepare" -> {
                    val ask = VpnService.prepare(this)
                    if (ask == null) {
                        result.success(true)
                    } else {
                        pendingPermission = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(ask, 1)
                    }
                }
                "start" -> {
                    val intent = Intent(this, AvetService::class.java)
                        .setAction(AvetService.ACTION_START)
                        .putExtra(AvetService.EXTRA_CONFIG, call.argument<String>("config"))
                        .putExtra(AvetService.EXTRA_SECRET, call.argument<String>("secret"))
                        .putExtra("memoryMb", call.argument<Int>("memoryMb") ?: 450)
                    startForegroundService(intent)
                    result.success(true)
                }
                "stop" -> {
                    startService(Intent(this, AvetService::class.java).setAction(AvetService.ACTION_STOP))
                    result.success(true)
                }
                "status" -> result.success(
                    mapOf(
                        "running" to AvetService.running,
                        "error" to AvetService.lastError,
                        "network" to AvetService.network,
                        "switches" to AvetService.switches,
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("the VPN permission's answer")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1) {
            pendingPermission?.success(resultCode == RESULT_OK)
            pendingPermission = null
        }
    }
    /** Hands the downloaded APK to the system installer: "ok", "permission" (the page that allows it was opened) or "error". */
    private fun installApk(path: String, allowSettings: Boolean): String {
        if (android.os.Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            if (allowSettings) {
                startActivity(
                    Intent(
                        android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        android.net.Uri.parse("package:$packageName"),
                    ),
                )
            }
            return "permission"
        }
        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.updates", java.io.File(path))
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return "ok"
    }
    /** The launcher entry is an alias of this activity; exactly one of them is enabled. Returns whether the icon was changed. */
    private fun setLauncherIcon(index: Int): Boolean {
        val want = if (index < 0) "IconDefault" else "IconA$index"
        val names = listOf("IconDefault") + (0 until 36).map { "IconA$it" }
        if (want !in names) return false
        val pm = packageManager
        fun cn(name: String) = android.content.ComponentName(packageName, "$packageName.$name")
        fun enabled(name: String): Boolean {
            val st = pm.getComponentEnabledSetting(cn(name))
            // "default" is what the manifest says: only IconDefault is enabled there
            return st == android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (st == android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && name == "IconDefault")
        }
        if (enabled(want) && names.none { it != want && enabled(it) }) return false
        // the new one first, then the others off, so that the app is never without an entry
        pm.setComponentEnabledSetting(cn(want), android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED, android.content.pm.PackageManager.DONT_KILL_APP)
        for (n in names) {
            if (n != want && enabled(n)) {
                pm.setComponentEnabledSetting(cn(n), android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED, android.content.pm.PackageManager.DONT_KILL_APP)
            }
        }
        return true
    }
}
