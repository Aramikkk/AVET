package app.avet

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A light diagnostic log: what the service and the app do (starts, stops, restarts of the core, network changes, a sample
 * of the memory and the battery every few minutes). It is kept in the app's folder on the shared storage
 * (Android/data/app.avet/files/diag.log), at most about 1 MB and one older file, so that it can be read after a long run.
 * No addresses, keys or traffic contents are written.
 */
object Diag {
    private var file: File? = null
    private const val LIMIT = 1_000_000L
    private val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    /** where the log is; null before the first [init] */
    fun dir(): File? = file?.parentFile

    @Synchronized
    fun init(context: Context) {
        if (file != null) return
        val dir = context.applicationContext.getExternalFilesDir(null) ?: context.applicationContext.filesDir
        file = File(dir, "diag.log")
    }

    @Synchronized
    fun log(message: String) {
        val f = file ?: return
        try {
            if (f.length() > LIMIT) {
                val old = File(f.parentFile, "diag.1.log")
                old.delete()
                f.renameTo(old)
            }
            f.appendText(format.format(Date()) + " " + message + "\n")
        } catch (_: Exception) {
        }
    }
}
