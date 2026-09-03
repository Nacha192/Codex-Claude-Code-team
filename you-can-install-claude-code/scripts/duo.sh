#!/usr/bin/env bash
# duo.sh - le canal entre Claude Code et Codex.
#
# Tout passe par des fichiers. Aucun demon, aucun etat en memoire, rien a
# installer. Si les deux agents meurent, le fil survit sur le disque et
# n importe qui peut l ouvrir et lire de quoi ils parlaient.
#
#   duo.sh init "<mission>"          cree .duo/ (mission, etat, echanges, claims)
#   duo.sh bonjour <qui> "<mission>" [carte]
#                                    la poignee de main. La carte est la liste
#                                    des outils REELS de la session : elle se
#                                    regarde, elle ne se recopie pas.
#                                    Toujours en premier, des deux cotes.
#   duo.sh envoyer [options] "<msg>" ecrit un tour et appelle Codex
#   duo.sh ecrire  [options] "<msg>" ecrit un tour SANS appeler Codex
#   duo.sh claim "<fichiers>" "<but>" [minutes]   reserve des fichiers
#   duo.sh claims                    ce qui est reserve, par qui, jusqu a quand
#   duo.sh libere                    rend les fichiers qu on avait reserves
#   duo.sh reprendre                 le briefing complet : mission, claims,
#                                    3 derniers tours. A lancer en premier
#                                    quand on reprend une mission en cours.
#   duo.sh pousser                   envoie le dernier tour DEJA ecrit, sans
#                                    en creer un double
#   duo.sh journal [n]               les n derniers tours dans le terminal
#   duo.sh suivre                    le fil EN DIRECT dans le terminal, chaque
#                                    tour s affiche des qu il arrive. Ctrl-C
#                                    pour sortir. A proposer a l utilisateur.
#   duo.sh fil                       tout le fil, en page HTML, pour archiver
#   duo.sh etat                      mission, pilote, session Codex, dernier tour
#
#   options de envoyer/ecrire :
#     --type <proposition|question|decision|preuve|resultat|blocage>
#     --de <claude|codex>   --a <claude|codex>
#     --fichiers "a.js b.md"   --reply <n>   --attendu "<ce qu on attend>"
#
# Variables : DUO_QUI=claude|codex (obligatoire pour claim et libere),
#             DUO_RACINE, CODEX_BIN, NO_COLOR.
#
# Codes de sortie : 0 ok, 1 usage, 2 Codex introuvable, 3 Codex a echoue.
# Code 4 : controle de securite refuse, ne pas contourner.
# Le 3 compte : l appelant doit pouvoir continuer sans lui.
#
# Deux choix de conception, tous deux issus d une erreur reelle :
#   - le NUMERO fait foi, pas l horodatage. Deux ecritures peuvent tomber dans
#     la meme seconde, et deux horloges ne sont jamais parfaitement d accord.
#   - on ecrit dans un fichier temporaire puis on renomme. Un lecteur ne voit
#     jamais un message a moitie ecrit.

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

# Tous les champs transmis sont controles avant ecriture et avant envoi.
verifier_texte() {
  printf '%s\0' "$@" | "$PY" "$SCRIPTS/message_guard.py" check
}

# Codex PEUT etre dans le PATH (installation npm : un shim `codex` y atterrit),
# mais ce n est pas garanti. Le dossier d installation, lui, contient un hash
# qui change a chaque mise a jour, et plusieurs versions peuvent coexister :
# ne jamais coder le chemin en dur, et garder le glob en DERNIER recours.
# Verifie le 2026-09-02 par Codex : `command -v codex` resolvait bien.
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

# Protection appliquee avant chaque commande qui ecrit, meme sans init.
# Le dernier * neutralise aussi les anciennes exceptions MISSION/etat.
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
  # Un ignore ne retire PAS les fichiers deja suivis de l index.
  if git -C "$RACINE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local suivis
    suivis=$(git -C "$RACINE" ls-files -- .duo) || return 1
    if [ -n "$suivis" ]; then
      echo "duo: .duo contient des fichiers deja suivis par git." >&2
      echo "Verifier puis retirer .duo de l index avec git rm -r --cached -- .duo." >&2
      echo "Les fichiers locaux restent sur disque ; l historique git reste a examiner." >&2
      return 1
    fi
  fi
}

