# Tuya SDK uses reflection and JNI. Rules from its Android integration guide.
-keep class com.thingclips.** { *; }
-dontwarn com.thingclips.**
-keep class com.alibaba.fastjson.** { *; }
-dontwarn com.alibaba.fastjson.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**
-keep class chip.** { *; }
-dontwarn chip.**
-keep class com.gzl.smart.** { *; }
-dontwarn com.gzl.smart.**

# Tuya's consumer rules retain Flutter's optional Play Store split classes.
# This sideloaded APK has no deferred components or split application.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
