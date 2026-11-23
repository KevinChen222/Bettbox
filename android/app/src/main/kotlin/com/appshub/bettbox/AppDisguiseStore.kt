package com.appshub.bettbox

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import java.io.File

object AppDisguiseStore {
    private const val TAG = "AppDisguiseStore"
    private const val PREFS_NAME = "app_disguise"
    private const val KEY_CUSTOM_NAME = "custom_app_name"
    private const val KEY_CUSTOM_ICON_PATH = "custom_app_icon_path"
    private const val KEY_LAUNCHER_PRESET = "launcher_preset"

    private const val MAIN_ACTIVITY_CLASS = "com.appshub.bettbox.MainActivity"
    private const val ALIAS_DEFAULT = "com.appshub.bettbox.MainActivityDefault"
    private const val ALIAS_NOTES = "com.appshub.bettbox.MainActivityDisguiseNotes"
    private const val ALIAS_CALCULATOR = "com.appshub.bettbox.MainActivityDisguiseCalculator"
    private const val ALIAS_TOOLBOX = "com.appshub.bettbox.MainActivityDisguiseToolbox"
    private const val ALIAS_LEGACY_LIGHT = "com.appshub.bettbox.MainActivityLight"
    private const val ALIAS_LEGACY_DARK = "com.appshub.bettbox.MainActivityDark"

    private val presetAliases = mapOf(
        "default" to ALIAS_DEFAULT,
        "notes" to ALIAS_NOTES,
        "calculator" to ALIAS_CALCULATOR,
        "toolbox" to ALIAS_TOOLBOX,
    )

    private val allAliases = listOf(
        ALIAS_DEFAULT,
        ALIAS_NOTES,
        ALIAS_CALCULATOR,
        ALIAS_TOOLBOX,
        ALIAS_LEGACY_LIGHT,
        ALIAS_LEGACY_DARK,
    )

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveBranding(context: Context, name: String?, iconPath: String?) {
        val cleanName = name?.trim()?.takeIf { it.isNotEmpty() }
        val cleanPath = iconPath?.trim()?.takeIf { it.isNotEmpty() }
        prefs(context).edit()
            .putString(KEY_CUSTOM_NAME, cleanName)
            .putString(KEY_CUSTOM_ICON_PATH, cleanPath)
            .apply()
    }

    fun getCustomName(context: Context): String? =
        prefs(context).getString(KEY_CUSTOM_NAME, null)?.trim()?.takeIf { it.isNotEmpty() }

    fun getCustomIconPath(context: Context): String? =
        prefs(context).getString(KEY_CUSTOM_ICON_PATH, null)?.trim()?.takeIf { it.isNotEmpty() }

    fun getLauncherPreset(context: Context): String =
        prefs(context).getString(KEY_LAUNCHER_PRESET, "default") ?: "default"

    fun hasCustomBranding(context: Context): Boolean =
        getCustomName(context) != null || getCustomIconPath(context) != null

    fun effectiveLabel(context: Context, fallback: String): String =
        getCustomName(context) ?: fallback

    fun loadCustomIconBitmap(context: Context, maxSizePx: Int = 256): Bitmap? {
        val path = getCustomIconPath(context) ?: return null
        return decodeSquareBitmap(path, maxSizePx)
    }

