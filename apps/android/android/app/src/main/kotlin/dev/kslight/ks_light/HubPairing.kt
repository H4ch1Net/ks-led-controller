package dev.kslight.ks_light

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** App-private, authenticated encryption; the file is excluded from Android backups. */
class HubPairing(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "hub-pairing-v1"))
    private val alias = "ks-light-hub-pairing-v1"
    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        check(create) { "Pairing key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    fun save(address: String, token: String) {
        require(address.length in 1..2048 && token.length in 1..4096)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        val plain = JSONObject().put("address", address).put("token", token).toString().toByteArray(Charsets.UTF_8)
        val encrypted = cipher.doFinal(plain)
        val stream = file.startWrite()
        try {
            stream.write(cipher.iv.size); stream.write(cipher.iv); stream.write(encrypted)
            file.finishWrite(stream)
        } catch (error: Exception) { file.failWrite(stream); throw error }
    }

    fun load(): Map<String, String>? {
        if (!file.baseFile.exists()) return null
        check(file.baseFile.length() <= 32768)
        val data = file.readFully()
        check(data.size > 29 && data[0].toInt() == 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, data.copyOfRange(1, 13)))
        val saved = JSONObject(String(cipher.doFinal(data.copyOfRange(13, data.size)), Charsets.UTF_8))
        return mapOf("address" to saved.getString("address"), "token" to saved.getString("token"))
    }

    fun forget() { file.delete() }
}
