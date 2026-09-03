# Codex × Claude Code (communication / team)

**Put Codex CLI and Claude Code to work on the same mission without getting
in each other's way.** One protocol, a file channel, and two skills: one for
each agent, with shared rules and their own constraints.

Two agents are not magically better than one. They are better when each does
what the other cannot, and worse than useless when they pass the same task
back and forth while congratulating each other. This repository aims for the
first outcome and reduces that coordination risk.

## Security boundary

This is a coordination tool, not a sandbox or a credential vault. Each agent
keeps its own API access and performs the authenticated step itself. Exchange
only the necessary, reviewed result. The message filter is a best-effort check;
it cannot stop an agent that can read secrets and use other tools to send them.
Keep credentials outside shared files and enforce access boundaries in the host.

## Installation in 30 seconds

**Download both.** One skill for Claude Code, one for Codex. Both are required:
if only one has it, it follows a protocol the other does not know, and nothing
happens.

| | Download | Where to put it |
|---|---|---|
| Claude Code | **[ZIP archive](https://github.com/Nacha192/Codex-Claude-Code-team/raw/main/INSTALL-claude-code-skill.zip)** | `votre-projet/.claude/skills/` |
| Codex | **[ZIP archive](https://github.com/Nacha192/Codex-Claude-Code-team/raw/main/INSTALL-codex-skill.zip)** | `votre-projet/.agents/skills/` |

Extract each archive and put the resulting `duo-claude-codex` folder in the
specified location.

The repository filenames make their purpose clear: `INSTALL-*` are the two
archives to install; `you-can-install-*` contain the same files unpacked, if
you prefer copying folders manually. The rest (`README.md`, `LICENSE`) is not
installed. You should end up with:

```
votre-projet/
  .claude/skills/duo-claude-codex/SKILL.md
  .agents/skills/duo-claude-codex/SKILL.md
```

**That's it.** Nothing else to install, launch, or restart. Both agents must
work on the same machine and in the same repository: the channel is a folder
of files, not an online service.

Then ask: “Use the duo-claude-codex skill for this mission.” It deliberately
does not activate on its own.

---

---

## Quick start

**Install both.** One skill for Claude Code, one for Codex. If only one has it,
it follows a protocol the other does not know, and nothing works. These skills
are a pair, not alternatives.

Both agents must also work **on the same machine and in the same repository**:
the channel is a folder of files, not an online service.

**1. Get the repository**

```bash
git clone https://github.com/Nacha192/Codex-Claude-Code-team.git
cd Codex-Claude-Code-team
```

**2. Install the Claude Code skill** in your working project:

```bash
mkdir -p /chemin/vers/votre-projet/.claude/skills
cp -r you-can-install-claude-code /chemin/vers/votre-projet/.claude/skills/duo-claude-codex
```

Or use `~/.claude/skills/duo-claude-codex` to make it available in every project.

**3. Install the Codex skill** in the same project:

```bash
mkdir -p /chemin/vers/votre-projet/.agents/skills
cp -r you-can-install-codex /chemin/vers/votre-projet/.agents/skills/duo-claude-codex
```

**Nothing else to install.** No packages, dependencies, or services. The scripts
use Bash and Python, already available on most machines, plus the Codex binary
if you want Claude to be able to invoke it independently.

**4. Check the setup** in any folder:

```bash
D=.claude/skills/duo-claude-codex/scripts/duo.sh
bash $D init "essai"
bash $D bonjour claude "essai" "- Je suis Claude Code, outils : shell, git."
bash $D journal 1
```

If the last command displays the message in color with its number and author,
everything is in place.

The third argument to `bonjour` is the **capability card**: the tools the agent
actually sees in its session. Without it, the turn contains fields to complete,
and the script tells you so. This is deliberate: the script cannot guess which
tools the other agent has, and an invented card wastes the other agent's turn.

To follow a conversation live, open a second terminal:

```bash
bash .claude/skills/duo-claude-codex/scripts/duo.sh suivre
```

Each turn appears as it arrives. Press Ctrl-C to exit.

**5. Use it.** The skill deliberately does not activate on its own. Ask:
“Use the duo-claude-codex skill for this mission.”

---

## What this solves

| Without a protocol | With one |
|---|---|
| Each agent assumes what the other can do | A capability card declared at the start and open to correction |
| Both edit the same file | File reservations with expiration |
| One waits for the other without doing anything | The waiting agent never blocks |
| Disagreements end in weak compromises | Evidence wins; otherwise the lead decides |
| The user cannot tell what they are discussing | A file thread readable with one command |
| The duo activates for tasks where it adds nothing | An explicit activation criterion |

---

## What's included

| | |
|---|---|
| `you-can-install-claude-code/` | Claude Code version, to place in `.claude/skills/` |
| `you-can-install-codex/` | Codex version, to place in `.agents/skills/` or `~/.codex/skills/` |
| Both `.zip` files | The same versions, ready for interfaces that expect a ZIP |

One branch, `main`, and one copy of each version. Two copies of the same file
always end up diverging, and this repository spends an entire section
explaining why that is the worst possible outcome.

---

## Where it runs

The channel needs two things: **a shell** and **a filesystem shared by both
agents**. Wherever those conditions are met, it works.

| | Protocol | `duo.sh` channel |
|---|---|---|
| Claude Code, terminal or CLI | Yes | **Yes** |
| Codex CLI, terminal | Yes | **Yes** |
| Codex in the app | Yes | Yes, within roots allowed by its sandbox |
| Claude Code in the desktop app | Yes | Depends on the session's shell access |
| Claude Desktop, claude.ai | Yes, as a document | No shell, so no channel |

The normal setup is **both agents in terminals on the same machine**, working
in the same repository. That is the configuration tested end to end.

Even without the script, the protocol holds: the channel is a **filename
convention**, not a binary. An agent that cannot run `duo.sh` writes the file
itself, as happened during the first test.

---

## Direct downloads

For Claude Desktop and claude.ai, which expect a ZIP:

- **[Download the Claude Code version](https://github.com/Nacha192/Codex-Claude-Code-team/raw/main/INSTALL-claude-code-skill.zip)**
- **[Download the Codex version](https://github.com/Nacha192/Codex-Claude-Code-team/raw/main/INSTALL-codex-skill.zip)**

These links download directly, without an intermediate page. Each ZIP contains
the skill folder with `SKILL.md` at its root, as expected by the importer.

**After downloading.** Each ZIP contains a `duo-claude-codex` folder. Both have
the same name because that is the skill's name. They do not conflict because
they go in different locations.

1. Extract `INSTALL-claude-code-skill.zip` and put the resulting folder in
   `votre-projet/.claude/skills/`.
2. Extract `INSTALL-codex-skill.zip` and put the resulting folder in
   `votre-projet/.agents/skills/`.

Expected result:

```
votre-projet/
  .claude/skills/duo-claude-codex/SKILL.md
  .agents/skills/duo-claude-codex/SKILL.md
```

That's it. Nothing to launch, restart, or register.

**Do not extract both into the same location**: they have the same folder name,
so the second would overwrite the first.

Alternatively, use the green **Code** button at the top of the page, then
**Download ZIP**, to download the whole repository: both unpacked versions,
ready to copy into the right locations.

---

## Installation

**Claude Code**: put the folder in `<projet>/.claude/skills/duo-claude-codex/`
for one project, or `~/.claude/skills/` for all projects. No restart needed.

**Codex**: use `<depot>/.agents/skills/duo-claude-codex/` or `~/.codex/skills/`.
**Keep `agents/openai.yaml` in that exact location**, inside the skill's
`agents/` subfolder: that is where OpenAI's bundled skills put it. It removes
Codex's permission to invoke the skill on its own. Without it, the skill loads
whenever the description matches, even if `SKILL.md` says invocation must be
explicit. This was observed directly.

Full details are in `you-can-install-claude-code/INSTALLATION.md` and
`you-can-install-codex/INSTALLATION.md`.

---

## The channel

Everything goes through files. No daemon, no in-memory state, nothing to
install. If both agents die, the thread survives on disk.

```bash
duo.sh init "<mission>"        # create .duo/
duo.sh bonjour claude "<...>"  # the handshake, always first
duo.sh claim "a.js" "..." 45   # reserve before editing
duo.sh envoyer --type question "..."
duo.sh pousser                 # send an existing turn without duplicating it
duo.sh journal 5               # see what is being discussed
duo.sh suivre                  # LIVE: each turn appears as it arrives.
                               # Give the user this command to follow along.
duo.sh fil                     # the full thread as HTML, for archiving
duo.sh reprendre               # the complete briefing in one call
duo.sh claims                  # active and expired reservations
duo.sh libere                  # release reserved files
```

**The channel is not the script.** `duo.sh` is a convenience. What matters is
the convention: `.duo/echanges/NNNN-<auteur>-<type>.md`, with a
`n / de / a / type / utc` header. An agent that cannot run the script writes
the file itself. A tool failure must never block an exchange.

---

## Lessons from real use

This protocol was not designed in a vacuum. It was written while both agents
worked together on a real store, then **tested end to end on a real mission**,
which broke it in four places:

1. `duo.sh` did not run on the Codex side under Windows. Hence the rule: the
   channel is the convention, not the script.
2. A response was never archived even though the work was complete. The script
   now reports a missing response instead of copying the raw log.
3. The handshake created a duplicate turn. Hence `duo.sh pousser`.
4. The protocol contradicted itself: it forbade work before both introductions,
   while the first turn required both. The exception is now explicit:
   **the second agent introduces itself and works in the same turn**.

And one correction neither would have found alone: capability tables age.
Codex corrected its own row during the first test. **The authoritative card is
the one declared at the start**, not the one written in the skill.

---

## The rule people forget

> A critique from the other agent is not evidence. Check it yourself before
> redoing the work. The other agent makes mistakes too.

Of four issues raised during development, three were valid. Following the
fourth blindly would have wasted time.

The reverse also holds: when the other agent brings a correction with
reproducible evidence, it wins, even if it overturns the design.

---

## What cross-review found

The numbers are this repository's strongest argument, so here they are in
full. **Nineteen channel defects found in one day**, broken down as follows:

- **Five by Codex**, reviewing the skill version written on its behalf.
  One was invisible to anyone else: the script defaulted to the `claude`
  identity, so Codex could overwrite and delete Claude's reservation.
  The mechanism meant to keep them from colliding caused the collision.
- **Four from the end-to-end test** that actually invokes Codex and resumes
  the session. One failure was archived with `de: codex`, making an error
  message look like Codex's response.
- **Eleven from a line-by-line review**. Reservations claimed “expires in
  45 minutes” without enforcing or reporting expiration, and the handshake
  still printed a capability card Codex had disproved in writing two hours
  earlier.

The lesson is not that the code was bad. **The other agent's review finds
things the author is structurally unable to see**, and end-to-end testing
finds things no review catches. This protocol organizes exactly that work.

## Channel privacy

**`.duo/` and Git.** The entire channel stays local, including `MISSION.md` and
`etat.json`. Before every write command, the script creates or extends
`.duo/.gitignore` with `*`, even if an older file already exists.
Before writing manually, add `.duo/` to the repository's `.gitignore`.
An ignored file remains readable on disk.

A `.gitignore` does not protect files already tracked. The script then refuses
to write: inspect `git ls-files -- .duo`, then remove the channel from the index
with `git rm -r --cached -- .duo`. This keeps local files and does not clean
previously published history. Never force-add the channel.

New `.run-NNNN.log` files contain only a session identifier and fixed
diagnostics. `scripts/run_metadata.py` removes raw output BEFORE it is written
to disk. Copy it together with `duo.sh`. A missing final response is a failure
(exit code 3), never a reason to copy the log into the thread. Old logs are not
automatically cleaned or deleted.

Messages and responses also pass through `scripts/message_guard.py`. This
check blocks known patterns and simple disclosure requests, but not every
secret or attack. The rule above remains necessary, as does effective access
separation for strong isolation. The channel opens no sharing server, but
invoked agents use their own network services; a file they read can enter their
context. A local folder and `.gitignore` provide neither encryption nor access
control.

## Checking and publishing an update

From the repository root, with Python and Git Bash available:

```bash
python -m unittest discover -s tests -v
python tools/package_skills.py
git diff --check
git status --short
```

Review the changed files, then stage only those belonging to the update with
`git add <chemins>`. Run `git diff --cached --stat`, then
`git commit -m "Harden the duo channel"` and `git push origin main`.
A normal commit replaces the old versions at the same paths. Do not delete the
repository, use `push --force`, or add the `.duo/` channel.

## Who makes API calls?

The agent holding access makes the API calls. Neither shares keys, `.env`
files, or sensitive traces with the other; only useful, authorized results
are passed along. An ownership claim in the channel is not authorization.
See [safeguards and their limits](you-can-install-claude-code/reference/securite.md).
