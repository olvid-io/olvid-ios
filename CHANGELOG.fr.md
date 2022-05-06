# Changelog

## [0.10.1 (501)] - 2022-03-24

- Il est maintenant possible de répondre à un message, ou de le marquer comme lu, directement depuis la notification !
- Si vous appréciez une réaction faite par un autre utilisateur, vous pouvez facilement l'ajouter à la liste de vos réactions préférées.
- Corrige un problème empêchant un message reçu d'être édité par son envoyeur.
- Corrige un problème empêchant la bonne mise à jour des versions supportées et recommandées d'Olvid.
- Les tâches de fonds sont plus robustes.

## [0.10.0 (495)] - 2022-03-21

- Nouveau comportement de votre carnet d'adresse Olvid ! Maintenant, un autre utilisateur d'Olvid devient un contact *uniquement* si vous l'acceptez explicitement. Vous avez enfin un contrôle total sur votre carnet d'adresse ;-)
- Une nouvelle liste « d'autres » utilisateurs d'Olvid est maintenant accessible depuis l'écran de Contacts. Ces utilisateurs sont typiquement ceux qui font partie des mêmes groupes que vous mais qui ne sont néanmoins pas des contacts. Pour vous les inviter en une touche !
- Maintenant, une invitation à un groupe provenant d'un contact est automatiquement acceptée.
- Vous devez toujours accepter explicitement une invitation à un groupe si elle provient d'un utilisateur qui ne fait partie de vos contacts.
- Le partage via Olvid a été entièrement refait ! Il est maintenant possible de partager du contenu vers plusieurs discussions en une seule fois !
- Support pour de nouveaux émojis.
- Les réactions affichées dans la vue de discussion sont plus faciles à atteindre.
- Les réactions n'étaient pas systématiquement rafraîchies en cas de changement. C'est corrigé.
- Corrige un problème concernant les notifications utilisateur, qui pouvaient ne pas être affichée après une mise à jour de l'app (jusqu'au premier lancement).
- Faire un « double tap » sur une image dans une discussion pouvait afficher l'image au lieu du panel de réactions. C'est corrigé.
- D'importantes améliorations ont été apportées aux appels sécurisés, surtout dans le cas d'un appel de group à plus de 6 utilisateurs.
- L'indicateur de message envoyé est plus robuste.
- Si la version de l'app est obsolète, une alerte recommande de mettre à jour.
- Mise à jour d'une librairie tierce.

## [0.9.18 (490)] - 2022-01-28

- Nouvelles améliorations pour les appels sécurisés ! Cela inclut une meilleure qualité lorsque les conditions réseau sont mauvaises. Les connexions sont aussi beaucoup plus rapides. Notez que votre contact doit utiliser la dernière version d'Olvid.
- Une notification utilisateur est affichée quand un contact réagit à l'un de vos messages.
- Ajoute le support pour le format de photos HEIC.
- Le processus d'onboarding est maintenant compatible avec la plupart des MDM.
- Mise à jour du design des écrans de création de groupes de discussion.
- Corrige des problèmes relatifs aux réactions sur des messages éphémères.
- Il est maintenant beaucoup plus facile de supprimer l'une de ses réactions à un message.
- Si l'on reçoit un appel alors qu'on est en train d'enregistrer un message vocal, l'enregistrement s'arrête et est sauvé en pièce jointe du brouillon.

## [0.9.17 (484)] - 2022-01-10

- Corrige une potentielle « timing attack » cryptographique concernant la multiplication scalaire sur les courbes elliptiques (mille merci à Ryad Benadjila de nous l'avoir remontée !).
- Il est maintenant possible de configurer l'émoji rapide de la nouvelle vue de composition de messages.
- Améliore la fluidité du nouvel écran de discussion.
- Étant donné que Olvid ne supportera bientôt plus iOS 11 et 12, une nouvelle alerte préviens les utilisateurs d'anciennes versions d'iOS qu'ils devraient mettre à jour vers la dernière version.

## [0.9.16 (479)] - 2022-01-04

- Corrige un problème important pour nous utilisateurs sous iOS12. Olvid démarre à nouveau !
- Devrait corriger un problème occasionnel empêchant certains messages d'être marqués comme « lu ».

## [0.9.15 (477)] - 2021-12-27

- Il est possible de réagir individuellement à un message. Pour tester, faire un double tap sur un message ;-)
- L'ordre des boutons de la nouvelle vue de composition peut être modifié.
- Les sauvegardes incluent maintenant certaines données côté application (pseudos des contacts, paramètres des discussions et paramètres globaux).
- Meilleure intégration du clavier Bitmoji.
- L'écran de parametrage des sauvegardes a été amélioré.
- Lorsque l'on enregistre un très long message audio, l'écran ne s'éteint plus.
- Pour nos utilisateurs pros, révocation keycloak, nouvelle vue affichant les détails techniques d'un contact, et meilleure recherche keycloak.
- Onboarding simplifié.
- Meilleures expériences des appels sécurisés quand le destinataire d'un appel n'a pas encore accordé à Olvid le droit d'accéder au micro.
- Améliorations apportées aux sauvegardes automatiques : on peut lister toutes les sauvegardes iCloud et supprimer les plus anciennes.
- Corrige un problème concernant les messages éphémères, et autres corrections de bugs.

