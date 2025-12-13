#!/bin/bash
# Backup an Obsidian vault to a timestamped zip file
# This script is called by the /backup-vault slash command

# Get vault name from argument, default to "Main"
VAULT_NAME="${1:-Main}"
VAULT_PATH="$HOME/vaults/$VAULT_NAME"
BACKUP_DIR="$HOME/vaults/backups"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/${VAULT_NAME}-${TIMESTAMP}.zip"

# Check if vault exists
if [ ! -d "$VAULT_PATH" ]; then
    echo "Error: Vault directory '$VAULT_PATH' does not exist"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create the backup
echo "Backing up vault '$VAULT_NAME'..."
echo "Source: $VAULT_PATH"
echo "Destination: $BACKUP_FILE"
echo ""

cd "$HOME/vaults" && zip -r "$BACKUP_FILE" "$VAULT_NAME" -q

# Check if backup was successful
if [ $? -eq 0 ]; then
    # Get file size
    FILE_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    echo "✓ Backup created successfully"
    echo "  File: ${VAULT_NAME}-${TIMESTAMP}.zip"
    echo "  Size: $FILE_SIZE"
    echo "  Location: $BACKUP_DIR"
else
    echo "✗ Backup failed"
    exit 1
fi
