# Codex × Claude Code

Un protocole de travail a deux entre **Codex CLI** et **Claude Code**, livre en
deux skills : un pour chacun, meme protocole, chacun avec ses contraintes.

Deux agents ne valent pas mieux qu un seul par magie. Ils valent mieux quand
chacun fait ce que l autre ne peut pas, et ils valent moins que zero quand ils
se repassent la meme tache en se felicitant. Ce depot sert a obtenir le premier
cas et a rendre le second difficile.

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

## Les branches

| Branche | Contenu |
|---|---|
| `main` | ce README et les deux versions |
| `claude-code` | la version Claude Code, `SKILL.md` a la racine |
| `codex` | la version Codex, `SKILL.md` a la racine |

Les branches `claude-code` et `codex` sont faites pour etre clonees directement
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
