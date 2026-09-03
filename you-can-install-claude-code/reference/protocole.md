# The full protocol

The templates below are not forms to fill in. They are the blocks you wish
you had included when an exchange goes wrong.

---

## Template 1: the opening message

This is the only message that may be long. Keep later messages brief.

```
MISSION: <one sentence>

WHAT I AM DOING WHILE YOU READ, so you do not work without direction:
- <what I am starting immediately>
- <what I will NOT touch because it is yours>

WHAT I HAVE ALREADY CHECKED; correct me if I am wrong:
- <fact 1, with the file path>
- <fact 2>

WHAT I AM ASKING YOU:
1. <a question>
2. <another question>

THE DECIDING CRITERION: <the rule that settles it, e.g. "between better-looking
and more readable as a thumbnail, choose readable">
```

Two often-skipped blocks that must stay:

- **“Correct me if I am wrong”** turns a monologue into a check. The other agent
  checks your facts instead of believing you; this has already prevented errors.
- **The deciding criterion** prevents an off-topic answer. Without it, the other
  agent answers whichever question it finds interesting.

---

## Template 2: asking for a critique

A weak critique is useless. Make it rigorous through instructions, not hope.

```
Here are <n> deliverables: <exact paths>

What I changed since last time:
- <change 1>

What I need from you, and I want you to actually open the files:
1. <the relevant test, e.g. "look at them as thumbnails first, as in a feed">
2. The MOST COSTLY flaw in each, ONE per deliverable, not three.
3. Your ranking and the criterion behind it.

Be demanding. I would rather redo this now than pay to learn the lesson later.
```

Two observed pitfalls:

- **“One flaw per deliverable, not three”** avoids a list of twenty minor
  observations that buries the important issue.
- **Naming the test** (“as a thumbnail”, “on mobile”, “at a glance”) separates
  useful critique from idle commentary.

When the answer arrives, **check before redoing the work**. A critique is not
evidence. Of the four critiques received while developing this skill, three
were valid and one relied on an impossible requirement.

---

## Template 3: disagreement

```
DISAGREEMENT: <subject in five words>

Your position: <stated honestly, without caricature>
My position: <my position>

What could settle this: <the test, file, or measurement>

My proposal: <run the test> / <you are the lead; decide>
```

Writing the other agent's position yourself, honestly, resolves half of all
disagreements on the spot: you realize it was right, or that the two positions
were addressing different things.

---

## Template 4: closing

```
MISSION COMPLETE.

What worked: <...>
What was costly: <...>
What you contributed that I would not have found alone: <...>
What I should have done alone: <...>
```

The last point is the most useful and the least pleasant to write. It prevents
reflexively teaming up next time.

---

## Turns

**One turn = one message = one file.** No meandering conversation: every turn
must make sense on its own six months later.

**At most three round trips on the same topic.** By the fourth, you are not
understanding each other, and another turn will not fix that. The lead decides,
writes down why, and everyone moves on.

**Do not relaunch just to ask for progress.** Either use a completion
notification or watch the disk with `attendre.ps1`. Relaunching costs a turn
and speeds up nothing.

---

## When the other agent does not respond

It happens: quota exhausted, dead session, timeout. It need not block the work.

1. `duo.sh` exits with code 3; the sent message stays archived in `echanges/`.
2. **Continue alone on anything that can be done alone**, and clearly tell the
   user what remains pending.
3. Never invent the missing response or report it as received.
4. When the other agent returns, Claude can relaunch Codex with `duo.sh pousser`.
   Codex replies with `duo.sh ecrire --de codex --a claude`.

During development of this skill, Codex hit its quota mid-mission. Work
continued without it for an hour, and it resumed at the same point. That is
exactly the intended behavior.
