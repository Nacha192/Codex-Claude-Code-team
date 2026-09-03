#!/usr/bin/env bash
# duo.sh - the channel between Claude Code and Codex.
#
# Everything goes through files. No daemon, no in-memory state, nothing to
# install. If both agents die, the thread survives on disk, and anyone
# can open it and read what they were discussing.
#
#   duo.sh init "<mission>"          create .duo/ (mission, state, exchanges, claims)
#   duo.sh bonjour <qui> "<mission>" [carte]
#                                    the handshake. The card lists the session's
#                                    ACTUAL tools: inspect them rather than
#                                    copying a list.
#                                    Always first, on both sides.
#   duo.sh envoyer [options] "<msg>" write a turn and invoke Codex
#   duo.sh ecrire  [options] "<msg>" write a turn WITHOUT invoking Codex
#   duo.sh claim "<fichiers>" "<but>" [minutes]   reserve files
#   duo.sh claims                    reserved files, owners, and expiration times
#   duo.sh libere                    release previously reserved files
#   duo.sh reprendre                 the full briefing: mission, claims,
#                                    last 3 turns. Run this first when
#                                    resuming an ongoing mission.
#   duo.sh pousser                   send the last ALREADY written turn
#                                    without duplicating it
#   duo.sh journal [n]               the last n turns in the terminal
#   duo.sh suivre                    the LIVE thread in the terminal; each
#                                    turn appears as it arrives. Ctrl-C
#                                    to exit. Offer this to the user.
#   duo.sh fil                       the full thread as HTML, for archiving
#   duo.sh etat                      mission, lead, Codex session, last turn
#
#   envoyer/ecrire options:
#     --type <proposition|question|decision|preuve|resultat|blocage>
#     --de <claude|codex>   --a <claude|codex>
#     --fichiers "a.js b.md"   --reply <n>   --attendu "<ce qu on attend>"
#
# Variables: DUO_QUI=claude|codex (required for claim and libere),
#             DUO_RACINE, CODEX_BIN, NO_COLOR.
#
# Exit codes: 0 ok, 1 usage, 2 Codex not found, 3 Codex failed.
# Code 4: security check rejected; do not bypass.
# Code 3 matters: the caller must be able to continue without Codex.
#
# Two design choices, both prompted by real mistakes:
#   - the NUMBER is authoritative, not the timestamp. Two writes can occur
#     in the same second, and two clocks never agree perfectly.
#   - write to a temporary file, then rename it. Readers never see
#     a half-written message.

set -uo pipefail
umask 077

RACINE="${DUO_RACINE:-$PWD}"
RACINE=$(cd -- "$RACINE" && pwd) || exit 1
DUO="$RACINE/.duo"
ECHANGES="$DUO/echanges"
CLAIMS="$DUO/claims"
NUMEROS="$DUO/.numeros"
MISSION="$DUO/MISSION.md"
ETAT="$DUO/etat.json"

PY=$(command -v python || command -v python3 || echo python)
SCRIPTS=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# All transmitted fields are checked before writing and sending.
verifier_texte() {
  printf '%s\0' "$@" | "$PY" "$SCRIPTS/message_guard.py" check
}

