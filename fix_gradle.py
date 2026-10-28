import os

kts = "android/build.gradle.kts"
groovy = "android/build.gradle"

kts_hook = """subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            project.extensions.configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(36)
            }
        }
    }
}

"""

groovy_hook = """subprojects {
    afterEvaluate { p ->
        if (p.hasProperty('android')) {
            p.android { compileSdkVersion 36 }
        }
    }
}

"""

if os.path.exists(kts):
    path, hook = kts, kts_hook
else:
    path, hook = groovy, groovy_hook

with open(path) as f:
    content = f.read()
with open(path, "w") as f:
    f.write(hook + content)
print("patched", path)