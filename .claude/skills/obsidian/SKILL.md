---
name: obsidian
description: Use when creating or editing Obsidian notes in ~/vaults/Main/, handles
  note creation workflow with tag and link enhancement
permalink: skills/obsidian/skill
---

# Obsidian Vault Skill

## When to Load This Skill

Load this skill WHEN:
- The user asks to create a new Obsidian note
- The user asks to update or edit an existing Obsidian note
- The user mentions working with files in `~/vaults/Main/`
- The conversation involves Obsidian vault operations

Do NOT load this skill when:
- Having general discussions about Obsidian (the application itself)
- Discussing note-taking strategies without actual file operations
- The user is asking about Obsidian features or settings
- The user is asking about notes *without* mentioning Obsidia

## Default Location

New notes should be created in `~/vaults/Main/ai/fleeting/` by default unless the user specifies otherwise.

## Workflow for Creating or Updating Notes

When creating or updating Obsidian notes, follow this workflow:

### 1. Create the First Draft
Write the complete note content with all the information the user requested. Don't worry about tags or links yet - just focus on the core content.

### 2. Invoke the Obsidian Enhancer Subagent
Use the Task tool to invoke the `obsidian-enhancer` subagent. Provide it with:
- The first draft of the note
- Whether this is a NEW note or EXISTING note being edited
- The file path where the note will be saved

Example:
```
I need you to enhance this Obsidian note draft with appropriate tags and links.

This is a NEW note that will be saved at: ~/Documents/Main/ai/example-note.md

Please analyze the vault, add relevant tags following the tag rules for new notes (ai, ai-generated, weedy, plus relevant existing tags), add appropriate Obsidian links with natural aliases, and return the enhanced version.

Here's the first draft:
[paste the draft content here]
```

### 3. Receive Enhanced Note
The subagent will return the enhanced note with:
- Proper frontmatter (tags and description)
- Obsidian links added throughout the content
- Natural-flowing alias text for links

### 4. Write the Final Note
Use the Write or Edit tool to save the enhanced note to the vault.

## Important Reminders

- **Always use the subagent** for tag and link enhancement - don't try to do it manually
- **Default location** is `~/vaults/Main/ai/fleeting` for new notes
- **The subagent handles** all tag selection, frontmatter creation, and link insertion
- **You handle** the core content creation and the actual file write operation
- **Security boundary**: The subagent analyzes; you execute the file modifications

## Example Flow

User: "Create a note about configuring tmux plugins"

You:
1. Draft the note content about tmux plugins
2. Invoke obsidian-enhancer subagent with the draft
3. Receive enhanced version with tags (ai, ai-generated, weedy, tmux, terminal, etc.) and links to related notes
4. Write the final enhanced note to ~/vaults/Main/ai/fleeting/tmux-plugins-configuration.md
