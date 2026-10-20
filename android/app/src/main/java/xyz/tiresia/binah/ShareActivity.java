package xyz.tiresia.binah;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.TextView;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Train on this (docs/SHELL.md §7), from any app's share sheet, with a card at the bottom saying
 * what happened. A link, or a passage of 20 words or more, goes to /api/save with this phone's
 * token, or with the window's sign-in if the phone isn't connected yet; the next nightly run
 * turns it into practice items. Tap the card for Today.
 */
public class ShareActivity extends Activity {
    private static final Pattern LINK = Pattern.compile("https?://\\S+");
    private TextView title, detail;
    private boolean leaving;
    private volatile boolean saved;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.share);
        title = findViewById(R.id.shareTitle);
        detail = findViewById(R.id.shareDetail);
        Context app = getApplicationContext();
        findViewById(R.id.shareRoot).setOnClickListener(v -> leave(0));
        findViewById(R.id.card).setOnClickListener(v -> {
            if (saved) startActivity(MainActivity.open(app, "#today"));
            leave(0);
        });

        Intent in = getIntent();
        String text = in.getStringExtra(Intent.EXTRA_TEXT), subject = in.getStringExtra(Intent.EXTRA_SUBJECT);
        String[] what = what(text, subject);
        String url = what[0], passage = what[1], name = what[2];
        detail.setText(name != null && !name.isEmpty() ? name : url != null ? Uri.parse(url).getHost() : first(passage));
        new Thread(() -> {
            try {
                if (url == null && passage == null) throw new Exception("Nothing to send: share a link or some text.");
                String said;
                if (Server.token(app) == null) said = Server.save(app, url, passage, name, false);
                else try {
                    said = Server.save(app, url, passage, name, true);
                } catch (Server.Failure f) {
                    if (f.status != 401) throw f;
                    said = Server.save(app, url, passage, name, false);     // the token was refused: the sign-in still saves it
                }
                saved = true;
                say("Sent to Binah", said);
                leave(4000);
            } catch (Exception e) {
                say("Not sent", e.getMessage());
                leave(4500);
            }
        }).start();
    }

    /** What was shared, as {url, passage, title}: a link with a few words is the link (the
     *  words its title); 20 words or more are a passage, with the link if there was one. */
    static String[] what(String text, String subject) {
        String t = text == null ? "" : text.trim();
        String link = link(t);
        String rest = link == null ? t : t.replace(link, "").trim();
        boolean passage = rest.split("\\s+").length >= 20;
        String title = subject != null && !subject.trim().isEmpty() ? subject.trim()
                : link != null && !passage && !rest.isEmpty() ? rest : null;
        if (passage) return new String[]{link, rest, title};
        if (link != null) return new String[]{link, null, title};
        return new String[]{null, t.isEmpty() ? null : t, title};
    }

    static String link(String text) {
        if (text == null) return null;
        Matcher m = LINK.matcher(text);
        return m.find() ? m.group() : null;
    }

    private static String first(String passage) {
        if (passage == null) return "";
        return passage.length() > 80 ? passage.substring(0, 80) + "…" : passage;
    }

    private void say(String t, String d) {
        runOnUiThread(() -> { title.setText(t); detail.setText(d == null ? "" : d); });
    }

    private void leave(long after) {
        runOnUiThread(() -> title.postDelayed(() -> {
            if (leaving) return;
            leaving = true;
            finish();
        }, after));
    }
}
