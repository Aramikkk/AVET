package app.avet

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import java.io.File
import org.json.JSONObject

/**
 * The quick-settings tile: a tap switches the VPN. Off, it starts with the last config the app built (no screen opens);
 * only when there is nothing to start with (no VPN permission yet, no config made) does it open the app to connect.
 */
class AvetTile : TileService() {
    private val main = Handler(Looper.getMainLooper())

    override fun onStartListening() = refresh()

    private fun refresh(running: Boolean = AvetService.running) {
        val tile = qsTile ?: return
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "AVET"
        tile.icon = Icon.createWithResource(this, R.drawable.ic_notification)
        tile.updateTile()
    }

    override fun onClick() {
        if (AvetService.running) {
            startService(Intent(this, AvetService::class.java).setAction(AvetService.ACTION_STOP))
            refresh(false)
            main.postDelayed({ refresh() }, 1500)
            return
        }
        if (startWithLastConfig()) {
            // the tile lights at once; the service's real state is read again a moment later
            refresh(true)
            main.postDelayed({ refresh() }, 2500)
            return
        }
        openApp()
    }

    /** Starts the service with the config of the last start; false when there is no permission or no config to do it. */
    private fun startWithLastConfig(): Boolean {
        return try {
            if (VpnService.prepare(this) != null) return false
            val last = listOf("last_start.json", "resume.json").firstNotNullOfOrNull { name ->
                try {
                    File(filesDir, name).takeIf { it.exists() }?.let { JSONObject(it.readText()) }
                } catch (_: Exception) {
                    null
                }
            } ?: return false
            startForegroundService(
                Intent(this, AvetService::class.java)
                    .setAction(AvetService.ACTION_START)
                    .putExtra(AvetService.EXTRA_CONFIG, last.getString("config"))
                    .putExtra(AvetService.EXTRA_SECRET, last.optString("secret", ""))
                    .putExtra("memoryMb", last.optInt("memoryMb", 450)),
            )
            true
        } catch (e: Exception) {
            Log.w("AvetTile", "start from the tile failed", e)
            false
        }
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("connect", true)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