# --- etat.json : lu et ecrit par python, jamais par sed. -------------------
etat_lire() {
  [ -f "$ETAT" ] || { echo ""; return 0; }
  "$PY" -c "import json,sys
try: print(json.load(open(sys.argv[1],encoding='utf-8')).get(sys.argv[2],''))
except Exception: sys.exit(1)" "$ETAT" "$1" 2>/dev/null
}

# Lecture, modification, ecriture : deux appels simultanes se perdaient une
# cle, et os.replace levait un PermissionError sous Windows quand l autre
# tenait encore le fichier. Un verrou par mkdir, plus une reprise sur echec.
etat_ecrire() {
  "$PY" - "$ETAT" "$1" "$2" <<'PYEOF'
import json,sys,os,tempfile,time,errno
p,k,v = sys.argv[1],sys.argv[2],sys.argv[3]
verrou = p + ".verrou"
pris = False
for _ in range(100):                       # 5 s au plus
    try:
        os.mkdir(verrou); pris = True; break
    except OSError as e:
        if e.errno != errno.EEXIST: break
        time.sleep(0.05)
if not pris:
    sys.exit("duo: verrou etat.json indisponible, aucune modification")
try:
    d = {}
    if os.path.exists(p):
        try: d = json.load(open(p, encoding="utf-8"))
        except Exception: sys.exit("duo: etat.json illisible, aucune modification")
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
    for essai in range(20):                # Windows garde le fichier ouvert
        try:
            os.replace(tmp, p); break
        except PermissionError:
            time.sleep(0.05)
    else:
        os.unlink(tmp)
        sys.exit("duo: etat.json occupe, cle non ecrite")
finally:
    if pris:
        try: os.rmdir(verrou)
        except OSError: pass
PYEOF
}

# Le numero suivant se deduit des fichiers presents : pas de compteur a
# desynchroniser, et un fichier supprime a la main ne casse rien.
# Le numero est une ressource partagee : deux agents qui ecrivaient en meme
# temps calculaient le meme, et un des deux messages disparaissait. Mesure :
# 8 pertes sur 10 envois simultanes. On reserve donc le numero par un mkdir,
# atomique partout, Windows compris.
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
    [ "$t" -gt 200 ] && { echo "duo: impossible de reserver un numero" >&2; return 1; }
  done
}

cmd_init() {
  verifier_texte "${1:-}" || return 4
  mkdir -p "$ECHANGES" "$CLAIMS" || return 1
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
  etat_ecrire __init__ "${intitule:-sans titre}" || return 1
  echo "canal pret dans $DUO"
}

# --- ecrire un tour -------------------------------------------------------
TYPE="proposition"; DE="${DUO_QUI:-claude}"; A="codex"; FICHIERS=""; REPLY=""; ATTENDU=""; SANS_TOUR=0
[ "$DE" = "codex" ] && A="claude"
# Une option sans valeur faisait planter le script sur "unbound variable"
# a cause de set -u, avec un message que personne ne peut interpreter.
besoin_valeur() {
  [ $# -ge 2 ] || { echo "duo: l option $1 attend une valeur." >&2; return 1; }
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
  case "$DE:$A" in claude:codex|codex:claude) ;; *) echo "duo: auteurs invalides" >&2; return 1 ;; esac
  [[ "$TYPE" =~ ^[a-z][a-z0-9_-]*$ ]] || { echo "duo: type invalide" >&2; return 1; }
  local champ
  for champ in "$FICHIERS" "$REPLY" "$ATTENDU"; do
    [[ "$champ" != *$'\n'* && "$champ" != *$'\r'* ]] || {
      echo "duo: une metadonnee doit tenir sur une ligne." >&2; return 1; }
  done
  [[ -z "$REPLY" || "$REPLY" =~ ^[0-9]+$ ]] || { echo "duo: reply invalide" >&2; return 1; }
  RESTE="$*"
}

