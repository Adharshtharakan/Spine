# Flutter's own classes are kept by the engine's consumer rules; these cover the
# plugins Spine ships.

# just_audio / ExoPlayer (Media3): reflection-based component loading.
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Keep annotated members Play Core / Flutter deferred components look up.
-keep class io.flutter.embedding.** { *; }
