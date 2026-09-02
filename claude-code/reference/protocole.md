# Le protocole en version longue

Les modeles ci-dessous ne sont pas des formulaires a remplir. Ce sont les
blocs qu on regrette de ne pas avoir mis quand un echange tourne mal.

---

## Modele 1 : le message d ouverture

C est le seul message ou l on a le droit d etre long. Apres, on est bref.

```
MISSION : <une phrase>

CE QUE JE FAIS PENDANT QUE TU LIS, pour que tu ne travailles pas dans le vide :
- <ce que je commence tout de suite>
- <ce a quoi je NE toucherai pas, parce que c est a toi>

CE QUE J AI DEJA VERIFIE, corrige-moi si je me trompe :
- <fait 1, avec le chemin du fichier>
- <fait 2>

CE QUE JE TE DEMANDE :
1. <une question>
2. <une autre>

LE CRITERE QUI TRANCHE : <la phrase qui departage, ex. "entre plus beau et
plus lisible en vignette, on prend lisible">
```

Les deux blocs qu on saute et qu il faut garder :

- **"Corrige-moi si je me trompe"** transforme un monologue en verification.
  L autre agent lit vos faits au lieu de vous croire, et il vous a deja evite
  des erreurs comme ca.
- **Le critere qui tranche** est ce qui empeche une reponse hors sujet. Sans
  lui, l autre repond a la question qu il trouve interessante.

---

## Modele 2 : demander une critique

Une critique molle ne sert a rien. On la rend dure par la consigne, pas par
l espoir.

```
Voici <n> livrables : <chemins exacts>

Ce que j ai change depuis la derniere fois :
- <changement 1>

Ce que je te demande, et je veux que tu ouvres vraiment les fichiers :
1. <le test qui compte, ex. "regarde-les en vignette d abord, comme dans un fil">
2. Le defaut LE PLUS COUTEUX de chacun, UN par livrable, pas trois.
3. Ton classement et sur quel critere.

Sois dur. Je prefere refaire maintenant que payer pour l apprendre.
```

Deux pieges observes :

- **"Un defaut par livrable, pas trois"** evite la liste de vingt remarques
  mineures ou l essentiel se noie.
- **Nommer le test** ("en vignette", "sur mobile", "en lecture rapide") est ce
  qui separe une critique utile d une critique de salon.

Et au retour : **verifier avant de refaire**. Une critique n est pas une preuve.
Sur les quatre critiques recues lors de la mise au point de ce skill, trois
etaient justes et une reposait sur une exigence impossible.

---

## Modele 3 : le desaccord

```
DESACCORD : <sujet en cinq mots>

Ta position : <la sienne, ecrite honnetement, sans la caricaturer>
Ma position : <la mienne>

Ce qui pourrait nous departager : <le test, le fichier, la mesure>

Ce que je propose : <faire le test> / <toi qui pilotes, tranche>
```

Ecrire la position de l autre soi-meme, et honnetement, resout la moitie des
desaccords sur place : on decouvre en l ecrivant qu il avait raison, ou que les
deux positions ne parlaient pas de la meme chose.

---

## Modele 4 : la cloture

```
FIN DE MISSION.

Ce qui a marche : <...>
Ce qui a coute cher : <...>
Ce que tu m as apporte que je n aurais pas trouve seul : <...>
Ce que j aurais du faire seul : <...>
```

Le dernier point est le plus utile et le plus desagreable a ecrire. C est lui
qui empeche de se mettre a deux par reflexe la fois suivante.

---

## Les tours de parole

**Un tour = un message = un fichier.** Pas de conversation a batons rompus :
chaque tour doit pouvoir se lire seul dans six mois.

**Trois allers-retours maximum sur un meme sujet.** Au quatrieme, on ne se
comprend pas, et un tour de plus n y changera rien. Le pilote tranche, ecrit
pourquoi, on avance.

**On ne relance pas pour savoir ou il en est.** Soit on a une notification de
fin, soit on surveille le disque avec `attendre.ps1`. Relancer coute un tour et
n accelere rien.

---

## Le cas ou l autre ne repond pas

Il arrive : quota atteint, session morte, timeout. Ce n est pas un blocage.

1. `duo.sh` sort en code 3 et le message envoye reste archive dans `echanges/`.
2. **Continuer seul sur ce qui est faisable seul**, et dire clairement a
   l utilisateur ce qui reste en suspens.
3. Ne jamais inventer la reponse manquante, ne jamais l annoncer comme recue.
4. Quand l autre revient, lui renvoyer le meme message avec `duo.sh suite`.

Lors de la mise au point de ce skill, Codex a atteint son quota en pleine
mission. Le travail a continue sans lui pendant une heure et il a repris au
meme endroit. C est exactement le comportement vise.