# Codex MAY be on PATH (npm installs a codex shim there), but this is not
# guaranteed. The installation folder contains a hash that changes with
# each update, and multiple versions may coexist: never hardcode the path,
# and keep the glob as a LAST resort.
# Verified by Codex on 2026-09-02: `command -v codex` resolved successfully.
trouver_codex() {
  if [ -n "${CODEX_BIN:-}" ]; then
    [ -x "$CODEX_BIN" ] || return 1
    echo "$CODEX_BIN"; return 0
  fi
  if command -v codex >/dev/null 2>&1; then command -v codex; return 0; fi
  local c
  c=$(grep -o "CODEX_CLI_PATH = '[^']*'" "$HOME/.codex/config.toml" 2>/dev/null \
      | head -1 | sed "s/.*= '//; s/'$//")
  if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return 0; fi
  c=$(ls -d "$HOME/AppData/Local/OpenAI/Codex/bin"/*/codex.exe 2>/dev/null | head -1)
  if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return 0; fi
  return 1
}

utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Protection applies before every write command, even without init.
# The final * also overrides old MISSION/etat exceptions.
proteger_canal() {
  mkdir -p "$DUO" || return 1
  "$PY" - "$DUO/.gitignore" <<'PYEOF'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8") if p.exists() else ""
if not t.rstrip().endswith("# duo: canal local prive\n*"):
    with p.open("a", encoding="utf-8", newline="\n") as f:
        f.write("\n# duo: canal local prive\n*\n")
PYEOF
  [ $? -eq 0 ] || return 1
  # Ignoring a file does NOT remove already tracked files from the index.
  if git -C "$RACINE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local suivis
    suivis=$(git -C "$RACINE" ls-files -- .duo) || return 1
    if [ -n "$suivis" ]; then
      echo "duo: .duo contains files already tracked by git." >&2
      echo "Review, then remove .duo from the index with git rm -r --cached -- .duo." >&2
      echo "Local files remain on disk; git history still needs review." >&2
      return 1
    fi
  fi
}

# --- etat.json: read and written by Python, never sed. --------------------
etat_lire() {
  [ -f "$ETAT" ] || { echo ""; return 0; }
  "$PY" -c "import json,sys
try: print(json.load(open(sys.argv[1],encoding='utf-8')).get(sys.argv[2],''))
except Exception: sys.exit(1)" "$ETAT" "$1" 2>/dev/null
}

# Read, modify, write: concurrent calls used to lose a key, and os.replace
# raised PermissionError on Windows while the other call still held the file.
# Use a mkdir lock, plus retries on failure.
etat_ecrire() {
  "$PY" - "$ETAT" "$1" "$2" <<'PYEOF'
import json,sys,os,tempfile,time,errno
p,k,v = sys.argv[1],sys.argv[2],sys.argv[3]
verrou = p + ".verrou"
pris = False
for _ in range(100):                       # at most 5 s
    try:
        os.mkdir(verrou); pris = True; break
    except OSError as e:
        if e.errno != errno.EEXIST: break
        time.sleep(0.05)
if not pris:
    sys.exit("duo: etat.json lock unavailable; no changes made")
try:
    d = {}
    if os.path.exists(p):
        try: d = json.load(open(p, encoding="utf-8"))
        except Exception: sys.exit("duo: etat.json unreadable; no changes made")
    if k == "__init__":
        defaults = {'mission': v, 'pilote': '', 'session_codex': '',
                    'dernier_tour': '0000', 'statut': 'ouverte'}
        for name, value in defaults.items():
            d.setdefault(name, value)
    else:
        if k == "dernier_tour":
            v = f"{max(int(d.get(k, 0)), int(v)):04d}"
        d[k] = v
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    for essai in range(20):                # Windows keeps the file open
        try:
            os.replace(tmp, p); break
        except PermissionError:
            time.sleep(0.05)
    else:
        os.unlink(tmp)
        sys.exit("duo: etat.json busy; key not written")
finally:
    if pris:
        try: os.rmdir(verrou)
        except OSError: pass
PYEOF
}

# Derive the next number from existing files: no counter to desynchronize,
# and manually deleting a file breaks nothing.
# The number is shared: concurrent writers calculated the same one,
# making one message disappear. Measured: 8 losses in 10 simultaneous sends.
# Reserve the number with mkdir, which is atomic everywhere, including Windows.
prochain_numero() {
  local n
  n=$( { ls -1 "$ECHANGES" 2>/dev/null | sed -n 's/^\([0-9]\{4,\}\)-.*/\1/p'
         ls -1 "$NUMEROS"  2>/dev/null ; } | sort -n | tail -1 )
  printf '%04d' $(( 10#${n:-0} + 1 ))
}

reserver_numero() {
  local n t=0
  mkdir -p "$NUMEROS" || return 1
  while :; do
    n=$(prochain_numero)
    if mkdir "$NUMEROS/$n" 2>/dev/null; then printf '%s' "$n"; return 0; fi
    t=$((t+1))
    [ "$t" -gt 200 ] && { echo "duo: unable to reserve a number" >&2; return 1; }
  done
}

cmd_init() {
  verifier_texte "${1:-}" || return 4
  mkdir -p "$ECHANGES" "$CLAIMS" || return 1
  local intitule="${1:-}"
  if [ ! -f "$MISSION" ]; then
    cat > "$MISSION" <<EOF
# Mission

## What we are doing
${intitule:-(one sentence, not a paragraph)}

## Success criterion
(verifiable by someone else. If you cannot write it down,
 the mission is not ready and the duo will go in circles.)

## Who leads, and why for THIS task
(business context, history, connectors -> claude
 images, browser, visual inspection -> codex
 pure code -> whoever already has the context)

## Division of work
| Who | Does | Must not touch |
|-----|------|-----------------|
| claude | | |
| codex  | | |

## Desaccords
(Disagreements: never erase one. Record both positions, who decided,
 and the evidence behind the decision.)
EOF
    echo "created: $MISSION"
  fi
  etat_ecrire __init__ "${intitule:-sans titre}" || return 1
  echo "channel ready in $DUO"
}

# --- write a turn --------------------------------------------------------
TYPE="proposition"; DE="${DUO_QUI:-claude}"; A="codex"; FICHIERS=""; REPLY=""; ATTENDU=""; SANS_TOUR=0
[ "$DE" = "codex" ] && A="claude"
# An option without a value used to crash with "unbound variable" because
# of set -u, producing a message nobody could interpret.
besoin_valeur() {
  [ $# -ge 2 ] || { echo "duo: option $1 requires a value." >&2; return 1; }
}

lire_options() {
  local destinataire_explicite=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --type|--de|--a|--fichiers|--reply|--attendu)
        besoin_valeur "$@" || return 1 ;;
    esac
    case "$1" in
      --type)     TYPE="$2"; shift 2 ;;
      --de)       DE="$2";   shift 2 ;;
      --a)        A="$2"; destinataire_explicite=1; shift 2 ;;
      --fichiers) FICHIERS="$2"; shift 2 ;;
      --reply)    REPLY="$2"; shift 2 ;;
      --attendu)  ATTENDU="$2"; shift 2 ;;
      --) shift; break ;;
      --sans-tour) SANS_TOUR=1; shift ;;
      *) break ;;
    esac
  done
  if [ "$destinataire_explicite" = 0 ]; then
    [ "$DE" = codex ] && A=claude || A=codex
  fi
  case "$DE:$A" in claude:codex|codex:claude) ;; *) echo "duo: invalid authors" >&2; return 1 ;; esac
  [[ "$TYPE" =~ ^[a-z][a-z0-9_-]*$ ]] || { echo "duo: invalid type" >&2; return 1; }
  local champ
  for champ in "$FICHIERS" "$REPLY" "$ATTENDU"; do
    [[ "$champ" != *$'\n'* && "$champ" != *$'\r'* ]] || {
      echo "duo: metadata must fit on one line." >&2; return 1; }
  done
  [[ -z "$REPLY" || "$REPLY" =~ ^[0-9]+$ ]] || { echo "duo: invalid reply" >&2; return 1; }
  RESTE="$*"
}

