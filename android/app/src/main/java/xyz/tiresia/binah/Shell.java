package xyz.tiresia.binah;

import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.HapticFeedbackConstants;
import android.webkit.WebMessage;
import android.webkit.WebMessagePort;
import android.webkit.WebView;

import org.json.JSONObject;

/**
 * window.binahShell's Android half (docs/SHELL.md §2): haptic, bars, share, openExternal and mic.
 *
 * The page and the app talk over a message port, which the app hands to the main frame after
 * each load ("binah:port"), addressed to Binah's own origin; shell.js builds binahShell on it.
 * A port reaches only the page it was posted to, where addJavascriptInterface would have put
 * the app's calls in every frame. Each call is {id, op, args}; the answer is {id, result}.
 *
 * The first port goes as soon as the page shows, so its calls don't wait for every picture to
 * load; if nothing has come back on it by the time the page has finished loading (shell.js
 * wasn't listening yet), another goes. A document's ports stay open until the next one starts,
 * so a call made on an earlier port still gets its answer there.
 */
final class Shell {
    private final MainActivity activity;
    private final WebView web;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final java.util.List<WebMessagePort> ports = new java.util.ArrayList<>();
    /** Something came back on this document's ports: the page has one. */
    private boolean heard;
    /** What the page has asked, for check.sh ("haptic confirm", "mic true"). */
    static final java.util.List<String> asked = java.util.Collections.synchronizedList(new java.util.ArrayList<>());

    Shell(MainActivity activity, WebView web) {
        this.activity = activity;
        this.web = web;
    }

    /** A port for the page in the window (another one, if it hasn't answered on the first). */
    void connect() {
        WebMessagePort[] ch = web.createWebMessageChannel();
        ports.add(ch[0]);
        ch[0].setWebMessageCallback(new WebMessagePort.WebMessageCallback() {
            @Override
            public void onMessage(WebMessagePort p, WebMessage m) {
                heard = true;
                handle(p, m.getData());
            }
        }, main);
        web.postWebMessage(new WebMessage("binah:port", new WebMessagePort[]{ch[1]}), Uri.parse(Server.base(activity)));
    }

    /** Whether the page has used a port since its document started. */
    boolean heard() {
        return heard;
    }

    /** A new document: the last one's ports go. */
    void close() {
        for (WebMessagePort p : ports) {
            try { p.close(); } catch (RuntimeException ignored) { }
        }
        ports.clear();
        heard = false;
    }

    private void handle(WebMessagePort p, String data) {
        int id = -1;
        try {
            JSONObject m = new JSONObject(data);
            id = m.optInt("id", -1);
            JSONObject a = m.optJSONObject("args");
            if (a == null) a = new JSONObject();
            String op = m.optString("op");
            switch (op) {
                case "haptic":
                    asked.add("haptic " + a.optString("kind"));
                    reply(p, id, haptic(a.optString("kind")));
                    break;
                case "bars":
                    // the page's ground behind the status and navigation bars, light or dark icons
                    asked.add("bars " + a.optString("bg") + " " + (a.optBoolean("dark") ? "dark" : "light"));
                    reply(p, id, activity.bars(a.optString("bg"), a.optBoolean("dark")));
                    break;
                case "share":
                    asked.add("share");
                    reply(p, id, share(a.optString("text"), a.optString("url")));
                    break;
                case "openExternal":
                    asked.add("openExternal " + a.optString("url"));
                    reply(p, id, activity.outside(Uri.parse(a.optString("url"))));
                    break;
                case "mic":
                    // a voice answer is recording: the screen stays on until it stops
                    asked.add("mic " + a.optBoolean("on"));
                    activity.recording(a.optBoolean("on"));
                    reply(p, id, true);
                    break;
                default:
                    asked.add("unknown " + op);
                    reply(p, id, false);
            }
        } catch (Exception e) {
            reply(p, id, false);
        }
    }

    /** A tap felt in the hand: confirm (a right answer), reject (a miss), tick (a choice, a tab). */
    private boolean haptic(String kind) {
        int k = "confirm".equals(kind) ? HapticFeedbackConstants.CONFIRM
                : "reject".equals(kind) ? HapticFeedbackConstants.REJECT
                : HapticFeedbackConstants.CLOCK_TICK;
        web.performHapticFeedback(k);
        return true;
    }

    /** The share sheet, with a link or text. */
    private boolean share(String text, String url) {
        String all = (text + (url.isEmpty() || text.contains(url) ? "" : (text.isEmpty() ? "" : "\n") + url)).trim();
        if (all.isEmpty()) return false;
        Intent send = new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, all);
        activity.startActivity(Intent.createChooser(send, null));
        return true;
    }

    private void reply(WebMessagePort p, int id, boolean result) {
        String json = "{\"id\":" + id + ",\"result\":" + result + "}";
        main.post(() -> {
            try { p.postMessage(new WebMessage(json)); } catch (RuntimeException ignored) { /* the page has gone */ }
        });
    }
}
