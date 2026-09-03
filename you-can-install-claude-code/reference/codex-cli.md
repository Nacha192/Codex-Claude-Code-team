# The Codex CLI: verified findings

Verified on this machine, Windows 11, `codex-cli 0.152.0`. Unverified points
are marked as such. A reference note is not a source: if a point informs your
decision, verify it again.

---

## Where the binary is

**It can be on PATH.** An npm installation puts a `codex` shim there.
Verified on 2026-09-02 on this machine: `command -v codex` resolved to
`.../scoop/apps/nodejs/current/bin/codex`. This note said the opposite.
That was wrong, and Codex caught it.

Search order, from most to least reliable:

1. The `CODEX_BIN` variable, if set.
2. `command -v codex`.
3. The `CODEX_CLI_PATH` key in `~/.codex/config.toml`.
4. `~/AppData/Local/OpenAI/Codex/bin/<hash>/codex.exe`.

The hash changes with each update, and **multiple versions coexist**, so the
glob can select an older one. That is why it comes last.
**Never hardcode a path.** `duo.sh` performs this search.

---

## Useful commands

```bash
codex exec -C <dossier> -s <sandbox> -o <fichier> "<prompt>"
codex exec resume --last -o <fichier> "<prompt>"
```

- `-C` sets the working directory.
- `-s workspace-write` permits writing in the working directory.
- `-o` writes the response to a file. **Use it every time**: standard output
  is noisy; the file is not.

**Confirmed pitfall, with a correction.** `codex exec resume --help` declares
neither `-C` nor `-s`; passing them fails. Use `cd` first. However,
**exactly what `resume` inherits from the original sandbox is not documented
anywhere**: the previous version of this note asserted it without evidence.
If sandbox behavior matters for your work, verify it rather than assuming.

---

## Where its instructions live

Three distinct layers, confirmed by Codex itself with documentation links.

**`AGENTS.md`: always loaded.** The chain is built once when the run starts:
`~/.codex/AGENTS.override.md`, or otherwise `~/.codex/AGENTS.md`, then one file
per directory from the Git root to the current directory. Files are
**concatenated**; those closer to the current directory take precedence on
conflicts. An `AGENTS.override.md` replaces `AGENTS.md` at the same level.
Default combined limit: 32 KiB.

**Skills: loaded on demand, just like Claude's.** Name and description are
visible initially; the full `SKILL.md` loads only when the task matches or
the skill is invoked. Locations:

- Repository: `.agents/skills/<nom>/SKILL.md`.
- User: `~/.codex/skills/<nom>/SKILL.md`.

**`openai.yaml` belongs in `<skill>/agents/openai.yaml`, not the skill root.**
Verified against OpenAI's bundled skills, which all put it there. Format:

```yaml
interface:
  display_name: "Readable name"
  short_description: "One sentence."
policy:
  allow_implicit_invocation: false
```

`allow_implicit_invocation: false` **forbids Codex from invoking the skill on
its own initiative**. This removes permission; it is not a switch preventing
an otherwise inevitable load.

**The most costly design mistake to avoid** is believing Codex only has
permanent instructions. It has the same progressive disclosure as we do.
The full protocol belongs in a skill, **not** `AGENTS.md`, or it would load
for every task.

**`config.toml`: behavior and capabilities.** Model, sandbox, approvals,
MCP, notifications. This is not the place for a business protocol.

**Custom prompts.** They appear as `/prompts:<nom>`. These are explicitly run
commands, not injected instructions. On this machine, `~/.codex/prompts/`
**does not exist**: a `ls` with no output means absent, not empty.

---

## Waking it externally

```bash
codex exec "message"                       # new run
codex exec resume --last "message"         # resume the latest conversation
codex exec resume <SESSION_ID> "message"   # deterministic resumption
```

**`--last` is fragile** when multiple runs progress in parallel. The protocol
stores an explicit session ID. It is printed in the run header on the
`session id:` line, and `duo.sh` extracts it from the output.

