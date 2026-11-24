package app.avet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONObject

/** After the phone has started: connects with the last config when the setting is on and the VPN permission is already given. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON"
        ) return
        try {
            val rules = JSONObject(File(context.filesDir, "rules.json").readText())
            if (!rules.optBoolean("boot", false)) {
                Log.i(TAG, "boot: the setting is off")
                note(context, "INFO", "the setting is off")
                return
            }
            if (VpnService.prepare(context) != null) {
                Log.w(TAG, "boot: no VPN permission yet")
                note(context, "WARN", "no VPN permission")
                return
            }
            // the last config the app built; else the last start the service kept
            val last = listOf("last_start.json", "resume.json").firstNotNullOfOrNull { name ->
                try {
                    File(context.filesDir, name).takeIf { it.exists() }?.let { JSONObject(it.readText()) }
                } catch (_: Exception) { null }
            }
            if (last == null) {
                Log.w(TAG, "boot: no config to start with (the app has to connect once)")
                note(context, "WARN", "no config to start with: connect once in the app")
                return
            }
            Log.i(TAG, "boot: starting the VPN")
            note(context, "INFO", "starting the VPN")
            context.startForegroundService(
                Intent(context, AvetService::class.java)
                    .setAction(AvetService.ACTION_START)
                    .putExtra(AvetService.EXTRA_CONFIG, last.getString("config"))
                    .putExtra(AvetService.EXTRA_SECRET, last.optString("secret", ""))
                    .putExtra("memoryMb", last.optInt("memoryMb", 450)),
            )
        } catch (e: Exception) {
            Log.e(TAG, "boot: failed", e)
            note(context, "ERROR", "failed: ${e.message}")
        }
    }

    /** A line in the app's own journal (Settings, Logs) as the core writes its lines: what the start at boot did or why it did not. */
    private fun note(context: Context, level: String, text: String) {
        try {
            val at = SimpleDateFormat("Z yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            File(context.filesDir, "box.log").appendText("$at $level boot: $text\n")
        } catch (_: Exception) {}
    }

    private companion object {
        const val TAG = "AvetBoot"
    }
}