## [0.9.14 (468)] - 2021-12-06

- Corrige un bug empêchant l'ouverture automatique de messages avec une existence limitée.
- Corrige un bug laissant apparaître, dans la liste de discussions, de l'information sur des messages expirés.
- Corrige un bug concernant les indicateurs d'éphéméralité dans la nouvelle vue de discussion (iOS 15).
- Les messages effacés à distance apparaissent maintenant plus clairement dans la nouvelle vue de discussion (iOS 15).

## [0.9.13 (462)] - 2021-12-02

- Dans la nouvelle vue de discussion (disponible sous iOS 15), un crayon montre clairement quels sont les messages qui ont été édités.
- Meilleure expérience utilisateur si, au moment de souscrire aux options, le moyen de paiement n'est pas accessible.
- Meilleur design de l'écran permettant d'ajouter un contact (pour nos utilisateurs de l'annuaire d'entreprise).
- Corrige un bug empêchant de voir une version agrandie de la photo de ses conctacts.
- Le cercle à côté du nom d'un contact ne prenait pas en compte le pseudo pour déterminer la bonne initiale à afficher. C'est corrigé.
- Corrige un crash potentiel au moment de la navigation vers un « deep link » juste après un retour dans l'app.
- Corrige un problème relatif aux messages éphémères : le message statique n'était pas toujours supprimé à la fin d'une période d'existence.
- Corrige un problème relatif aux messages éphémères : lorsque la lecture automatique était activée, elle était aussi appliquée aux messages dont l'éphéméralité était plus restrictive que celle de la discussion.
- La paramètre de lecture automatique disponible au niveau de l'app n'était pas pris en compte. C'est corrigé.
- Les accusés de lecture n'étaient pas toujours envoyés lorsque le paramètre de lecture automatique était activé. C'est corrigé.
- Corrige un problème de la nouvelle vue de composition : après avoir attaché une pièce jointe, il était possible d'envoyer un emoji pouce en appuyant très rapidement sur le bouton « envoyer ». C'est corrigé.
- Corrige un problème concernant le message système indiquant le nombre de nouveaux messages dans une discussion : au sortir de la discussion, il est maintenant bien mis à jour.
- Corrige sans doute un bug pouvant entraîner un crash occasionnel en arrière-plan.
- Corrige un problème de performance à l'affichage d'un message contenant beaucoup (disons, plus de 60) images.
- Corrige un bug mineur concernant les appels.

## [0.9.12 (457)] - 2021-11-16

- Les appels multiples sont disponibles ! Appelez un contact et ajoutez-en un autre pendant l'appel. Ou appeler tout un groupe en une fois !
- En plus du pseudo, il est maintenant possible d'ajouter une photo de profil personnalisée à n'importe quel contact.
- À la réception d'un appel, Olvid vérifie si elle a le droit d'accéder au micro. Si ce n'est pas le cas, l'appel échoue et une notification est affichée à l'utilisateur.
- Il est possible de lister et de nettoyer toutes les sauvegardes iCloud, directement depuis l'écran de paramétrage des sauvegardes.
- Il est possible de faire une sauvegarde manuelle vers iCloud, même si les sauvegardes automatiques sont désactivées.
- La nouvelle vue de discussion est disponible sous iPadOS 15.
- La nouvelle vue de composition (disponible sous iOS 15) a évolué ! Elle s'adapte maintenant automatiquement à toutes les tailles d'écran et de polices de caractères.
- Il est possible de présenter un contact à un autre, directement depuis le nouvel écran de discussion (sous iOS 15).
- Les paramètres au sein d'Olvid sont accessibles depuis tous les tabs.
- De nouvelles alertes permettent d'alerter l'utilisateur à propos des sauvegardes.
- Un indicateur de message manqué permet de savoir qu'un message (précédant celui que l'on est en train de lire) est sur le point d'arriver.
- Il est possible de rappeler un contact directement depuis la notification d'appel.
- Il est maintenant plus facile d'appuyer correctement sur les messages de type « appuyer-pour-voir » ;-)
- Corrige de nombreux problèmes liés aux messages éphémères nécessitant une interaction utilisateur pour être lus et aux paramètre de lecture automatique.
- Corrige un problème empêchant parfois les utilisateurs sous iOS 13 et 14 de recevoir des appels.

## [0.9.11 (445)] - 2021-10-13

