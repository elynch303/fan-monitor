#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="local.fan-monitor"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
RISE_DIR="$PLUGINS_DIR/local.rise"

fail() { echo "install: $*" >&2; exit 1; }

# Detect which bar is active
active_bar=$(python3 -c "
import json, sys
try:
    d = json.load(open('$SHELL_JSON'))
    print(d.get('bar', {}).get('id', 'default'))
except:
    print('default')
")

echo "Detected bar: $active_bar"

# ── local.rise integration ────────────────────────────────────────────────────
if [[ "$active_bar" == "local.rise" ]]; then
  [[ -d "$RISE_DIR" ]] || fail "local.rise plugin not found at $RISE_DIR"

  echo "Installing local.rise integration…"

  # Copy widget and panel files
  cp "$REPO/rise/FanMonitorWidget.qml" "$RISE_DIR/modules/FanMonitorWidget.qml"
  cp "$REPO/rise/FanPanel.qml"         "$RISE_DIR/panels/FanPanel.qml"

  # Patch Theme.qml, shell.qml, BarSlot.qml
  python3 - "$RISE_DIR" <<'PYEOF'
import sys, re

rise = sys.argv[1]

MARKER_BEGIN = "// --- fan-monitor-begin ---"
MARKER_END   = "// --- fan-monitor-end ---"

def already_patched(text):
    return MARKER_BEGIN in text

def apply(path, fn):
    text = open(path, encoding="utf-8").read()
    if already_patched(text):
        print(f"  {path}: already patched, skipping")
        return
    result = fn(text)
    if result is None:
        print(f"  {path}: patch anchor not found — skipping")
        return
    open(path, "w", encoding="utf-8").write(result)
    print(f"  {path}: patched OK")

# ── Theme.qml ─────────────────────────────────────────────────────────────────
def patch_theme(text):
    # 1. Add fanMonitorVisible to anyPopupVisible (append to last line of the property)
    text = re.sub(
        r'(\|\| trayMenuVisible\b)',
        r'\1\n        ' + MARKER_BEGIN + '\n        || fanMonitorVisible\n        ' + MARKER_END,
        text, count=1
    )
    # 2. Add closePopups reset — find the last reset line and insert after
    text = re.sub(
        r'(if \(except !== "trayMenuVisible"\) trayMenuVisible = false)',
        r'\1\n        ' + MARKER_BEGIN + '\n        if (except !== "fanMonitorVisible") fanMonitorVisible = false\n        ' + MARKER_END,
        text, count=1
    )
    # 3. Add barX property near batteryBarX
    text = re.sub(
        r'(property real batteryBarX:\s+0)',
        r'\1\n    ' + MARKER_BEGIN + '\n    property bool fanMonitorVisible: false\n    property real fanMonitorBarX: 0\n    ' + MARKER_END,
        text, count=1
    )
    # 4. Add applyAnchor entry near battery
    text = re.sub(
        r'(else if \(name === "battery"\) batteryBarX = x)',
        r'\1\n        ' + MARKER_BEGIN + '\n        else if (name === "fanMonitor") fanMonitorBarX = x\n        ' + MARKER_END,
        text, count=1
    )
    return text

apply(rise + "/Theme.qml", patch_theme)

# ── shell.qml ─────────────────────────────────────────────────────────────────
def patch_shell(text):
    return re.sub(
        r'(BatteryPanel \{ root: theme \})',
        r'\1\n    ' + MARKER_BEGIN + '\n    FanPanel { root: theme }\n    ' + MARKER_END,
        text, count=1
    )

apply(rise + "/shell.qml", patch_shell)

# ── BarSlot.qml ───────────────────────────────────────────────────────────────
def patch_barslot(text):
    # 1. Add component after compBluetooth
    text = re.sub(
        r'(Component \{ id: compBluetooth[^\n]+\n)',
        r'\1    ' + MARKER_BEGIN + '\n    Component { id: compFanMonitor; FanMonitorWidget { root: barSlot.root } }\n    ' + MARKER_END + '\n',
        text, count=1
    )
    # 2. Add to registry
    text = re.sub(
        r'("G15": compBluetooth\b)',
        r'\1,\n        ' + MARKER_BEGIN + '\n        "G16": compFanMonitor\n        ' + MARKER_END,
        text, count=1
    )
    # 3. Add G16 to rightModel ListElements
    text = re.sub(
        r'(ListElement \{ gid: "G15" \}\n        \})',
        r'ListElement { gid: "G15" } ' + MARKER_BEGIN + ' ListElement { gid: "G16" } ' + MARKER_END + '\n        }',
        text, count=1
    )
    # 4. Add to panelAnchors
    text = re.sub(
        r'(bluetooth:\s+island\.groupX\("G15"[^\n]+\n)',
        r'\1                ' + MARKER_BEGIN + '\n                fanMonitor: island.groupX("G16", 0.5),\n                ' + MARKER_END + '\n',
        text, count=1
    )
    # 5. Extend rightSplits from 6 to 7 elements
    text = re.sub(
        r'(property var rightSplits:\s+\[false, false, false, false, false, false\])',
        r'property var rightSplits: [false, false, false, false, false, false, false] ' + MARKER_BEGIN + MARKER_END,
        text, count=1
    )
    return text

apply(rise + "/BarSlot.qml", patch_barslot)

print("Patching complete.")
PYEOF

  echo "Restarting shell…"
  omarchy restart shell 2>/dev/null || true
  echo ""
  echo "Fan Monitor installed in local.rise bar (right side, drag to reorder)."

# ── standard Omarchy bar ──────────────────────────────────────────────────────
else
  TARGET="$PLUGINS_DIR/$PLUGIN_ID"
  if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    fail "$TARGET already exists — run uninstall.sh first"
  fi

  ln -s "$REPO" "$TARGET"
  echo "Linked $REPO → $TARGET"

  # Add widget to shell.json right section (before omarchy.power if present)
  python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PYEOF'
import json, sys
path, plugin_id = sys.argv[1], sys.argv[2]
d = json.load(open(path, encoding="utf-8"))

bar = d.get("bar", {})
layout = bar.get("layout")

def insert_before_power(lst, entry):
    for i, item in enumerate(lst):
        iid = item if isinstance(item, str) else item.get("id", "")
        if iid == "omarchy.power":
            lst.insert(i, entry)
            return
    lst.append(entry)

if layout:
    right = layout.get("right", [])
    entry = {"id": plugin_id}
    if not any((x if isinstance(x, str) else x.get("id")) == plugin_id for x in right):
        insert_before_power(right, entry)
        layout["right"] = right
elif "right" in bar:
    right = bar["right"]
    if plugin_id not in right:
        insert_before_power(right, plugin_id)
        bar["right"] = right

d["bar"] = bar
open(path, "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
print(f"Added {plugin_id} to bar layout")
PYEOF

  omarchy plugin rescan 2>/dev/null || true
  echo ""
  echo "Fan Monitor installed. Click the 󱕘 icon in your bar to open."
fi
