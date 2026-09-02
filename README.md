# Codex × Claude Code (communication / team)

**Faire travailler Codex CLI et Claude Code ensemble sur une meme mission, sans
qu ils se marchent dessus.** Un protocole, un canal de fichiers, et deux skills :
un pour chacun, meme regles, chacun avec ses contraintes propres.

Deux agents ne valent pas mieux qu un seul par magie. Ils valent mieux quand
chacun fait ce que l autre ne peut pas, et ils valent moins que zero quand ils
se repassent la meme tache en se felicitant. Ce depot sert a obtenir le premier
cas et a rendre le second difficile.

---

## Demarrage rapide

**Il faut installer les deux.** Un skill chez Claude Code, un chez Codex. Si un
seul des deux l a, il suit un protocole que l autre ne connait pas, et rien ne
fonctionne. Ce n est pas un skill au choix, c est une paire.

Les deux agents doivent aussi travailler **sur la meme machine et dans le meme
depot** : le canal est un dossier de fichiers, pas un service en ligne.

**1. Recuperer le depot**

```bash
git clone https://github.com/Nacha192/Codex-Claude-Code-communication-team-.git
cd Codex-Claude-Code-communication-team-
```

**2. Poser le skill de Claude Code**, dans le projet ou vous travaillez :

```bash
mkdir -p /chemin/vers/votre-projet/.claude/skills
cp -r claude-code /chemin/vers/votre-projet/.claude/skills/duo-claude-codex
```

Ou `~/.claude/skills/duo-claude-codex` pour l avoir dans tous vos projets.

**3. Poser le skill de Codex**, dans le meme projet :

```bash
mkdir -p /chemin/vers/votre-projet/.agents/skills
cp -r codex /chemin/vers/votre-projet/.agents/skills/duo-claude-codex
```

**Rien d autre a installer.** Pas de paquet, pas de dependance, pas de service.
Les scripts utilisent bash et python, deja presents sur la plupart des machines,
et le binaire de Codex si vous voulez que Claude puisse l appeler tout seul.

**4. Verifier**, dans un dossier quelconque :

```bash
bash .claude/skills/duo-claude-codex/scripts/duo.sh init "essai"
bash .claude/skills/duo-claude-codex/scripts/duo.sh bonjour claude "essai"
bash .claude/skills/duo-claude-codex/scripts/duo.sh journal 1
```

Si le dernier affiche le message avec son en-tete numerote, tout est en place.

**5. S en servir.** Le skill ne se declenche pas tout seul, c est voulu. On le
demande : « utilise le skill duo-claude-codex pour cette mission ».

---

## Ce que ca resout

| Sans protocole | Avec |
|---|---|
| Chacun suppose ce que l autre sait faire | Une carte declaree a l ouverture, corrigeable |
| Les deux modifient le meme fichier | Reservation avec expiration |
| L un attend l autre sans rien faire | Celui qui attend ne bloque jamais |
| Un desaccord se termine en compromis mou | La preuve gagne, sinon le pilote tranche |
| L utilisateur ne sait pas de quoi ils parlent | Un fil de fichiers lisible en une commande |
| Le duo se declenche sur des taches ou il ne sert a rien | Un critere de declenchement ecrit noir sur blanc |

---

## Ce qu il y a dedans

| | |
|---|---|
| `claude-code/` | la version Claude Code, a poser dans `.claude/skills/` |
| `codex/` | la version Codex, a poser dans `.agents/skills/` ou `~/.codex/skills/` |
| les deux `.zip` | les memes, prets a importer la ou un zip est attendu |

Une seule branche, `main`, et une seule copie de chaque version. Deux copies du
meme fichier finissent toujours par diverger, et ce depot passe une section
entiere a expliquer pourquoi c est le pire resultat possible.

---

## Ou ca tourne

Le canal a besoin de deux choses : **un shell** et **un systeme de fichiers
partage entre les deux agents**. Partout ou ces deux conditions sont reunies,
tout fonctionne.

| | Le protocole | Le canal `duo.sh` |
|---|---|---|
| Claude Code, terminal ou CLI | oui | **oui** |
| Codex CLI, terminal | oui | **oui** |
| Codex depuis l application | oui | oui, dans les racines autorisees par son sandbox |
| Claude Code depuis l application de bureau | oui | selon l acces shell de la session |
| Claude Desktop, claude.ai | oui, comme document | non, pas de shell |

