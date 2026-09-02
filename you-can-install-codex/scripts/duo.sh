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
NUMEROS="$DUO/.numeros"
MISSION="$DUO/MISSION.md"
ETAT="$DUO/etat.json"

PY=$(command -v python || command -v python3 || echo python)

# Codex PEUT etre dans le PATH (installation npm : un shim `codex` y atterrit),
# mais ce n est pas garanti. Le dossier d installation, lui, contient un hash
# qui change a chaque mise a jour, et plusieurs versions peuvent coexister :
# ne jamais coder le chemin en dur, et garder le glob en DERNIER recours.
# Verifie le 2026-09-02 par Codex : `command -v codex` resolvait bien.
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
# Le numero est une ressource partagee : deux agents qui ecrivaient en meme
# temps calculaient le meme, et un des deux messages disparaissait. Mesure :
# 8 pertes sur 10 envois simultanes. On reserve donc le numero par un mkdir,
# atomique partout, Windows compris.
prochain_numero() {
  local n
  n=$( { ls -1 "$ECHANGES" 2>/dev/null | sed -n 's/^\([0-9]\{4\}\)-.*/\1/p'
         ls -1 "$NUMEROS"  2>/dev/null ; } | sort -n | tail -1 )
  printf '%04d' $(( 10#${n:-0} + 1 ))
}

reserver_numero() {
  local n t=0
  mkdir -p "$NUMEROS"
  while :; do
    n=$(prochain_numero)
    if mkdir "$NUMEROS/$n" 2>/dev/null; then printf '%s' "$n"; return 0; fi
    t=$((t+1))
    [ "$t" -gt 200 ] && { echo "duo: impossible de reserver un numero" >&2; return 1; }
  done
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
TYPE="proposition"; DE="${DUO_QUI:-claude}"; A="codex"; FICHIERS=""; REPLY=""; ATTENDU=""; SANS_TOUR=0
[ "$DE" = "codex" ] && A="claude"
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
  # Le numero de la reponse se RESERVE lui aussi : sinon la course revenait par
  # la porte de derriere, la moitie corrigee seulement.
  local n; n=$(reserver_numero) || return 1
  local sortie="$ECHANGES/$n-codex-reponse.md"

  # `codex exec resume --help` ne declare ni -C ni -s : les passer echoue.
  # On fait donc le `cd` avant. Ce que resume herite exactement du sandbox
  # d origine n est PAS documente : ne pas s appuyer dessus, verifier au besoin.
  # `--last` devient ambigu des que deux runs tournent, d ou le session id.
  local log="$DUO/.dernier-run.log"
  if [ -n "$sid" ]; then
    ( cd "$RACINE" && "$codex" exec resume "$sid" -o "$sortie" "$RESTE" ) >"$log" 2>&1
  else
    "$codex" exec -C "$RACINE" -s workspace-write -o "$sortie" "$RESTE" >"$log" 2>&1
  fi
  local code=$?

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
      echo "duo: session id introuvable dans le log, la reprise passera par --last" >&2
    fi
  fi

  # Le quota est une panne temporaire, pas un bug : on le nomme pour que
  # l appelant sache qu il doit continuer seul et reprendre plus tard.
  # Codex refuse de tourner hors d un depot git de confiance. Sans ce message,
  # l appelant lisait "code 1" et cherchait au mauvais endroit. Constate.
  if grep -q "Not inside a trusted directory" "$log" 2>/dev/null; then
    echo "codex refuse ce dossier : il n est pas un depot git de confiance." >&2
    echo "  Ouvrir la mission dans un depot git (git init suffit), ou lancer" >&2
    echo "  codex une fois a la main dans ce dossier pour l approuver." >&2
    rm -f "$sortie"; return 3
  fi

  if grep -q "usage limit" "$log" 2>/dev/null; then
    echo "codex a atteint son quota. Reprendre plus tard, le message est archive." >&2
    rm -f "$sortie"; return 3
  fi

  # -o n est pas toujours honore : quand la reponse part sur la sortie standard
  # et pas dans le fichier, on la recupere du log plutot que de la perdre. Bug
  # trouve au premier test reel du protocole : les images etaient produites et
  # la reponse n etait nulle part dans le fil.
  #
  # MAIS uniquement si le run a REUSSI. Sans cette condition, un echec etait
  # archive dans le fil signe "de: codex", donc un message d erreur se faisait
  # passer pour sa reponse. Trouve au test de bout en bout.
  if [ $code -eq 0 ] && [ ! -s "$sortie" ] && [ -s "$log" ]; then
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


# --- suivre : le fil dans le terminal, qui se met a jour tout seul --------
# Pas une page web. Un terminal qu on laisse ouvert a cote, qui affiche chaque
# nouveau tour des qu il arrive. La commande ne rend la main qu au Ctrl-C.
COUL_CLAUDE=$'[38;5;179m'; COUL_CODEX=$'[38;5;74m'
GRIS=$'[38;5;244m'; VIF=$'[1m'; RAZ=$'[0m'

# Un tour, mis en forme. Utilise par journal et par suivre : une seule
# presentation, sinon les deux divergent.
afficher_tour() {
  local f="$1" nom base coul qui ligne dans_entete=1
  base=$(basename "$f" .md)
  case "$base" in *-codex-*) coul="$COUL_CODEX"; qui=CODEX ;; *) coul="$COUL_CLAUDE"; qui=CLAUDE ;; esac
  local n type utc
  n=${base%%-*}
  type=${base##*-}
  utc=$(sed -n 's/^utc: //p' "$f" | head -1)
  printf '%s%s  %s %s%s  %s%s%s
' "$coul" "$VIF" "$n" "$qui" "$RAZ" "$GRIS" "$type ${utc#*T}" "$RAZ"
  # le corps commence apres le second ---
  # barre ASCII : l UTF-8 sortait en mojibake selon la console Windows
  awk 'BEGIN{d=0} /^---$/{d++; next} d>=2 && (NF || vu) {vu=1; print}' "$f"     | sed "s/^/  ${coul}|${RAZ} /"
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
      afficher_tour "$f"
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
  mkdir -p "$CLAIMS"
  local f="$CLAIMS/$qui.md" tmp="$CLAIMS/$qui.$$-${RANDOM:-0}.partiel"
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
  ls -1 "$ECHANGES"/*.md 2>/dev/null | tail -"$n" | while read -r f; do
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
    echo "<header><b>$(etat_lire mission)</b><span>"
    if [ "$SUIVI" = "1" ]; then echo "en direct, recharge toutes les 2 s &middot; $(utc)"
    else echo "instantane du $(utc) &middot; duo.sh suivre pour le direct"; fi
    echo '</span></header>'
    for f in "$ECHANGES"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in *-codex-*) k=codex ;; *) k=claude ;; esac
      echo "<article class=\"$k\"><h3>$(basename "$f" .md)</h3>"
      sed 's/&/\&amp;/g; s/</\&lt;/g' "$f"
      echo '</article>'
    done
    [ -z "$(ls -1 "$ECHANGES" 2>/dev/null)" ] && echo '<p class="vide">Personne n a encore parle.</p>'
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
  suivre)  cmd_suivre ;;
  etat)    cmd_etat ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 1 ;;
esac
