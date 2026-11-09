package com.sysiphe.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Mise à jour intégrée : l'APK est téléchargé par Dart dans le cache
 * (cacheDir/updates), puis on ouvre l'installeur Android dessus.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sysiphe/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updatesDir" -> {
                        val dir = File(cacheDir, "updates").apply { mkdirs() }
                        result.success(dir.absolutePath)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path manquant", null)
                        } else {
                            result.success(installApk(File(path)))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** "started", ou "needs_permission" (réglage « sources inconnues » ouvert). */
    private fun installApk(apk: File): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
            return "needs_permission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updateprovider", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        return "started"
    }
}
