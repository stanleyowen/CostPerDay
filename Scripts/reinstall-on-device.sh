#!/bin/bash
# Keeps a free-provisioning build of Wallet alive on a paired iPhone.
#
# A free Apple developer account signs apps with a 7-day provisioning profile.
# This script is run every 2 hours by a LaunchAgent (see
# Scripts/install-reinstall-agent.sh). Each run:
#   1. exits quietly unless the last successful reinstall was >= 5 days ago;
#   2. checks the Mac is online and the iPhone is reachable (same Wi-Fi as the
#      Mac, or plugged in); if not, notifies and waits for the next run;
#   3. builds the last commit (never half-edited files) with a freshly
#      generated 7-day profile and installs it over the existing app, which
#      keeps the app's data.
#
# Usage: reinstall-on-device.sh [--force]   (--force ignores the 5-day wait)
#
# Environment (all optional):
#   WALLET_DEVICE         UDID/name of the iPhone (default: first paired physical iPhone)
#   WALLET_REPO           git repo to build from (default: this checkout; the
#                         LaunchAgent uses a mirror outside ~/Documents)
#   WALLET_REF            git ref to build (default: HEAD of the repo's current branch)
#   WALLET_CONFIGURATION  Debug or Release (default: Release)
#   WALLET_REINSTALL_DAYS days between reinstalls (default: 5)

set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"

REPO="${WALLET_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
DEVICE="${WALLET_DEVICE:-}"
REF="${WALLET_REF:-HEAD}"
CONFIGURATION="${WALLET_CONFIGURATION:-Release}"
INTERVAL_DAYS="${WALLET_REINSTALL_DAYS:-5}"
BUNDLE_ID="com.stanley.wallet"

STATE_DIR="$HOME/Library/Application Support/WalletReinstall"
WORK="$HOME/Library/Caches/WalletReinstall"
LOG="$HOME/Library/Logs/WalletReinstall.log"
BUILD_LOG="$WORK/last-build.log"
PROFILE_DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
              "$HOME/Library/MobileDevice/Provisioning Profiles")

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "$STATE_DIR" "$WORK" "$(dirname "$LOG")"
# Keep the log small.
if [[ -f "$LOG" ]] && (( $(stat -f%z "$LOG") > 2000000 )); then
    tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

notify() { # title, message
    /usr/bin/osascript - "$1" "$2" >/dev/null 2>&1 <<'EOF'
on run argv
    display notification (item 2 of argv) with title (item 1 of argv) sound name "default"
end run
EOF
}

fail() { # message: notify, log, and leave the retry to the next scheduled run
    log "FAILED: $1"
    notify "Wallet reinstall failed" "$1 Retrying in 2 hours."
    exit 0
}

# One run at a time (a build can outlast a wake-up burst of launchd runs).
LOCK="$WORK/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    # Stale lock from a crashed run?
    if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]]; then
        rm -rf "$LOCK" && mkdir "$LOCK" || exit 0
    else
        exit 0
    fi
fi
trap 'rm -rf "$LOCK"' EXIT

# 1. Due?
now=$(date +%s)
last=$(cat "$STATE_DIR/last-success" 2>/dev/null || echo 0)
if (( FORCE == 0 && now - last < INTERVAL_DAYS * 86400 )); then
    exit 0
fi
log "Reinstall due (last success: $( ((last)) && date -r "$last" '+%Y-%m-%d %H:%M' || echo never))."

# 2a. Mac online? (A fresh profile has to come from Apple.)
if ! /usr/sbin/scutil -r developerservices2.apple.com | grep -q '^Reachable'; then
    fail "The Mac is offline."
fi

# 2b. Find the iPhone and check it can be reached.
JSON="$WORK/devices.json"
if [[ -z "$DEVICE" ]]; then
    xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
    DEVICE=$(/usr/bin/python3 -I - "$JSON" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit()
for d in devices:
    if (d.get("hardwareProperties", {}).get("reality") == "physical"
            and d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
            and d.get("connectionProperties", {}).get("pairingState") == "paired"):
        print(d["hardwareProperties"].get("udid") or d["identifier"])
        break
EOF
)
    [[ -n "$DEVICE" ]] || fail "No paired iPhone found."
