# R8 obfuscated Room's generated WorkDatabase_Impl, which WorkManager looks up
# reflectively - the app then died on startup inside androidx.startup's
# InitializationProvider. WorkManager arrives with MediaPipe.
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.RoomDatabase { *; }
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.ListenableWorker { public <init>(...); }
-dontwarn androidx.room.**
-dontwarn androidx.work.**

# MediaPipe crosses into its native code by class and method name.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
-dontwarn autovalue.shaded.**
