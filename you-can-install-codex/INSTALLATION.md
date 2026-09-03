<!-- YES THIS WAS CODED BY CODEX AND CLAUDE CODE LMAO -->

# Installing the skill

Two versions, two locations. The protocol is the same; the scripts and
wording differ.

---

## Claude Code in the terminal

A skill is a **folder** containing a `SKILL.md` with `name` and `description`
header fields. There are two possible locations:

| Where | Scope |
|---|---|
| `<projet>/.claude/skills/duo-claude-codex/` | This project only |
| `~/.claude/skills/duo-claude-codex/` | Every project on the machine |

Nothing to restart or register. The skill appears in the available skills list
in the next session and loads when a task matches its `description` or when
invoked by name.

To check that it is visible, ask for the skills list or type
`/duo-claude-codex`.

---

## Claude Desktop and claude.ai

The interface accepts a **ZIP of the folder** in Settings, under
Capabilities / Skills. The ZIP must contain the folder with `SKILL.md` at its
root: `duo-claude-codex/SKILL.md`, not just `SKILL.md`.

Use `INSTALL-claude-code-skill.zip` for this.

**A candid caveat:** this skill invokes shell scripts and the Codex binary.
Claude Desktop may have neither a shell nor Codex installed, so **the protocol
can be read, but the channel cannot run**. The skill works fully in the
terminal. Elsewhere, it serves as a document.

---

## Codex

Same principle, different paths:

| Where | Scope |
|---|---|
| `<depot>/.agents/skills/duo-claude-codex/` | The repository, and therefore the team |
| `~/.codex/skills/duo-claude-codex/` | The machine |

Use `INSTALL-codex-skill.zip`.

**Do not put the protocol in `AGENTS.md`.** `AGENTS.md` loads for **every**
task, including those where the duo makes no sense; its content would cost
tokens every time. One line is enough:

```markdown
To work with Claude Code, load the duo-claude-codex skill.
```

**`openai.yaml` belongs in `<skill>/agents/openai.yaml`.** Putting it at the
skill root was a mistake Codex caught during review. OpenAI's bundled skills
confirm the correct location: they all put it there.

```
.agents/skills/duo-claude-codex/
  SKILL.md
  agents/openai.yaml      <- here
```

Contents:

```yaml
interface:
  display_name: "Duo Claude Code x Codex"
  short_description: "Collaboration protocol for Codex and Claude Code."
policy:
  allow_implicit_invocation: false
```

`allow_implicit_invocation: false` **removes Codex's permission to invoke this
skill on its own**. The distinction matters: this removes permission, rather
than switching off an otherwise inevitable load. Without it, Codex invokes
the skill whenever the description matches, even if `SKILL.md` explicitly says
it requires invocation. This happened with a simple message mentioning the duo.
A skill that activates for tasks where it adds nothing eventually gets disabled.

**Note:** a Codex run in a `workspace-write` sandbox may be unable to write
to `~/.codex`. Copy to the machine-wide location manually.

---

## Machine requirements for the channel

- **Bash.** Git Bash is enough on Windows.
- **Python**, for `etat.json`. It is already installed if `python` or
  `python3` responds.
- **The Codex binary.** Often on PATH (npm installs a shim), but not always.
  `duo.sh` tries `CODEX_BIN`, then `command -v codex`, then
  `~/.codex/config.toml`, then the installation folder. If that fails, set
  `CODEX_BIN=/chemin/vers/codex.exe`.
- **PowerShell** for `attendre.ps1`, only for external orchestration.

A thirty-second check in an empty folder:

```bash
bash duo.sh init "essai"
bash duo.sh ecrire --type question "ca marche ?"
bash duo.sh journal 1
bash duo.sh etat
```

If `journal` displays the message with its numbered header, everything is in
place. `envoyer` is the only command that needs Codex.

---

## Updating

Both versions are on the `main` branch. Copy each folder to its respective
location, including every file in `scripts/`. Do not extract both ZIPs into
the same folder.

After updating, run `duo.sh init "<mission>"` in each project you use: it extends
Git protection for the existing channel without deleting exchanges. If channel
files are already tracked, review them and remove them from the index as the
script's message explains. Old logs remain on disk; new runs no longer retain
raw output.

## Separating access

Never copy the access holder's `.env` to the other agent. The holder performs
API calls itself. See `reference/securite.md` for the filter's limits and the
required permissions. Install all scripts together, including `message_guard.py`.
