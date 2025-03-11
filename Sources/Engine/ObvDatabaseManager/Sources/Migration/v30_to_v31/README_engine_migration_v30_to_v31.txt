ENGINE DATABASE
---------------

In produnction: v30
In development: v31

----
ContactIdentity
+<attribute name="isCertifiedByOwnKeycloak" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

This new attribute must be set to "false" during migration.

---
GroupServerUserData
-<attribute name="groupDetailsVersion" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>

Removing this attribute requires no particular action during migration.

---
IdentityServerUserData
-<attribute name="ownedIdentityDetailsVersion" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>

Removing this attribute requires no particular action during migration.

---
KeycloakServer

This new table requires no action

---
OwnedIdentity

-<relationship name="latestIdentityDetails" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="OwnedIdentityDetailsLatest" inverseName="ownedIdentity" inverseEntity="OwnedIdentityDetailsLatest"/>
+<relationship name="keycloakServer" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="KeycloakServer" inverseName="managedOwnedIdentity" inverseEntity="KeycloakServer"/>

No action required

---
OwnedIdentityDetails and OwnedIdentityDetailsLatest

Thes tables are deleted, this requires no action during migration

---
OwnedIdentityDetailsPublished

This table used to be a sub-entity of OwnedIdentityDetails. This is no longer the case. This requires no action  during migration
All the attributes that were defined in the OwnedIdentityDetails table are now defined in this OwnedIdentityDetailsPublished table. Nothing to migrate here.

---
PersistedTrustOrigin
<attribute name="identityServer" optional="YES" attributeType="String"/> --> <attribute name="identityServer" optional="YES" attributeType="URI"/>

The type changes from String to URI. Since we can drop all entries, and since the argument is optional, we will drop all attribute values (we expect none anyway).
