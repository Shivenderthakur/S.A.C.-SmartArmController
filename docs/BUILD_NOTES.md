# Build notes

Four real problems came up porting this app, all of them from the toolchain rather than
the application code. Each is recorded here with the symptom, the cause and the fix that
is now in the repo.

## Toolchain

| Component | Version |
| --- | --- |
| Flutter | 3.47.2 (Dart 3.13.2) |
| Gradle | 9.3.1 |
| Android Gradle Plugin | 9.1.0 |
| Kotlin Gradle Plugin | 2.4.0 |
| MediaPipe Tasks Vision | 0.10.35 |

AGP 9 is the common thread through the first two problems and R8 through the last two.

---

## 1. `flutter_inappwebview` will not evaluate under AGP 9

**Symptom.** The build failed during project evaluation, before compiling anything.

**Cause.** `flutter_inappwebview_android` 1.1.3 calls
`getDefaultProguardFile('proguard-android.txt')`, which AGP 9 rejects.

**Fix.** The dependency was dropped. Patching the copy in `~/.pub-cache` would have worked
but silently reverts on `flutter pub cache repair`, so it is not a fix you can rely on.

This is also why `android/app/build.gradle.kts` references its ProGuard file as
`proguardFile("proguard-rules.pro")` rather than going through `getDefaultProguardFile`.

---

## 2. `camera_android_camerax` fails to compile under AGP 9

**Symptom.**

```
Execution failed for task ':camera_android_camerax:compileReleaseJavaWithJavac'
camera-core-1.5.3-api.jar(/androidx/camera/core/SurfaceRequest.class):
  error: Cannot attach type annotations @org.jspecify.annotations.NonNull
  to SurfaceRequest.mSurfaceRecreationCompleter:
  class file for androidx.concurrent.futures.CallbackToFutureAdapter not found
```

**Cause.** `camera-core` 1.5.3 exposes `androidx.concurrent.futures` types in its public
API, but AGP 9 no longer leaks that transitive dependency onto the plugin's compile
classpath. Adding it to the app module does not help — the failure is in the plugin's own
module.

**Fix.** A `subprojects` block in `android/build.gradle.kts` adds the dependency back for
that one module:

```kotlin
subprojects {
    if (project.name == "camera_android_camerax") {
        afterEvaluate {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}
```

**This block must sit before the `subprojects { project.evaluationDependsOn(":app") }`
block.** That block evaluates the subprojects as a side effect, and calling `afterEvaluate`
on an already-evaluated project throws:

```
Cannot run Project.afterEvaluate(Action) when the project is already evaluated.
```

The ordering is load-bearing, so leave the comment in place if you reorganise the file.

---

## 3. R8 obfuscated Room's generated `WorkDatabase_Impl`

**Symptom.** The release APK compiled cleanly, installed fine, and died instantly on
launch:

```
java.lang.RuntimeException: Unable to get provider androidx.startup.InitializationProvider:
  java.lang.RuntimeException: Failed to create an instance of androidx.work.impl.WorkDatabase
    at androidx.work.WorkManagerInitializer.b(...)
```

**Cause.** Room generates `WorkDatabase_Impl` and WorkManager looks it up reflectively by
name. R8 renamed it, so the lookup failed inside `androidx.startup`'s
`InitializationProvider` — which runs before any application code, hence the immediate
death. WorkManager is not a direct dependency; it arrives transitively with the ML Kit and
MediaPipe artifacts.

**Fix.** Keep rules in `android/app/proguard-rules.pro` for `androidx.room` and
`androidx.work`. Those rules are still in the file and are correct — but see the next
problem for why they are not what is actually protecting the build today.

---

## 4. R8 broke MediaPipe's native library loader

**Symptom.** The nastiest of the four, because nothing crashed. The app ran, the camera
preview was live, the UI said "no hand", and the servo values sat at their defaults
forever. No exception surfaced anywhere in the Dart code.

The native log told the real story:

```
E/SmartArm: landmarker init failed
  java.lang.ExceptionInInitializerError
    at com.google.mediapipe.tasks.core.TaskRunner.create(...)
    at com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker.createFromOptions(...)
  Caused by: java.lang.IllegalStateException: no caller found on the stack for: ao
    at com.google.mediapipe.framework.Graph.<clinit>(...)
```

**Cause.** MediaPipe's native-library loader walks the call stack to find its caller's
class, so it can use that class's `ClassLoader` for `System.loadLibrary`. R8's optimiser
inlined the frame it was looking for, the walk found nothing, and
`com.google.mediapipe.framework.Graph`'s static initialiser threw. That propagated up as
`ExceptionInInitializerError` out of `HandLandmarker.createFromOptions`, so `landmarker`
stayed `null`.

From then on every frame crossed the channel, hit `val hands = landmarker ?: return null`
on the first line of `detect`, and returned "no hand" — which is exactly what a scene with
no hand in it looks like. The failure was completely invisible from the UI.

Note that `-keep class com.google.mediapipe.** { *; }` was already in place and did not
help: the class names were preserved (`Graph` appears unobfuscated in the trace) but the
problem was **inlining**, not renaming, and keep rules do not prevent that.

**Fix.** Minification is off for release builds:

```kotlin
release {
    signingConfig = signingConfigs.getByName("debug")
    isMinifyEnabled = false
    isShrinkResources = false
    proguardFile("proguard-rules.pro")
}
```

This also makes problem 3 moot. The keep rules stay in the file so that re-enabling
shrinking does not immediately reintroduce the WorkManager crash, but the MediaPipe
inlining issue would need more than keep rules — `-dontoptimize` at minimum — so think
before turning minification back on.

The cost is a larger APK: about 88 MB, up from 85 MB. Given that the APK is dominated by
`libmediapipe_tasks_jni.so` (roughly 10 MB per ABI) and the 7.8 MB model, shrinking Dart
and Java bytecode was never buying much.

---

## Debugging lessons worth keeping

**`flutter build ... | tail` hides Gradle failures.** The pipeline's exit status is the
exit status of `tail`, which always succeeds. Use `set -o pipefail`, or check that the APK
actually exists afterwards.

**A release build that compiles can still fail at launch — or silently do nothing.**
Problems 3 and 4 both produced a perfectly clean build. Always install, launch and read
the log before calling a build good:

```bash
set -o pipefail
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -n com.roboticdroid.smartcontroller/.MainActivity
adb logcat -d AndroidRuntime:E SmartArm:I '*:S'
```

Problem 4 in particular did not crash, so only the native log revealed it. That is why
`MainActivity.kt` logs under the `SmartArm` tag on initialisation failure and periodically
reports frame counts and timings.

**`dart:developer`'s `log()` is inert in AOT release builds.** Diagnostics added on the
Dart side produced nothing in `logcat`, which briefly made it look as though the Dart code
was not running at all. Release-mode diagnostics have to come from the native side via
`android.util.Log`, or from something else that survives AOT compilation. This cost real
time during problem 4 — the absence of Dart logs was misread as evidence that the channel
call was never made.

**Check `adb shell dumpsys window | grep mCurrentFocus` before trusting a screenshot.** A
locked or asleep device returns an all-black screencap that looks exactly like a broken
render.
