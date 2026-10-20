package xyz.tiresia.binah.app.core

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyStore
import java.util.Locale
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Where Binah is: the public address by default, a sandbox for testing (Settings). */
object Server {
    const val DEFAULT_BASE = "https://binah.tiresia.xyz"
    fun prefs(c: Context): SharedPreferences = c.getSharedPreferences("binah", Context.MODE_PRIVATE)

    fun base(c: Context): String = normal(prefs(c).getString("base", DEFAULT_BASE)) ?: DEFAULT_BASE

    /** http or https, a host, a port if any, no path. */
    fun normal(s: String?): String? {
        if (s == null) return null
        val u = Uri.parse(s.trim())
        val scheme = u.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https" || u.host.isNullOrEmpty()) return null
        return scheme + "://" + u.host!!.lowercase() + (if (u.port > 0) ":${u.port}" else "")
    }

    fun setBase(c: Context, s: String): Boolean {
        val n = normal(s.ifBlank { DEFAULT_BASE }) ?: return false
        prefs(c).edit().putString("base", n).apply()
        return true
    }

    fun url(c: Context, path: String) = base(c) + path
}

/** This phone's device token (docs/API.md, Signing in), encrypted with a key that never leaves the
 *  phone's keystore. While this app runs beside the WebView app it connects as "android-native-<model>",
 *  so the other's token keeps working. The token is kept as the WebView app keeps its own (prefs
 *  "binah", "token", 12 bytes of IV then AES-GCM), so at the switch-over (README) KEY becomes that
 *  app's "binah-token-key" and the name "android-<model>", and the update opens signed in. */
object Token {
    private const val KEY = "binah-native-token-key"