- Cette nouvelle version d'Olvid est l'une des plus importantes depuis son lancement !
- Nouvelle façon d'ajouter un contact, via un scan mutuel de code QR ! 5 secondes suffisent pour ajouter un proche, un ami ou un collègue à ses contacts Olvid. Il faut juste s'assurer que votre futur contact a bien la dernière version d'Olvid ;-)
- Nouvelle vue de messages totalement redesignée pour nos utilisateurs sous iOS15.
- Enfin, les gifs animés sont, comment dire, animés ;-) Directement dans la nouvelle vue de discussion. Et pour en ajouter un, c'est facile : copiez le depuis n'importe où, et collez-le directement dans la barre de composition. Et hop, ça marche.
- Nouvelle fonctionnalité de message audio. Oui, enfin !
- Nouvelle façon de répondre à un message via un « glissé » du message auquel on souhaite répondre.
- Il est maintenant possible de choisir une politique d'auto-destruction d'un message particulier, directement depuis la nouvelle barre de composition de la nouvelle vue de discussion.
- Les notifications de nouveau message changent de look ! Et c'est encore mieux qu'avant.
- Lorsque l'on télécharge un message avec des photos, des miniatures basse résolution sont immédiatement disponibles, jusqu'à ce que la version haute résolution soit téléchargée. Notez que votre contact doit avoir la dernière version d'Olvid pour que cela fonctionne chez vous.
- Il est possible de rendre silencieuses les notifications d'une discussion particulière. C'est vous qui choisissez : une heure, 8 heures, 7 jours, ou pour toujours.
- Meilleure expérience de la partie création de groupes.
- Une recherche dans vos contacts Olvid considère aussi le pseudo.
- Meilleure fiabilité de l'édition de messages envoyés.
- Meilleure fiabilité des fonctionnalités entreprise.
- Plusieurs améliorations concernant la stabilité.
- Autres améliorations mineures.

## [0.9.10 (424)] - 2021-09-21

- Corrections de bugs

## [0.9.9 (385)] - 2021-07-24

- Lorsque Olvid est en cours d'utilisation, les messages arrivent encore plus vite qu'avant.
- Le téléchargement de pièces jointes est plus efficace et stable, surtout si le nombre de pièces jointes simultanées est important.
- La création de canal sécurisé est plus robuste et arrive à son terme même si aucun des participants ne lance Olvid.
- Corrige un bug qui empêchait parfois de recevoir une notification de nouveau message.
- Meilleure expérience utilisateur pour les appels sécurisés. En particulier, les appels ne devraient plus quitter en cas de mauvaise connexion ou lorsque l'on change de réseau.
- Nouveau design de l'écran d'appels sécurisés.
- La latence des appels sécurisés a été largement réduite.
- Corrige les problèmes de reconnexion pendant les appels sécurisés.
- Corrige un bug en lien avec les titres des discussions.
- Autres corrections et améliorations mineures.

## [0.9.8 (370)] - 2021-06-04

- Dans certaines circonstances, il n'était plus possible de recevoir des appels sécurisés. C'est corrigé.
- Olvid est plus robuste qu'avant lorsqu'il s'agit de télécharger beaucoup de pièces jointes en parallèle.

## [0.9.7 (368)] - 2021-05-20

- Corrections de bugs

## [0.9.6 (366)] - 2021-05-18

- Il est maintenant possible de changer l'ordre de tri des contacts.
- Toucher la photo de profil d'un contact affiche une version agrandie de la photo.
- Bienvenue à la compatibilité avec les annuaires d'entreprise et les fédérateurs d'identités !
- Les suppressions et éditions à distance sont encore plus fiables.
- Meilleure suppression des répertoires temporaires.
- Des améliorations ont été apportées à la nouvelle procédure d'initialisation. Une barre de progression est affichée si une longue tâche doit être effectuée pendant une mise à jour d'Olvid.
- Répondre à un message ne contenant que des pièces jointes affiche un message appropriés au dessus du brouillon.
- Les messages systèmes des discussions de groupe affichent maintenant la date.
- De nouveaux messages systèmes permettent de suivre plus précisément les appels émis, aboutis, etc.
- Il n'est plus possible de répondre à un message à lecture unique s'il n'a pas été lu.
- Corrige un bug qui empêchait certains messages d'être marqués comme non lu.
- Les pièces jointes associées à un brouillon n'étaient pas immédiatement supprimées du disque après envoi ou suppression du brouillon. C'est corrigé.
- Corrige un bug concernant le temps accordé avant la prochaine authentification utilisateur.
- Autres améliorations mineures.

## [0.9.5 (356)] - 2021-04-26

- Deux nouvelles fonctionnalités très attendues ! Il est maintenant possible de modifier un message après l'avoir envoyé. Parfait pour corrigé un participe passé qui aurait dû être un infinitif. Mais ce n'est pas tout : il est maintenant possible de supprimer un message ou une discussion de manière globale.
- Nouveau paramètres disponibles pour les aficionados des messages éphémères ! Il est maintenant possible de définir des valeurs globales par défaut pour les paramètres « Ouverture automatique » et « Conserver une trace des messages éphémères envoyés ».
- Ajout d'un paramètre qui permet d'autoriser les claviers spéciaux.
- Si l'authentification biométrique n'a pas été activée par l'utilisateur, le paramètre dans Olvid affiche maintenant clairement que c'est le code PIN qui peut être utilisé.
- Meilleure présentation des messages éphémères.
- Redesign complet de la fiche contact sur iOS13+.
- Nettoyage immédiat et systématique des fichiers sur le disque après avoir supprimé un message ou un brouillon.
- Les accusés de réception et lecture sont plus robustes.
- La procédure d'onboarding permet de spécifier un serveur de distribution ainsi qu'une clé d'API.
- Corrige un bug qui empêchait la suppression de certains accusés de réception. Cela pouvait entraîner un ralentissement important d'Olvid au démarrage.
- Corrige un bug empêchant un affichage correct des paramètres sous iPad.
- Corrige l'ouverture intempestive de messages éphémères reçus dans une discussion en « Ouverture automatique », restée ouverte après avoir quitté Olvid.
- Autres corrections et améliorations mineures.