**`notify` is OUTGOING.** Codex calls a command with a JSON payload when an
event occurs. It is not an incoming mailbox.

**There is no clean way to inject a message into a running `codex exec`.**
Each exchange is a new process invocation that can resume the same session.
A continuously live agent would require the Codex App Server or SDK, a
heavier architecture.

**Be precise about that statement's scope.** It is a CLI orchestration rule,
**not an inability of Codex**. Codex itself notes the distinction: depending
on the session, it can keep processes alive, wait for their output, and use
deferred tools. The actual rule is that a non-interactive `codex exec` should
not watch the channel indefinitely.

Protocol consequence: **do not ask a `codex exec` to wait.** It finishes,
publishes, returns control, and the orchestrator relaunches it.

---

## Its tools

**This list is indicative and dated, not authoritative.** Exposed tools depend
on the host, installed plugins, and session policy. On 2026-09-02, Codex itself
found that a tool this note took for granted (`node_repl`) was not exposed
in its session.

**The only authoritative card is the one the run declares during the
handshake.** Ask for it; do not infer it from this note.

Observed at least once:

- `image_gen`: image generation. **This is the capability that usually
  justifies the duo.** Images land in `~/.codex/generated_images/`.
- Chrome and internal browser control, `computer-use`.
- Connectors, subagents, and background tasks, **depending on the session**.
  Do not claim it has none.

---

## What it does better, honestly

Observed during an ad-creative redesign for a demo project, not assumed:

- **It generates usable images and understands why they work.** Asked what it
  added to break the AI look, it said adding clutter was not enough: the two
  sides of a room should show different patterns of use. That was better than
  the instruction it received.
- **It critiques rigorously and is often right.** Three of four issues it
  raised were fixed because it was right.
- **It lacks the business context**, which helps critique: it sees what we
  no longer notice.

## What it does less well

- It lacks the project's history. Reject a critique asking to redo something
  already settled with the user rather than following it.
- It cannot check unwritten business constraints. If a constraint matters,
  put it in the message or a file it can read.

---

## Its limits

Three observed here, four described by Codex.

- **Quota.** "You ve hit your usage limit... try again at HH:MM". Observed
  twice. Temporary failure: continue alone, resume later, do not loop.
- **Empty output.** Dead session; the `-o` file is zero bytes. `duo.sh`
  treats this as a failure.
- **Very long messages.** It loses the middle. Beyond one page, write to a
  repository file and give its path.
- **Session timeout:** there is no universal duration to encode. Limits come
  from the host, tools, and calling process.
- **Context:** depends on the model; long conversations compact automatically.
  **Do not put a fixed size in the protocol.**
- **Quota:** depends on account and model, available through `/status`, and
  not stable. Observed twice while developing this skill.
- **Sandbox and approvals:** imposed by the session, not a general rule.
  Printed in the run header (`approval:`, `sandbox:`). Observed here:
  `workspace-write [workdir, /tmp, $TMPDIR]`, approval `never`.
- **Writing outside allowed roots:** impossible. **Permission written in a
  prompt does not make a read-only mount writable.** During this review,
  Codex was instructed to edit `.agents/skills/` and was denied access.
  If the other agent must write somewhere, verify the root permits it;
  do not take its word for it.

---

## Review status

**Reviewed by Codex on 2026-09-02**, using `codex-cli 0.152.0`. It found twelve
false or overly absolute claims in this note. All were corrected above after
checking what could be verified here: PATH, `resume --help` output, the run
header, and the location of `openai.yaml` in OpenAI's bundled skills.

**The CLAIM question is settled:** the only reservation is
`.duo/claims/<agent>.md`. A message's `fichiers:` field is a descriptive record
of touched files; **it reserves nothing**. Codex's sound reasoning: a
reservation is current state that can be inspected, replaced, expired, and
released; the journal is immutable. Two sources always diverge.

**Still open:** nothing blocking. Remember that this note ages. A capability
listed here is a hypothesis; one declared during the handshake is a fact.
