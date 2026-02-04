#!/bin/bash

# Restore the hardcoded newline addition in sidekick.nvim
SIDEKICK_DIR="$HOME/.local/share/nvim/lazy/sidekick.nvim"
CLI_FILE="$SIDEKICK_DIR/lua/sidekick/cli/init.lua"

# Check if the sidekick directory exists
if [ ! -d "$SIDEKICK_DIR" ]; then
    echo "Error: sidekick.nvim directory not found at $SIDEKICK_DIR"
    exit 1
fi

# Check if the CLI file exists
if [ ! -f "$CLI_FILE" ]; then
    echo "Error: CLI file not found at $CLI_FILE"
    exit 1
fi

# Create a backup
cp "$CLI_FILE" "$CLI_FILE.backup.restore"
echo "Created backup: $CLI_FILE.backup.restore"

# Find the line and restore it
# Using sed to find the exact pattern and replace it
sed -i 's/state\.session:send(msg)/state.session:send(msg .. "\\n")/g' "$CLI_FILE"

# Verify the change was made
if grep -q 'state\.session:send(msg .. "\\n")' "$CLI_FILE"; then
    echo "Successfully restored hardcoded newline to sidekick send function"
    echo "The line 'state.session:send(msg)' has been changed to 'state.session:send(msg .. \"\\n\")'"
else
    echo "Warning: Could not find the expected pattern in the file"
    echo "Restoring from backup..."
    cp "$CLI_FILE.backup.restore" "$CLI_FILE"
    exit 1
fi

echo "Done! Restart Neovim to apply the changes."
