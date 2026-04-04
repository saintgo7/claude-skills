# Claude Code Skills

A curated collection of Claude Code slash command skills.

## Quick Install

```bash
# Clone
git clone https://github.com/saintgo7/claude-skills.git
cd claude-skills

# Install all skills globally
chmod +x install.sh && ./install.sh

# Or install a specific skill
./install.sh searcam-book
```

Restart Claude Code after installing. Skills are available as `/skill-name`.

## Available Skills

| Skill | Command | Description |
|-------|---------|-------------|
| [searcam-book](commands/searcam-book.md) | `/searcam-book` | SearCam technical book chapter writer — Korean & English parallel authoring |

## How Skills Work

Skills are Markdown files stored in `~/.claude/commands/`. Each file defines a slash command that Claude Code can invoke. The installer copies files from `commands/` into your global Claude Code commands directory.

```
~/.claude/commands/
└── searcam-book.md   ← installed here
```

## Usage After Install

```
/searcam-book "Ch11 Wi-Fi scan chapter"
/searcam-book "Ch18 testing chapter — update with new test cases"
/searcam-book --list
```

## Update

```bash
git pull
./install.sh
```

## Uninstall

```bash
./uninstall.sh              # Remove all skills from this pack
./uninstall.sh searcam-book # Remove a specific skill
```

## Contributing

1. Add your skill `.md` file to `commands/`
2. Include YAML frontmatter with `description` and `model` fields
3. Open a PR

### Skill Template

```markdown
---
description: "One-line description of what this skill does"
model: sonnet
---

# Skill Name

[What this skill does and when to use it]

## Usage

$ARGUMENTS examples:
- "example input 1"
- "example input 2"
```

## License

MIT