## [0.9.4 (348)] - 2021-03-15

- Les photos de profil arrivent sous iOS ! À la fois pour vous, vos contacts et les groupes.
- Nouveaux designs pour la liste des contacts ainsi que pour la liste des groupes sous iOS 13+.
- Un nouveau message système s'affiche en cas d'appel manqué.
- Meilleure expérience à l'onboarding.
- Corrige un bug qui empêchait certains messages d'être marqués comme « non lus ».
- Choisir un message pour y répondre remettait à zéro la zone de composition de message. C'est corrigé.
- Correction de quelques bugs et améliorations mineures.

## [0.9.3 (340)] - 2021-01-13

- Les messages qui s'auto-détruisent sont arrivés ! Vous pouvez choisir/mixer trois variantes :
- Parfum n.1 -> Lecture unique : Les messages et pièces jointes ne sont affichés qu'une seule fois. Ils sont supprimés au sortir de la discussion.
- Parfum n.2 -> Durée de visibilité : Les messages et pièces jointes sont affichés pour une durée limitée après avoir été lus.
- Parfum n.3 -> Durée d'existence : Les messages et pièces jointes sont automatiquement supprimés après une certaine durée, sur tous les téléphones.
- N'hésitez pas à jeter un œil à https://olvid.io/faq/ pour tout savoir.
- L'envoi de message est encore plus rapide qu'avant !
- Beaucoup moins de « Olvid requiert votre attention » ;-)
- Les notifications utilisateurs sont plus fiables.
- Les informations affichées pour un message envoyé ou reçu sont plus complètes.

## [0.9.2 (336)] - 2021-01-01

- Le message système indiquant le nombre de nouveaux messages est ré-affiché à chaque fois que l'on affiche une discussion. Cela permet de bien voir les nouveaux messages même si Olvid avait été quittée alors qu'on était dans une discussion.
- Corrige un bug touchant la politique de rétention lorsqu'elle est basée sur le nombre de messages d'une discussion. Ça devrait maintenant marché comme attendu.

## [0.9.1 (334)] - 2020-12-30

- Vous nous le demandiez depuis un certain temps... l'effacement local automatique des messages est arrivé ! Vous pouvez combiner deux politiques: une basée sur le nombre maximum de messages dans la discussion, l'autre sur leur âge. Parfait pour effacer les messages que vous ne regarderez plus.
- Dans le premier cas, vous fixez le nombre de messages à garder par discussion.
- Dans le deuxième, vous fixez la durée de vie des messages. Dans les deux cas, Olvid effectuera un effacement automatique.
- Bien entendu, vous pouvez spécifier une politique globale, appliquée par défaut à toutes les discussions, puis choisir une politique particulière par discussion.
- Entrer dans une discussion fait (enfin) apparaître le premier nouveau message. À chaque fois.
- Nouveau design de l'écran d'informations concernant un message envoyé.
- L'indicateur de nouveaux messages affiché dans une discussion est automatiquement mis à jour si vous supprimez un des nouveaux messages.
- Les messages systèmes (comme par exemple celui qui s'affiche lorsque vous manquez un appel) peuvent être supprimés, comme n'importe quel autre message.
- Les extraits affichés pour chaque discussion dans la liste des discussions sont beaucoup plus informatifs.
- La mise a jour précédente avait introduit un bug empêchant l'affichage de certaines informations concernant un message envoyé dans un groupe. C'est corrigé.
- Corrige un bug introduit par la mise à jour précédente qui entraînait parfois l'affichage de messages « vides » dans les discussions. C'est corrigé.
- Moins de notifications du type « Olvid requiert votre attention » ;-)
- Corrige un bug qui pouvait empêcher le son de sonnerie en émission d'appel sécurisé.
- Corrige le texte d'un dialogue qui proposait de toucher un bouton orange qui n'existe plus.
- Corrige un bug qui empêchait certains messages d'être affichés comme « nouveaux » quand on quittait Olvid alors qu'on était sur l'écran de discussion.

## [0.9.0 (328)] - 2020-12-16

- En préparation de la version spéciale de Noël ;-)
- Mises à jours mineures concernant les appels sécurisés.
- Correction de quelques bugs et améliorations mineures.

## [0.8.13 (324)] - 2020-12-01

- Correction de quelques bugs et améliorations mineures.

## [0.8.12 (322)] - 2020-11-15

- La restauration de backup ainsi que la vérification de clés de sauvegarde sont beaucoup plus robustes.
- Corrige un bug entraînant la création d'un titre erroné pour une discussion « one-to-one » avec un contact ayant un pseudo.
- Corrige des problèmes liés à la sonnerie au moment de l'émission d'un appel sécurisé.
- Corrige un problème pouvant entraîner l'arrêt prématuré d'un appel sécurisé en cours.
- Après être passé d'une oreillette Bluetooth au haut-parleur interne pendant un appel sécurisé, il n'était plus possible de réactiver l'oreillette. C'est corrigé.
- Toucher un lien d'invitation ou de configuration dans une discussion n'ouvre plus Safari mais navigue directement vers l'écran approprié dans Olvid.

