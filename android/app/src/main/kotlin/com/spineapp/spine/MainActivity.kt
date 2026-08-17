package com.spineapp.spine

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import java.io.File

class MainActivity : FlutterActivity() {

    private companion object {
        const val CAPTURE_GUARD_CHANNEL = "spine/capture_guard"
        const val STORY_SHARE_CHANNEL = "spine/story_share"
        const val FILE_PROVIDER_AUTHORITY = "com.spineapp.spine.storyshare.fileprovider"
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        const val FACEBOOK_PACKAGE = "com.facebook.katana"

        // Must match kReelAdFactoryId in native_ad_preloader.dart. A mismatch
        // surfaces only at ad-load time, as "factory not found".
        const val REEL_AD_FACTORY = "reelAd"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Applied here rather than waiting for Dart to ask: the flag must be on
        // the window before the first frame, and the app should never be
        // capturable during the moments before the Flutter side has started.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            REEL_AD_FACTORY,
            ReelNativeAdFactory(applicationContext),
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_GUARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setProtected" -> {
                        // FLAG_SECURE is the real thing on Android: the OS
                        // refuses screenshots and screen recording, and blanks
                        // the window in the recents switcher.
                        val enabled = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(true)
                    }

                    "isProtected" -> {
                        val flags = window.attributes.flags
                        result.success(
                            flags and WindowManager.LayoutParams.FLAG_SECURE != 0
                        )
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORY_SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canShare" -> {
                        val target = call.argument<String>("target")
                        result.success(isInstalled(packageFor(target)))
                    }

                    "shareToStory" -> {
                        val target = call.argument<String>("target")
                        val path = call.argument<String>("path")
                        result.success(shareToStory(target, packageFor(target), path))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        // Without this a hot restart re-registers over a live factory and the
        // engine keeps the old one alive with it.
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, REEL_AD_FACTORY)
    }

    private fun packageFor(target: String?): String? = when (target) {
        "instagram" -> INSTAGRAM_PACKAGE
        "facebook" -> FACEBOOK_PACKAGE
        else -> null
    }

    private fun isInstalled(packageName: String?): Boolean {
        if (packageName == null) return false
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (error: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * Hands the rendered story card straight to Instagram/Facebook's own
     * "Add to Story" screen via their documented sticker-share intent.
     * Returns false (letting the Dart side fall back to the OS share sheet)
     * whenever the target isn't installed or the image path is missing —
     * this never throws past that.
     */
    private fun shareToStory(target: String?, packageName: String?, path: String?): Boolean {
        if (packageName == null || path == null || !isInstalled(packageName)) return false
        val file = File(path)
        if (!file.exists()) return false

        // Instagram and Facebook each expose their own "Add to Story" intent
        // action; the extras (background image + a matching interactive
        // sticker uri) are otherwise the same documented contract.
        val action = when (target) {
            "instagram" -> "com.instagram.share.ADD_TO_STORY"
            "facebook" -> "com.facebook.stories.ADD_TO_STORY"
            else -> return false
        }

        return try {
            val uri: Uri = FileProvider.getUriForFile(this, FILE_PROVIDER_AUTHORITY, file)
            val intent = Intent(action).apply {
                setDataAndType(uri, "image/png")
                putExtra("interactive_asset_uri", uri)
                setPackage(packageName)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) == null) return false
            startActivity(intent)
            true
        } catch (error: Exception) {
            false
        }
    }
}
