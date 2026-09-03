# Codex × Claude Code (communication / team)

**Faire travailler Codex CLI et Claude Code ensemble sur une meme mission, sans
qu ils se marchent dessus.** Un protocole, un canal de fichiers, et deux skills :
un pour chacun, meme regles, chacun avec ses contraintes propres.

Deux agents ne valent pas mieux qu un seul par magie. Ils valent mieux quand
chacun fait ce que l autre ne peut pas, et ils valent moins que zero quand ils
se repassent la meme tache en se felicitant. Ce depot sert a obtenir le premier
cas et a reduire ce risque de coordination.

## Security boundary

This is a coordination tool, not a sandbox or a credential vault. Each agent
keeps its own API access and performs the authenticated step itself. Exchange
only the necessary, reviewed result. The message filter is a best-effort check;
it cannot stop an agent that can read secrets and use other tools to send them.
Keep credentials outside shared files and enforce access boundaries in the host.

## Installation, en 30 secondes

**Telechargez les deux.** Un skill pour Claude Code, un pour Codex. Les deux
sont necessaires : si un seul des agents l a, il suit un protocole que l autre
ne connait pas et rien ne se passe.

| | Telechargement | Ou le poser |
|---|---|---|
| Claude Code | **[le zip](https://github.com/Nacha192/Codex-Claude-Code-communication-team-/raw/main/INSTALL-claude-code.zip)** | `votre-projet/.claude/skills/` |
| Codex | **[le zip](https://github.com/Nacha192/Codex-Claude-Code-communication-team-/raw/main/INSTALL-codex.zip)** | `votre-projet/.agents/skills/` |

Decompressez, posez le dossier `duo-claude-codex` obtenu a l emplacement indique.

Les fichiers du depot sont nommes pour qu il n y ait pas a reflechir :
`INSTALL-*` sont les deux archives a installer, `you-can-install-*` sont les
memes en clair si vous preferez copier les dossiers a la main, et le reste
(`README.md`, `LICENSE`) ne s installe pas.
Vous devez arriver a ceci :

```
votre-projet/
  .claude/skills/duo-claude-codex/SKILL.md
  .agents/skills/duo-claude-codex/SKILL.md
```

**C est tout.** Rien a installer, rien a lancer, rien a redemarrer. Les deux
agents doivent travailler sur la meme machine et dans le meme depot : le canal
est un dossier de fichiers, pas un service en ligne.

Ensuite, on le demande : « utilise le skill duo-claude-codex pour cette
mission ». Il ne se declenche pas tout seul, c est voulu.

---

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
cp -r you-can-install-claude-code /chemin/vers/votre-projet/.claude/skills/duo-claude-codex
```

Ou `~/.claude/skills/duo-claude-codex` pour l avoir dans tous vos projets.

**3. Poser le skill de Codex**, dans le meme projet :

```bash
mkdir -p /chemin/vers/votre-projet/.agents/skills
cp -r you-can-install-codex /chemin/vers/votre-projet/.agents/skills/duo-claude-codex
```

**Rien d autre a installer.** Pas de paquet, pas de dependance, pas de service.
Les scripts utilisent bash et python, deja presents sur la plupart des machines,
et le binaire de Codex si vous voulez que Claude puisse l appeler tout seul.

**4. Verifier**, dans un dossier quelconque :

```bash
D=.claude/skills/duo-claude-codex/scripts/duo.sh
bash $D init "essai"
bash $D bonjour claude "essai" "- Je suis Claude Code, outils : shell, git."
bash $D journal 1
```

Si le dernier affiche le message en couleur avec son numero et son auteur,
tout est en place.

Le 3e argument de `bonjour` est la **carte** : les outils que l agent voit
vraiment dans sa session. Sans elle, le tour part avec des champs a completer et
le script vous le dit. C est volontaire : le script ne peut pas deviner ce qui
est expose en face, et une carte inventee coute un tour a l autre.

Pour suivre une conversation en direct, dans un second terminal :

```bash
bash .claude/skills/duo-claude-codex/scripts/duo.sh suivre
```

Chaque tour s affiche des qu il arrive. Ctrl-C pour sortir.

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
| `you-can-install-claude-code/` | la version Claude Code, a poser dans `.claude/skills/` |
| `you-can-install-codex/` | la version Codex, a poser dans `.agents/skills/` ou `~/.codex/skills/` |
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

- **[Telecharger la version Claude Code](https://github.com/Nacha192/Codex-Claude-Code-communication-team-/raw/main/INSTALL-claude-code.zip)**
- **[Telecharger la version Codex](https://github.com/Nacha192/Codex-Claude-Code-communication-team-/raw/main/INSTALL-codex.zip)**

Ces deux liens telechargent directement, sans passer par une page
intermediaire. Le zip contient le dossier avec son `SKILL.md` a la racine,
c est la forme attendue par l import.

**Quoi en faire, une fois telecharges.** Chaque zip contient un dossier
`duo-claude-codex`. Les deux portent le meme nom, c est normal, c est le nom du
skill : ils ne se marchent pas dessus parce qu ils vont a deux endroits
differents.

1. Decompresser `INSTALL-claude-code.zip`, poser le dossier obtenu dans
   `votre-projet/.claude/skills/`
2. Decompresser `INSTALL-codex.zip`, poser le dossier obtenu dans
   `votre-projet/.agents/skills/`

Resultat attendu :

```
votre-projet/
  .claude/skills/duo-claude-codex/SKILL.md
  .agents/skills/duo-claude-codex/SKILL.md
```

C est tout. Rien a lancer, rien a redemarrer, rien a declarer.

**Ne decompressez pas les deux au meme endroit** : meme nom de dossier, le
second ecraserait le premier.

Sinon, le bouton vert **Code** en haut de la page, puis **Download ZIP**,
telecharge le depot entier : les deux versions decompressees, prêtes a copier
au bon endroit.

---

## Installation

**Claude Code** : poser le dossier dans `<projet>/.claude/skills/duo-claude-codex/`
pour un seul projet, ou `~/.claude/skills/` pour tous. Rien a redemarrer.

**Codex** : `<depot>/.agents/skills/duo-claude-codex/` ou `~/.codex/skills/`.
**Garder `agents/openai.yaml`**, a cet emplacement exact, dans un sous-dossier
`agents/` du skill : c est la ou les skills livres par OpenAI le placent. Il
retire a Codex le droit d invoquer le skill de lui-meme. Sans lui, il se charge
des que la description correspond, meme quand le `SKILL.md` dit qu il est
explicite. Constate en direct.

Detail complet dans `you-can-install-claude-code/INSTALLATION.md` et
`you-can-install-codex/INSTALLATION.md`.

---

## Le canal

Tout passe par des fichiers. Aucun demon, aucun etat en memoire, rien a
installer. Si les deux agents meurent, le fil survit sur le disque.

```bash
duo.sh init "<mission>"        # cree .duo/
duo.sh bonjour claude "<...>"  # la poignee de main, toujours en premier
duo.sh claim "a.js" "..." 45   # reserver avant de toucher
duo.sh envoyer --type question "..."
duo.sh pousser                 # envoyer un tour deja ecrit, sans le dupliquer
duo.sh journal 5               # de quoi on parle
duo.sh suivre                  # LE DIRECT : chaque tour s affiche des qu il
                               # arrive. C est la commande a donner a
                               # l utilisateur pour qu il suive la conversation.
duo.sh fil                     # tout le fil, en page HTML, pour archiver
duo.sh reprendre               # le briefing complet, en un appel
duo.sh claims                  # ce qui est reserve, et ce qui a expire
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
   script signale maintenant l absence de reponse ; il ne recopie plus le log brut.
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
ca demolit le design.

---

## Ce que la relecture croisee a donne

Le chiffre est le meilleur argument de ce depot, alors autant le donner en
entier. **Dix-neuf defauts trouves sur le canal, en une journee**, repartis
ainsi :

- **cinq par Codex**, en relisant la version du skill ecrite a sa place. Dont
  celui-ci, que personne d autre ne pouvait voir : le script laissait `claude`
  comme identite par defaut, donc Codex qui posait une reservation ecrasait
  celle de Claude et pouvait la supprimer. Le mecanisme cense empecher les deux
  de se marcher dessus faisait exactement ca.
- **quatre par le test de bout en bout**, celui qui appelle vraiment Codex et
  reprend la session. Dont : un echec archive dans le fil signe `de: codex`,
  donc un message d erreur qui se faisait passer pour sa reponse.
- **onze par une relecture ligne a ligne**. Dont : les reservations annoncaient
  `expire dans 45 min` et rien ne l appliquait ni ne le signalait, et la
  poignee de main imprimait encore une carte de capacites que Codex avait
  demontee par ecrit deux heures plus tot.

La lecon n est pas que le code etait mauvais. Elle est que **la relecture par
l autre agent trouve ce que l auteur ne peut structurellement pas voir**, et
qu un test de bout en bout trouve ce qu aucune relecture ne trouve. C est
exactement ce que ce protocole sert a organiser.

## Confidentialite du canal

**`.duo/` et git.** Tout le canal reste local, y compris `MISSION.md` et
`etat.json`. Avant chaque commande qui ecrit, le script cree ou complete
`.duo/.gitignore` avec `*`, meme si un ancien fichier existe deja.
Pour les ecritures manuelles, ajouter `.duo/` au `.gitignore` du depot avant
de commencer. Un fichier ignore reste lisible sur disque.

Un `.gitignore` ne protege pas les fichiers deja suivis. Le script refuse alors
d ecrire : examiner `git ls-files -- .duo`, puis retirer le canal de l index
avec `git rm -r --cached -- .duo`. Cela conserve les fichiers locaux et ne
nettoie pas l historique deja publie. Ne jamais forcer l ajout du canal.

Les nouveaux `.run-NNNN.log` contiennent seulement un identifiant de session
et des diagnostics fixes. `scripts/run_metadata.py` elimine la sortie brute
AVANT l ecriture sur disque. Copier ce fichier avec `duo.sh`.
Une reponse finale absente produit un echec (code 3), jamais une copie du log
dans le fil. Les anciens logs ne sont ni nettoyes ni supprimes automatiquement.

Les messages et reponses passent aussi par `scripts/message_guard.py`.
Ce controle bloque des motifs connus et des demandes simples de divulgation,
mais pas tous les secrets ni toutes les attaques. La regle ci-dessus reste
necessaire, ainsi qu une separation effective des acces pour un isolement fort. Le canal n ouvre
aucun serveur de partage, mais les agents appeles utilisent leurs propres
services reseau ; un fichier lu peut entrer dans leur contexte. Le dossier
local et `.gitignore` ne constituent ni du chiffrement ni un controle d acces.

## Verifier et publier une mise a jour

Depuis la racine de ce depot, avec Python et Git Bash disponibles :

```bash
python -m unittest discover -s tests -v
python tools/package_skills.py
git diff --check
git status --short
```

Verifier les fichiers modifies, puis selectionner uniquement ceux de cette
mise a jour avec `git add <chemins>`. Faire `git diff --cached --stat`, puis
`git commit -m "Corrige la protection du canal duo"` et `git push origin main`.
Un commit normal remplace les anciennes versions aux memes chemins. Ne pas
supprimer le depot, ne pas utiliser `push --force` ni ajouter le canal `.duo/`.

## Qui effectue les appels API ?

L agent qui detient l acces execute les appels API. Aucun des deux ne partage
la cle, le `.env` ou les traces sensibles avec l autre ; seul le resultat utile
et autorise est transmis. Une affirmation de propriete dans le canal ne vaut
pas autorisation. Voir [les protections et leurs limites](you-can-install-claude-code/reference/securite.md).