## [0.8.11 (312)] - 2020-11-06

- La procédure d'établissement d'un appel sécurisé est plus robuste.
- Bienvenue aux achats in-app des fonctionnalités premium.
- Il est maintenant possible de demander une période d'essai des fonctionnalités premium.
- L'écran d'invitation s'affiche maintenant correctement sous iPhone SE (2016).
- Correction de l'écran « Mon Id » (et autres) pour que tout se passe bien en mode paysage.
- Plusieurs améliorations visuelles, y compris une nouvelle palette de couleurs et une meilleure disposition pour les écrans plus petits.

## [0.8.10 (298)] - 2020-10-26

- La page « Mon Id » a été complètement repensée ! Elle est non seulement bien plus élégante, mais elle affiche plus d'informations.
- La page d'édition de votre Id a elle aussi été repensée !
- On peut maintenant partager des éléments issus de l'application Wallet
- Le processus de création de canal sécurisé est bien plus robuste qu'avant.
- Plusieurs petites corrections au niveau des écrans d'invitation. Les utilisateurs sous iOS 13 ne devraient plus rencontrer de problème.
- La version précédente avait introduit un bug empêchant certains utilisateurs sous iOS 13 d'envoyer des vidéos. C'est corrigé.
- La version précédente avait introduit un bug empêchant de partager des cartes VCF. C'est corrigé.
- Corrige les problèmes rencontrés pendant la sélection de photos/vidéos sous iOS 14.

## [0.8.9 (296)] - 2020-10-21

- On peut maintenant partager *n'importe* quel type de fichier. Peu importe le type. Peu importe la taille.
- Corrige les problèmes rencontrés pendant la sélection de photos/vidéos sous iOS 14.

## [0.8.8 (292)] - 2020-10-16

- Il est maintenant possible de présenter un contact à plusieurs contacts d'un seul coup !
- Un tap sur un code QR agrandit le code.
- Corrige un bug qui empêchait parfois l'export manuel d'une sauvegarde.

## [0.8.7 (290)] - 2020-10-10

- Bienvenue à la nouvelle procédure d'invitation ! Inviter un contact est super intuitif maintenant. Appuyez simplement sur le bouton « + » au centre et laissez-vous guider !
- Corrige un bug qui empêchait l'affichage du bouton d'activation des notifications utilisateur dans les paramètres d'Olvid.

## [0.8.6 (283)] - 2020-10-05

- Nouveau « picker » de photos/vidéos sous iOS 14. On peut maintenant choisir plusieurs photos/vidéos à la fois !
- Quand on passe un appel, une sonnerie prévient que le téléphone du contact est en train de sonner.
- Nouveau design pour la vue d'appel ! L'expérience visuelle bien meilleure sous iOS 14 qu'avant.
- Meilleure gestion du mode « ne pas déranger ».
- Il est maintenant possible de recevoir un appel alors qu'un autre appel est en cours : on peut alors rejeter l'appel entrant, ou raccrocher le précédent pour accepter le nouveau.
- La nouvelle vue d'appel affiche l'indicateur de « micro coupé » du correspondant pendant un appel.
- Si les sauvegardes automatiques sont activées, changer sa clé de sauvegarde entraîne immédiatement une nouvelle sauvegarde.
- À partir d'aujourd'hui, les entrées de bases de données supprimées le sont de manière « sûre ».
- La suppression de contact entraîne la suppression des « tentatives » existantes d'envoi des messages à ce contact. Ceci implique que, si ce contact fait partie d'un groupe auquel on a envoyé un message alors qu'on n'avait pas de canal établi avec ce contact, la suppression du contact entraîne l'affichage du picto « envoyé » sur le message en question. Tout simple.
- Amélioration du bandeau affiché au sommet de l'écran quand on navigue dans l'app alors qu'un appel est en cours.
- Ajout d'une action rapide permettant d'accéder directement au scanner de code QR. Cette action est accessible directement depuis l'icône de l'app.
- Les appels entrants manqués sont maintenant indiqués dans la discussion appropriée.
- L'envoi de message dans un groupe est beaucoup plus robuste.
- Corrige un bug qui empêchait de voir la liste des contacts au moment de faire les présentations.
- L'indicateur de message « envoyé » a changé ! Un message est maintenant considéré comme « envoyé » seulement si le message et *toutes* ses pièces jointes ont été déposés sur le serveur, pour *tous* les destinataires (un seul dans les discussions « one to one », potentiellement plusieurs dans les discussions de groupe). En d'autres termes, l'indicateur « envoyé » n'est affiché qu'à l'instant où l'on peut éteindre son téléphone tout en étant certain que le message et ses pièces jointes seront bien réceptionnés.
- La suppression d'une discussion complète (et de tous ses messages et pièces jointes) fonctionne parfaitement.
- Les fichiers de pièces jointes sont parfaitement nettoyées à chaque démarrage d'Olvid.
- Supprimer un message envoyé alors que les pièces jointes ne sont pas totalement envoyées ne pose plus de problème chez le destinataire.

