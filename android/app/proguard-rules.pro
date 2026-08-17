# Flutter's own classes are kept by the engine's consumer rules; these cover the
# plugins Spine ships. Release builds run R8 (isMinifyEnabled), so anything
# reached only by reflection or only from the manifest has to be named here.

# just_audio / ExoPlayer (Media3): reflection-based component loading.
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# flutter_local_notifications serialises scheduled notifications with Gson, so
# its model classes must keep their field names.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# The home-screen widget is instantiated by the system from the manifest, never
# from code R8 can see.
-keep class * extends android.appwidget.AppWidgetProvider { *; }
-keep class es.antonborri.home_widget.** { *; }

# Keep annotated members Play Core / Flutter deferred components look up.
-keep class io.flutter.embedding.** { *; }

# The Google Mobile Ads SDK and the reel native ad layout. NativeAdView and
# MediaView are named only in reel_native_ad.xml, so R8 sees no reference to
# them from code and would otherwise strip them — the ad then inflates to a
# ClassNotFoundException in release only, which is the worst place to find it.
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-keep class com.spineapp.spine.ReelNativeAdFactory { *; }

# Mediation adapters are loaded reflectively by class name from the AdMob
# server response, so nothing in the APK references them directly.
-keep class com.google.ads.mediation.** { *; }
-keep class com.facebook.ads.** { *; }
-dontwarn com.facebook.ads.**
