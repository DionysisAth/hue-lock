# Release-build (R8) keep rules. Picked up automatically by the Flutter
# Gradle plugin for minified release builds.

# WorkManager (pulled in by the Google Mobile Ads SDK) is initialized at app
# start and creates its Room database reflectively (WorkDatabase_Impl). R8
# full mode drops the no-arg constructors of such classes, which crashed the
# release APK on launch with:
#   "Failed to create an instance of androidx.work.impl.WorkDatabase"
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class * extends androidx.startup.Initializer { <init>(); }