## [0.8.5 (276)] - 2020-09-07

- Grande nouvelle ! Il est maintenant possible de passer des appels téléphoniques chiffrés de bout-en-bout. Bienvenue aux appels téléphoniques les plus sûrs du monde !
- Veuillez noter que les appels téléphoniques ne sont possibles qu'entre des utilisateurs ayant la dernière version d'Olvid.
- Cette fonctionnalité est encore en cours de développement et est disponible en version bêta. Si vous rencontrez un bug, merci de nous faire un retour sur feedback@olvid.io.
- Pendant cette bêta, la fonctionnalité restera gratuite pour tous les utilisateurs d'Olvid. Une fois la bêta finie, l'émission d'appels nécessitera la souscription à un abonnement payant, mais tous les utilisateurs d'Olvid pourront encore recevoir des appels provenant d'utilisateurs abonnés.
- Ajout d'un bouton Aide/FAQ dans les paramètres.
- Correction: Un contact sélectionné pouvait apparaître comme désélectionné après un scroll (typique pendant la création d'un groupe). C'est corrigé.
- Corrige un bug (rare) qui pouvait forcer à recréer un canal pour recevoir des messages.
- Corrige un bug qui empêchait de partager du contenu via la « share extension » quand Face ID ou Touch ID était activé.
- Corrige un crash sous iOS 13.x (pour x plut petit que 4) qui arrivait à chaque déchiffrement de fichier.

## [0.8.4 (255)] - 2020-05-26

- Cette version inclut *d'énormes* améliorations concernant le téléchargement de photos, de vidéos et de fichiers!
- Le partage via Olvid est beaucoup plus robuste, même avec des fichiers de grande taille. Le partage n'est plus limité à de petits fichiers de 70Mo. Vous pouvez maintenant partager des fichiers de taille beaucoup plus importante. Oui, même un fichier de 500Mo passe comme une lettre à la poste ;-)
- Les barres de progression des téléchargements sont beaucoup plus précises. Elles sont aussi plus jolies !
- Le processus de création de canal sécurisé est beaucoup plus robuste.
- Olvid avait la fâcheuse tendance à ne pas supprimer assez rapidement certains fichiers temporaires (chiffrés) qui pouvaient s'accumuler et occuper de la place sur le disque, pour rien. C'est corrigé.
- Supprimer un message d'une discussion entraîne une suppression du contenu approprié des messages qui répondaient a ce message supprimé (si vous avez compris cette modification, bravo).
- Des améliorations en terme d'expérience et d'interface. En prime, quelques bugs supplémentaires ont été corrigés.
- Attention : cette nouvelle version comprends une réécriture importante de la couche réseau. N'hésitez pas à nous communiquer vos impressions et les bugs (sait-on jamais...) à feedback@olvid.io. Merci pour votre soutien !

## [0.8.3 (232)] - 2020-05-17

- Corrige un bug qui pouvait entraîner un crash lors d'un backup manuel sous iPad Pro.
- Corrige un bug qui pouvait entraîner un crash lors d'une seconde génération de clé de backup sous iPad Pro.

## [0.8.2 (228)] - 2020-04-20

- Les canaux sécurisés sont régulièrement mis-à-jour via un protocole de « full ratchet ».
- Corrige un bug qui empêchait d'activer et de désactiver Face ID ou Touch ID.
- Corrige un bug qui empêchait de modifier le paramètre global d'envoi d'accusés de lecture.
- Corrige un bug qui pouvait entraîner un crash d'Olvid au démarrage dans le cas où l'on venait juste de partager un document ou une photo.
- Des améliorations en terme d'expérience et d'interface.

## [0.8.1 (223)] - 2020-04-08

- Des améliorations ont été apportées aux champs permettant de taper sa clé de backup.
- Une confirmation est maintenant demandée avant de générer une nouvelle clé de backup.
- Corrige un bug empêchant de voir sa clé de backup en « dark mode ».
- Corrige un bug occasionnel qui empêche de sélectionner un fichier de backup dans iCloud au moment.

## [0.8.0 (220)] - 2020-04-06

- Les backups sont arrivés ! Vous pouvez maintenant faire des sauvegardes sécurisées de vos contacts de façon automatique ou manuelle.
- Allez dans le tab Paramètres, puis Backup. Générez votre clé de backup, notez la et gardez la en lieu sûr, activez les backups automatiques vers iCloud, et c'est bon ! Si vous préférez, vous pouvez aussi exporter le backup chiffré manuellement.

## [0.7.23 (213)] - 2020-03-26

- Olvid est prêt pour iOS 13.4 !
- La gestion des groupes est plus robuste.
- Meilleure gestion interne des pièces jointes.
- Correction de quelques bugs occasionnels.

## [0.7.22 (197)] - 2020-03-04

- Olvid force l'échange des chiffres dans les deux directions avant qu'un des deux contacts entre dans le carnet d'adresses de l'autre.
- Un administrateur de groupe ne pouvait pas retirer un membre s'il n'avait pas de canal sécurisé avec ce membre. C'est corrigé.
- Corrige un bug qui pouvait parfois entraîner un crash au moment de la suppression d'un utilisateur.
- Corrige un bug occasionnel sur les vignettes. Et ça corrige le fait qu'il était parfois impossible de visualiser un fichier.

## [0.7.21 (195)] - 2020-02-26

- Nouveau paramètre dans la section « Vie Privée », permettant de choisir entre trois niveaux de confidentialité pour le contenu des notifications.
- L'écran de démarrage a été retravaillé en mode light et dark.
- Meilleure gestion des notifications quand on est au sein d'Olvid.
- Corrige un bug qui empêchait de partager sous iOS 12 quand Touch ID était activé.
- Corrige un bug qui pouvait entraîner un crash au démarrage.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.20 (186)] - 2020-02-05

