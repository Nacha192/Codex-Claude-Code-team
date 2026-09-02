#!/usr/bin/env bash
# duo.sh - le canal entre Claude Code et Codex.
#
# Tout passe par des fichiers. Aucun demon, aucun etat en memoire, rien a
# installer. Si les deux agents meurent, le fil survit sur le disque et
# n importe qui peut l ouvrir et lire de quoi ils parlaient.
#
#   duo.sh init "<mission>"          cree .duo/ (mission, etat, echanges, claims)
#   duo.sh bonjour <qui> "<mission>" la poignee de main : qui je suis, ce que
#                                    j ai, ce que je n ai pas. Toujours en
#                                    premier, des deux cotes.
#   duo.sh envoyer [options] "<msg>" ecrit un tour et appelle Codex
#   duo.sh ecrire  [options] "<msg>" ecrit un tour SANS appeler Codex
#   duo.sh claim "<fichiers>" "<but>" [minutes]   reserve des fichiers
#   duo.sh claims                    ce qui est reserve, par qui, jusqu a quand
#   duo.sh libere                    rend les fichiers qu on avait reserves
#   duo.sh reprendre                 le briefing complet : mission, claims,
#                                    3 derniers tours. A lancer en premier
#                                    quand on reprend une mission en cours.
#   duo.sh journal [n]               les n derniers tours dans le terminal
#   duo.sh fil                       tout le fil, en page HTML
#   duo.sh etat                      mission, pilote, session Codex, dernier tour
#
#   options de envoyer/ecrire :
#     --type <proposition|question|decision|preuve|resultat|blocage>
#     --de <claude|codex>   --a <claude|codex>
#     --fichiers "a.js b.md"   --reply <n>   --attendu "<ce qu on attend>"
#
# Codes de sortie : 0 ok, 1 usage, 2 Codex introuvable, 3 Codex a echoue.
# Le 3 compte : l appelant doit pouvoir continuer sans lui.
#
# Deux choix de conception, tous deux issus d une erreur reelle :
#   - le NUMERO fait foi, pas l horodatage. Deux ecritures peuvent tomber dans
#     la meme seconde, et deux horloges ne sont jamais parfaitement d accord.
#   - on ecrit dans un fichier temporaire puis on renomme. Un lecteur ne voit
#     jamais un message a moitie ecrit.

set -uo pipefail

RACINE="${DUO_RACINE:-$PWD}"
DUO="$RACINE/.duo"
ECHANGES="$DUO/echanges"
CLAIMS="$DUO/claims"
MISSION="$DUO/MISSION.md"
ETAT="$DUO/etat.json"

PY=$(command -v python || command -v python3 || echo python)

# Codex n est pas dans le PATH sur une installation Windows standard, et le
# dossier d installation contient un hash qui change a chaque mise a jour :
# ne jamais coder le chemin en dur.
trouver_codex() {
  if [ -n "${CODEX_BIN:-}" ] && [ -x "$CODEX_BIN" ]; then echo "$CODEX_BIN"; return 0; fi
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

# --- etat.json : lu et ecrit par python, jamais par sed. -------------------
etat_lire() {
  [ -f "$ETAT" ] || { echo ""; return 0; }
  "$PY" -c "import json,sys
try: print(json.load(open(sys.argv[1],encoding='utf-8')).get(sys.argv[2],''))
except Exception: print('')" "$ETAT" "$1" 2>/dev/null
}

etat_ecrire() {
  "$PY" - "$ETAT" "$1" "$2" <<'PYEOF'
import json,sys,os,tempfile
p,k,v = sys.argv[1],sys.argv[2],sys.argv[3]
d = {}
if os.path.exists(p):
    try: d = json.load(open(p,encoding='utf-8'))
    except Exception: d = {}
d[k] = v
fd,tmp = tempfile.mkstemp(dir=os.path.dirname(p))
with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(d,f,ensure_ascii=False,indent=2)
os.replace(tmp,p)
PYEOF
}

# Le numero suivant se deduit des fichiers presents : pas de compteur a
# desynchroniser, et un fichier supprime a la main ne casse rien.
prochain_numero() {
  local n
  n=$(ls -1 "$ECHANGES" 2>/dev/null | sed -n 's/^\([0-9]\{4\}\)-.*/\1/p' | sort -n | tail -1)
  printf '%04d' $(( 10#${n:-0} + 1 ))
}

cmd_init() {
  mkdir -p "$ECHANGES" "$CLAIMS"
  local intitule="${1:-}"
  if [ ! -f "$MISSION" ]; then
    cat > "$MISSION" <<EOF
# Mission

## Ce qu on fait
${intitule:-(une phrase, pas un paragraphe)}

## Le critere de reussite
(verifiable par quelqu un d autre. Si vous ne savez pas l ecrire,
 la mission n est pas prete et le duo va tourner en rond.)

## Qui pilote, et pourquoi sur CETTE tache
(metier, historique, connecteurs -> claude
 image, navigateur, inspection visuelle -> codex
 code pur -> celui qui a deja le contexte)

## Repartition
| Qui | Fait | Ne touche pas a |
|-----|------|-----------------|
| claude | | |
| codex  | | |

## Desaccords
(on n efface jamais un desaccord. On ecrit les deux positions, qui a tranche,
 et sur quelle preuve.)
EOF
    echo "cree : $MISSION"
  fi
  [ -f "$ETAT" ] || "$PY" -c "import json,sys;json.dump({'mission':sys.argv[1],'pilote':'','session_codex':'','dernier_tour':'0000','statut':'ouverte'},open(sys.argv[2],'w',encoding='utf-8'),ensure_ascii=False,indent=2)" "${intitule:-sans titre}" "$ETAT"
  echo "canal pret dans $DUO"
}

# --- ecrire un tour -------------------------------------------------------
TYPE="proposition"; DE="claude"; A="codex"; FICHIERS=""; REPLY=""; ATTENDU=""; SANS_TOUR=0
lire_options() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --type)     TYPE="$2"; shift 2 ;;
      --de)       DE="$2";   shift 2 ;;
      --a)        A="$2";    shift 2 ;;
      --fichiers) FICHIERS="$2"; shift 2 ;;
      --reply)    REPLY="$2"; shift 2 ;;
      --attendu)  ATTENDU="$2"; shift 2 ;;
      --sans-tour) SANS_TOUR=1; shift ;;
      *) break ;;
    esac
  done
  RESTE="$*"
}