ecrire_tour() {
  local corps="$1" n f tmp
  verifier_texte "$corps" "$FICHIERS" "$REPLY" "$ATTENDU" || return 4
  mkdir -p "$ECHANGES" || return 1
  n=$(reserver_numero) || return 1
  f="$ECHANGES/$n-$DE-$TYPE.md"
  # nom de temporaire UNIQUE : deux ecritures simultanees partageaient le meme
  # et se detruisaient l une l autre.
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
  # renommage atomique : jamais de lecture partielle. Verifie : un mv qui
  # echoue passait inapercu et on annoncait un message qui n existait pas.
  mv -f "$tmp" "$f" || { echo "duo: impossible d ecrire $f" >&2; rm -f "$tmp"; return 1; }
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
    echo "duo: envoyer appelle seulement Codex depuis Claude ; utiliser ecrire pour repondre." >&2; return 1; }
  verifier_texte "$RESTE" "$FICHIERS" "$REPLY" "$ATTENDU" || return 4
  local sid; sid=$(etat_lire session_codex) || return 4
  if [ -n "$sid" ] && [[ ! "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "duo: identifiant de session invalide, envoi refuse." >&2; return 4
  fi
  local prompt
  prompt=$(printf '%s' "$RESTE" | "$PY" "$SCRIPTS/message_guard.py" envelope) || return 4
  local codex; codex=$(trouver_codex) || {
    echo "codex introuvable. Pose CODEX_BIN=/chemin/vers/codex.exe" >&2; return 2; }

  local envoye="(tour deja ecrit)"
  if [ "$SANS_TOUR" = "0" ]; then
    envoye=$(ecrire_tour "$RESTE") || {
      echo "duo: le tour n a pas pu etre ecrit, on n appelle pas Codex." >&2; return 1; }
  fi
  TYPE="reponse"; DE="codex"; A="claude"; FICHIERS=""; ATTENDU=""
  # Le numero de la reponse se RESERVE lui aussi : sinon la course revenait par
  # la porte de derriere, la moitie corrigee seulement.
  local n; n=$(reserver_numero) || return 1
  local sortie="$ECHANGES/$n-codex-reponse.md"
  local brouillon="$DUO/.reponse-$n.partiel"

  # `codex exec resume --help` ne declare ni -C ni -s : les passer echoue.
  # On fait donc le `cd` avant. Ce que resume herite exactement du sandbox
  # d origine n est PAS documente : ne pas s appuyer dessus, verifier au besoin.
  # `--last` devient ambigu des que deux runs tournent, d ou le session id.
  # Un log PAR ENVOI : deux envoyer concurrents partageaient le meme fichier,
  # donc l un lisait l erreur ou le session id de l autre.
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

  # Codex imprime "session id: <uuid>" dans son en-tete de run. On s ancre sur
  # L ETIQUETTE, jamais sur "le premier UUID du log" : un UUID peut apparaitre
  # dans la reponse elle-meme, et le format de sortie n est pas un contrat.
  # Dependance testee sur codex-cli 0.152.0. Si l ancre disparait, on le dit.
  # Uniquement si le run a abouti : sinon on avertissait d un session id
  # manquant alors que la vraie cause etait plus bas, et on brouillait le
  # message utile.
  if [ -z "$sid" ] && [ $code -eq 0 ]; then
    local trouve
    trouve=$(grep -o 'session id:.*' "$log" | head -1 \
             | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    if [ -n "$trouve" ]; then
      etat_ecrire session_codex "$trouve"
    else
      echo "duo: session id introuvable dans le log, le prochain envoi ouvrira une nouvelle session" >&2
    fi
  fi

  if [ $code -eq 0 ] && [ -s "$brouillon" ]; then
    if ! "$PY" "$SCRIPTS/message_guard.py" file "$brouillon"; then
      rm -f "$brouillon"
      echo "duo: reponse refusee avant publication dans le fil." >&2
      return 4
    fi
  fi

  # Seule la reponse finale peut devenir un tour, jamais les sorties d outils.
  # -o ecrit hors du fil ; publication atomique une fois le processus termine.
  if [ $code -eq 0 ] && [ -s "$brouillon" ]; then
    { echo "---"; echo "n: $n"; echo "de: codex"; echo "a: claude";
      echo "type: reponse"; echo "utc: $(utc)"; echo "---"; echo
      cat "$brouillon"; } > "$sortie.partiel" && mv -f "$sortie.partiel" "$sortie" || code=3
  fi
  rm -f "$brouillon" "$sortie.partiel"

  # On ne cherche une cause d echec QUE si le run a echoue. La version
  # precedente fouillait le log dans tous les cas, et Codex, en lisant duo.sh
  # pendant son exploration, avait recopie dans sa sortie la ligne source qui
  # contient la phrase d erreur. Le script a donc conclu a un echec, supprime
  # une reponse valide, et personne n aurait compris pourquoi.
  # Les motifs sont ancres en debut de ligne pour la meme raison.
  if [ $code -ne 0 ] || [ ! -s "$sortie" ]; then
    rm -f "$sortie"     # -o cree parfois un fichier vide : pas de tour muet
    if grep -qE '^Not inside a trusted directory' "$log" 2>/dev/null; then
      echo "codex refuse ce dossier : il n est pas un depot git de confiance." >&2
      echo "  Ouvrir la mission dans un depot git (git init suffit), ou lancer" >&2
      echo "  codex une fois a la main dans ce dossier pour l approuver." >&2
    elif grep -qE "You.?ve hit your usage limit|^Error: usage limit" "$log" 2>/dev/null; then
      echo "codex a atteint son quota. Reprendre plus tard, le message est archive." >&2
    else
      echo "codex n a pas repondu (code $code). Log : $log" >&2
    fi
    echo "Le message reste archive dans $envoye. Le canal est asynchrone :" >&2
    echo "continue seul sur ce qui ne depend pas de lui, ne boucle pas." >&2
    return 3
  fi

  etat_ecrire dernier_tour "$n" || return 1
  echo "$sortie"
}

# --- bonjour : la poignee de main d ouverture ------------------------------
# Ce n est pas de la politesse. Sans elle, chacun suppose ce que l autre sait
# faire, et on a deja perdu une demi-journee sur une supposition fausse. Le
# bonjour porte une carte d identite : qui je suis, ce que j ai, ce que je n ai
# pas, et ce que je commence tout de suite.
cmd_bonjour() {
  local qui="${1:-claude}" mission="${2:-}"
  case "$qui" in claude|codex) ;; *) echo "duo: auteur invalide" >&2; return 1 ;; esac
  mkdir -p "$ECHANGES" "$CLAIMS" || return 1
  # La carte n est PLUS ecrite en dur. Elle l etait, et elle annoncait un REPL
  # persistant que Codex n avait pas, en niant des connecteurs et des taches de
  # fond qu il avait. Codex a demontre les deux. Un script ne peut pas savoir
  # quels outils sont exposes dans la session d en face : c est l agent qui
  # regarde et qui declare. Le 3e argument porte cette carte.
  local carte="${3:-}"
  if [ -z "$carte" ]; then
    carte="- **Je suis $([ "$qui" = codex ] && echo 'Codex CLI' || echo 'Claude Code')**, dans \`$(basename "$RACINE")\`.
- **Les outils que je vois VRAIMENT dans cette session :** (a remplir en
  regardant mes outils, jamais en recopiant un tableau)
- **Ce que je ne vois pas ici :** (a remplir)
- **Ma contrainte d orchestration :** (a remplir)"
    echo "duo: carte non fournie. Le modele est dans le tour, a completer." >&2
    echo "     Usage : duo.sh bonjour $qui \"<mission>\" \"<ta carte>\"" >&2
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
  # On pousse SON dernier tour, pas "tout sauf ceux de codex" : code en dur,
  # Codex poussait le message de Claude a sa place.
  local moi dernier
  moi="${DUO_QUI:-claude}"
  [ "$moi" = "claude" ] || {
    echo "duo: pousser appelle Codex ; Codex doit repondre avec ecrire." >&2; return 1; }
  dernier=$(ls -1 "$ECHANGES"/*.md 2>/dev/null | grep -- "-$moi-" | tail -1)
  [ -z "$dernier" ] && { echo "aucun tour a pousser" >&2; return 1; }
  # On retire l en-tete : l autre agent lit le corps, pas nos metadonnees.
  # C etait fait par deux `sed 1,/^---$/d` a la suite, et ca vidait le fichier :
  # la premiere supprimait deja tout l en-tete (la ligne 1 EST un ---, donc la
  # plage court jusqu au --- de fermeture), la seconde supprimait le corps
  # jusqu a la fin faute de troisieme ---. pousser n a donc jamais rien envoye.
  # Meme extraction que afficher_tour : on compte les delimiteurs.
  local corps; corps=$(awk 'BEGIN{d=0} {sub(/\r$/,"")} d<2 && /^---$/{d++; next} d>=2' "$dernier")
  [ -z "$corps" ] && { echo "duo: le tour $dernier n a pas de corps." >&2; return 1; }
  cmd_envoyer --sans-tour "$corps"
}


# --- suivre : le fil dans le terminal, qui se met a jour tout seul --------
# Pas une page web. Un terminal qu on laisse ouvert a cote, qui affiche chaque
# nouveau tour des qu il arrive. La commande ne rend la main qu au Ctrl-C.
# Couleurs. Ecrites en \033 et non en caractere ESC brut : un ESC dans le
# fichier survit mal a une edition, a un copier-coller ou a un diff.
# Desactivables : NO_COLOR=1, la convention usuelle, et automatiquement
# quand la sortie n est pas un terminal (redirection vers un fichier).
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  COUL_CLAUDE=""; COUL_CODEX=""; GRIS=""; VIF=""; RAZ=""
else
  COUL_CLAUDE=$'\033[38;5;179m'; COUL_CODEX=$'\033[38;5;74m'
  GRIS=$'\033[38;5;244m'; VIF=$'\033[1m'; RAZ=$'\033[0m'
fi

# Un tour, mis en forme. Utilise par journal et par suivre : une seule
# presentation, sinon les deux divergent.
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
  # Le corps commence apres le second ---. Mais un fichier ecrit par un outil
  # tiers peut ne pas avoir d en-tete du tout : on affiche alors le fichier
  # entier plutot qu un tour vide. Un message affiche a moitie est pire qu un
  # message brut.
  # barre ASCII : l UTF-8 sortait en mojibake selon la console Windows
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
  printf '%sfil en direct. Ctrl-C pour sortir.%s

' "$GRIS" "$RAZ"
  # on affiche d abord ce qui existe deja, puis on attend la suite
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

# --- claims : dire ce qu on prend AVANT de le prendre ----------------------
# L identite n a pas de valeur par defaut sur les commandes qui ECRASENT ou
# SUPPRIMENT. Sans ce garde-fou, Codex lancant `duo.sh claim` sans DUO_QUI
# ecrivait dans claude.md, et `duo.sh libere` supprimait la reservation de
# Claude. Constate en test, pas suppose.
qui_suis_je() {
  if [ -z "${DUO_QUI:-}" ]; then
    echo "duo: pose DUO_QUI=claude ou DUO_QUI=codex avant claim/libere." >&2
    echo "     Sans ca, on ecrase la reservation de l autre." >&2
    return 1
  fi
  case "$DUO_QUI" in
    claude|codex) printf '%s' "$DUO_QUI" ;;
    *) echo "duo: DUO_QUI vaut claude ou codex, pas '$DUO_QUI'." >&2; return 1 ;;
  esac
}

cmd_claim() {
  local fichiers="${1:-}" but="${2:-}" min="${3:-45}" qui
  qui=$(qui_suis_je) || return 1
  [ -z "$fichiers" ] && { echo "usage: duo.sh claim \"a.js b.md\" \"objectif\" [minutes]" >&2; return 1; }
  verifier_texte "$fichiers" "$but" || return 4
  [[ "$min" =~ ^[1-9][0-9]*$ ]] || { echo "duo: duree invalide" >&2; return 1; }
  mkdir -p "$CLAIMS" || return 1
  local f="$CLAIMS/$qui.md" tmp="$CLAIMS/$qui.$$-${RANDOM:-0}.partiel"
  {
    echo "# Reserve par $qui"
    echo "- pose le : $(utc)"
    echo "- expire dans : $min min"
    echo "- objectif : $but"
    echo "- fichiers :"
    printf "  - %s\n" "$fichiers"
  } > "$tmp"
  mv -f "$tmp" "$f" || return 1
  echo "$f"
}

# Le claim annonce "expire dans 45 min" depuis le debut, et RIEN ne l appliquait
# ni ne le signalait. Un agent qui rendait la main sans liberer bloquait donc un
# fichier pour toujours, c est-a-dire exactement ce que l expiration devait
# empecher. On calcule l age et on le dit.
claim_perime() {                       # 0 = perime
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
    sys.exit(1)                        # illisible : on ne perime pas au hasard
PYEOF
}

cmd_claims() {
  local n=0 f
  for f in "$CLAIMS"/*.md; do
    [ -e "$f" ] || continue
    cat "$f"
    if claim_perime "$f"; then
      printf '%s  ^ EXPIRE. Le fichier est libre : ecrire a son auteur avant
' "$GRIS"
      printf '    de le prendre, il tourne peut-etre encore.%s
' "$RAZ"
    fi
    echo; n=$((n+1))
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
  local qui
  qui=$(qui_suis_je) || return 1
  if [ -f "$CLAIMS/$qui.md" ]; then
    rm -f "$CLAIMS/$qui.md"; echo "$qui a libere ses fichiers"
  else
    echo "$qui n avait rien de reserve"
  fi
}

cmd_journal() {
  local n="${1:-5}" f
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || { echo "duo: nombre de tours invalide" >&2; return 1; }
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
    echo '<!doctype html><meta charset="utf-8"><title>Fil Claude / Codex</title>'
    # La page se recharge seule. Inoffensif quand on la consulte a froid :
    # elle se recontente d afficher le meme contenu.
    [ "$SUIVI" = "1" ] && echo '<meta http-equiv="refresh" content="2">'
    echo '<style>body{background:#0f1117;color:#e8e8e8;font:15px/1.65 ui-sans-serif,system-ui;max-width:920px;margin:0 auto;padding:40px 20px}'
    echo 'article{border-left:3px solid;padding:2px 0 2px 16px;margin:26px 0;white-space:pre-wrap}'
    echo '.claude{border-color:#c98b3a}.codex{border-color:#3aa7c9}'
    echo 'h3{font-size:12px;letter-spacing:.1em;text-transform:uppercase;opacity:.6;margin:0 0 8px}'
    echo 'header{display:flex;justify-content:space-between;align-items:baseline;border-bottom:1px solid #262a36;padding-bottom:14px}'
    echo 'header b{font-weight:600}header span{font-size:12px;opacity:.55}'
    echo '.vide{opacity:.5;font-style:italic;margin-top:40px}</style>'
    echo "<header><b>$(etat_lire mission | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</b><span>"
    if [ "$SUIVI" = "1" ]; then echo "en direct, recharge toutes les 2 s &middot; $(utc)"
    else echo "instantane du $(utc) &middot; duo.sh suivre pour le direct"; fi
    echo '</span></header>'
    for f in "$ECHANGES"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in *-codex-*) k=codex ;; *) k=claude ;; esac
      echo "<article class=\"$k\"><h3>$(basename "$f" .md | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</h3>"
      sed 's/&/\&amp;/g; s/</\&lt;/g' "$f"
      echo '</article>'
    done
    [ -z "$(ls -1 "$ECHANGES" 2>/dev/null)" ] && echo '<p class="vide">Personne n a encore parle.</p>'
  } > "$DUO/fil.partiel"
  mv -f "$DUO/fil.partiel" "$html" || return 1
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
