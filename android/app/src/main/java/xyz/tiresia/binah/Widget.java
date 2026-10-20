package xyz.tiresia.binah;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.util.ArrayMap;
import android.util.SizeF;
import android.widget.RemoteViews;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Today's edition on the home screen (docs/SHELL.md §6): a ring of the games done with the
 * count in it, and on the 4×2 the next game, the minutes left and the week. Tap: Today.
 *
 * It asks /api/widget with the phone's token, gently: when it's placed, every half hour
 * (Android's own update, never more often than the contract's 15 minutes), on unlock at
 * most every 15 minutes (Binah.java), and when the app goes to the background. If Binah
 * can't be reached it keeps the last numbers, dimmed.
 */
public class Widget extends AppWidgetProvider {
    private static final String KEPT = "widget.json", AT = "widget.at", FAILED = "widget.failed";
    private static volatile boolean asking;

    @Override
    public void onUpdate(Context context, AppWidgetManager widgets, int[] ids) {
        render(context);
        PendingResult done = goAsync();
        Context app = context.getApplicationContext();
        new Thread(() -> {
            try { fetch(app); } finally { done.finish(); }
        }).start();
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager widgets, int id, android.os.Bundle options) {
        render(context);
    }

    /** Asks again if the last answer is older than this, in the background. */
    static void refreshIfOlder(Context context, long ms) {
        Context app = context.getApplicationContext();
        if (System.currentTimeMillis() - Server.prefs(app).getLong(AT, 0) < ms || asking) return;
        new Thread(() -> fetch(app)).start();
    }

    /** /api/widget, kept, then every placed widget drawn again. */
    static void fetch(Context c) {
        if (asking) return;
        asking = true;
        SharedPreferences p = Server.prefs(c);
        try {
            JSONObject w = Server.widget(c);
            p.edit().putString(KEPT, w.toString()).putLong(AT, System.currentTimeMillis()).putBoolean(FAILED, false).apply();
        } catch (Exception e) {
            p.edit().putBoolean(FAILED, true).apply();
        } finally {
            asking = false;
            render(c);
        }
    }

    static JSONObject kept(Context c) {
        String s = Server.prefs(c).getString(KEPT, null);
        try { return s == null ? null : new JSONObject(s); } catch (Exception e) { return null; }
    }

    /** Every placed copy, in both sizes: the launcher shows whichever fits. */
    static void render(Context c) {
        AppWidgetManager widgets = AppWidgetManager.getInstance(c);
        int[] ids = widgets.getAppWidgetIds(new ComponentName(c, Widget.class));
        if (ids.length == 0) return;
        JSONObject w = kept(c);
        boolean dim = w == null || Server.prefs(c).getBoolean(FAILED, false) || !today(w);
        Map<SizeF, RemoteViews> sizes = new ArrayMap<>();
        sizes.put(new SizeF(100f, 100f), views(c, R.layout.widget_small, w, dim));
        sizes.put(new SizeF(240f, 100f), views(c, R.layout.widget_wide, w, dim));
        for (int id : ids) widgets.updateAppWidget(id, new RemoteViews(sizes));
    }

    /** The answer is about today (the phone's date), not an edition from yesterday. */
    private static boolean today(JSONObject w) {
        return java.time.LocalDate.now().toString().equals(w.optString("day"));
    }

    private static RemoteViews views(Context c, int layout, JSONObject w, boolean dim) {
        RemoteViews v = new RemoteViews(c.getPackageName(), layout);
        int done = w == null ? 0 : w.optInt("done", 0), total = w == null ? 0 : w.optInt("total", 0);
        boolean finished = w != null && w.optBoolean("finished", false);
        v.setProgressBar(R.id.ring, 100, total > 0 ? Math.min(100, 100 * done / total) : 0, false);
        v.setTextViewText(R.id.count, w == null ? "ב" : finished ? "✓" : done + "/" + total);
        v.setTextViewText(R.id.label, w == null ? "Connect in Binah" : finished ? "Done today" : "Today");
        if (layout == R.layout.widget_wide) {
            JSONObject next = w == null ? null : w.optJSONObject("next");
            JSONObject week = w == null ? null : w.optJSONObject("week");
            int left = w == null ? 0 : (int) Math.round(w.optDouble("minutes_left", 0));
            if (w == null) {
                v.setTextViewText(R.id.title, "Today's edition");
                v.setTextViewText(R.id.detail, "Open Binah, signed in, to connect this phone.");
            } else if (finished) {
                v.setTextViewText(R.id.title, "Today's edition is done.");
                v.setTextViewText(R.id.detail, "Anything else today is extra, in Practice.");
            } else {
                v.setTextViewText(R.id.title, next != null ? next.optString("name") : "Today's edition");
                v.setTextViewText(R.id.detail, done + " of " + total + " games" + (left > 0 ? " · about " + left + " min left" : ""));
            }
            v.setTextViewText(R.id.week, week == null ? "" : "This week: " + week.optInt("active") + " of " + week.optInt("goal") + " days");
            if (dim) v.setColorStateList(R.id.title, "setTextColor", R.color.widgetText2);
        }
        if (dim) {
            v.setColorStateList(R.id.count, "setTextColor", R.color.widgetText2);
            v.setColorStateList(R.id.ring, "setProgressTintList", R.color.widgetText2);
        }
        v.setOnClickPendingIntent(R.id.root, PendingIntent.getActivity(c, 1, MainActivity.open(c, "#today"),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        return v;
    }

    /** Long-press Binah's icon: Today, Practice, Skills, and the app's own settings. */
    static void shortcuts(Context c) {
        ShortcutManager sm = c.getSystemService(ShortcutManager.class);
        if (sm == null) return;
        List<ShortcutInfo> list = new ArrayList<>();
        list.add(shortcut(c, "today", "Today", "Today's edition", R.drawable.ic_shortcut_today, "#today"));
        list.add(shortcut(c, "practice", "Practice", null, R.drawable.ic_shortcut_practice, "#practice"));
        list.add(shortcut(c, "skills", "Skills", null, R.drawable.ic_shortcut_skills, "#skills"));
        list.add(new ShortcutInfo.Builder(c, "settings").setShortLabel("App settings").setLongLabel("Binah app settings")
                .setIcon(Icon.createWithResource(c, R.drawable.ic_shortcut_settings))
                .setIntent(new Intent(Intent.ACTION_VIEW).setClass(c, SettingsActivity.class)).build());
        try {
            sm.setDynamicShortcuts(list);
        } catch (IllegalStateException | IllegalArgumentException ignored) {
            // the launcher's limit on shortcuts; nothing lost but them
        }
    }

    private static ShortcutInfo shortcut(Context c, String id, String label, String longLabel, int icon, String route) {
        ShortcutInfo.Builder b = new ShortcutInfo.Builder(c, id)
                .setShortLabel(label)
                .setIcon(Icon.createWithResource(c, icon))
                .setIntent(MainActivity.open(c, route).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP));
        if (longLabel != null) b.setLongLabel(longLabel);
        return b.build();
    }
}