ecrire_tour() {
  local corps="$1" n f tmp
  mkdir -p "$ECHANGES"
  n=$(prochain_numero)
  f="$ECHANGES/$n-$DE-$TYPE.md"
  tmp="$f.partiel"
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
  mv -f "$tmp" "$f"          # renommage atomique : jamais de lecture partielle
  etat_ecrire dernier_tour "$n"
  echo "$f"
}

cmd_ecrire() {
  lire_options "$@"
  [ -z "$RESTE" ] && { echo "usage: duo.sh ecrire [options] \"message\"" >&2; return 1; }
  ecrire_tour "$RESTE"
}

cmd_envoyer() {
  lire_options "$@"
  [ -z "$RESTE" ] && { echo "usage: duo.sh envoyer [options] \"message\"" >&2; return 1; }

  local codex; codex=$(trouver_codex) || {
    echo "codex introuvable. Pose CODEX_BIN=/chemin/vers/codex.exe" >&2; return 2; }

  local envoye="(tour deja ecrit)"
  [ "$SANS_TOUR" = "0" ] && envoye=$(ecrire_tour "$RESTE")
  local sid; sid=$(etat_lire session_codex)
  TYPE="reponse"; DE="codex"; A="claude"; FICHIERS=""; ATTENDU=""
  local n; n=$(prochain_numero)
  local sortie="$ECHANGES/$n-codex-reponse.md"

  # resume herite du cwd et du sandbox de la session : il REFUSE -C et -s.
  # Et --last devient ambigu des que deux runs tournent, d ou le session id.
  local log="$DUO/.dernier-run.log"
  if [ -n "$sid" ]; then
    ( cd "$RACINE" && "$codex" exec resume "$sid" -o "$sortie" "$RESTE" ) >"$log" 2>&1
  else
    "$codex" exec -C "$RACINE" -s workspace-write -o "$sortie" "$RESTE" >"$log" 2>&1
  fi
  local code=$?

  # Codex imprime "session id: <uuid>" dans son en-tete de run. C est la source
  # la plus fiable : pas de fouille dans ~/.codex/sessions, pas de --last
  # ambigu des que deux runs tournent en parallele.
  if [ -z "$sid" ]; then
    local trouve
    trouve=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$log" | head -1)
    [ -n "$trouve" ] && etat_ecrire session_codex "$trouve"
  fi

  # Le quota est une panne temporaire, pas un bug : on le nomme pour que
  # l appelant sache qu il doit continuer seul et reprendre plus tard.
  if grep -q "usage limit" "$log" 2>/dev/null; then
    echo "codex a atteint son quota. Reprendre plus tard, le message est archive." >&2
    rm -f "$sortie"; return 3
  fi

  # -o n est pas toujours honore : quand la reponse part sur la sortie standard
  # et pas dans le fichier, on la recupere du log plutot que de la perdre. Bug
  # trouve au premier test reel du protocole : les images etaient produites et
  # la reponse n etait nulle part dans le fil.
  if [ ! -s "$sortie" ] && [ -s "$log" ] && ! grep -q "usage limit" "$log"; then
    { echo "---"; echo "n: $n"; echo "de: codex"; echo "a: claude";
      echo "type: reponse"; echo "utc: $(utc)";
      echo "note: recupere du log, -o n avait rien ecrit"; echo "---"; echo
      cat "$log"; } > "$sortie.partiel" && mv -f "$sortie.partiel" "$sortie"
  fi

  if [ $code -ne 0 ] || [ ! -s "$sortie" ]; then
    echo "codex n a pas repondu (code $code)." >&2
    echo "Le message reste archive dans $envoye. Le canal est asynchrone :" >&2
    echo "continue seul sur ce qui ne depend pas de lui, ne boucle pas." >&2
    return 3
  fi

  etat_ecrire dernier_tour "$n"
  echo "$sortie"
}