Le cas normal est **les deux en terminal sur la meme machine**, chacun dans le
meme depot. C est la configuration sur laquelle le protocole a ete teste de bout
en bout.

Et meme sans le script, le protocole tient : le canal est une **convention de
nommage de fichiers**, pas un binaire. Un agent qui ne peut pas lancer `duo.sh`
ecrit le fichier lui-meme, ce qui est arrive lors du premier test.

---

## Telechargement direct

Pour Claude Desktop et claude.ai, qui attendent un zip :

- **[Telecharger la version Claude Code](https://github.com/Nacha192/Codex-Claude-Code-communication-team-/raw/main/duo-claude-codex-claude.zip)**
- **[Telecharger la version Codex](https://github.com/Nacha192/Codex-Claude-Code-communication-team-/raw/main/duo-claude-codex-codex.zip)**

Ces deux liens telechargent directement, sans passer par une page
intermediaire. Le zip contient le dossier avec son `SKILL.md` a la racine,
c est la forme attendue par l import.

Sinon, le bouton vert **Code** en haut de la page, puis **Download ZIP**,
telecharge le depot entier : les deux versions decompressees, prêtes a copier
au bon endroit.

---

## Installation

**Claude Code** : poser le dossier dans `<projet>/.claude/skills/duo-claude-codex/`
pour un seul projet, ou `~/.claude/skills/` pour tous. Rien a redemarrer.

**Codex** : `<depot>/.agents/skills/duo-claude-codex/` ou `~/.codex/skills/`.
**Garder `openai.yaml`** : sans lui, Codex charge le skill des que la description
correspond, meme quand le `SKILL.md` dit qu il est explicite. Constate en direct.

Detail complet dans `INSTALLATION.md`.

---

## Le canal

Tout passe par des fichiers. Aucun demon, aucun etat en memoire, rien a
installer. Si les deux agents meurent, le fil survit sur le disque.

```bash
duo.sh init "<mission>"        # cree .duo/
duo.sh bonjour claude "<...>"  # la poignee de main, toujours en premier
duo.sh claim "a.js" "..." 45   # reserver avant de toucher
duo.sh envoyer --type question "..."
duo.sh journal 5               # de quoi on parle
duo.sh fil                     # tout le fil, en page HTML
duo.sh reprendre               # le briefing complet, en un appel
duo.sh libere                  # rendre les fichiers reserves
```

**Le canal n est pas le script.** `duo.sh` est un confort. Ce qui compte est la
convention : `.duo/echanges/NNNN-<auteur>-<type>.md`, avec un en-tete
`n / de / a / type / utc`. Un agent qui ne peut pas lancer le script ecrit le
fichier lui-meme. Un echec d outil ne doit jamais bloquer un echange.

---

## Ce qui vient d un usage reel

Ce protocole n a pas ete concu dans le vide. Il a ete ecrit pendant que les deux
agents travaillaient ensemble sur une vraie boutique, puis **teste du debut a la
fin sur une mission reelle**, ce qui l a casse a quatre endroits :

1. `duo.sh` ne tournait pas cote Codex sous Windows. D ou la regle : le canal est
   la convention, pas le script.
2. Une reponse n a ete archivee nulle part alors que le travail etait fait. Le
   script recupere maintenant le log quand la sortie est vide.
3. La poignee de main creait un tour en double. D ou `duo.sh pousser`.
4. Le protocole se contredisait : il interdisait de travailler avant les deux
   presentations, alors que le premier tour exigeait les deux. L exception est
   ecrite : **le second se presente et execute dans le meme tour**.

Et une correction qu aucun des deux n aurait trouvee seul : le tableau des
capacites vieillit. Codex a corrige sa propre ligne au premier test. **La carte
qui fait foi est celle declaree a l ouverture**, pas celle ecrite dans le skill.

---

## La regle qu on oublie

> Une critique de l autre agent n est pas une preuve. On verifie soi-meme avant
> de refaire. Il se trompe aussi.

Sur quatre defauts releves lors de la mise au point, trois etaient justes. Le
quatrieme aurait fait perdre du temps s il avait ete suivi les yeux fermes.

Et l inverse : quand il corrige avec une preuve reproductible, il gagne, meme si
ca demolit le design. C est arrive six fois.
