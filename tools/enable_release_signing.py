#!/usr/bin/env python3
"""Teach an older android/app/build.gradle.kts to sign with key.properties.

v1 and v2 shipped a build.gradle.kts that always signed release builds with the
debug key - it carries a literal "TODO: Add your own signing config". Publishing
those versions as real releases means building that old source with today's
signing, so this rewrites the *checked-out copy* to read android/key.properties
the way the current build does. It never touches a commit.

Idempotent: a file that already reads key.properties is left alone. Fails loudly
when an anchor is missing, because the alternative is quietly publishing a
debug-signed APK that no phone can install over a real release.
"""

import sys

KEYSTORE_BLOCK = """// The release keystore, from android/key.properties (git-ignored; CI writes it
// from secrets). Without it, release builds fall back to the debug key.
val keystoreProperties = Properties().apply {
    rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

"""

SIGNING_BLOCK = """    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

"""

OLD_SIGNING = 'signingConfig = signingConfigs.getByName("debug")'
NEW_SIGNING = (
    'signingConfig = signingConfigs.findByName("release") '
    '?: signingConfigs.getByName("debug")'
)


def fail(message):
    # ::error:: makes it a GitHub Actions annotation as well as a failure.
    print(f"::error::{message}")
    sys.exit(1)


def patch(path):
    with open(path) as f:
        src = f.read()

    if "key.properties" in src:
        print(f"{path} already reads key.properties - nothing to do")
        return

    if "import java.util.Properties" not in src:
        src = "import java.util.Properties\n\n" + src

    if "\nandroid {" not in src:
        fail(f"no top-level `android {{` block in {path}")
    src = src.replace("\nandroid {", "\n" + KEYSTORE_BLOCK + "android {", 1)

    if "    buildTypes {" not in src:
        fail(f"no `buildTypes` block in {path}")
    src = src.replace("    buildTypes {", SIGNING_BLOCK + "    buildTypes {", 1)

    if OLD_SIGNING not in src:
        fail(
            f"the release buildType in {path} does not select the debug "
            "signingConfig, so there is nothing safe to swap - refusing to guess"
        )
    src = src.replace(OLD_SIGNING, NEW_SIGNING, 1)

    with open(path, "w") as f:
        f.write(src)
    print(f"patched {path} to sign release builds with key.properties")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "android/app/build.gradle.kts"
    patch(target)
