#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEVBOX_JSON="$DIR/../devbox.json"

echo "## devbox-update: pin packages to latest versions"
echo "## devbox.json: $DEVBOX_JSON"

# Extract package names from devbox.json (strips @version suffix)
PACKAGES=$(grep -oP '"[a-zA-Z0-9_-]+@[^"]*"' "$DEVBOX_JSON" | tr -d '"' | cut -d@ -f1)

for PKG in $PACKAGES; do
  CURRENT=$(grep -oP "\"${PKG}@[^\"]*\"" "$DEVBOX_JSON" | tr -d '"' | cut -d@ -f2)
  LATEST=$(devbox search "$PKG" 2>/dev/null | grep -oP '\(([0-9][^,)]+)' | head -1 | tr -d '(')

  if [ -z "$LATEST" ]; then
    echo "  ⚠️  $PKG: could not resolve latest version (keeping $CURRENT)"
    continue
  fi

  if [ "$CURRENT" = "$LATEST" ]; then
    echo "  ✓  $PKG@$CURRENT (up to date)"
  else
    echo "  ⬆  $PKG: $CURRENT → $LATEST"
    # Use sed to replace in devbox.json
    sed -i "s|\"${PKG}@${CURRENT}\"|\"${PKG}@${LATEST}\"|g" "$DEVBOX_JSON"
  fi
done

echo ""
echo "## Updated devbox.json packages:"
grep -oP '"[a-zA-Z0-9_-]+@[^"]*"' "$DEVBOX_JSON" | tr -d '"' | sed 's/^/  /'