# --- bonjour : la poignee de main d ouverture ------------------------------
# Ce n est pas de la politesse. Sans elle, chacun suppose ce que l autre sait
# faire, et on a deja perdu une demi-journee sur une supposition fausse. Le
# bonjour porte une carte d identite : qui je suis, ce que j ai, ce que je n ai
# pas, et ce que je commence tout de suite.
cmd_bonjour() {
  local qui="${1:-claude}" mission="${2:-}"
  mkdir -p "$ECHANGES" "$CLAIMS"
  local carte
  if [ "$qui" = "codex" ]; then
    carte="- **Je suis Codex CLI**, dans \`$(basename "$RACINE")\`.
- **J ai** : generation et retouche d images, pilotage de navigateur, un REPL Node persistant, l inspection visuelle en boucle.
- **Je n ai pas** : de connecteurs metier authentifies, de memoire entre les sessions hors fichiers, de taches en arriere-plan.
- **Ma contrainte** : je ne peux pas rester vivant a attendre. Je publie et je m arrete, c est toi qui me relances."
  else
    carte="- **Je suis Claude Code**, dans \`$(basename "$RACINE")\`.
- **J ai** : le contexte metier long, les connecteurs, les taches en arriere-plan avec reveil, les sous-agents, la lecture et l ecriture rapides du depot.
- **Je n ai pas** : de generation d images, de pilotage de navigateur, de REPL persistant.
- **Ma contrainte** : je vois le depot et l historique, pas ce que tu vois toi. Corrige-moi quand je suppose."
  fi
  DE="$qui"; [ "$qui" = "codex" ] && A="claude" || A="codex"
  TYPE="bonjour"; FICHIERS=""; REPLY=""

  # Le deuxieme bonjour n ouvre pas le canal, il y repond. On le dit, et on
  # pointe le tour auquel il repond : le fil doit se lire sans deviner.
  local premier ouverture
  premier=$(ls -1 "$ECHANGES" 2>/dev/null | grep -- '-bonjour\.md$' | head -1)
  if [ -n "$premier" ]; then
    REPLY="${premier%%-*}"
    ATTENDU="qu on choisisse le pilote et qu on demarre"
    ouverture="Bonjour. Je reponds au tien."
  else
    ATTENDU="ton bonjour, avec ta propre carte"
    ouverture="Bonjour. J ouvre le canal."
  fi

  ecrire_tour "$ouverture

$carte

**La mission telle que je la comprends :** ${mission:-(a completer)}

**Le pilote que je propose, et pourquoi :** (a completer)

**Ce que je commence tout de suite, ne le refais pas :** (a completer)

**Avant de commencer :** corrige ma carte si elle est fausse. Tant qu on ne
s est pas presentes tous les deux, chacun suppose ce que l autre sait faire, et
une supposition fausse coute une demi-journee."
}