fi

xcrun devicectl device info details --device "$DEVICE" --timeout 60 \
    --json-output "$JSON" >/dev/null 2>&1
IFS=$'\t' read -r NAME TUNNEL TRANSPORT < <(/usr/bin/python3 -I - "$JSON" <<'EOF'
import json, sys
try:
    r = json.load(open(sys.argv[1]))["result"]
except Exception:
    print("Your iPhone\tnone\tnone"); sys.exit()
c = r.get("connectionProperties", {})
name = r.get("deviceProperties", {}).get("name") or "Your iPhone"
print("\t".join([name, c.get("tunnelState", "none"), c.get("transportType", "none")]))
EOF
)
if [[ "$TUNNEL" != "connected" ]]; then
    fail "$NAME isn't reachable — keep it unlocked on the same Wi-Fi as the Mac (or plug it in)."
fi
log "Device $NAME reachable over $TRANSPORT."

# 3a. Source: the committed tree only.
SRC="$WORK/src"
COMMIT=$(git -C "$REPO" rev-parse --short "$REF" 2>/dev/null) || fail "Can't resolve $REF in $REPO."
rm -rf "$SRC" && mkdir -p "$SRC"
git -C "$REPO" archive "$REF" | tar -x -C "$SRC" || fail "Couldn't export $REF."

# 3b. Move the cached profile aside so Xcode generates a fresh 7-day one
#     instead of reusing the current one (which may have only 2 days left).
BACKUP="$WORK/old-profiles"
rm -rf "$BACKUP" && mkdir -p "$BACKUP"
for dir in "${PROFILE_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    for p in "$dir"/*.mobileprovision; do
        [[ -f "$p" ]] || continue
        appid=$(security cms -D -i "$p" 2>/dev/null \
            | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null)
        if [[ "$appid" == *".$BUNDLE_ID" ]]; then
            mv "$p" "$BACKUP/" && log "Set aside profile $(basename "$p")."
        fi
    done
done
restore_profiles() {
    for p in "$BACKUP"/*.mobileprovision; do
        [[ -f "$p" ]] && mv -n "$p" "${PROFILE_DIRS[0]}/"
    done
}

# 3c. Build.
DERIVED="$WORK/DerivedData"
log "Building $COMMIT ($CONFIGURATION)…"
if ! xcodebuild build \
        -project "$SRC/Wallet.xcodeproj" -scheme Wallet \
        -configuration "$CONFIGURATION" \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates \
        > "$BUILD_LOG" 2>&1; then
    restore_profiles
    grep -E 'error:' "$BUILD_LOG" | head -5 >> "$LOG"
    fail "Build failed (see $BUILD_LOG)."
fi

APP=$(find "$DERIVED/Build/Products/$CONFIGURATION-iphoneos" -maxdepth 1 -name '*.app' | head -1)
[[ -d "$APP" ]] || { restore_profiles; fail "Built app not found."; }

EXPIRES=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null \
    | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
EXPIRES_EPOCH=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$EXPIRES" '+%s' 2>/dev/null)
EXPIRES_LOCAL=$( [[ -n "$EXPIRES_EPOCH" ]] && date -r "$EXPIRES_EPOCH" '+%a %-d %b %H:%M' || echo "$EXPIRES")
log "Built $(basename "$APP"); profile expires $EXPIRES_LOCAL."

# 3d. Install over the existing app (keeps its data). Wi-Fi connections to a
#     dozing iPhone drop now and then, so try a few times.
installed=0
for attempt in 1 2 3 4; do
    if xcrun devicectl device install app --device "$DEVICE" "$APP" --timeout 300 \
            >> "$BUILD_LOG" 2>&1; then
        installed=1; break
    fi
    log "Install attempt $attempt failed."
    sleep 30
    xcrun devicectl device info details --device "$DEVICE" --timeout 60 >/dev/null 2>&1
done
(( installed )) || fail "Built, but installing on $NAME failed (see $BUILD_LOG)."

echo "$now" > "$STATE_DIR/last-success"
rm -rf "$BACKUP"
log "Installed $COMMIT on $NAME."
notify "Wallet reinstalled" "Build $COMMIT installed on $NAME. Valid until $EXPIRES_LOCAL."
