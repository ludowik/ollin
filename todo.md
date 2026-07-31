L'implémentation de Ollin en C++ respecte les règles snake ? à 100 % ?

Syntaxe
- do end : bloc libre pour indentation
- enum Name A[=1],B,C end : création de constante dans un objet Name, le premier prend la valeur 1 par défaut, les suivants font +1. Forcer la valeur d'un item est possible =valeur, les suivants font +1

Optimisations :
math.noise : l'accès à une fonction d'un module builtin est résolu comment ?
possible de cacher à la compilation ou à l'exécution le lien entre math.noise et noise sans être obligé de le recalculer

Tutoriel / Samples : voxel_world
- lors des déplacements donner l'impression de fluidité mais pas de linéarite dans l'oeil de l'utilisateur...
	
Joystick
- en faire un objet du langage ?

Module graphics:
- Plan roundRect => rect mais avec des angles ronds. Nouvelle fonction ou paramètre optionnelle pour les angles ? 

Modules :
- UI : button, check box pour commencer, l'UI doit utiliser les fonctionnalités 
- Audio
- Video capture

Produire une version iPhone
Produire une version web client lourd