    fun decodeSquareBitmap(path: String?, maxSizePx: Int = 256): Bitmap? {
        if (path.isNullOrBlank()) return null
        val file = File(path)
        if (!file.exists() || !file.isFile) return null
        return runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            var sampleSize = 1
            val minSide = minOf(bounds.outWidth, bounds.outHeight)
            while (minSide / (sampleSize * 2) >= maxSizePx) {
                sampleSize *= 2
            }

            val decoded = BitmapFactory.decodeFile(
                file.absolutePath,
                BitmapFactory.Options().apply { inSampleSize = sampleSize }
            ) ?: return null

            val side = minOf(decoded.width, decoded.height)
            val x = (decoded.width - side) / 2
            val y = (decoded.height - side) / 2
            val cropped = if (decoded.width != decoded.height) {
                Bitmap.createBitmap(decoded, x, y, side, side).also {
                    if (it !== decoded) decoded.recycle()
                }
            } else {
                decoded
            }

            if (cropped.width > maxSizePx) {
                Bitmap.createScaledBitmap(cropped, maxSizePx, maxSizePx, true).also {
                    if (it !== cropped) cropped.recycle()
                }
            } else {
                cropped
            }
        }.onFailure {
            Log.w(TAG, "Failed to decode custom icon: ${it.message}")
        }.getOrNull()
    }

    fun buildTaskDescription(
        context: Context,
        original: ActivityManager.TaskDescription? = null,
    ): ActivityManager.TaskDescription? {
        val customName = getCustomName(context)
        val customBitmap = loadCustomIconBitmap(context, 192)
        if (customName == null && customBitmap == null) {
            return original
        }

        val label = customName ?: original?.label ?: context.getString(R.string.bett_box)
        val primaryColor = original?.primaryColor ?: 0

        if (customBitmap != null) {
            @Suppress("DEPRECATION")
            return if (primaryColor != 0) {
                ActivityManager.TaskDescription(label, customBitmap, primaryColor)
            } else {
                ActivityManager.TaskDescription(label, customBitmap)
            }
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityManager.TaskDescription.Builder()
                .setLabel(label)
                .apply {
                    if (primaryColor != 0) setPrimaryColor(primaryColor)
                }
                .build()
        } else {
            @Suppress("DEPRECATION")
            if (primaryColor != 0) {
                ActivityManager.TaskDescription(label, null as Bitmap?, primaryColor)
            } else {
                ActivityManager.TaskDescription(label)
            }
        }
    }

    fun applyTaskDescription(activity: Activity) {
        val desc = buildTaskDescription(activity) ?: return
        runCatching {
            activity.setTaskDescription(desc)
        }.onFailure {
            Log.w(TAG, "Failed to apply TaskDescription: ${it.message}")
        }
    }

    fun applyLauncherPreset(context: Context, preset: String): Boolean {
        val normalized = if (presetAliases.containsKey(preset)) preset else "default"
        val targetAlias = presetAliases.getValue(normalized)
        val appContext = context.applicationContext
        val pm = appContext.packageManager
        val pkg = appContext.packageName

        return runCatching {
            // Enable the target alias first so the launcher always sees a valid entry.
            pm.setComponentEnabledSetting(
                ComponentName(pkg, targetAlias),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            for (alias in allAliases) {
                if (alias == targetAlias) continue
                pm.setComponentEnabledSetting(
                    ComponentName(pkg, alias),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
            prefs(appContext).edit().putString(KEY_LAUNCHER_PRESET, normalized).apply()
            true
        }.onFailure {
            Log.e(TAG, "Failed to switch launcher preset to $normalized: ${it.message}")
        }.getOrDefault(false)
    }

    fun isPinShortcutSupported(context: Context): Boolean =
        ShortcutManagerCompat.isRequestPinShortcutSupported(context.applicationContext)

    fun requestPinCustomShortcut(
        context: Context,
        name: String?,
        iconPath: String?,
    ): Boolean {
        val appContext = context.applicationContext
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(appContext)) {
            return false
        }

        val label = name?.trim()?.takeIf { it.isNotEmpty() }
            ?: getCustomName(appContext)
            ?: appContext.getString(R.string.bett_box)

        val bitmap = decodeSquareBitmap(iconPath, 256)
            ?: loadCustomIconBitmap(appContext, 256)
            ?: renderPresetFallbackBitmap(appContext)

        val iconCompat = if (bitmap != null) {
            IconCompat.createWithBitmap(bitmap)
        } else {
            IconCompat.createWithResource(appContext, R.mipmap.ic_launcher_light)
        }

        val launchIntent = Intent(Intent.ACTION_MAIN).apply {
            component = ComponentName(appContext.packageName, MAIN_ACTIVITY_CLASS)
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val shortcut = ShortcutInfoCompat.Builder(
            appContext,
            "custom_launcher_${System.currentTimeMillis()}",
        )
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(iconCompat)
            .setIntent(launchIntent)
            .build()

        return runCatching {
            ShortcutManagerCompat.requestPinShortcut(appContext, shortcut, null)
        }.onFailure {
            Log.e(TAG, "Failed to request pin shortcut: ${it.message}")
        }.getOrDefault(false)
    }

    private fun renderPresetFallbackBitmap(context: Context): Bitmap? {
        val resId = when (getLauncherPreset(context)) {
            "notes" -> R.drawable.ic_disguise_notes
            "calculator" -> R.drawable.ic_disguise_calculator
            "toolbox" -> R.drawable.ic_disguise_toolbox
            else -> R.mipmap.ic_launcher_light
        }
        val drawable = ContextCompat.getDrawable(context, resId) ?: return null
        val size = 192
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return bitmap
    }

    fun loadRoundedWidgetIconBitmap(context: Context, sizePx: Int = 192): Bitmap? {
        val source = loadCustomIconBitmap(context, sizePx)
            ?: renderPresetFallbackBitmap(context)
            ?: return null
        val scaled = if (source.width != sizePx || source.height != sizePx) {
            Bitmap.createScaledBitmap(source, sizePx, sizePx, true).also {
                if (it !== source) source.recycle()
            }
        } else {
            source
        }
        val output = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = Rect(0, 0, sizePx, sizePx)
        val rectF = RectF(rect)
        val radius = sizePx * 0.22f
        canvas.drawRoundRect(rectF, radius, radius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(scaled, rect, rect, paint)
        if (scaled !== output) scaled.recycle()
        return output
    }
}
