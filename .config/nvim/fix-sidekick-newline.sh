#!/bin/bash

# Find and replace the hardcoded newline addition in sidekick.nvim
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
cp "$CLI_FILE" "$CLI_FILE.backup"
echo "Created backup: $CLI_FILE.backup"

# Find the line and replace it
# Using sed to find the exact pattern and replace it
# The pattern needs to be escaped properly for sed
sed -i 's/state\.session:send(msg .. "\\n")/state.session:send(msg)/g' "$CLI_FILE"

# Verify the change was made
if grep -q 'state\.session:send(msg)' "$CLI_FILE"; then
    echo "Successfully removed hardcoded newline from sidekick send function"
    echo "The line 'state.session:send(msg .. \"\\n\")' has been changed to 'state.session:send(msg)'"
else
    echo "Warning: Could not find the expected pattern in the file"
    echo "Restoring from backup..."
    cp "$CLI_FILE.backup" "$CLI_FILE"
    exit 1
fi

echo "Done! Restart Neovim to apply the changes."