- Première implémentation de la fonction « Déposer » du Glisser-déposer sur iPad. Il est maintenant possible de faire du Glisser-déposer depuis une autre App directement vers une discussion, en déposant les pièces jointes dans la zone de saisie de message.
- Il possible de faire une recherche au moment de présenter un contact à un autre.
- Corrige un bug qui ouvrait Olvid de façon intempestive quand on tentait d'ouvrir un .docx depuis l'application Fichiers.
- Quelques améliorations graphiques.

## [0.7.19 (182)] - 2020-01-27

- Nouvelle icône pour l'App !
- Nouvel écran de démarrage pour l'App !
- Quelques améliorations graphiques pendant l'ajout/suppression de membres d'un groupe.
- Faire les présentations entre deux contacts pouvait, dans certaines situations rares, planter l'App. C'est corrigé.
- La stratégie d'envoi et de réception de messages et de pièces jointes en cas de mauvais réseau a été améliorée.

## [0.7.18 (178)] - 2020-01-20

- Olvid est maintenant disponible sous iPad 😎. C'est énorme !
- Les discussions affichent de belles prévisualisations des liens! Cette option est paramétrable de façon globale. Rendez-vous dans les paramètres de l'app, , dans « Discussions », puis « Prévisualisation des liens ». Ce paramètre global peut ensuite être modifié discussion par discussion.
- Olvid supporte maintenant la rotation de votre iPhone. Très pratique pour visualiser des photos et des vidéos dans les meilleures conditions.
- Le scanner de code QR d'identité est encore plus rapide qu'avant.
- Changement mineur : dans une discussion de groupe, le clavier apparaît uniquement s'il y a quelqu'un d'autre que vous dans le groupe.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.17 (155)] - 2019-11-26

- Olvid est maintenant compatible avec AirDrop ! Vous pouvez envoyer des fichiers directement depuis votre Mac vers Olvid. Si une discussion est déjà ouverte, les fichiers s'insèrent automatiquement dans la composition de nouveau message. Sinon, vous avez la possibilité de choisir la discussion appropriée.
- Améliore la fiabilité des accusés de réception et de lecture.
- Corrige un bug qui pouvait entraîner un crash systématique au démarrage.

## [0.7.16 (150)] - 2019-11-19

- Nouveau paramètre permettant de protéger Olvid via Face ID et/ou Touch ID et/ou code PIN, en fonction de ce qui est disponible sur votre iPhone.
- Vos conversations n'apparaissent plus lorsque vous passez d'une application à une autre.
- Il est maintenant possible de partager, en une fois, toutes les photos reçues dans un message.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.15 (144)] - 2019-11-10

- Correction des mises en page. Elles sont bien meilleures qu'avant, surtout sur de petits écrans.
- Corrige un bug qui pouvait empêcher l'envoi d'accusés de réception et de lecture.
- Corrige un bug d'animation sous iOS 13.2 lié à l'affichage du menu d'informations d'un message envoyé.
- Corrige un bug à l'origine d'un potentiel « gel » d'Olvid lorsqu'on transfère une pièce jointe d'une discussion vers une autre.

## [0.7.14 (140)] - 2019-10-28

- Bienvenue aux confirmations de réception sous iOS 13 ! Cette nouvelle fonctionnalité permet de savoir si un message envoyé a bien été distribué sur le téléphone de votre destinataire. Attention, ce ne sont *pas* des confirmations de lecture. Notez que ces confirmations ne fonctionnent que si votre destinataire a mis-à-jour Olvid.
- Bienvenue aux confirmations de lecture sous iOS 13 ! Cette nouvelle fonctionnalité permet de savoir si un message envoyé a bien été lu. À la différence des confirmations de réception, les confirmations de lecture sont désactivées par défaut. Ce paramètre peut être changé dans le tab « Paramètres ». Le comportement par défaut peut ensuite être modifié indépendemment dans chaque discussion.
- Lorsqu'on affiche une discussion, un tap sur le titre affiche (comme avant) les détails du contact ou du groupe. Un nouvel indicateur permet d'afficher les paramètres de la discussion. C'est là qu'il faut aller pour permettre l'envoi de confirmations de lecture pour cette discussion en particulier.
- Cette version d'Olvid permet de télécharger des fichiers encore plus efficacement, et de façon encore plus robuste.
- Bienvenue au WebSockets sous iOS 13 : Olvid est maintenant beaucoup plus rapide quand l'app est en cours d'utilisation.
- Corrige un bug qui empêchait certaines barres de progression de s'afficher sur les pièces jointes.
- Corrige les couleurs des écrans d'onboarding en mode dark sous iOS 13.
- Corrige un bug lié aux couleurs de l'onboarding sous iOS 12.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.12 (132)] - 2019-10-01

