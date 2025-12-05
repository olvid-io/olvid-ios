#  Engine database migration from v62 to v63

## ObvObliviousChannel: Updated entity

-<attribute name="aFullRatchetOfTheSendSeedIsInProgress" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
+<attribute name="aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES" elementID="aFullRatchetOfTheSendSeedIsInProgress"/>

Renamed attribute. Since we specify an elementID in the destination model, this does not prevent a lightweight migration.

-<attribute name="numberOfDecryptedMessagesSinceLastFullRatchetSentMessage" attributeType="Integer 64" minValueString="0" defaultValueString="0" usesScalarValueType="YES"/>
-<attribute name="numberOfEncryptedMessagesSinceLastFullRatchetSentMessage" attributeType="Integer 64" minValueString="0" defaultValueString="0" usesScalarValueType="YES"/>

Dropped attributes. This does not prevent a lightweight migration.

-<attribute name="timestampOfLastFullRatchetSentMessage" attributeType="Date" usesScalarValueType="NO"/>
+<attribute name="timestampOfLastFullRatchetRequest" attributeType="Date" usesScalarValueType="NO" elementID="timestampOfLastFullRatchetSentMessage"/>

Renamed attribute. Since we specify an elementID in the destination model, this does not prevent a lightweight migration.


## ProtocolInstance: Updated entity

Adds new fetch indexes. This does not prevent a lightweight migration


## ReceivedMessage: Updated entity

Adds new fetch indexes. This does not prevent a lightweight migration


## Conclusion

A lightweight migration is sufficient.