    val deviceName: String get() {
        val model = Build.MODEL.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9]+"), "-").trim('-')
        return ("android-native-" + model.ifEmpty { "device" }).take(36).trimEnd('-')
    }

    fun get(c: Context): String? {
        val box = Server.prefs(c).getString("token", null) ?: return null
        return runCatching {
            val all = Base64.decode(box, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all, 0, 12))
            String(cipher.doFinal(all, 12, all.size - 12), Charsets.UTF_8)
        }.getOrNull()
    }

    fun set(c: Context, token: String?): Boolean {
        if (token.isNullOrBlank()) { Server.prefs(c).edit().remove("token").apply(); return true }
        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val sealed = cipher.iv + cipher.doFinal(token.trim().toByteArray(Charsets.UTF_8))
            Server.prefs(c).edit().putString("token", Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
        }.isSuccess
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(KEY, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        g.init(KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return g.generateKey()
    }
}

class ApiError(val status: Int, message: String) : IOException(message) {
    val signedOut get() = status == 401
}

/** Binah's JSON API (docs/API.md), with this phone's bearer token. */
object Api {
    val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }
    lateinit var app: Context
    /** Told when the server says 401, so the app can ask for a sign-in. */
    var onSignedOut: (() -> Unit)? = null

    fun userAgent(c: Context) = "Binah/" + runCatching { c.packageManager.getPackageInfo(c.packageName, 0).versionName }.getOrNull() + " (Android native)"

    suspend inline fun <reified T> get(path: String): T = json.decodeFromString(send(path, "GET", null, null))
    suspend inline fun <reified T> post(path: String, body: Map<String, Any?> = emptyMap()): T =
        json.decodeFromString(send(path, "POST", toJson(body).toString().toByteArray(), "application/json"))

    /** A multipart POST: the fields, then the file (Just a Minute, the benchmark's talk). */
    suspend inline fun <reified T> upload(path: String, fields: Map<String, String>, file: ByteArray, name: String, mime: String): T {
        val boundary = "binah-" + UUID.randomUUID()
        val out = ByteArrayOutputStream()
        for ((k, v) in fields) out.write("--$boundary\r\nContent-Disposition: form-data; name=\"$k\"\r\n\r\n$v\r\n".toByteArray())
        out.write("--$boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"$name\"\r\nContent-Type: $mime\r\n\r\n".toByteArray())
        out.write(file)
        out.write("\r\n--$boundary--\r\n".toByteArray())
        return json.decodeFromString(send(path, "POST", out.toByteArray(), "multipart/form-data; boundary=$boundary"))
    }

    suspend fun send(path: String, method: String, body: ByteArray?, type: String?): String = withContext(Dispatchers.IO) {
        val token = Token.get(app) ?: run { withContext(Dispatchers.Main) { onSignedOut?.invoke() }; throw ApiError(401, "Sign in to Binah again.") }
        val h = URL(Server.url(app, path)).openConnection() as HttpURLConnection
        try {
            h.requestMethod = method
            h.connectTimeout = 15_000
            h.readTimeout = 60_000
            h.useCaches = false
            h.setRequestProperty("Authorization", "Bearer $token")
            h.setRequestProperty("User-Agent", userAgent(app))
            if (body != null) {
                h.doOutput = true
                h.setRequestProperty("Content-Type", type)
                h.setFixedLengthStreamingMode(body.size)
                h.outputStream.use { it.write(body) }
            }
            val status = try { h.responseCode } catch (e: IOException) { throw ApiError(0, "Binah didn't answer: ${e.message}") }
            val text = (if (status < 400) h.inputStream else h.errorStream)?.use { String(it.readBytes(), Charsets.UTF_8) } ?: ""
            if (status == 401) { withContext(Dispatchers.Main) { onSignedOut?.invoke() }; throw ApiError(401, "Sign in to Binah again.") }
            if (status !in 200..299) throw ApiError(status, detail(text) ?: "Binah answered $status.")
            text
        } catch (e: ApiError) { throw e } catch (e: IOException) {
            throw ApiError(0, "Binah didn't answer: ${e.message}")
        } finally { h.disconnect() }
    }

    fun detail(text: String): String? = runCatching { json.parseToJsonElement(text).jsonObject["detail"]?.jsonPrimitive?.content }.getOrNull()

    /** A request body from Kotlin values: maps, lists, strings, numbers, booleans and nulls. */
    fun toJson(v: Any?): JsonElement = when (v) {
        null -> kotlinx.serialization.json.JsonNull
        is JsonElement -> v
        is String -> kotlinx.serialization.json.JsonPrimitive(v)
        is Number -> kotlinx.serialization.json.JsonPrimitive(v)
        is Boolean -> kotlinx.serialization.json.JsonPrimitive(v)
        is Map<*, *> -> JsonObject(v.entries.associate { (k, x) -> k.toString() to toJson(x) })
        is List<*> -> kotlinx.serialization.json.JsonArray(v.map { toJson(it) })
        else -> kotlinx.serialization.json.JsonPrimitive(v.toString())
    }

    /** Signs in with the username and password, once, and keeps a device token instead of the cookie:
     *  POST /api/login, then POST /api/devices with that cookie. */
    suspend fun signIn(c: Context, user: String, password: String) = withContext(Dispatchers.IO) {
        fun post(path: String, body: String, cookie: String?): Pair<Int, Pair<String, String?>> {
            val h = URL(Server.url(c, path)).openConnection() as HttpURLConnection
            try {
                h.requestMethod = "POST"
                h.doOutput = true
                h.instanceFollowRedirects = false
                h.setRequestProperty("Content-Type", "application/json")
                h.setRequestProperty("User-Agent", userAgent(c))
                if (cookie != null) h.setRequestProperty("Cookie", cookie)
                h.outputStream.use { it.write(body.toByteArray()) }
                val status = h.responseCode
                val text = (if (status < 400) h.inputStream else h.errorStream)?.use { String(it.readBytes(), Charsets.UTF_8) } ?: ""
                val set = h.headerFields.entries.firstOrNull { it.key.equals("Set-Cookie", true) }?.value
                    ?.firstOrNull { it.startsWith("binah=") }?.substringBefore(';')
                return status to (text to set)
            } catch (e: IOException) { throw ApiError(0, "Binah didn't answer: ${e.message}") } finally { h.disconnect() }
        }
        val (s1, r1) = post("/api/login", toJson(mapOf("user" to user, "password" to password)).toString(), null)
        if (s1 !in 200..299) throw ApiError(s1, detail(r1.first) ?: "Binah answered $s1.")
        val cookie = r1.second ?: throw ApiError(0, "Binah signed in but sent no cookie.")
        val (s2, r2) = post("/api/devices", toJson(mapOf("name" to Token.deviceName)).toString(), cookie)
        if (s2 !in 200..299) throw ApiError(s2, detail(r2.first) ?: "Binah answered $s2.")
        val d = json.decodeFromString<Device>(r2.first)
        if (!Token.set(c, d.token)) throw ApiError(0, "This phone's keystore didn't take the token.")
    }

    /** Polls an attempt every 1.5 s, then every 3 s, until `done` says so (docs/API.md, Answering). */
    suspend fun waitFor(id: Int, done: (Attempt) -> Boolean): Attempt {
        repeat(200) { i ->
            val a: Attempt = get("/api/attempts/$id")
            if (done(a)) return a
            delay(if (i < 10) 1500 else 3000)
        }
        return get("/api/attempts/$id")
    }

    fun escape(id: String): String = Uri.encode(id)
}
