package nl.michelknoop.pleya.share

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Foreground service that keeps the process (and thus the Dart-side Pleya
 * Share HTTP server) alive while the app is backgrounded or the screen is
 * off. Holds a partial wakelock (CPU) and a high-perf wifi lock (radio) —
 * without these, Doze suspends the sockets within minutes.
 *
 * The service carries no logic of its own; the Dart isolate keeps serving as
 * long as the process lives. Started/stopped from Dart via the
 * `nl.michelknoop.pleya/share_service` MethodChannel.
 */
class PleyaShareService : Service() {

  companion object {
    private const val TAG = "PleyaShareService"
    private const val CHANNEL_ID = "pleya_share_hosting"
    private const val NOTIFICATION_ID = 7462
    const val EXTRA_TITLE = "title"
    const val EXTRA_TEXT = "text"

    fun start(context: Context, title: String, text: String) {
      val intent = Intent(context, PleyaShareService::class.java)
        .putExtra(EXTRA_TITLE, title)
        .putExtra(EXTRA_TEXT, text)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, PleyaShareService::class.java))
    }
  }

  private var wifiLock: WifiManager.WifiLock? = null
  private var wakeLock: PowerManager.WakeLock? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Pleya Share"
    val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""

    createChannel()
    val notification = buildNotification(title, text)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }
    acquireLocks()
    // Not sticky: without the Dart isolate there is nothing to serve, so a
    // system restart of the bare service would only show a dead notification.
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    releaseLocks()
    super.onDestroy()
  }

  private fun acquireLocks() {
    if (wifiLock == null) {
      try {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "$TAG:wifi").apply {
          setReferenceCounted(false)
          acquire()
        }
      } catch (e: Exception) {
        Log.w(TAG, "wifi lock unavailable", e)
      }
    }
    if (wakeLock == null) {
      try {
        val power = applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$TAG:cpu").apply {
          setReferenceCounted(false)
          acquire()
        }
      } catch (e: Exception) {
        Log.w(TAG, "wake lock unavailable", e)
      }
    }
  }

  private fun releaseLocks() {
    try {
      wifiLock?.release()
    } catch (_: Exception) {}
    wifiLock = null
    try {
      wakeLock?.release()
    } catch (_: Exception) {}
    wakeLock = null
  }

  private fun createChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    manager.createNotificationChannel(
      NotificationChannel(CHANNEL_ID, "Pleya Share", NotificationManager.IMPORTANCE_LOW).apply {
        setShowBadge(false)
      },
    )
  }

  private fun buildNotification(title: String, text: String): Notification {
    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
    val contentIntent = launchIntent?.let {
      PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(this, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION") Notification.Builder(this)
    }
    return builder
      .setContentTitle(title)
      .setContentText(text)
      .setSmallIcon(applicationInfo.icon)
      .setOngoing(true)
      .setContentIntent(contentIntent)
      .build()
  }
}