# --- pousser : envoyer un tour DEJA ecrit ----------------------------------
# duo.sh bonjour ecrit un tour. L envoyer avec "envoyer" en creerait un second,
# identique. pousser prend le dernier tour ecrit et le transmet tel quel.
cmd_pousser() {
  local dernier
  dernier=$(ls -1 "$ECHANGES"/*.md 2>/dev/null | grep -v -- '-codex-' | tail -1)
  [ -z "$dernier" ] && { echo "aucun tour a pousser" >&2; return 1; }
  # on retire l en-tete : l autre agent lit le corps, pas nos metadonnees
  local corps; corps=$(sed '1,/^---$/d; 1,/^---$/d' "$dernier")
  cmd_envoyer --sans-tour "$corps"
}

# --- claims : dire ce qu on prend AVANT de le prendre ----------------------
cmd_claim() {
  local fichiers="${1:-}" but="${2:-}" min="${3:-45}" qui="${DUO_QUI:-claude}"
  [ -z "$fichiers" ] && { echo "usage: duo.sh claim \"a.js b.md\" \"objectif\" [minutes]" >&2; return 1; }
  mkdir -p "$CLAIMS"
  local f="$CLAIMS/$qui.md" tmp="$CLAIMS/$qui.partiel"
  {
    echo "# Reserve par $qui"
    echo "- pose le : $(utc)"
    echo "- expire dans : $min min"
    echo "- objectif : $but"
    echo "- fichiers :"
    for x in $fichiers; do echo "  - $x"; done
  } > "$tmp"
  mv -f "$tmp" "$f"
  echo "$f"
}

cmd_claims() {
  local n=0
  for f in "$CLAIMS"/*.md; do
    [ -e "$f" ] || continue
    cat "$f"; echo; n=$((n+1))
  done
  [ $n -eq 0 ] && echo "(rien de reserve)"
  return 0
}

# --- reprendre : le briefing complet en un appel --------------------------
# Un agent qui arrive dans un depot ou .duo/ existe deja ne doit pas avoir a
# fouiller. Une commande, et il sait la mission, qui pilote, ce qui est reserve,
# et les trois derniers tours. C est la commande a lancer EN PREMIER quand on
# reprend une mission commencee.
cmd_reprendre() {
  [ -f "$MISSION" ] || { echo "aucune mission ici. Lance : duo.sh init \"<mission>\"" >&2; return 1; }
  echo "════ LA MISSION ═══════════════════════════════════════════"
  cat "$MISSION"
  echo
  echo "════ RESERVE ══════════════════════════════════════════════"
  cmd_claims
  echo
  echo "════ LES 3 DERNIERS TOURS ═════════════════════════════════"
  cmd_journal 3
  echo
  echo "════ ET MAINTENANT ════════════════════════════════════════"
  echo "1. Verifier ce que l autre a livre AVANT de l integrer."
  echo "2. Poser un claim avant de modifier quoi que ce soit."
  echo "3. Repondre au dernier tour, en disant ce qu on fait pendant ce temps."
}

# --- liberer : un claim qu on ne libere pas est un fichier mort ------------
cmd_libere() {
  local qui="${DUO_QUI:-claude}"
  if [ -f "$CLAIMS/$qui.md" ]; then
    rm -f "$CLAIMS/$qui.md"; echo "$qui a libere ses fichiers"
  else
    echo "$qui n avait rien de reserve"
  fi
}

cmd_journal() {
  local n="${1:-5}"
  ls -1 "$ECHANGES"/*.md 2>/dev/null | tail -n "$n" | while read -r f; do
    echo "┌─ $(basename "$f" .md)"
    sed 's/^/│ /' "$f" | head -45
    echo "└────────────────────────────────────────────"
  done
}

cmd_fil() {
  local html="$DUO/fil.html"
  {
    echo '<!doctype html><meta charset="utf-8"><title>Fil Claude / Codex</title>'
    echo '<style>body{background:#0f1117;color:#e8e8e8;font:15px/1.65 ui-sans-serif,system-ui;max-width:920px;margin:0 auto;padding:40px 20px}'
    echo 'article{border-left:3px solid;padding:2px 0 2px 16px;margin:26px 0;white-space:pre-wrap}'
    echo '.claude{border-color:#c98b3a}.codex{border-color:#3aa7c9}'
    echo 'h3{font-size:12px;letter-spacing:.1em;text-transform:uppercase;opacity:.6;margin:0 0 8px}</style>'
    for f in "$ECHANGES"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in *-codex-*) k=codex ;; *) k=claude ;; esac
      echo "<article class=\"$k\"><h3>$(basename "$f" .md)</h3>"
      sed 's/&/\&amp;/g; s/</\&lt;/g' "$f"
      echo '</article>'
    done
  } > "$DUO/fil.partiel"
  mv -f "$DUO/fil.partiel" "$html"
  echo "$html"
}

cmd_etat() {
  [ -f "$MISSION" ] || { echo "pas de mission. Lance : duo.sh init \"<mission>\""; return 1; }
  sed -n '1,/^## Desaccords/p' "$MISSION"
  echo "── etat"
  [ -f "$ETAT" ] && { cat "$ETAT"; echo; }
  echo "── derniers tours"
  ls -1 "$ECHANGES" 2>/dev/null | tail -6
  echo "── reserve"
  cmd_claims
}

case "${1:-}" in
  init)    shift; cmd_init "${1:-}" ;;
  bonjour) shift; cmd_bonjour "${1:-claude}" "${2:-}" ;;
  envoyer) shift; cmd_envoyer "$@" ;;
  ecrire)  shift; cmd_ecrire "$@" ;;
  claim)   shift; cmd_claim "${1:-}" "${2:-}" "${3:-45}" ;;
  claims)  cmd_claims ;;
  pousser) cmd_pousser ;;
  libere)  cmd_libere ;;
  reprendre) cmd_reprendre ;;
  journal) shift; cmd_journal "${1:-5}" ;;
  fil)     cmd_fil ;;
  etat)    cmd_etat ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 1 ;;
esac
