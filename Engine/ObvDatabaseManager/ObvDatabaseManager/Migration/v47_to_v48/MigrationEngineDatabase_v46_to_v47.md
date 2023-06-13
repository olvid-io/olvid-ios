#  Engine database migration from v47 to v48

## ContactGroupV2 - Modified entity

<attribute name="rawBlobMainSeed" optional="YES" attributeType="Binary"/>
<attribute name="rawBlobVersionSeed" optional="YES" attributeType="Binary"/>
<attribute name="rawVerifiedAdministratorsChain" optional="YES" attributeType="Binary"/>

Those attributes are now optional. This does not prevent lightweight migration.

+<attribute name="rawLastModificationTimestamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
+<attribute name="rawPushTopic" optional="YES" attributeType="String"/>
+<attribute name="serializedSharedSettings" optional="YES" attributeType="String"/>

New attributes, all optionals. This does not prevent lightweight migration.

## KeycloakServer - Modified entity

<attribute name="latestGroupUpdateTimestamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

New optional attribute. This does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
