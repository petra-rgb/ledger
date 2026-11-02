#!/usr/bin/env bash
# Builds Ledger.apk.
#
# Deliberately does NOT use Homebrew. This Mac is arm64 but its Homebrew lives in
# /usr/local, so it runs under Rosetta and believes it is on Intel — a platform
# Homebrew dropped in 2026. With no Intel bottles left it tries to compile node,
# openssl, cmake and Python from source, which is what failed.
#
# Instead every tool is fetched as a native arm64 archive straight from its vendor
# and unpacked into ./.toolchain. Nothing is installed system-wide, no sudo is
# needed, and deleting that folder undoes all of it.
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$PWD"
TC="$ROOT/.toolchain"
SDK="$TC/android-sdk"
mkdir -p "$TC"

say(){ printf "\n\033[1m==> %s\033[0m\n" "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }

ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || say "Note: expected arm64, found $ARCH — continuing anyway"

# ---------------------------------------------------------------- Node ------
NODE_DIR="$TC/node"
if [ ! -x "$NODE_DIR/bin/node" ]; then
  say "Fetching Node (native arm64, no installer)"
  NODE_URL="$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin) if r.get('lts') and 'osx-arm64-tar' in r.get('files',[])]
v=rs[0]['version']; print(f'https://nodejs.org/dist/{v}/node-{v}-darwin-arm64.tar.gz')")"
  echo "    $NODE_URL"
  curl -fL --progress-bar "$NODE_URL" -o "$TC/node.tar.gz"
  rm -rf "$NODE_DIR" && mkdir -p "$NODE_DIR"
  tar -xzf "$TC/node.tar.gz" -C "$NODE_DIR" --strip-components=1
  rm -f "$TC/node.tar.gz"
fi
export PATH="$NODE_DIR/bin:$PATH"
say "node $(node --version) / npm $(npm --version)"

# ---------------------------------------------------------------- JDK 21 ----
# Capacitor 7 compiles its Android library at Java 21 (sourceCompatibility
# VERSION_21), so 17 fails with "invalid source release: 21". The system JDK 20
# here is an x86_64 build and would run translated; this one is native arm64.
JDK_DIR="$TC/jdk21"
rm -rf "$TC/jdk17"   # superseded, reclaim the space
if [ ! -x "$JDK_DIR/bin/javac" ]; then
  say "Fetching Temurin JDK 21 (native arm64)"
  curl -fL --progress-bar -o "$TC/jdk.tar.gz" \
    "https://api.adoptium.net/v3/binary/latest/21/ga/mac/aarch64/jdk/hotspot/normal/eclipse?project=jdk"
  rm -rf "$TC/jdk-tmp" && mkdir -p "$TC/jdk-tmp"
  tar -xzf "$TC/jdk.tar.gz" -C "$TC/jdk-tmp"
  HOME_DIR="$(find "$TC/jdk-tmp" -maxdepth 3 -type d -name Home -path '*Contents*' | head -1)"
  rm -rf "$JDK_DIR" && mv "$HOME_DIR" "$JDK_DIR"
  rm -rf "$TC/jdk-tmp" "$TC/jdk.tar.gz"
fi
export JAVA_HOME="$JDK_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
say "java $("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"

# ------------------------------------------------------- Android SDK --------
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
SDKMGR="$SDK/cmdline-tools/latest/bin/sdkmanager"

if [ ! -x "$SDKMGR" ]; then
  say "Fetching Android command-line tools (native arm64, no Android Studio)"
  # Resolved from Google's own package manifest rather than a hardcoded build number.
  CLT_URL="$(curl -fsSL https://dl.google.com/android/repository/repository2-3.xml | python3 -c "
import re,sys
x=sys.stdin.read()
b=re.search(r'<remotePackage[^>]*path=\"cmdline-tools;latest\".*?</remotePackage>', x, re.S).group(0)
best=None
for a in re.findall(r'<archive>.*?</archive>', b, re.S):
    u=re.search(r'<url>([^<]+)</url>', a)
    if u and 'mac_arm64' in u.group(1): best=u.group(1)
    if u and 'mac_x86_64' in u.group(1) and not best: best=u.group(1)
print('https://dl.google.com/android/repository/'+best)")"
  echo "    $CLT_URL"
  curl -fL --progress-bar "$CLT_URL" -o "$TC/clt.zip"
  rm -rf "$TC/clt-tmp" && mkdir -p "$TC/clt-tmp"
  unzip -q "$TC/clt.zip" -d "$TC/clt-tmp"
  mkdir -p "$SDK/cmdline-tools"
  rm -rf "$SDK/cmdline-tools/latest"
  mv "$TC/clt-tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
  rm -rf "$TC/clt-tmp" "$TC/clt.zip"
fi
[ -x "$SDKMGR" ] || { echo "sdkmanager missing at $SDKMGR" >&2; exit 1; }

say "Accepting SDK licences and installing platform packages"
yes 2>/dev/null | "$SDKMGR" --sdk_root="$SDK" --licenses >/dev/null || true
"$SDKMGR" --sdk_root="$SDK" "platform-tools" "platforms;android-35" "build-tools;35.0.0"

# --------------------------------------------------------- Capacitor --------
[ -d node_modules ] || { say "Installing Capacitor"; npm install; }
[ -d android ]      || { say "Creating the Android project"; npx --no-install cap add android; }

say "Syncing web assets into the Android project"
npx --no-install cap sync android

# Point Gradle at this SDK without touching anything global.
printf 'sdk.dir=%s\n' "$SDK" > android/local.properties

# ------------------------------------------------- Permissions --------------
MANIFEST=android/app/src/main/AndroidManifest.xml
add_perm(){ grep -q "$1" "$MANIFEST" || /usr/bin/sed -i '' "s#<application#<uses-permission android:name=\"$1\" />\n    <application#" "$MANIFEST"; }
add_perm android.permission.INTERNET
add_perm android.permission.CAMERA
add_perm android.permission.POST_NOTIFICATIONS
add_perm android.permission.SCHEDULE_EXACT_ALARM

# ------------------------------------------------------------- Build --------
say "Building the APK (Gradle downloads itself on the first run — expect quiet minutes)"
cd android
JAVA_HOME="$JAVA_HOME" ./gradlew assembleDebug --no-daemon

cp app/build/outputs/apk/debug/app-debug.apk "$ROOT/Ledger.apk"
say "Done → $ROOT/Ledger.apk ($(du -h "$ROOT/Ledger.apk" | cut -f1))"
cat <<EOF

Install it on your phone with either:
  1. USB:  $SDK/platform-tools/adb install -r "$ROOT/Ledger.apk"
  2. File: copy Ledger.apk to the phone and tap it (allow "install unknown apps")

Everything this script downloaded lives in $TC — delete that folder to undo it all.
EOF
