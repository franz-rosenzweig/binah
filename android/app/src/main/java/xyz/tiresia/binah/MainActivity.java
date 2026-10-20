package xyz.tiresia.binah;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Message;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import android.window.OnBackInvokedDispatcher;

import org.json.JSONObject;

/**
 * Binah: the live site in a WebView (docs/SHELL.md). The page is the whole interface and is
 * phone first; this adds Back through the page (binahBack), the microphone for voice answers,
 * the page's colours behind the system bars, the share sheet and haptics (Shell), and opening
 * on a page of Binah from the widget, the shortcuts and binah://go/<route>.
 *
 * Only Binah loads here: any other address goes to the browser or the app it belongs to.
 */
public class MainActivity extends Activity {
    static final String EXTRA_ROUTE = "binah.route";
    private static final int MIC = 1;

    private WebView web;
    private Shell shell;
    private String loadedBase;

    /** Opens Binah on a page ("#practice"). */
    static Intent open(android.content.Context c, String route) {
        Intent i = new Intent(c, MainActivity.class).setAction(Intent.ACTION_VIEW)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        // distinct data, so PendingIntents for different pages stay different
        i.setData(Uri.parse("binah://go/" + (route == null ? "" : route.replaceFirst("^#", ""))));
        return i;
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        if ((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            WebView.setWebContentsDebuggingEnabled(true);
            // the test build is pointed at a sandbox by check.py, never the real app
            Intent in = getIntent();
            if (in.getStringExtra("binah.base") != null) Server.setBase(this, in.getStringExtra("binah.base"));
            if (in.getStringExtra("binah.token") != null) {
                Server.setToken(this, in.getStringExtra("binah.token"));
                Server.prefs(this).edit().putString("tokenName", Server.deviceName()).apply();   // the check's, kept as this device's
            }
        }
        CookieManager.getInstance().setAcceptCookie(true);

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportMultipleWindows(true);             // target=_blank comes to onCreateWindow, and goes out
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setTextZoom(100);                            // the page sizes its own text, not the phone's font scale twice
        s.setUserAgentString(s.getUserAgentString() + " Binah/" + Binah.version(this) + " (Android shell)");
        web.setWebViewClient(new Pages());
        web.setWebChromeClient(new Chrome());
        shell = new Shell(this, web);
        setContentView(web);
        insets();
        if (Build.VERSION.SDK_INT >= 33) {
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::back);
        }
        loadedBase = Server.base(this);
        web.loadUrl(Server.url(this, route(getIntent())));
        Widget.shortcuts(this);
    }

    /** Signed in, and no token of this phone's own yet: it makes one ("android-<model>") with
     *  the window's sign-in, so the widget and Train on this work without a trip to Settings. */
    private boolean connecting;
    private void connectIfSignedIn() {
        if (connecting || web == null || (Server.token(this) != null && Server.ownToken(this))) return;
        web.evaluateJavascript("!!(window.binahState && binahState().signedIn)", yes -> {
            if (!"true".equals(yes) || connecting) return;
            connecting = true;
            new Thread(() -> {
                try {
                    Server.setToken(this, Server.connect(this));
                    Widget.fetch(this);
                    runOnUiThread(() -> Toast.makeText(this, "This phone is connected to Binah", Toast.LENGTH_SHORT).show());
                } catch (Exception e) {
                    connecting = false;
                }
            }).start();
        });
    }

    /** binah://go/practice → "#practice"; a Binah address as its route; null for Today. */
    private String route(Intent intent) {
        Uri d = intent == null ? null : intent.getData();
        if (d == null) return intent == null ? null : intent.getStringExtra(EXTRA_ROUTE);
        if ("binah".equals(d.getScheme()) && "go".equals(d.getHost())) {
            String p = d.getPath() == null ? "" : d.getPath().replaceFirst("^/", "");
            return p.isEmpty() ? null : "#" + p;
        }
        if (Server.isOurs(this, d) && d.getFragment() != null) return "#" + d.getFragment();
        return null;
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String r = route(intent);
        go(r == null ? "#today" : r);
    }

