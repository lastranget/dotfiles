# Current Work

(No active projects)

## Distinguishing note types

There are two types of note databases that will be interatcted with frequently:
1. Obsidian
2. Basic Memory

### Obsidian (~/vaults/Main/)
The Obsidian vault is primarily for the *user*, but the user may have you reference and update it as well. The user will mention "obsidian" when it wants you to use obsidian, and the relevant skills and subagents to use will include "obsidian" in their titles.

### Basic Memory
Basic Memory is available via MCP, and this is primarily for aggregating session behavior and memory. The /update-memory slash command is intended to purely interact with Basic Memory.

#### Differences from Obsidian

Obsidian has a single vault, whereas there may be multiple Basic Memory projects.

### Important!
It can be confusing as to which note type you're intended to work with, so if you're ever in doubt, prompt the user for clarification

## Claude Code Slash Commands

When creating a new slash command:
1. Create the command file in `~/.claude/commands/`
2. Add an entry to the documentation in `~/vaults/Main/ai/claude-code-slash-commands.md`
3. Include the command name and a one-sentence description of what it does

## System Info
- OS: Ubuntu with i3 window manager
- Display manager: (not yet identified)
