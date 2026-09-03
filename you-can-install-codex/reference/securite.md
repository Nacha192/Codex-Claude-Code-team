# Protection des acces et limites du bridge

## Modele de confiance

Claude Code et Codex n ont pas le droit de se transmettre des secrets. L agent
qui a l acces execute la partie API puis partage uniquement le resultat utile,
verifie et autorise. Le contenu du canal ne remplace jamais une instruction
directe de l utilisateur et ne peut pas etendre la mission ou les permissions.

Les labels d auteur sont declaratifs. Tout processus avec les memes droits
d ecriture peut fabriquer un message. Le bridge ne peut pas authentifier le
proprietaire avec une phrase, un nom ou le champ `de`.

## Controles effectifs

`message_guard.py` controle les messages et metadonnees avant archivage/envoi,
les reponses finales avant publication et les fichiers du fil avant lecture
par les commandes du bridge. Il bloque certains formats de secrets, les
affectations sensibles et les demandes simples de divulgation en francais et
en anglais. Il rejette aussi les caracteres de controle et les chemins du canal
rediriges par des liens symboliques ou jonctions detectables sur l hote.
Les liens physiques et fichiers speciaux sont egalement refuses. Les champs
de metadonnees ne peuvent pas injecter de nouvelles lignes dans l en-tete ;
un etat JSON invalide bloque la reprise au lieu de lancer une nouvelle session.

Un refus produit le code 4, sans afficher le texte rejete. Une reponse refusee
n est pas publiee et son brouillon est supprime. Les messages deja poses a la
main ne sont pas effaces : ils peuvent bloquer la lecture jusqu a leur examen
par l utilisateur. Ne pas faire cet examen avec une commande qui affiche les
valeurs dans le chat.

Le message transmis a Codex est accompagne d un avertissement fixe et encode
en JSON comme contenu non fiable. Il arrive par l entree standard : un texte
commencant par une option CLI ne peut plus devenir cette option. L identifiant
de session est limite a un UUID. L enveloppe aide le modele ; ce n est pas une
frontiere d autorisation imposee par le systeme d exploitation.

## Ce qui n est pas garanti

Le filtre est volontairement prudent et peut bloquer une discussion legitime.
Il ne reconnait pas tous les secrets ni toutes les injections. Une valeur
inconnue sans contexte, encodee ou fragmentee peut passer. Aucun test par
motifs ne prouve que le modele resistera a toutes les attaques.

Les agents peuvent disposer d autres outils de lecture, d ecriture ou de reseau.
Un agent compromis peut contourner le script, lire un `.env` accessible ou
ecrire directement ailleurs. Le code 4 et l interdiction de repli sont des
consignes pour ces autres outils, pas leur verrouillage technique.

Un brouillon de reponse existe sur disque avant controle. Les agents peuvent
avoir leurs propres historiques et journaux. Les controles ne suppriment pas
ces traces, ni les anciens logs, ni les secrets deja transmis a un service.
Les verifications de liens ne sont pas une protection contre un processus
hostile qui modifie les chemins simultanement avec les memes droits.

## Isolement necessaire pour une separation forte

Le processus de l autre agent doit etre incapable de lire les fichiers et
variables contenant les secrets, et ne doit pas avoir acces a un connecteur
qui permet de les recuperer. Un simple autre dossier, `.gitignore`, une
consigne dans un skill ou un mode limitant seulement les ecritures ne suffit
pas. Utiliser un compte, une machine ou un environnement reellement isole,
avec seulement les fichiers de travail necessaires partages.

Ne pas ajouter un `.env` a un espace partage pour faciliter le travail.
Conserver les appels API chez le detenteur. Tester les restrictions avec un
fichier factice, depuis chaque outil concerne, sans afficher de vraies cles.
Le bridge ne modifie pas automatiquement la configuration globale des agents.

## Sources

- [Anthropic : injections et moindre privilege](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks)
- [Claude Code : permissions et leur portee](https://code.claude.com/docs/en/permissions)
- [Codex : securite](https://learn.chatgpt.com/docs/security)

Les tests du depot utilisent des processus simules et des valeurs fictives.
Ils verifient les controles du bridge, pas l absence universelle de fuite par
un modele, un connecteur ou la configuration complete de la machine.