    /** The page goes to a route: its own go() if it's there, the address otherwise. */
    void go(String route) {
        if (web == null) return;
        String r = route.replaceFirst("^#", "");
        String url = web.getUrl();
        if (url != null && Server.isOurs(this, Uri.parse(url))) {
            web.evaluateJavascript("window.binahCommand ? window.binahCommand(" + JSONObject.quote("go:" + r) + ") : (location.hash = "
                    + JSONObject.quote(r) + ")", null);
        } else {
            web.loadUrl(Server.url(this, "#" + r));
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        // the address changed in Settings: the page again, from there
        if (web != null && !Server.base(this).equals(loadedBase)) {
            loadedBase = Server.base(this);
            web.loadUrl(Server.url(this, ""));
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
        connectIfSignedIn();
        // playing moves the edition along: the widget asks again
        Widget.refreshIfOlder(this, 60 * 1000L);
    }

    // ---- Back ----

    /** A game closes, then Binah goes back; only with nowhere to go does Back leave. */
    private void back() {
        if (web == null) {
            moveTaskToBack(true);
            return;
        }
        web.evaluateJavascript("(() => { try { return !!(window.binahBack && window.binahBack()); } catch (e) { return false; } })()",
                went -> { if (!"true".equals(went)) moveTaskToBack(true); });
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (Build.VERSION.SDK_INT >= 33) super.onBackPressed();
        else back();
    }

    // ---- the microphone (docs/SHELL.md §2) ----

    private PermissionRequest waiting;
    /** What the page's requests were answered, for check.sh. */
    static final java.util.List<String> micAnswers = java.util.Collections.synchronizedList(new java.util.ArrayList<>());

    /** The page asks for audio capture: Binah's own origin, audio only. Android asks once for
     *  the microphone, then the page has it. */
    private void permission(PermissionRequest r) {
        boolean ours = Server.isOurs(this, r.getOrigin());
        boolean audioOnly = r.getResources().length > 0;
        for (String what : r.getResources()) audioOnly &= PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(what);
        if (!ours || !audioOnly) {
            micAnswers.add("deny " + r.getOrigin() + " " + String.join(",", r.getResources()));
            r.deny();
            return;
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            micAnswers.add("grant " + r.getOrigin());
            r.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
            return;
        }
        if (waiting != null) waiting.deny();
        waiting = r;
        requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MIC);
    }

    @Override
    public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (request != MIC || waiting == null) return;
        boolean yes = results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED;
        micAnswers.add((yes ? "grant " : "refused by Android ") + waiting.getOrigin());
        if (yes) waiting.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE}); else waiting.deny();
        waiting = null;
        if (!yes && !shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) {
            Toast.makeText(this, "The microphone is off for Binah. Turn it on in Binah's app settings to answer aloud.", Toast.LENGTH_LONG).show();
        }
    }

    /** A voice answer is recording (Shell's mic): the screen stays on until it stops. */
    void recording(boolean on) {
        if (on) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    // ---- the window ----

    /** The page sits between the status bar and the navigation bar, or the keyboard when
     *  it's open (the WebView gets shorter, so the page's tab bar stays on screen). */
    private void insets() {
        View content = findViewById(android.R.id.content);
        content.setOnApplyWindowInsetsListener((v, in) -> {
            Insets bars = in.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            int ime = in.getInsets(WindowInsets.Type.ime()).bottom;
            v.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom, ime));
            return WindowInsets.CONSUMED;
        });
        paintBars();
    }

    /** Behind the bars, the page's own ground: what the page last said (bars()), else the
     *  vault palette's, light or dark as the phone is. */
    private void paintBars() {
        boolean night = night();
        SharedPreferences t = getSharedPreferences("theme", MODE_PRIVATE);
        String key = night ? "night" : "day";
        int colour = t.getInt(key + ".bg", night ? 0xFF1B1D2B : 0xFFECE3D7);
        boolean dark = t.getBoolean(key + ".dark", night);
        getWindow().getDecorView().setBackgroundColor(colour);
        web.setBackgroundColor(colour);
        WindowInsetsController c = getWindow().getInsetsController();
        int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
        if (c != null) c.setSystemBarsAppearance(dark ? 0 : light, light);
    }

    private boolean night() {
        return (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
    }

    /** The page's ground (#rrggbb) and whether it's dark; kept for the phone's current mode, so
     *  the next start paints the same before the page loads. */
    boolean bars(String bg, boolean dark) {
        int colour;
        try { colour = 0xFF000000 | Integer.parseInt(bg.trim().replaceFirst("^#", ""), 16); } catch (NumberFormatException e) { return false; }
        String key = night() ? "night" : "day";
        getSharedPreferences("theme", MODE_PRIVATE).edit().putInt(key + ".bg", colour).putBoolean(key + ".dark", dark).apply();
        paintBars();
        return true;
    }

    @Override
    public void onConfigurationChanged(Configuration config) {
        super.onConfigurationChanged(config);
        paintBars();
    }

    @Override
    protected void onDestroy() {
        if (waiting != null) waiting.deny();
        if (shell != null) shell.close();
        if (web != null) web.destroy();
        super.onDestroy();
    }

    /** Anything that isn't Binah: the browser, Mail. */
    boolean outside(Uri url) {
        String scheme = url.getScheme() == null ? "" : url.getScheme().toLowerCase();
        if (!(scheme.equals("http") || scheme.equals("https") || scheme.equals("mailto"))) return false;
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        } catch (ActivityNotFoundException e) {
            return false;
        }
    }

    /** Binah couldn't be reached: a plain page in its colours, with a way to try again. */
    private void unreachable(WebView view, String why) {
        boolean night = night();
        String html = "<!doctype html><meta name=viewport content='width=device-width'><meta charset=utf-8><style>"
                + "body{font:16px/1.5 sans-serif;margin:0;height:100vh;display:flex;align-items:center;justify-content:center;text-align:center;padding:24px;box-sizing:border-box;"
                + (night ? "background:#1b1d2b;color:#b5bfe2}" : "background:#ece3d7;color:#575279}")
                + "h1{font:italic 500 26px Georgia,serif;margin:0 0 8px}a{display:inline-block;margin-top:18px;padding:12px 22px;border-radius:14px;text-decoration:none;font-weight:700;"
                + (night ? "background:#e2e7fb;color:#292c3c}" : "background:#2b2744;color:#fbf8f3}")
                + "</style><div><h1>Binah didn't answer</h1><p>" + android.text.Html.escapeHtml(why) + "</p>"
                + "<a href='" + Server.url(this, "") + "'>Try again</a></div>";
        view.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
    }

    /** Only Binah in the window. */
    private final class Pages extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri url = request.getUrl();
            if (Server.isOurs(MainActivity.this, url) || "about".equals(url.getScheme())) return false;
            if (!request.isForMainFrame()) return false;
            outside(url);
            return true;
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, android.webkit.WebResourceError error) {
            if (!request.isForMainFrame() || !Server.isOurs(MainActivity.this, request.getUrl())) return;
            unreachable(view, String.valueOf(error.getDescription()));
        }

        /** A new document: it needs its own port (Shell). A route change in the page (#…) doesn't
         *  start one, but WebView still calls onPageFinished for it; the page keeps its port then. */
        private boolean fresh = true, shown;

        @Override
        public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
            fresh = true;
            shown = false;
            shell.close();
            recording(false);
        }

        /** The page shows: its port now, so the app's calls don't wait for every picture to load. */
        @Override
        public void onPageCommitVisible(WebView view, String url) {
            if (shown || url == null || !Server.isOurs(MainActivity.this, Uri.parse(url))) return;
            shown = true;
            shell.connect();
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            if (url == null || !Server.isOurs(MainActivity.this, Uri.parse(url))) return;
            if (!shell.heard()) shell.connect();           // shell.js wasn't listening for the first yet
            if (!fresh) return;
            fresh = false;
            view.postDelayed(MainActivity.this::connectIfSignedIn, 3000);
        }
    }

    private final class Chrome extends WebChromeClient {
        @Override
        public void onPermissionRequest(PermissionRequest request) {
            runOnUiThread(() -> permission(request));
        }

        @Override
        public void onPermissionRequestCanceled(PermissionRequest request) {
            if (waiting == request) waiting = null;
        }

        /** target=_blank and window.open: Binah's own pages in this window, anything else goes
         *  out. The new WebView only ever learns the address. */
        @Override
        public boolean onCreateWindow(WebView view, boolean dialog, boolean gesture, Message result) {
            WebView probe = new WebView(MainActivity.this);
            probe.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                    Uri u = r.getUrl();
                    if (Server.isOurs(MainActivity.this, u)) web.loadUrl(u.toString());
                    else outside(u);
                    v.destroy();
                    return true;
                }
            });
            ((WebView.WebViewTransport) result.obj).setWebView(probe);
            result.sendToTarget();
            return true;
        }
    }
}
