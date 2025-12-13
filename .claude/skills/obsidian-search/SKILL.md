---
name: obsidian-search
description: Use for SEMANTIC searches in ~/vaults/Main/ when user needs conceptual/cross-domain
  note discovery (e.g., "what do I know about X?", "notes that would help with Y").
  NOT for simple keyword searches - use grep/glob for those (e.g., "notes mentioning Z")
permalink: skills/obsidian-search/skill
---

# Obsidian Search Skill

## When to Load This Skill

This skill is designed for **semantic/conceptual searches** that benefit from content analysis. It costs 4-5x more tokens than direct grep/glob, so use it only when semantic understanding adds clear value.

**Load this skill for SEMANTIC/CONCEPTUAL queries:**
- "What do I know about improving my productivity?" (broad concept)
- "Find notes that would help me customize Claude Code" (needs interpretation)
- "Notes about terminal workflow optimization" (conceptual)
- "Everything related to my development environment" (multi-domain)
- "Do I have anything useful about X?" (needs judgment of "useful")

**Load this skill for CROSS-DOMAIN queries:**
- "Notes combining tmux AND Claude" (intersection of topics)
- "Where have I documented automation workflows?" (multiple areas)
- "Find connections between Obsidian and AI tools" (relationship discovery)

**Load this skill when EXPLICITLY requested:**
- User says "search my vault" or "semantically search my notes"
- User says "look through my notes" (implies broader analysis)
- User asks "check my Obsidian notes" (implies semantic review)

**Load this skill for LARGE RESULT SETS:**
- Query likely to match 20+ files needing filtering
- User needs "best 5" from many candidates

## When NOT to Load This Skill

Do NOT load when **simple keyword/pattern matching works** (use grep/glob directly):

**Keyword searches (use Grep instead):**
- ❌ "Find notes mentioning tmux" → `Grep "tmux"`
- ❌ "Notes with 'Claude' in them" → `Grep "Claude"`
- ❌ "Files tagged with X" → `Grep "tags:.*X"`
- ❌ "Notes about claude" (specific keyword) → `Grep "claude"`

**Pattern searches (use Glob instead):**
- ❌ "Load MOC notes" → `Glob "*MOC*.md"`
- ❌ "Files ending in -config" → `Glob "*-config.md"`
- ❌ "Notes in ai/ folder" → `Glob "ai/**/*.md"`

**Specific file operations:**
- ❌ User provides file paths or specific names
- ❌ User wants to CREATE or EDIT (use `obsidian` skill)

**Non-search activities:**
- ❌ Discussing Obsidian features/settings
- ❌ General Obsidian application questions

## Decision Criteria: Skill vs. Direct Tools

Before loading this skill, ask yourself:

1. **Does this need semantic understanding?**
   - ✅ "notes about productivity" → Use skill
   - ❌ "notes with word 'tmux'" → Use grep

2. **Are clear keywords/patterns given?**
   - ❌ Vague/conceptual → Use skill
   - ✅ Specific literal terms → Use grep/glob

3. **Expected result set size?**
   - ✅ 20+ files needing analysis → Use skill
   - ❌ <10 likely matches → Use grep/glob

4. **Cross-domain or single-topic?**
   - ✅ Multiple domains → Use skill
   - ❌ Single clear topic → Use grep/glob

**Default:** When in doubt, use grep/glob first. Only use this skill when semantic analysis clearly adds value over simple text matching.

## Workflow for Finding Relevant Notes

When searching for relevant Obsidian notes, follow this workflow:

### 1. Understand the Search Intent
Clarify what information or topics to search for based on:
- The user's explicit request
- The current conversation context
- Related topics that might provide useful context

### 2. Invoke the Obsidian Note Finder Subagent
Use the Task tool to invoke the `obsidian-note-finder` subagent. Provide it with:
- Clear description of what to search for
- Current conversation context if relevant
- Any specific filters (tags, topics, date ranges if mentioned)

Example:
```
I need you to search the Obsidian vault for notes relevant to [topic/question].

Current context: [brief summary of what we're working on]

Please analyze the vault, identify relevant notes based on titles, tags, and descriptions, read the most promising candidates, and return a structured report of which notes are relevant and why.
```

### 3. Review Subagent Recommendations
The subagent will return a structured report with:
- High relevance notes (directly related)
- Medium relevance notes (tangentially related)
- Suggested notes to explore (metadata matches only)

Carefully review these recommendations to determine which notes to fully load.

### 4. Load Selected Notes
For notes the subagent marked as highly relevant:
- Use the Read tool to load the full content
- Focus on notes that the subagent has already read and verified
- Consider loading medium relevance notes if they might add important context

### 5. Present Findings to User
Synthesize the information and present:
- Summary of what was found
- Key insights from the most relevant notes
- Connections between notes if applicable
- Suggestions for notes the user might want to explore further

## Important Reminders

- **Always use the subagent** for initial search and filtering - don't try to manually search the vault
- **The subagent handles** vault analysis, metadata filtering, and initial content sampling
- **You handle** the decision of which notes to fully load and how to present findings
- **Be selective** - don't overwhelm the user with every loosely related note
- **Security boundary**: The subagent searches and recommends; you execute the final reads and presentation

## Example Flow

**Good Use Case (Semantic/Conceptual):**

User: "What do I know about improving my terminal workflow?"

You:
1. Recognize this is conceptual (not just "tmux" keyword) → Load skill
2. Invoke obsidian-note-finder subagent with semantic context: "terminal workflow improvement, productivity, efficiency"
3. Receive report identifying cross-domain notes (tmux, bash completion, terminal multiplexers, keyboard shortcuts, automation scripts)
4. Read high-relevance notes the subagent recommended
5. Present findings: "I found several relevant notes across different areas: Your tmux configuration covers session management for parallel workflows, bash-completion note discusses faster command entry, and your terminal automation scripts note has workflow optimization ideas. These combine to form a comprehensive view of your terminal productivity system."

**Bad Use Case (Should Use Grep):**

User: "Do I have notes mentioning tmux?"

You:
1. Recognize this is a keyword search → Don't load skill
2. Use Grep directly: `Grep "tmux"`
3. Find matching files quickly
4. Present findings: "Found 3 notes mentioning tmux: tmux.md, terminal-setup.md, and tmux-plugins.md"

## Tips for Effective Searches

- **Choose the right tool**: This skill costs 4-5x tokens vs grep/glob. Use it only when semantic understanding is clearly needed
- **Be specific** about what you're looking for when invoking the subagent - provide context and intent
- **Trust the rankings** - The subagent's relevance assessments are based on actual content analysis, not just metadata
- **Don't re-read** - The subagent already samples content; only fully load notes the user specifically needs
- **Suggest alternatives** - If results are limited, propose related search terms or tag explorations
- **When uncertain** - Start with grep/glob. Only escalate to this skill if simple matching fails to find what's needed
