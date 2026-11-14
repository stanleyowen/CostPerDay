#!/bin/bash
# Installs (or removes) the LaunchAgent that runs reinstall-on-device.sh every
# 2 hours. The script itself only rebuilds once 5 days have passed since the
# last successful reinstall, so most runs exit immediately.
#
# macOS privacy protection stops background jobs from reading ~/Documents, so
# the agent never touches this checkout. Instead it runs a copy of the script
# from ~/Library/Application Support/WalletReinstall and builds from a bare
# mirror there, which git hooks in this repo (post-commit, post-checkout,
# post-merge, post-rewrite) keep pointed at the checked-out commit.
#
# Usage:
#   Scripts/install-reinstall-agent.sh [DEVICE]   install; DEVICE = UDID or name,
#                                                 default: first paired iPhone
#   Scripts/install-reinstall-agent.sh --uninstall
#
# After installing:
#   Run now:     launchctl kickstart gui/$(id -u)/com.stanley.wallet.reinstall
#   Force a run: "$HOME/Library/Application Support/WalletReinstall/reinstall-on-device.sh" --force
#   Log:         ~/Library/Logs/WalletReinstall.log

set -euo pipefail

LABEL="com.stanley.wallet.reinstall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
SUPPORT="$HOME/Library/Application Support/WalletReinstall"
MIRROR="$SUPPORT/repo.git"
HOOKS_DIR="$(git -C "$REPO" rev-parse --absolute-git-dir)/hooks"
HOOKS=(post-commit post-checkout post-merge post-rewrite)
MARKER="# wallet-reinstall-mirror"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$PLIST"
    for h in "${HOOKS[@]}"; do
        grep -q "$MARKER" "$HOOKS_DIR/$h" 2>/dev/null && rm -f "$HOOKS_DIR/$h"
    done
    rm -rf "$MIRROR" "$SUPPORT/reinstall-on-device.sh"
    echo "Removed $LABEL and its git hooks."
    exit 0
fi

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
    JSON="$(mktemp)"
    xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
    DEVICE=$(/usr/bin/python3 -I - "$JSON" <<'EOF'
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    h = d.get("hardwareProperties", {})
    if (h.get("reality") == "physical" and h.get("deviceType") == "iPhone"
            and d.get("connectionProperties", {}).get("pairingState") == "paired"):
        print(h.get("udid") or d["identifier"]); break
EOF
)
    rm -f "$JSON"
    [[ -n "$DEVICE" ]] || { echo "No paired iPhone found; pass its UDID." >&2; exit 1; }
fi

# Mirror + script copy outside ~/Documents.
mkdir -p "$SUPPORT" "$(dirname "$PLIST")" "$HOME/Library/Logs"
[[ -d "$MIRROR" ]] || git init --quiet --bare "$MIRROR"
git -C "$REPO" push --quiet --force "$MIRROR" HEAD:refs/heads/build
install -m 755 "$REPO/Scripts/reinstall-on-device.sh" "$SUPPORT/reinstall-on-device.sh"

# Hooks that keep the mirror (and the script copy) on the checked-out commit.
for h in "${HOOKS[@]}"; do
    if [[ -e "$HOOKS_DIR/$h" ]] && ! grep -q "$MARKER" "$HOOKS_DIR/$h"; then
        echo "warning: $HOOKS_DIR/$h already exists; not replacing it." >&2
        echo "         Add this line to it: git push -q -f \"$MIRROR\" HEAD:refs/heads/build" >&2
        continue
    fi
    cat > "$HOOKS_DIR/$h" <<'EOF'
#!/bin/sh
# wallet-reinstall-mirror
# Installed by Scripts/install-reinstall-agent.sh: copies the checked-out commit
# outside ~/Documents for the LaunchAgent that reinstalls Wallet on the iPhone.
D="$HOME/Library/Application Support/WalletReinstall"
[ -d "$D/repo.git" ] || exit 0
git push --quiet --force "$D/repo.git" HEAD:refs/heads/build >/dev/null 2>&1
git show HEAD:Scripts/reinstall-on-device.sh > "$D/reinstall-on-device.sh.tmp" 2>/dev/null \
    && mv "$D/reinstall-on-device.sh.tmp" "$D/reinstall-on-device.sh" \
    && chmod 755 "$D/reinstall-on-device.sh"
rm -f "$D/reinstall-on-device.sh.tmp"
exit 0
EOF
    chmod 755 "$HOOKS_DIR/$h"
done

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SUPPORT/reinstall-on-device.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SUPPORT</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>WALLET_DEVICE</key>
        <string>$DEVICE</string>
        <key>WALLET_REPO</key>
        <string>$MIRROR</string>
        <key>WALLET_REF</key>
        <string>build</string>
    </dict>
    <!-- Every 2 hours; a run missed while the Mac slept fires on wake. -->
    <key>StartInterval</key>
    <integer>7200</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/WalletReinstall.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/WalletReinstall.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $LABEL for device $DEVICE (runs every 2 h; reinstalls every 5 days)."
