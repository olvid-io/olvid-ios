#  Engine database migration from v33 to v34

## ContactIdentity

+<attribute name="isForcefullyTrustedByUser" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
+<attribute name="isRevokedAsCompromised" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Non nillable attributes, but a default value is provided for each. This does not prevent a lightweight migration.


## KeycloakRevokedIdentity

New table. This does not prevent a lightweight migration.


## KeycloakServer

+<attribute name="latestRevocationListTimetamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
+<attribute name="rawPushTopics" optional="YES" attributeType="Binary"/>
+<attribute name="rawServerSignatureKey" optional="YES" attributeType="Binary"/>
+<attribute name="selfRevocationTestNonce" optional="YES" attributeType="String"/>

Nillable attributes. This does not prevent a lightweight migration.

 +<relationship name="revokedIdentities" toMany="YES" deletionRule="Cascade" destinationEntity="KeycloakRevokedIdentity" inverseName="keycloakServer" inverseEntity="KeycloakRevokedIdentity"/>

Relationship to the new table. This does not prevent a lightweight migration.


## Warning: ObvJWK serialization changed

This has an impact on the `rawServerSignatureKey` values stored within the `KeycloakServer` database. But since this is a new key, no problem.


## Conclusion

A lightweight migration is sufficient.
