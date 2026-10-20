package xyz.tiresia.binah;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

/**
 * The app's own settings (the page has its own Settings): Binah's address, this phone's token,
 * and the microphone. Reached from the long-press menu on Binah's icon.
 */
public class SettingsActivity extends Activity {
    private static final int MIC = 1;
    private TextView status, mic;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.settings);
        View root = findViewById(R.id.scroll);
        root.setOnApplyWindowInsetsListener((v, in) -> {
            Insets bars = in.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });
        // dark icons on the light parchment, light ones on the dark ground
        boolean night = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        WindowInsetsController bars = getWindow().getInsetsController();
        int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
        if (bars != null) bars.setSystemBarsAppearance(night ? 0 : light, light);

        EditText base = findViewById(R.id.base);
        base.setText(Server.base(this));
        findViewById(R.id.useBase).setOnClickListener(v -> {
            TextView note = findViewById(R.id.baseNote);
            if (Server.setBase(this, base.getText().toString())) {
                base.setText(Server.base(this));
                note.setText("Binah opens from " + Server.base(this) + ". Sign in there once.");
            } else {
                note.setText("That isn't an address Binah can use. It starts with https:// or http://.");
            }
        });

        status = findViewById(R.id.status);
        Button connect = findViewById(R.id.connect);
        connect.setOnClickListener(v -> {
            connect.setEnabled(false);
            new Thread(() -> {
                String said;
                try {
                    Server.setToken(this, Server.connect(this));
                    Widget.fetch(this);
                    said = "This phone is connected";
                } catch (Exception e) {
                    said = e.getMessage();
                }
                String s = said;
                runOnUiThread(() -> { connect.setEnabled(true); Toast.makeText(this, s, Toast.LENGTH_LONG).show(); show(); });
            }).start();
        });
        findViewById(R.id.forget).setOnClickListener(v -> { Server.setToken(this, null); show(); });

        mic = findViewById(R.id.mic);
        findViewById(R.id.allowMic).setOnClickListener(v -> {
            if (asked() && !shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) {
                // Android won't ask again: the switch is in the app's page in Android's settings
                startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName())));
            } else {
                getSharedPreferences("mic", MODE_PRIVATE).edit().putBoolean("asked", true).apply();
                requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MIC);
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        show();
    }

    @Override
    public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        show();
    }

    private boolean asked() {
        return getSharedPreferences("mic", MODE_PRIVATE).getBoolean("asked", false);
    }

    private void show() {
        JSONObject w = Widget.kept(this);
        if (Server.token(this) == null) status.setText("Not connected yet. Sign in to Binah in the app, then press Connect.");
        else if (w != null) status.setText("Connected. Today: " + (w.optBoolean("finished") ? "the edition is done."
                : w.optInt("done") + " of " + w.optInt("total") + " games."));
        else status.setText("Connected.");
        findViewById(R.id.forget).setVisibility(Server.token(this) == null ? View.GONE : View.VISIBLE);

        boolean on = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
        mic.setText(on ? "On. Binah's page can record your spoken answers."
                : "Off. Binah asks the first time a game needs your voice, or turn it on here.");
        findViewById(R.id.allowMic).setVisibility(on ? View.GONE : View.VISIBLE);
    }
}
