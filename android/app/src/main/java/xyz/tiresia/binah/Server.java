package xyz.tiresia.binah;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.webkit.CookieManager;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Where Binah is, the device token, and the endpoints the native parts use (docs/SHELL.md
 * §5–7). The widget and Train on this send the token (Authorization: Bearer), never the
 * window's cookie; the cookie is used only to make the token, and to save from the share
 * sheet before the phone is connected.
 */
final class Server {
    static final String DEFAULT_BASE = "https://binah.tiresia.xyz";
    private static final String PREFS = "binah";

    private Server() {}

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** http or https, a host, a port if any, no path. */
    static String base(Context c) {
        String n = normal(prefs(c).getString("base", DEFAULT_BASE));
        return n == null ? DEFAULT_BASE : n;
    }

    static String normal(String s) {
        if (s == null) return null;
        Uri u = Uri.parse(s.trim());
        String scheme = u.getScheme() == null ? "" : u.getScheme().toLowerCase();
        if (!(scheme.equals("http") || scheme.equals("https")) || u.getHost() == null || u.getHost().isEmpty()) return null;
        return scheme + "://" + u.getHost().toLowerCase() + (u.getPort() > 0 ? ":" + u.getPort() : "");
    }

    static boolean setBase(Context c, String s) {
        String n = normal(s == null || s.trim().isEmpty() ? DEFAULT_BASE : s);
        if (n == null) return false;
        prefs(c).edit().putString("base", n).apply();
        return true;
    }

    /** A page of Binah ("#today"), or a path on the server ("/api/save"). */
    static String url(Context c, String where) {
        if (where == null || where.isEmpty()) return base(c) + "/";
        if (where.startsWith("#")) return base(c) + "/" + where;
        return base(c) + (where.startsWith("/") ? where : "/" + where);
    }

    /** A page the window may show: the base URL's origin, and nothing else. */
    static boolean isOurs(Context c, Uri u) {
        if (u == null || u.getHost() == null) return false;
        Uri b = Uri.parse(base(c));
        return String.valueOf(u.getScheme()).equalsIgnoreCase(b.getScheme())
                && u.getHost().equalsIgnoreCase(b.getHost()) && port(u) == port(b);
    }

    private static int port(Uri u) {
        return u.getPort() > 0 ? u.getPort() : "https".equalsIgnoreCase(u.getScheme()) ? 443 : 80;
    }

    // ---- the token, encrypted with a key that never leaves the phone's keystore ----

    private static final String KEY = "binah-token-key";

