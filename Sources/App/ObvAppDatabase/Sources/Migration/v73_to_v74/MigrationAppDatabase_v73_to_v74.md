# App database migration from v73 to v74

## PersistedLocation: New entity

## PersistedMessage: Updated entity

+<attribute name="isLocation" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Added attribute with a default attribute, does not prevent lightweight migration.

## PersistedMessageReceived: Updated entity

+<relationship name="locationContinuousReceived" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="PersistedLocationContinuousReceived" inverseName="receivedMessages" inverseEntity="PersistedLocationContinuousReceived"/>
+<relationship name="locationOneShotReceived" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PersistedLocationOneShotReceived" inverseName="receivedMessage" inverseEntity="PersistedLocationOneShotReceived"/>

Adds two to-one optional relationships, does not prevent lightweight migration.

## PersistedMessageSent: Updated entity

+<relationship name="locationContinuousSent" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="PersistedLocationContinuousSent" inverseName="sentMessages" inverseEntity="PersistedLocationContinuousSent"/>
+<relationship name="locationOneShotSent" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PersistedLocationOneShotSent" inverseName="sentMessage" inverseEntity="PersistedLocationOneShotSent"/>

Adds two to-one optional relationships, does not prevent lightweight migration.

## PersistedObvContactDevice: Updated entity

+<relationship name="location" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PersistedLocationContinuousReceived" inverseName="contactDevice" inverseEntity="PersistedLocationContinuousReceived"/>

Adds one optional relationship, does not prevent lightweight migration.

## PersistedObvOwnedDevice

+<relationship name="location" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PersistedLocationContinuousSent" inverseName="ownedDevice" inverseEntity="PersistedLocationContinuousSent"/>

Adds one optional relationship, does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
