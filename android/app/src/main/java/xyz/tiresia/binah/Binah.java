package xyz.tiresia.binah;

import android.app.Application;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;

/**
 * The process: the widget asks again when the phone is unlocked, at most every 15 minutes
 * (docs/SHELL.md §6). Android delivers "unlocked" only to a running process, so this is on
 * while Binah's process is alive.
 */
public class Binah extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        BroadcastReceiver unlocked = new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                Widget.refreshIfOlder(c, 15 * 60 * 1000L);
            }
        };
        IntentFilter filter = new IntentFilter(Intent.ACTION_USER_PRESENT);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(unlocked, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(unlocked, filter);
    }

    static String version(Context c) {
        try {
            return c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return "0";
        }
    }
}
