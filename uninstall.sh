#!/bin/bash
set -euo pipefail

PLUGIN_ID="local.fan-monitor"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
RISE_DIR="$PLUGINS_DIR/local.rise"

fail() { echo "uninstall: $*" >&2; exit 1; }

active_bar=$(python3 -c "
import json, sys
try:
    d = json.load(open('$SHELL_JSON'))
    print(d.get('bar', {}).get('id', 'default'))
except:
    print('default')
")

MARKER_BEGIN="// --- fan-monitor-begin ---"
MARKER_END="// --- fan-monitor-end ---"

if [[ "$active_bar" == "local.rise" ]]; then
  echo "Removing local.rise integration…"

  # Remove copied files
  rm -f "$RISE_DIR/modules/FanMonitorWidget.qml"
  rm -f "$RISE_DIR/panels/FanPanel.qml"

  # Remove patches
  python3 - "$RISE_DIR" <<'PYEOF'
import sys, re

rise = sys.argv[1]
MARKER_BEGIN = "// --- fan-monitor-begin ---"
MARKER_END   = "// --- fan-monitor-end ---"

def strip_markers(text):
    pattern = re.compile(
        r'\s*' + re.escape(MARKER_BEGIN) + r'.*?' + re.escape(MARKER_END),
        re.DOTALL
    )
    return pattern.sub("", text)

for rel in ["Theme.qml", "shell.qml", "BarSlot.qml"]:
    path = rise + "/" + rel
    text = open(path, encoding="utf-8").read()
    if MARKER_BEGIN not in text:
        print(f"  {rel}: not patched, skipping")
        continue
    # Restore rightSplits to 6 elements
    if rel == "BarSlot.qml":
        text = re.sub(
            r'property var rightSplits:\s*\[false, false, false, false, false, false, false\]',
            'property var rightSplits: [false, false, false, false, false, false]',
            text
        )
    result = strip_markers(text)
    open(path, "w", encoding="utf-8").write(result)
    print(f"  {rel}: unpatched OK")
PYEOF

  echo "Restarting shell…"
  omarchy restart shell 2>/dev/null || true
  echo "Fan Monitor removed from local.rise."

else
  TARGET="$PLUGINS_DIR/$PLUGIN_ID"
  [[ -L "$TARGET" ]] || fail "$TARGET is not a symlink — remove manually"
  rm "$TARGET"
  echo "Removed $TARGET"

  # Remove from shell.json
  python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PYEOF'
import json, sys
path, plugin_id = sys.argv[1], sys.argv[2]
d = json.load(open(path, encoding="utf-8"))
bar = d.get("bar", {})
layout = bar.get("layout")

def remove_id(lst, pid):
    return [x for x in lst if (x if isinstance(x, str) else x.get("id", "")) != pid]

if layout:
    if "right" in layout:
        layout["right"] = remove_id(layout["right"], plugin_id)
elif "right" in bar:
    bar["right"] = remove_id(bar["right"], plugin_id)

d["bar"] = bar
open(path, "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
print(f"Removed {plugin_id} from bar layout")
PYEOF

  omarchy plugin rescan 2>/dev/null || true
  echo "Fan Monitor uninstalled."
fi
