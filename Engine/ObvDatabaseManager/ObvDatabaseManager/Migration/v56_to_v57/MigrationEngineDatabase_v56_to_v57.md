#  Engine database migration from v56 to v57

## ContactDevice: Updated entity

+<attribute name="latestChannelCreationPingTimestamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Adds an optional attribute. This does not prevent a lightweight migration.

+<relationship name="preKeyForContactDevice" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PreKeyForContactDevice" inverseName="contactDevice" inverseEntity="PreKeyForContactDevice"/>

Optional relationship, nil by default, which is ok. This does not prevent a lightweight migration.

## ContactIdentity

+<attribute name="rawWasContactRecentlyOnline" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
+<attribute name="serverTimestampOfLastContactDiscovery" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Adds a mandatory attribute, with a default value, and an optional attribute. This does not prevent a lightweight migration.

## InboxMessage

+<attribute name="rawExpectedContactForReProcessing" optional="YES" attributeType="Binary"/>

Adds an optional attribute. This does not prevent a lightweight migration.

## OwnedDevice

+<attribute name="latestChannelCreationPingTimestamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Adds an optional attribute. This does not prevent a lightweight migration.

+<relationship name="preKeyForRemoteOwnedDevice" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PreKeyForRemoteOwnedDevice" inverseName="remoteOwnedDevice" inverseEntity="PreKeyForRemoteOwnedDevice"/>
+<relationship name="preKeysForCurrentDevice" toMany="YES" deletionRule="Cascade" destinationEntity="PreKeyForCurrentOwnedDevice" inverseName="currentOwnedDevice" inverseEntity="PreKeyForCurrentOwnedDevice"/>

Adds an optional relationship, and a to-many relationship. This does not prevent a lightweight migration.

## PreKeyAbstract (and sub-entities PreKeyForContactDevice, PreKeyForCurrentOwnedDevice, PreKeyForRemoteOwnedDevice)

Adds new entities. This does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
