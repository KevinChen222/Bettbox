package com.appshub.bettbox.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import com.appshub.bettbox.AppDisguiseStore
import com.appshub.bettbox.R

class DisguiseIconWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val views = buildRemoteViews(context)
        for (widgetId in appWidgetIds) {
            runCatching {
                appWidgetManager.updateAppWidget(widgetId, views)
            }.onFailure {
                Log.w(TAG, "Failed to update disguise widget $widgetId: ${it.message}")
            }
        }
    }

    companion object {
        private const val TAG = "DisguiseIconWidget"
        private const val MAIN_ACTIVITY_CLASS = "com.appshub.bettbox.MainActivity"

        fun buildRemoteViews(context: Context): RemoteViews {
            val appContext = context.applicationContext
            val views = RemoteViews(appContext.packageName, R.layout.disguise_icon_widget)

            val label = AppDisguiseStore.effectiveLabel(
                appContext,
                appContext.getString(R.string.bett_box),
            )
            views.setTextViewText(R.id.disguise_widget_label, label)

            val roundedBitmap = AppDisguiseStore.loadRoundedWidgetIconBitmap(appContext, 192)
            if (roundedBitmap != null) {
                views.setImageViewBitmap(R.id.disguise_widget_icon, roundedBitmap)
            } else {
                views.setImageViewResource(R.id.disguise_widget_icon, R.mipmap.ic_launcher_light)
            }

            val launchIntent = Intent(Intent.ACTION_MAIN).apply {
                component = ComponentName(appContext.packageName, MAIN_ACTIVITY_CLASS)
                addCategory(Intent.CATEGORY_LAUNCHER)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val pendingIntent = PendingIntent.getActivity(appContext, 9101, launchIntent, flags)
            views.setOnClickPendingIntent(R.id.disguise_widget_root, pendingIntent)

            return views
        }

        fun refreshAll(context: Context) {
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext) ?: return
            val provider = ComponentName(appContext, DisguiseIconWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(provider)
            if (ids.isEmpty()) return
            val views = buildRemoteViews(appContext)
            for (id in ids) {
                runCatching {
                    manager.updateAppWidget(id, views)
                }.onFailure {
                    Log.w(TAG, "Failed to refresh disguise widget $id: ${it.message}")
                }
            }
        }

        fun isPinSupported(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val manager = AppWidgetManager.getInstance(context.applicationContext) ?: return false
            return manager.isRequestPinAppWidgetSupported
        }

        fun requestPin(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext) ?: return false
            if (!manager.isRequestPinAppWidgetSupported) return false

            val provider = ComponentName(appContext, DisguiseIconWidgetProvider::class.java)
            val extras = Bundle().apply {
                putParcelable(AppWidgetManager.EXTRA_APPWIDGET_PREVIEW, buildRemoteViews(appContext))
            }
            return runCatching {
                manager.requestPinAppWidget(provider, extras, null)
            }.onFailure {
                Log.e(TAG, "Failed to request pin disguise widget: ${it.message}")
            }.getOrDefault(false)
        }
    }
}
