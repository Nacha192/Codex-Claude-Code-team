# Le CLI de Codex, ce qui a ete verifie

Verifie sur cette machine, Windows 11, `codex-cli 0.152.0`. Ce qui n a pas ete
verifie est marque comme tel. Une fiche n est pas une source : si un point vous
sert a decider, revalidez-le.

---

## Ou est le binaire

Il n est **pas dans le PATH**. Trois endroits ou le chercher, dans cet ordre :

1. la variable `CODEX_BIN` si elle est posee ;
2. la cle `CODEX_CLI_PATH` dans `~/.codex/config.toml` ;
3. `~/AppData/Local/OpenAI/Codex/bin/<hash>/codex.exe`.

Le hash du dossier change a chaque mise a jour : **ne jamais coder un chemin en
dur**. `duo.sh` fait cette recherche.

---

## Les commandes utiles

```bash
codex exec -C <dossier> -s <sandbox> -o <fichier> "<prompt>"
codex exec resume --last -o <fichier> "<prompt>"
```

- `-C` fixe le repertoire de travail.
- `-s workspace-write` autorise l ecriture dans le dossier de travail.
- `-o` ecrit la reponse dans un fichier. **A utiliser systematiquement** : la
  sortie standard est bruitee, le fichier ne l est pas.

**Piege confirme :** `resume` **refuse** `-C` et `-s`. Il herite du repertoire
et du sandbox de la session reprise. Il faut faire un `cd` avant, pas passer
l option. C est la premiere erreur commise en montant ce canal.

---

## Ou vivent ses instructions

Trois couches distinctes, confirmees par Codex lui-meme avec les liens de sa
documentation.

**`AGENTS.md` : toujours charge.** La chaine est construite une fois au
demarrage du run : `~/.codex/AGENTS.override.md` sinon `~/.codex/AGENTS.md`,
puis, de la racine git jusqu au repertoire courant, un fichier par repertoire.
Les fichiers sont **concatenes**, et les plus proches du repertoire courant ont
priorite en cas de conflit. Un `AGENTS.override.md` remplace l `AGENTS.md` du
meme niveau. Limite combinee par defaut : 32 Kio.

**Skills : charges a la demande, exactement comme chez Claude.** Nom et
description visibles au depart, `SKILL.md` charge integralement seulement quand
la tache correspond ou quand il est invoque. Emplacements :

- depot : `.agents/skills/<nom>/SKILL.md`
- utilisateur : `~/.codex/skills/<nom>/SKILL.md`

C est **l erreur de conception la plus couteuse a eviter** : croire que Codex n a
que des instructions permanentes. Il a la meme divulgation progressive que nous.
Le protocole complet va donc dans un skill, **pas** dans `AGENTS.md`, sinon il
serait charge pour toutes les taches.

**`config.toml` : comportement et capacites.** Modele, sandbox, approbations,
MCP, notifications. Ce n est pas l endroit d un protocole metier.

**Custom prompts.** Ils apparaissent en `/prompts:<nom>`. Ce sont des commandes
lancees explicitement, pas des instructions injectees. Sur cette machine le
dossier `~/.codex/prompts/` **n existe pas** : un `ls` sans sortie veut dire
absent, pas vide.

---

## Le reveiller depuis l exterieur

```bash
codex exec "message"                       # nouveau run
codex exec resume --last "message"         # reprend la derniere conversation
codex exec resume <SESSION_ID> "message"   # reprise deterministe
```

**`--last` est fragile** des que plusieurs runs avancent en parallele. Le
protocole stocke un session id explicite. Il est imprime dans l en-tete du run,
ligne `session id:`, et `duo.sh` l extrait de la sortie.

**`notify` est SORTANT.** Codex appelle une commande avec un payload JSON quand
un evenement survient. Ce n est pas une boite aux lettres entrante.

**Il n existe pas de moyen propre d injecter un message dans un `codex exec` en
cours.** Chaque echange est une nouvelle invocation de processus qui peut
reprendre la meme session. Un agent toujours vivant demanderait le Codex App
Server ou le SDK, une architecture plus lourde.

Consequence directe sur le protocole : **on ne demande jamais a Codex
d attendre.** Il finit, il publie, il meurt, et l orchestrateur le relance.

---

## Ses outils

Lus dans `config.toml` :

- `image_gen` : generation d images. **C est la capacite qui justifie le duo**
  la plupart du temps.
- MCP `node_repl` : un REPL Node persistant.
- Pilotage de Chrome et d un navigateur interne.
- `computer-use`.
- Les images produites atterrissent dans `~/.codex/generated_images/`.

---

## Ce qu il fait mieux, honnetement

Constate sur la refonte des creatives un projet de demonstration, pas suppose :

- **Il genere des images utilisables, et il sait pourquoi elles marchent.**
  Interroge sur ce qu il ajoutait pour casser le rendu IA, il a repondu qu il ne
  suffit pas d ajouter du desordre mais qu il faut montrer que les deux cotes de
  la piece n ont pas servi de la meme facon. C est meilleur que la consigne qui
  lui avait ete donnee.
- **Il critique durement et souvent juste.** Sur quatre defauts qu il a releves,
  trois ont ete corriges parce qu il avait raison.
- **Il ne connait pas le contexte metier**, et c est une force pour la critique :
  il voit ce qu on ne voit plus.

## Ce qu il fait moins bien

- Il n a pas l historique du projet. Une critique qui demande de refaire une
  chose deja tranchee avec l utilisateur doit etre ecartee, pas suivie.
- Il ne peut pas verifier une contrainte metier non ecrite. Si la contrainte
  compte, elle doit etre dans le message ou dans un fichier qu il peut lire.

---

## Ses limites

Trois observees ici, quatre decrites par lui.

- **Quota.** "You ve hit your usage limit... try again at HH:MM". Observe deux
  fois. Panne temporaire : continuer seul, reprendre plus tard, ne pas boucler.
- **Sortie vide.** Session morte, le fichier `-o` fait zero octet. `duo.sh`
  traite ce cas comme un echec.
- **Messages tres longs.** Il perd le milieu. Au-dela d une page, ecrire dans un
  fichier du depot et lui donner le chemin.
- **Timeout de session** : aucune duree universelle a encoder. Les limites
  viennent de l hote, des outils et du processus appelant.
- **Contexte** : depend du modele, et il compacte automatiquement les
  conversations longues. **Ne pas inscrire une taille fixe dans le protocole.**
- **Quota** : depend du compte et du modele, consultable avec `/status`, non
  stable. Observe deux fois pendant la mise au point de ce skill.
- **Sandbox** : generalement `workspace-write` avec approbation `on-request`,
  reseau restreint, pas d escalade interactive depuis un run non interactif.
- **Ecriture hors des racines autorisees** : impossible sans permission. Un run
  sandboxe ne peut pas forcement ecrire dans `~/.codex`.

---

## Reste a confirmer

- Ou vit exactement le CLAIM : un fichier `claims/` separe, un champ dans
  l en-tete de message, ou les deux. `duo.sh` fait les deux en attendant sa
  reponse, il a atteint son quota avant de trancher.
- La version Codex du skill, dans `.agents/skills/duo-claude-codex/`, a ete
  redigee de ce cote-ci faute de quota. **Elle doit etre relue par lui.**
