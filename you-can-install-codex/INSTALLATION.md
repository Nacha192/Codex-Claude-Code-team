# Installer le skill

Deux versions, deux emplacements. Le protocole est le meme, les scripts et le
vocabulaire different.

---

## Claude Code, dans le terminal

Un skill est un **dossier** contenant un `SKILL.md` avec un en-tete `name` et
`description`. Deux emplacements possibles :

| Ou | Portee |
|---|---|
| `<projet>/.claude/skills/duo-claude-codex/` | ce projet seulement |
| `~/.claude/skills/duo-claude-codex/` | tous les projets de la machine |

Rien a redemarrer, rien a declarer. Le skill apparait dans la liste des skills
disponibles a la session suivante, et il se charge quand la tache correspond a
sa `description` ou quand on l appelle par son nom.

Pour verifier qu il est vu : demander la liste des skills, ou taper
`/duo-claude-codex`.

---

## Claude Desktop et claude.ai

L interface accepte un **zip du dossier** dans les reglages, section
Capacites / Skills. Le zip doit contenir le dossier avec son `SKILL.md` a la
racine, c est-a-dire `duo-claude-codex/SKILL.md`, pas `SKILL.md` tout seul.

C est `duo-claude-codex-claude.zip` qui est fait pour ca.

**Reserve honnete :** ce skill appelle des scripts shell et le binaire de Codex.
Dans Claude Desktop il n y a pas forcement de shell ni de Codex installe, donc
**la partie protocole se lira, la partie canal ne s executera pas**. Le skill
sert pleinement dans le terminal. Ailleurs, il vaut comme document.

---

## Codex

Meme principe, autres chemins :

| Ou | Portee |
|---|---|
| `<depot>/.agents/skills/duo-claude-codex/` | le depot, donc l equipe |
| `~/.codex/skills/duo-claude-codex/` | la machine |

C est `duo-claude-codex-codex.zip`.

**Ne pas mettre le protocole dans `AGENTS.md`.** `AGENTS.md` est charge pour
**toutes** les taches, y compris celles ou le duo n a aucun sens : le contenu
serait paye a chaque fois. Une seule ligne y suffit :

```markdown
Pour travailler avec Claude Code, charger le skill duo-claude-codex.
```

**`openai.yaml` doit accompagner le SKILL.md.** Il tient en trois lignes :

```yaml
policy:
  allow_implicit_invocation: false
```

Sans lui, Codex charge le skill des que la description correspond, meme si le
`SKILL.md` dit noir sur blanc qu il est explicite. Constate en direct : il s est
auto-invoque sur un simple message qui parlait du duo. Un skill qui se declenche
sur des taches ou il ne sert a rien finit desactive.

**Attention :** un run Codex en sandbox `workspace-write` ne peut pas forcement
ecrire dans `~/.codex`. La copie vers l emplacement machine se fait a la main.

---

## Ce qu il faut sur la machine pour que le canal marche

- **Bash.** Git Bash suffit sous Windows.
- **Python**, pour `etat.json`. Deja present si `python` ou `python3` repond.
- **Le binaire de Codex.** Il n est pas dans le PATH sous Windows : `duo.sh` le
  cherche dans `~/.codex/config.toml` puis dans le dossier d installation. En cas
  d echec, poser `CODEX_BIN=/chemin/vers/codex.exe`.
- **PowerShell** pour `attendre.ps1`, uniquement si on orchestre depuis
  l exterieur.

Verification en trente secondes, dans un dossier vide :

```bash
bash duo.sh init "essai"
bash duo.sh ecrire --type question "ca marche ?"
bash duo.sh journal 1
bash duo.sh etat
```

Si `journal` affiche le message avec son en-tete numerote, tout est en place.
`envoyer` est la seule commande qui a besoin de Codex.

---

## Les deux branches

Les deux dossiers sont independants et peuvent vivre sur deux branches :

```
branche claude-code  ->  .claude/skills/duo-claude-codex/
branche codex        ->  .agents/skills/duo-claude-codex/
```

Le seul contenu partage est le protocole lui-meme. Si on le modifie d un cote,
**il faut le reporter de l autre**, sinon on obtient deux verites divergentes,
ce qui est exactement le probleme que ce skill est cense resoudre.
