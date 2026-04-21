# Claude Code Skills

A curated collection of Claude Code skills — slash commands and operational playbooks.

## Quick Install (slash command skills)

```bash
git clone https://github.com/saintgo7/claude-skills.git
cd claude-skills
chmod +x install.sh && ./install.sh
```

Restart Claude Code after installing.

## Available Skills

| Skill | Type | Description |
|-------|------|-------------|
| [searcam-book](commands/searcam-book.md) | `/searcam-book` | SearCam technical book chapter writer — Korean & English parallel authoring |
| [exam-system](exam-system/) | playbook | Online exam operations — monitoring, incident response, student management, post-exam reporting |

## Slash Command Skills (`commands/`)

Markdown files installed to `~/.claude/commands/`. Each defines a `/skill-name` command.

```bash
./install.sh               # install all
./install.sh searcam-book  # install one
./uninstall.sh             # remove all
```

```
~/.claude/commands/
└── searcam-book.md
```

## Playbook Skills (`exam-system/`, ...)

Directory-based skills with scripts and templates. Copy to `~/.claude/skills/`.

```
~/.claude/skills/exam-system/
├── SKILL.md        ← trigger phrases & design notes
├── playbook.md     ← step-by-step operational guide
├── scripts/        ← ready-to-run operator scripts
└── templates/      ← reusable code templates
```

## Contributing

1. Slash commands: add `.md` to `commands/` with YAML frontmatter
2. Playbooks: add a directory under the repo root

## License

MIT
