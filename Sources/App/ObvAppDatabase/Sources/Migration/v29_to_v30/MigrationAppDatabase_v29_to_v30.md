APP DATABASE
------------

In production: v29
In development: v30

----
PersistedDiscussion
+<relationship name="remoteDeleteAndEditRequests" toMany="YES" deletionRule="Cascade" destinationEntity="RemoteDeleteAndEditRequest" inverseName="discussion" inverseEntity="RemoteDeleteAndEditRequest"/>

This to-many relationship points to a new table called RemoteDeleteAndEditRequest. During migration, we can safely do nothing.

---
PersistedDiscussionLocalConfiguration
+<attribute name="muteNotificationsEndDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

This optional value requires not particular action during migration.

----
PersistedObvContactIdentity
+<attribute name="isCertifiedByOwnKeycloak" attributeType="Boolean" usesScalarValueType="YES"/>

This new attribute must be set to "false" during migration.

---
PersistedObvOwnedIdentity
+<attribute name="isKeycloakManaged" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

This new attribute must be set to "false" during migration.

---
+RemoteDeleteAndEditRequest

New table that requires no action during migration.
