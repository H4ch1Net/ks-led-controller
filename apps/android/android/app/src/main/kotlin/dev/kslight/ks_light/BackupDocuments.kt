package dev.kslight.ks_light

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** User-selected documents only; no storage permission or retained URI access. */
class BackupDocuments(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var exportText: String? = null
    private val requestCode = 6241
    private val maxBytes = 262144

    fun launch(text: String?, result: MethodChannel.Result) {
        if (pending != null) { result.error("BUSY", "A document picker is already open", null); return }
        if (text != null && text.toByteArray(Charsets.UTF_8).size > maxBytes) {
            result.error("INVALID", "Backup is too large", null); return
        }
        pending = result
        exportText = text
        val intent = Intent(if (text == null) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(if (text == null) "*/*" else "application/json")
        if (text != null) intent.putExtra(Intent.EXTRA_TITLE, "ks-light-rooms-scenes.json")
        try { activity.startActivityForResult(intent, requestCode) }
        catch (_: Exception) { finishError("Could not open the document picker") }
    }

    fun onResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val result = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null; exportText = null; result.success(null); return true
        }
        val text = exportText
        // Document providers can be remote; never block the activity thread.
        Thread {
            try {
                val value: Any = if (text != null) {
                    activity.contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write(text.toByteArray(Charsets.UTF_8)); it.flush()
                    } ?: error("No output stream")
                    true
                } else {
                    val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (output.size() + count > maxBytes) error("Backup is too large")
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    } ?: error("No input stream")
                    Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
                }
                activity.runOnUiThread {
                    if (pending === result) {
                        pending = null; exportText = null; result.success(value)
                    }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (pending === result) finishError("Could not read or write the backup. Use a UTF-8 file up to 256 KiB.")
                }
            }
        }.start()
        return true
    }

    private fun finishError(message: String) {
        val result = pending
        pending = null; exportText = null
        result?.error("DOCUMENT_FAILED", message, null)
    }

    fun close() { finishError("Document operation interrupted. Try again when the app is open.") }
}
