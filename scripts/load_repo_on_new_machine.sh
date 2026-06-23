#!/bin/bash

# Dotfiles installation script
# Clones bare repo and checks out dotfiles to $HOME
#
# To install dotfiles on a new machine, run:
#   curl -sSL https://raw.githubusercontent.com/lastranget/dotfiles/master/load_repo_on_new_machine.sh | bash

set -e

DOTFILES_REPO="git@github.com:lastranget/dotfiles.git"
DOTFILES_DIR="$HOME/.cfg"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Temporary git wrapper until we can source the alias
_cfg() {
    /usr/bin/git --git-dir="$DOTFILES_DIR/" --work-tree="$HOME" "$@"
}

# Ensure .cfg is in .gitignore to prevent recursion
echo ".cfg" >> "$HOME/.gitignore"

# Clone the bare repository
git clone --bare "$DOTFILES_REPO" "$DOTFILES_DIR"

# Configure remote tracking (bare clone doesn't set this up properly)
_cfg config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
_cfg fetch origin

# Try to checkout
if _cfg checkout 2>/dev/null; then
    echo "Checked out dotfiles successfully."
else
    echo "Backing up pre-existing dotfiles to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    _cfg checkout 2>&1 | egrep "^\s+" | awk '{print $1}' | while read -r file; do
        mkdir -p "$BACKUP_DIR/$(dirname "$file")"
        mv "$HOME/$file" "$BACKUP_DIR/$file"
    done
    _cfg checkout
fi

# Set up branch tracking
_cfg branch --set-upstream-to=origin/master master 2>/dev/null || true

# Hide untracked files
_cfg config --local status.showUntrackedFiles no

# Source the aliases for current shell
source "$HOME/.bash_aliases"

echo "Dotfiles installed. 'cfg' alias now available."