ecrire_tour() {
  local corps="$1" n f tmp
  verifier_texte "$corps" "$FICHIERS" "$REPLY" "$ATTENDU" || return 4
  mkdir -p "$ECHANGES" || return 1
  n=$(reserver_numero) || return 1
  f="$ECHANGES/$n-$DE-$TYPE.md"
  # UNIQUE temporary filename: concurrent writes used to share one and
  # destroy each other.
  tmp="$f.$$-${RANDOM:-0}.partiel"
  {
    echo "---"
    echo "n: $n"
    echo "de: $DE"
    echo "a: $A"
    echo "type: $TYPE"
    echo "utc: $(utc)"
    [ -n "$REPLY" ]    && echo "reply_to: $REPLY"
    [ -n "$FICHIERS" ] && echo "fichiers: $FICHIERS"
    [ -n "$ATTENDU" ]  && echo "attendu: $ATTENDU"
    echo "---"
    echo
    printf '%s\n' "$corps"
  } > "$tmp"
  # Atomic rename prevents partial reads. Verified: a failed mv used to
  # go unnoticed, and we announced a message that did not exist.
  mv -f "$tmp" "$f" || { echo "duo: unable to write $f" >&2; rm -f "$tmp"; return 1; }
  etat_ecrire dernier_tour "$n" || return 1
  echo "$f"
}

cmd_ecrire() {
  lire_options "$@" || return 1
  [ -z "$RESTE" ] && { echo "usage: duo.sh ecrire [options] \"message\"" >&2; return 1; }
  ecrire_tour "$RESTE"
}

