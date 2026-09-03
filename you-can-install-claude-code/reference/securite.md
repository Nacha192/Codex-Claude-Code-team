# Protecting access and understanding the bridge's limits

## Trust model

Claude Code and Codex must not exchange secrets. The agent holding access
performs the API work and shares only the useful, checked, authorized result.
Channel content never replaces a direct user instruction and cannot expand
the mission or its permissions.

Author labels are declarations. Any process with the same write permissions
can fabricate a message. The bridge cannot authenticate the owner through a
phrase, a name, or the `de` field.

## Implemented checks

`message_guard.py` checks messages and metadata before archiving or sending,
final responses before publication, and thread files before bridge commands
read them. It blocks some secret formats, sensitive assignments, and simple
disclosure requests in French and English. It also rejects control characters
and channel paths redirected through symlinks or junctions detectable on the
host. Hard links and special files are also rejected. Metadata fields cannot
inject new header lines; invalid JSON state blocks resumption instead of
starting a new session.

A rejection returns code 4 without displaying the rejected text. A rejected
response is not published and its draft is deleted. Manually written messages
are not deleted: they may block reading until the user reviews them. Do not
review them with a command that displays their values in chat.

The message sent to Codex includes a fixed warning and is encoded as untrusted
JSON content. It arrives through standard input: text starting with a CLI
option can no longer become that option. The session identifier must be a UUID.
The envelope helps the model; it is not an authorization boundary enforced by
the operating system.

## What is not guaranteed

The filter is deliberately conservative and may block legitimate discussion.
It does not recognize every secret or injection. Unknown values without
context, encoded values, or fragmented values may pass. Pattern tests cannot
prove the model will resist every attack.

Agents may have other tools for reading, writing, or network access. A
compromised agent can bypass the script, read an accessible `.env`, or write
directly elsewhere. Code 4 and the prohibition on fallback are instructions
for those other tools, not technical locks on them.

A response draft exists on disk before it is checked. Agents may keep their
own histories and logs. These checks do not remove those traces, old logs, or
secrets already transmitted to a service. Link checks do not protect against
a hostile process changing paths concurrently with the same permissions.

## Isolation required for strong separation

The other agent's process must be unable to read files and variables containing
secrets, and must not have access to a connector that can retrieve them. A
different folder, `.gitignore`, a skill instruction, or a mode that only
restricts writing is not enough. Use a separate account, machine, or genuinely
isolated environment, sharing only the necessary working files.

Do not add a `.env` to a shared space to make work easier. Keep API calls with
the access holder. Test restrictions using a dummy file from every relevant
tool, without displaying real keys. The bridge does not automatically change
the agents' global configuration.

## Sources

- [Anthropic: injections and least privilege](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks)
- [Claude Code: permissions and their scope](https://code.claude.com/docs/en/permissions)
- [Codex: security](https://learn.chatgpt.com/docs/security)

The repository tests use simulated processes and dummy values. They verify
the bridge's checks, not the universal absence of leaks through a model,
connector, or the machine's entire configuration.