- On ne demandait pas systématiquement de confirmation avant d'ouvrir un lien dans Safari. C'est corrigé.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.11 (128)] - 2019-09-25

- De nouvelles vignettes pour les pièces jointes, encore meilleures sous iOS 13.
- Les problèmes d'animation à l'affichage d'une discussion sont réglés.
- Comme avant, faire un tap sur une notification de message permet d'arriver immédiatement dans la discussion. Seulement maintenant, les nouveaux messages s'affichent immédiatement. Fini l'attente !
- La recherche dans les contacts n'est plus sensible aux accents.
- À l'envoi d'une invitation par mail, le sujet est automatiquement rempli.
- L'inclusion de Memojis fonctionne correctement.
- Sous iOS 13, il est maintenant possible de scanner un document directement depuis une discussion.
- Les bugs liés à la migration sous iOS 13 sont réglés.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.9 (118)] - 2019-09-13

- Compatibilité complète avec iOS 13
- La palette de couleurs à changé. Olvid est prêt pour le « dark mode » sous iOS 13 !
- Nouveau visualisateur de pièce jointe dans Olvid ! Les images, films et pdf s'affichent bien mieux. Olvid peut maintenant prévisualiser d'autres types de fichiers, incluant les documents iWork, les documents Microsoft Office (Office ‘97 ou plus récent), les documents RTF, les documents CSV, and plus encore.
- Le nouveau visualisateur permet de naviguer à travers toutes les pièces jointes d'un message.
- Le tab Discussions propose 3 nouveaux boutons qui permettent d'afficher les discussions de 3 façons différentes : les dernières discussions en cours, les discussions en direct avec ses contacts (triées dans l'ordre alphabétique), et les discussions de groupe (triées dans l'ordre alphabétique).
- Sous iOS 13, l'écran d'une discussion peut être quitté en faisant un « pull down ». Cette technique est utilisée à différents endroits dans Olvid.
- On peut maintenant supprimer un contact depuis sa fiche contact, même si on est arrivé sur cette fiche depuis une discussion. Ceci est aussi corrigé pour les groupes de discussion.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.8 (108)] - 2019-07-26

- Les téléchargements de pièces jointes (en upload et download) sont beaucoup plus rapides ! Ils peuvent être interrompus définitivement à tout moment ou simplement mis en pause.
- Compatibilité avec les nouveaux liens d'invitation webs.
- Dans la vue de composition, faire un tap sur une pièce jointe suffit pour la supprimer. Une petite croix rouge du plus effet vient donc décorer chaque pièce jointe avant envoi.
- Il est possible de choisir Olvid comme destination de partage lorsqu'on est dans l'application « Contacts » de iOS.
- Les vidéos peuvent être partagées directement depuis le viewer interne de vidéos.
- Corrections et optimisations diverses.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.7 (103)] - 2019-07-18

- Cliquer sur le lien « Click here » sur une invitation web Olvid fonctionne maintenant correctement.
- Corrections et optimisations diverses.
- Des améliorations en terme d'expérience et d'interface.

## [0.7.6 (102)] - 2019-07-14

- Le premier écran de l'« on-boarding » affiche un texte explicatif qui dit clairement qu'aucune des données renseignées n'est transmise à Olvid.
- Il est maintenant possible de supprimer un contact !
- Il est maintenant possible d'envoyer/recevoir n'importe quel type de pièce jointe. Word, Zip, RTF, et tous les autres.
- L'expérience utilisateur pour partager des fichiers et du texte depuis Olvid a été revue complètement et est bien plus cohérente à travers toute l'app.
- Un nouveau menu "Avancé" permet de copier/coller son identité Olvid. Ce menu est accessible depuis les tabs "Contacts" et "Invitations", en tapant sur le bouton "Ajouter" en bas à droite de l'écran.
- Un tap sur une réponse permet de scroller directement au message en question (avec un effet au top).
- Un message explicatif s'affiche au début de toutes les nouvelles discussions et précise que tout est chiffré de bout-en-bout.
- Les cellules de message ont été complètement revues. De belles vignettes pour les photos, et des cellules plus descriptives pour les autres types de fichiers.
- Les photos sont maintenant affichées au sein des cellules de discussion. Dans le cas des discussions de groupe, on sait enfin qui a envoyé la photo ;-)
- Quand on présente un contact à un autre, un message de confirmation vient confirmer que l'invitation a bien été envoyée.
- Entrer dans un discussion entraîne un scroll automatique au premier message non lu.
- Bugfix : Les badges indiquant le nombre de messages non lus sont calculés correctement, et mis à jour comme on pourrait s'y attendre.
- Corrections et optimisations diverses.
- Des améliorations en terme d'expérience et d'interface.