cmd_envoyer() {
  lire_options "$@" || return 1
  [ -z "$RESTE" ] && { echo "usage: duo.sh envoyer [options] \"message\"" >&2; return 1; }

  [ "$DE:$A" = "claude:codex" ] || {
    echo "duo: envoyer only invokes Codex from Claude; use ecrire to reply." >&2; return 1; }
  verifier_texte "$RESTE" "$FICHIERS" "$REPLY" "$ATTENDU" || return 4
  local sid; sid=$(etat_lire session_codex) || return 4
  if [ -n "$sid" ] && [[ ! "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "duo: invalid session identifier; send rejected." >&2; return 4
  fi
  local prompt
  prompt=$(printf '%s' "$RESTE" | "$PY" "$SCRIPTS/message_guard.py" envelope) || return 4
  local codex; codex=$(trouver_codex) || {
    echo "codex not found. Set CODEX_BIN=/chemin/vers/codex.exe" >&2; return 2; }

  local envoye="(turn already written)"
  if [ "$SANS_TOUR" = "0" ]; then
    envoye=$(ecrire_tour "$RESTE") || {
      echo "duo: unable to write the turn; Codex will not be invoked." >&2; return 1; }
  fi
  TYPE="reponse"; DE="codex"; A="claude"; FICHIERS=""; ATTENDU=""
  # RESERVE the response number too, or the race returns through the
  # other path and the fix is only half complete.
  local n; n=$(reserver_numero) || return 1
  local sortie="$ECHANGES/$n-codex-reponse.md"
  local brouillon="$DUO/.reponse-$n.partiel"

  # `codex exec resume --help` declares neither -C nor -s: passing them fails.
  # Use cd first. Exactly what resume inherits from the original sandbox
  # is NOT documented: do not rely on it; verify when needed.
  # --last becomes ambiguous with two runs, hence the explicit session ID.
  # One log PER SEND: concurrent envoyer calls used to share a file,
  # so one read the other's error or session ID.
  local log="$DUO/.run-$n.log"
  local codes
  if [ -n "$sid" ]; then
    ( cd "$RACINE" && "$codex" exec resume "$sid" -o "$brouillon" - <<< "$prompt" ) 2>&1 |
      "$PY" "$SCRIPTS/run_metadata.py" >"$log"
    codes=("${PIPESTATUS[@]}")
  else
    "$codex" exec -C "$RACINE" -s workspace-write -o "$brouillon" - <<< "$prompt" 2>&1 |
      "$PY" "$SCRIPTS/run_metadata.py" >"$log"
    codes=("${PIPESTATUS[@]}")
  fi
  local code=${codes[0]}
  [ "${codes[1]}" -eq 0 ] || code=3

  # Codex prints "session id: <uuid>" in the run header. Match the LABEL,
  # never "the first UUID in the log": a UUID may appear in the response,
  # and the output format is not a contract.
  # Dependency tested on codex-cli 0.152.0. Report a missing anchor.
  # Only check after a successful run: otherwise a missing-session-ID
  # warning used to obscure the actual failure reported further below.
  if [ -z "$sid" ] && [ $code -eq 0 ]; then
    local trouve
    trouve=$(grep -o 'session id:.*' "$log" | head -1 \
             | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    if [ -n "$trouve" ]; then
      etat_ecrire session_codex "$trouve"
    else
      echo "duo: session id not found in the log; the next send will open a new session" >&2
    fi
  fi

  if [ $code -eq 0 ] && [ -s "$brouillon" ]; then
    if ! "$PY" "$SCRIPTS/message_guard.py" file "$brouillon"; then
      rm -f "$brouillon"
      echo "duo: response rejected before publication in the thread." >&2
      return 4
    fi
  fi

  # Only the final response becomes a turn, never tool output.
  # -o writes outside the thread; publish atomically after the process ends.
  if [ $code -eq 0 ] && [ -s "$brouillon" ]; then
    { echo "---"; echo "n: $n"; echo "de: codex"; echo "a: claude";
      echo "type: reponse"; echo "utc: $(utc)"; echo "---"; echo
      cat "$brouillon"; } > "$sortie.partiel" && mv -f "$sortie.partiel" "$sortie" || code=3
  fi
  rm -f "$brouillon" "$sortie.partiel"

  # Search for a failure cause ONLY when the run failed. The previous
  # version always searched the log. While exploring duo.sh, Codex copied
  # a source line containing the error phrase into its output.
  # The script then inferred failure and deleted a valid response,
  # leaving no understandable explanation.
  # Patterns are anchored at the start of a line for the same reason.
  if [ $code -ne 0 ] || [ ! -s "$sortie" ]; then
    rm -f "$sortie"     # -o sometimes creates an empty file: no silent turns
    if grep -qE '^Not inside a trusted directory' "$log" 2>/dev/null; then
      echo "codex rejected this directory: it is not a trusted git repository." >&2
      echo "  Open the mission in a git repository (git init is enough), or run" >&2
      echo "  codex manually once in this directory to approve it." >&2
    elif grep -qE "You.?ve hit your usage limit|^Error: usage limit" "$log" 2>/dev/null; then
      echo "codex has reached its quota. Resume later; the message is archived." >&2
    else
      echo "codex did not respond (code $code). Log: $log" >&2
    fi
    echo "The message remains archived in $envoye. The channel is asynchronous:" >&2
    echo "continue alone on independent work; do not retry in a loop." >&2
    return 3
  fi

  etat_ecrire dernier_tour "$n" || return 1
  echo "$sortie"
}

# --- bonjour: the opening handshake --------------------------------------
# This is not politeness. Without it, each agent assumes the other's tools;
# a false assumption has already cost half a day. The greeting carries
# an identity card: who I am, what I have, what I lack, and what I start now.
cmd_bonjour() {
  local qui="${1:-claude}" mission="${2:-}"
  case "$qui" in claude|codex) ;; *) echo "duo: invalid author" >&2; return 1 ;; esac
  mkdir -p "$ECHANGES" "$CLAIMS" || return 1
  # The card is NO LONGER hardcoded. It used to advertise a persistent REPL
  # Codex lacked, while denying connectors and background tasks it had.
  # Codex demonstrated both errors. A script cannot know which tools
  # the other session exposes: the agent must inspect and declare them.
  # The third argument carries that card.
  local carte="${3:-}"
  if [ -z "$carte" ]; then
    carte="- **I am $([ "$qui" = codex ] && echo 'Codex CLI' || echo 'Claude Code')**, in \`$(basename "$RACINE")\`.
- **The tools I ACTUALLY see in this session:** (fill in by inspecting
  my tools, never by copying a table)
- **What I do not see here:** (fill in)
- **My orchestration constraint:** (fill in)"
    echo "duo: no capability card supplied. Complete the template in the turn." >&2
    echo "     Usage: duo.sh bonjour $qui \"<mission>\" \"<ta carte>\"" >&2
  fi
  DE="$qui"; [ "$qui" = "codex" ] && A="claude" || A="codex"
  TYPE="bonjour"; FICHIERS=""; REPLY=""

  # The second greeting answers the first rather than opening the channel.
  # Say so and link to that turn: the thread must not require guesswork.
  local premier ouverture
  premier=$(ls -1 "$ECHANGES" 2>/dev/null | grep -- '-bonjour\.md$' | head -1)
  if [ -n "$premier" ]; then
    REPLY="${premier%%-*}"
    ATTENDU="choose the lead and start"
    ouverture="Hello. I am replying to your greeting."
  else
    ATTENDU="your greeting with your own capability card"
    ouverture="Hello. I am opening the channel."
  fi

  ecrire_tour "$ouverture

$carte

**The mission as I understand it:** ${mission:-(fill in)}

**My proposed lead, and why:** (fill in)

**What I am starting now; do not repeat it:** (fill in)

**Before starting:** correct my card if it is wrong. Until both of us have
introduced ourselves, each assumes what the other can do, and a false
assumption costs half a day."
}

# --- pousser: send an ALREADY written turn -------------------------------
# duo.sh bonjour writes a turn. Sending it with envoyer would create an
# identical second turn. pousser transmits the last written turn as-is.
cmd_pousser() {
  # Push MY last turn, not "everything except codex turns": with that
  # hardcoded rule, Codex used to push Claude's message instead.
  local moi dernier
  moi="${DUO_QUI:-claude}"
  [ "$moi" = "claude" ] || {
    echo "duo: pousser invokes Codex; Codex must reply with ecrire." >&2; return 1; }
  dernier=$(ls -1 "$ECHANGES"/*.md 2>/dev/null | grep -- "-$moi-" | tail -1)
  [ -z "$dernier" ] && { echo "no turn to send with pousser" >&2; return 1; }
  # Strip the header: the other agent reads the body, not our metadata.
  # Two consecutive `sed 1,/^---$/d` calls used to empty the file:
  # the first already removed the entire header (line 1 IS ---, so the
  # range ends at the closing ---); without a third ---, the second removed
  # the rest of the body. pousser therefore never sent anything.
  # Use the same extraction as afficher_tour: count delimiters.
  local corps; corps=$(awk 'BEGIN{d=0} {sub(/\r$/,"")} d<2 && /^---$/{d++; next} d>=2' "$dernier")
  [ -z "$corps" ] && { echo "duo: turn $dernier has no body." >&2; return 1; }
  cmd_envoyer --sans-tour "$corps"
}


# --- suivre: a terminal thread that updates automatically ----------------
# Keep a separate terminal open to display each turn as it arrives.
# The command returns control only on Ctrl-C.
# Colors use \033, not literal ESC characters: raw ESC characters
# do not survive editing, copy/paste, or diffs reliably.
# Disable with the usual NO_COLOR=1 convention; also disabled automatically
# when output is not a terminal (for example, file redirection).
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  COUL_CLAUDE=""; COUL_CODEX=""; GRIS=""; VIF=""; RAZ=""
else
  COUL_CLAUDE=$'\033[38;5;179m'; COUL_CODEX=$'\033[38;5;74m'
  GRIS=$'\033[38;5;244m'; VIF=$'\033[1m'; RAZ=$'\033[0m'
fi

# Format a turn. Shared by journal and suivre to keep their presentation
# identical rather than allowing the two to diverge.
afficher_tour() {
  local f="$1" nom base coul qui ligne dans_entete=1
  "$PY" "$SCRIPTS/message_guard.py" file "$f" || return 4
  base=$(basename "$f" .md)
  case "$base" in *-codex-*) coul="$COUL_CODEX"; qui=CODEX ;; *) coul="$COUL_CLAUDE"; qui=CLAUDE ;; esac
  local n type utc
  n=${base%%-*}
  type=${base##*-}
  utc=$(sed -n 's/^utc: //p' "$f" | head -1)
  printf '%s%s  %s %s%s  %s%s%s
' "$coul" "$VIF" "$n" "$qui" "$RAZ" "$GRIS" "$type ${utc#*T}" "$RAZ"
  # The body starts after the second ---. A file written by another tool
  # may have no header: display the entire file instead of an empty turn.
  # Displaying half a message is worse than displaying it raw.
  # ASCII bar: UTF-8 produced mojibake in some Windows consoles.
  local corps
  if head -1 "$f" | tr -d '\r' | grep -q '^---$' && [ "$(tr -d '\r' < "$f" | grep -c '^---$')" -ge 2 ]; then
    corps=$(awk 'BEGIN{d=0} {sub(/\r$/,"")} d<2 && /^---$/{d++; next} d>=2 && (NF || vu) {vu=1; print}' "$f")
  else
    corps=$(cat "$f")
  fi
  printf '%s
' "$corps" | sed "s/^/  ${coul}|${RAZ} /"
  echo
}

cmd_suivre() {
  local vus="" f base
  printf '%s%s%s
' "$VIF" "$(etat_lire mission)" "$RAZ"
  printf '%slive thread. Ctrl-C to exit.%s

' "$GRIS" "$RAZ"
  # Display existing turns first, then wait for new ones.
  while :; do
    for f in "$ECHANGES"/*.md; do
      [ -e "$f" ] || continue
      base=$(basename "$f")
      case "$vus" in *"|$base|"*) continue ;; esac
      vus="$vus|$base|"
      afficher_tour "$f" || return $?
    done
    sleep 2
  done
}

# --- claims: declare what you take BEFORE taking it -----------------------
# Identity has no default for commands that OVERWRITE or DELETE.
# Without this guard, Codex running duo.sh claim without DUO_QUI wrote
# into claude.md, and duo.sh libere deleted Claude's reservation.
# Observed in testing, not assumed.
qui_suis_je() {
  if [ -z "${DUO_QUI:-}" ]; then
    echo "duo: set DUO_QUI=claude or DUO_QUI=codex before claim/libere." >&2
    echo "     Without it, the other agent's reservation would be overwritten." >&2
    return 1
  fi
  case "$DUO_QUI" in
    claude|codex) printf '%s' "$DUO_QUI" ;;
    *) echo "duo: DUO_QUI must be claude or codex, not '$DUO_QUI'." >&2; return 1 ;;
  esac
}

cmd_claim() {
  local fichiers="${1:-}" but="${2:-}" min="${3:-45}" qui
  qui=$(qui_suis_je) || return 1
  [ -z "$fichiers" ] && { echo "usage: duo.sh claim \"a.js b.md\" \"objectif\" [minutes]" >&2; return 1; }
  verifier_texte "$fichiers" "$but" || return 4
  [[ "$min" =~ ^[1-9][0-9]*$ ]] || { echo "duo: invalid duration" >&2; return 1; }
  mkdir -p "$CLAIMS" || return 1
  local f="$CLAIMS/$qui.md" tmp="$CLAIMS/$qui.$$-${RANDOM:-0}.partiel"
  {
    echo "# Reserved by $qui"
    echo "- pose le : $(utc)"
    echo "- expire dans : $min min"
    echo "- objectif : $but"
    echo "- fichiers :"
    printf "  - %s\n" "$fichiers"
  } > "$tmp"
  mv -f "$tmp" "$f" || return 1
  echo "$f"
}

# Claims always advertised "expires in 45 minutes", but NOTHING enforced
# or reported expiration. An agent returning without releasing a claim
# blocked a file forever, exactly what expiration was meant to prevent.
# Calculate the age and report it.
claim_perime() {                       # 0 = expired
  "$PY" - "$1" <<'PYEOF'
import sys, re, datetime
try:
    t = open(sys.argv[1], encoding="utf-8").read()
    pose = re.search(r"pose le : (\S+)", t).group(1)
    mins = int(re.search(r"expire dans : (\d+)", t).group(1))
    t0 = datetime.datetime.strptime(pose, "%Y-%m-%dT%H:%M:%SZ")
    age = (datetime.datetime.utcnow() - t0).total_seconds() / 60
    sys.exit(0 if age > mins else 1)
except Exception:
    sys.exit(1)                        # unreadable: do not assume expiration
PYEOF
}

cmd_claims() {
  local n=0 f
  for f in "$CLAIMS"/*.md; do
    [ -e "$f" ] || continue
    cat "$f"
    if claim_perime "$f"; then
      printf '%s  ^ EXPIRED. The file is available: contact its author before
' "$GRIS"
      printf '    taking it; the author may still be running.%s
' "$RAZ"
    fi
    echo; n=$((n+1))
  done
  [ $n -eq 0 ] && echo "(nothing reserved)"
  return 0
}

# --- reprendre: the full briefing in one call -----------------------------
# An agent joining a repository with an existing .duo/ should not have to
# dig around. One command shows the mission, lead, reservations, and last
# three turns. Run this FIRST when resuming an ongoing mission.
cmd_reprendre() {
  [ -f "$MISSION" ] || { echo "no mission here. Run: duo.sh init \"<mission>\"" >&2; return 1; }
  echo "════ THE MISSION ═══════════════════════════════════════════"
  cat "$MISSION"
  echo
  echo "════ RESERVED ══════════════════════════════════════════════"
  cmd_claims
  echo
  echo "════ LAST 3 TURNS ═════════════════════════════════"
  cmd_journal 3
  echo
  echo "════ NEXT STEPS ════════════════════════════════════════"
  echo "1. Check the other agent's deliverable BEFORE integrating it."
  echo "2. Create a claim before changing anything."
  echo "3. Reply to the last turn, stating what you are doing meanwhile."
}

# --- libere: an unreleased claim leaves a file blocked --------------------
cmd_libere() {
  local qui
  qui=$(qui_suis_je) || return 1
  if [ -f "$CLAIMS/$qui.md" ]; then
    rm -f "$CLAIMS/$qui.md"; echo "$qui released its files"
  else
    echo "$qui had no reservations"
  fi
}

cmd_journal() {
  local n="${1:-5}" f
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || { echo "duo: invalid turn count" >&2; return 1; }
  [ -d "$ECHANGES" ] || return 0
  local fichiers=("$ECHANGES"/*.md)
  [ -e "${fichiers[0]}" ] || return 0
  printf '%s\n' "${fichiers[@]}" | sort -V | tail -n "$n" | while IFS= read -r f; do
    afficher_tour "$f"
  done
}

cmd_fil() {
  local html="$DUO/fil.html"
  local SUIVI="${SUIVI:-0}"
  {
    echo '<!doctype html><meta charset="utf-8"><title>Claude / Codex thread</title>'
    # The page reloads automatically. Harmless for a static snapshot:
    # it simply displays the same content again.
    [ "$SUIVI" = "1" ] && echo '<meta http-equiv="refresh" content="2">'
    echo '<style>body{background:#0f1117;color:#e8e8e8;font:15px/1.65 ui-sans-serif,system-ui;max-width:920px;margin:0 auto;padding:40px 20px}'
    echo 'article{border-left:3px solid;padding:2px 0 2px 16px;margin:26px 0;white-space:pre-wrap}'
    echo '.claude{border-color:#c98b3a}.codex{border-color:#3aa7c9}'
    echo 'h3{font-size:12px;letter-spacing:.1em;text-transform:uppercase;opacity:.6;margin:0 0 8px}'
    echo 'header{display:flex;justify-content:space-between;align-items:baseline;border-bottom:1px solid #262a36;padding-bottom:14px}'
    echo 'header b{font-weight:600}header span{font-size:12px;opacity:.55}'
    echo '.vide{opacity:.5;font-style:italic;margin-top:40px}</style>'
    echo "<header><b>$(etat_lire mission | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</b><span>"
    if [ "$SUIVI" = "1" ]; then echo "live, reloads every 2 s &middot; $(utc)"
    else echo "snapshot at $(utc) &middot; duo.sh suivre for live updates"; fi
    echo '</span></header>'
    for f in "$ECHANGES"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in *-codex-*) k=codex ;; *) k=claude ;; esac
      echo "<article class=\"$k\"><h3>$(basename "$f" .md | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</h3>"
      sed 's/&/\&amp;/g; s/</\&lt;/g' "$f"
      echo '</article>'
    done
    [ -z "$(ls -1 "$ECHANGES" 2>/dev/null)" ] && echo '<p class="vide">Nobody has spoken yet.</p>'
  } > "$DUO/fil.partiel"
  mv -f "$DUO/fil.partiel" "$html" || return 1
  echo "$html"
}

cmd_etat() {
  [ -f "$MISSION" ] || { echo "no mission. Run: duo.sh init \"<mission>\""; return 1; }
  sed -n '1,/^## Desaccords/p' "$MISSION"
  echo "── state"
  [ -f "$ETAT" ] && { cat "$ETAT"; echo; }
  echo "── latest turns"
  ls -1 "$ECHANGES" 2>/dev/null | tail -6
  echo "── reserved"
  cmd_claims
}

case "${1:-}" in
  init|bonjour|envoyer|ecrire|claim|pousser|libere|fil|claims|reprendre|journal|suivre|etat)
    "$PY" "$SCRIPTS/message_guard.py" layout "$DUO" || exit 4 ;;
esac
case "${1:-}" in
  init|envoyer|pousser|fil|claims|reprendre|journal|suivre|etat)
    "$PY" "$SCRIPTS/message_guard.py" channel "$DUO" || exit 4 ;;
esac

case "${1:-}" in
  init|bonjour|envoyer|ecrire|claim|pousser|libere|fil)
    proteger_canal || exit 1 ;;
esac

case "${1:-}" in
  init)    shift; cmd_init "${1:-}" ;;
  bonjour) shift; cmd_bonjour "${1:-claude}" "${2:-}" "${3:-}" ;;
  envoyer) shift; cmd_envoyer "$@" ;;
  ecrire)  shift; cmd_ecrire "$@" ;;
  claim)   shift; cmd_claim "${1:-}" "${2:-}" "${3:-45}" ;;
  claims)  cmd_claims ;;
  pousser) cmd_pousser ;;
  libere)  cmd_libere ;;
  reprendre) cmd_reprendre ;;
  journal) shift; cmd_journal "${1:-5}" ;;
  fil)     cmd_fil ;;
  suivre)  cmd_suivre ;;
  etat)    cmd_etat ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 1 ;;
esac