    static String token(Context c) {
        String box = prefs(c).getString("token", null);
        if (box == null) return null;
        try {
            byte[] all = Base64.decode(box, Base64.NO_WRAP);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, all, 0, 12));
            return new String(cipher.doFinal(all, 12, all.length - 12), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return null;
        }
    }

    static boolean setToken(Context c, String token) {
        if (token == null || token.trim().isEmpty()) {
            prefs(c).edit().remove("token").apply();
            return true;
        }
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key());
            byte[] iv = cipher.getIV(), sealed = cipher.doFinal(token.trim().getBytes(StandardCharsets.UTF_8));
            byte[] all = new byte[iv.length + sealed.length];
            System.arraycopy(iv, 0, all, 0, iv.length);
            System.arraycopy(sealed, 0, all, iv.length, sealed.length);
            prefs(c).edit().putString("token", Base64.encodeToString(all, Base64.NO_WRAP)).apply();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static SecretKey key() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(KEY)) return ((KeyStore.SecretKeyEntry) ks.getEntry(KEY, null)).getSecretKey();
        KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        g.init(new KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build());
        return g.generateKey();
    }

    // ---- requests ----

    static final class Failure extends IOException {
        final int status;
        Failure(int status, String message) { super(message); this.status = status; }
    }

    /** GET /api/widget: today's edition at a glance. */
    static JSONObject widget(Context c) throws IOException {
        return json(request(c, "GET", "/api/widget", null, true));
    }

    /** POST /api/save {url?, text?, title?}, with the token or, before the phone is connected,
     *  the window's sign-in. Answers what Binah said ("Saved for later…"). */
    static String save(Context c, String url, String text, String title, boolean withToken) throws IOException {
        try {
            JSONObject body = new JSONObject();
            if (url != null && !url.isEmpty()) body.put("url", url);
            if (text != null && !text.isEmpty()) body.put("text", text);
            if (title != null && !title.isEmpty()) body.put("title", title);
            JSONObject said = json(request(c, "POST", "/api/save", body.toString().getBytes(StandardCharsets.UTF_8), withToken));
            return said.optString("message", "Saved.");
        } catch (org.json.JSONException e) {
            throw new IOException(e);
        }
    }

    /** This device's name in Binah's device list: "android-" and the model, android-sm-s926u. Each
     *  device its own, since making a token replaces the one made under the same name. */
    static String deviceName() {
        String model = String.valueOf(android.os.Build.MODEL).toLowerCase(java.util.Locale.ROOT).replaceAll("[^a-z0-9]+", "-").replaceAll("^-|-$", "");
        String name = "android-" + (model.isEmpty() ? "device" : model);
        return name.length() > 24 ? name.substring(0, 24).replaceAll("-$", "") : name;
    }

    /** Whether the token here was made under this device's own name. */
    static boolean ownToken(Context c) {
        return deviceName().equals(prefs(c).getString("tokenName", ""));
    }

    /** POST /api/devices {"name": deviceName()} with the window's cookie: this device's token. */
    static String connect(Context c) throws IOException {
        try {
            byte[] body = new JSONObject().put("name", deviceName()).toString().getBytes(StandardCharsets.UTF_8);
            String t = json(request(c, "POST", "/api/devices", body, false)).optString("token", "");
            if (t.isEmpty()) throw new Failure(0, "Binah answered without a token.");
            prefs(c).edit().putString("tokenName", deviceName()).apply();
            return t;
        } catch (org.json.JSONException e) {
            throw new IOException(e);
        }
    }

    private static byte[] request(Context c, String method, String path, byte[] body, boolean token) throws IOException {
        HttpURLConnection h = (HttpURLConnection) new URL(url(c, path)).openConnection();
        try {
            h.setRequestMethod(method);
            h.setConnectTimeout(15000);
            h.setReadTimeout(30000);
            h.setUseCaches(false);
            h.setRequestProperty("User-Agent", "Binah/" + Binah.version(c) + " (Android shell)");
            if (token) {
                String t = token(c);
                if (t == null) throw new Failure(0, "This phone isn't connected yet. Open Binah once, signed in.");
                h.setRequestProperty("Authorization", "Bearer " + t);
            } else {
                String cookie = CookieManager.getInstance().getCookie(base(c));
                if (cookie != null) h.setRequestProperty("Cookie", cookie);
            }
            if (body != null) {
                h.setDoOutput(true);
                h.setRequestProperty("Content-Type", "application/json");
                h.setFixedLengthStreamingMode(body.length);
                try (OutputStream out = h.getOutputStream()) { out.write(body); }
            }
            int status = h.getResponseCode();
            byte[] answer = read(status < 400 ? h.getInputStream() : h.getErrorStream());
            if (status >= 200 && status < 300) return answer;
            String detail = null;
            try { detail = new JSONObject(new String(answer, StandardCharsets.UTF_8)).optString("detail", null); } catch (Exception ignored) { }
            if (status == 401) {
                // a token Binah doesn't know (made again elsewhere, or disconnected): gone from here too,
                // so the app makes a new one the next time it's open and signed in
                if (token) setToken(c, null);
                throw new Failure(401, token ? "Binah didn't know this phone's token. Open Binah once to connect it again."
                        : "Sign in to Binah in the app first.");
            }
            throw new Failure(status, detail != null ? detail : "Binah answered " + status + ".");
        } finally {
            h.disconnect();
        }
    }

    private static byte[] read(InputStream in) throws IOException {
        if (in == null) return new byte[0];
        try (InputStream i = in) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] chunk = new byte[16384];
            for (int n; (n = i.read(chunk)) > 0; ) out.write(chunk, 0, n);
            return out.toByteArray();
        }
    }

    private static JSONObject json(byte[] b) throws IOException {
        try {
            return new JSONObject(new String(b, StandardCharsets.UTF_8));
        } catch (org.json.JSONException e) {
            throw new IOException("Binah's answer wasn't JSON");
        }
    }
}
