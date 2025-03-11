APP DATABASE
------------

En prod: v27
En dev: v28

PersistedContactGroup
+<attribute name="customPhoto" optional="YES" attributeType="URI"/>  ---> customPhotoURL
+<attribute name="photo" optional="YES" attributeType="URI"/> ---> photoURL
Nécessite code pour migration ? Non.


PersistedObvContactIdentity
+<attribute name="customPhoto" optional="YES" attributeType="URI"/> ---> customPhotoURL
+<attribute name="photo" optional="YES" attributeType="URI"/> ---> photoURL
+<attribute name="note" optional="YES" attributeType="String"/>
Nécessite code pour migration ? Non.

PersistedObvOwnedIdentity
+<attribute name="photo" optional="YES" attributeType="URI"/> ---> photoURL
Nécessite code pour migration ? Non.

PersistedDiscussionSharedConfiguration
Relation discussion devient optionnelle.
Nécessite code pour migration ? Pas clair. Probablement pas. À tester.
