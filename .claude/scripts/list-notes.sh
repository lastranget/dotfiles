#!/bin/bash
# List all markdown notes in the Obsidian vault with their metadata
# This script is called by the /list-notes slash command

VAULT_PATH="${1:-$HOME/vaults/Main}"

find "$VAULT_PATH" -type f -name "*.md" | sort | while read -r file; do
    # Get the title (filename without .md extension) for linking
    title=$(basename "$file" .md)
    rel_path="${file#$VAULT_PATH/}"

    echo "---"
    echo "Title: $title"
    echo "Path: $rel_path"

    # Extract description and frontmatter tags
    result=$(awk '
        BEGIN {
            in_frontmatter=0
            in_tags_section=0
            description=""
            frontmatter_tags=""
        }
        /^---$/ {
            if (NR==1) {
                in_frontmatter=1
                next
            } else if (in_frontmatter) {
                in_frontmatter=0
                next
            }
        }
        in_frontmatter && /^description:/ {
            sub(/^description:[[:space:]]*/, "")
            description=$0
        }
        in_frontmatter && /^tags:/ {
            in_tags_section=1
            next
        }
        in_frontmatter && in_tags_section && /^  - / {
            sub(/^  - /, "")
            if (frontmatter_tags != "") frontmatter_tags = frontmatter_tags ", "
            frontmatter_tags = frontmatter_tags $0
        }
        in_frontmatter && in_tags_section && /^[a-zA-Z]/ {
            in_tags_section=0
        }
        END {
            print frontmatter_tags
            print description
        }
    ' "$file")

    # Extract inline tags using grep and sed
    inline_tags=$(grep -ohE '#[a-zA-Z][a-zA-Z0-9_-]*' "$file" 2>/dev/null | sed 's/^#//' | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')

    # Parse awk output
    fm_tags=$(echo "$result" | sed -n '1p')
    desc=$(echo "$result" | sed -n '2p')

    # Combine tags
    if [ -n "$fm_tags" ] && [ -n "$inline_tags" ]; then
        all_tags="$fm_tags, $inline_tags"
    elif [ -n "$fm_tags" ]; then
        all_tags="$fm_tags"
    elif [ -n "$inline_tags" ]; then
        all_tags="$inline_tags"
    else
        all_tags=""
    fi

    # Print tags
    if [ -n "$all_tags" ]; then
        echo "Tags: $all_tags"
    else
        echo "Tags: (none)"
    fi

    # Print description
    if [ -n "$desc" ]; then
        echo "Description: $desc"
    else
        echo "Description: (no description)"
    fi
done
echo "---"
