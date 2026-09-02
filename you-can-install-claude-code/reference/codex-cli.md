# Le CLI de Codex, ce qui a ete verifie

Verifie sur cette machine, Windows 11, `codex-cli 0.152.0`. Ce qui n a pas ete
verifie est marque comme tel. Une fiche n est pas une source : si un point vous
sert a decider, revalidez-le.

---

## Ou est le binaire

**Il peut etre dans le PATH.** Une installation npm y depose un shim `codex`.
Verifie le 2026-09-02 sur cette machine : `command -v codex` resolvait
`.../scoop/apps/nodejs/current/bin/codex`. La fiche affirmait l inverse, c etait
faux, et c est Codex qui l a releve.

Ordre de recherche, du plus fiable au plus fragile :

1. la variable `CODEX_BIN`, si elle est posee ;
2. `command -v codex` ;
3. la cle `CODEX_CLI_PATH` dans `~/.codex/config.toml` ;
4. `~/AppData/Local/OpenAI/Codex/bin/<hash>/codex.exe`.

Le hash change a chaque mise a jour et **plusieurs versions coexistent** : le
glob peut donc tomber sur une ancienne. Il est en dernier pour cette raison.
**Ne jamais coder un chemin en dur.** `duo.sh` fait cette recherche.

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

**Piege confirme, avec une correction.** `codex exec resume --help` ne declare
ni `-C` ni `-s` : les passer echoue. Il faut faire un `cd` avant. En revanche,
**ce que `resume` herite exactement du sandbox d origine n est documente nulle
part** : la version precedente de cette fiche l affirmait, sans preuve. Si le
sandbox compte pour ce que vous faites, verifiez-le, ne le supposez pas.

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

**`openai.yaml` va dans `<skill>/agents/openai.yaml`, pas a la racine du
skill.** Verifie sur les skills livres par OpenAI, tous le placent la. Sa forme :

```yaml
interface:
  display_name: "Nom lisible"
  short_description: "Une phrase."
policy:
  allow_implicit_invocation: false
```

`allow_implicit_invocation: false` **interdit a Codex d invoquer le skill de sa
propre initiative**. Ce n est pas un interrupteur qui empecherait un chargement
autrement inevitable, c est une autorisation qu on retire.

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

**Attention a la portee de cette phrase.** C est une regle d orchestration du
CLI, **pas une incapacite de Codex**. Codex leve la nuance lui-meme : selon la
session, il sait conserver des processus, attendre leur sortie et utiliser des
outils differes. Ce qui est vrai, c est qu un `codex exec` non interactif ne
doit pas surveiller le canal indefiniment.

Consequence sur le protocole : **on ne demande pas a un `codex exec` d attendre.**
Il finit, il publie, il rend la main, et l orchestrateur le relance.

---

## Ses outils

**Cette liste est indicative et datee. Elle ne fait pas foi.** Les outils
exposes dependent de l hote, des plugins installes et de la politique de la
session. Codex a constate lui-meme, le 2026-09-02, qu un outil que cette fiche
donnait pour acquis (`node_repl`) n etait pas expose dans sa session.

**La seule carte qui fait foi est celle que le run declare au bonjour.**
Demandez-la, ne la deduisez pas d ici.

Observe au moins une fois :

- `image_gen` : generation d images. **C est la capacite qui justifie le duo**
  la plupart du temps. Les images atterrissent dans `~/.codex/generated_images/`.
- Pilotage de Chrome et d un navigateur interne, `computer-use`.
- Des connecteurs, des sous-agents et des taches de fond, **selon la session**.
  Ne pas ecrire qu il n en a pas.

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
- **Sandbox et approbations** : imposes par la session, pas par une regle
  generale. Ils sont imprimes dans l en-tete du run (`approval:`, `sandbox:`).
  Observe ici : `workspace-write [workdir, /tmp, $TMPDIR]`, approbation `never`.
- **Ecriture hors des racines autorisees** : impossible. **Une autorisation
  ecrite dans le prompt ne rend pas un montage lecture seule inscriptible** :
  constate pendant cette relecture, Codex avait la consigne de modifier
  `.agents/skills/` et s est fait refuser l acces. Si l autre agent doit ecrire
  quelque part, verifiez que la racine est ouverte, ne lui faites pas confiance
  sur parole.

---

## Etat de la relecture

**Relu par Codex le 2026-09-02**, sur `codex-cli 0.152.0`. Il a releve douze
affirmations fausses ou trop absolues dans cette fiche. Toutes ont ete
corrigees ci-dessus, apres verification de ce qui etait verifiable ici : le
PATH, la sortie de `resume --help`, l en-tete du run, et l emplacement de
`openai.yaml` dans les skills livres par OpenAI.

**Le CLAIM est tranche** : la seule reservation est
`.duo/claims/<agent>.md`. Le champ `fichiers:` d un message est une trace
descriptive de ce qui a ete touche, **il ne reserve rien**. Raison donnee par
Codex, et elle est bonne : une reservation est un etat courant, qui se consulte,
se remplace, expire et se libere ; le journal, lui, est immuable. Deux sources
divergent toujours.

**Ce qui reste ouvert :** rien de bloquant. La regle a retenir est que cette
fiche vieillit. Une capacite lue ici est une hypothese, celle declaree au
bonjour est un fait.
