#  Engine database migration from v48 to v49


## ChannelCreationWithOwnedDeviceProtocolInstance - New entity

This does not prevent lightweight migration.


## ContactIdentity - Modified entity

-<attribute name="cryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawIdentity" attributeType="Binary"/>
+<attribute name="rawDateOfLastBootstrappedContactDeviceDiscovery" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

👉 This requires a heavyweight migration to transform the old cryptoIdentity attribute into the rawIdentity attribute.
The rawDateOfLastBootstrappedContactDeviceDiscovery is optional and requires no work.


## OwnedIdentity - Modified entity

-<attribute name="apiKey" attributeType="UUID" usesScalarValueType="NO"/>

👉 If set, this attribute should be copied into the ownAPIKey attribute of the associated KeycloakServer, if any.


## KeycloakServer - Modified entity

+<attribute name="ownAPIKey" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>

👉 Although the attribute is optional, we should set it with the value found in the associated owned identity, from the (deleted) apiKey attribute.


## OwnedDevice - Modified entity

+<attribute name="expirationDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
+<attribute name="latestRegistrationDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
+<attribute name="name" optional="YES" attributeType="String"/>

All attributes are optional and do not prevent lightweight migration.


## ProtocolInstance - Modified entity

+<relationship name="channelCreationWithRemoteOwnedDeviceInWaitingState" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="ChannelCreationWithOwnedDeviceProtocolInstance" inverseName="protocolInstance" inverseEntity="ChannelCreationWithOwnedDeviceProtocolInstance"/>

Nothing to do here.


## ServerPushNotification - Deleted entity

Nothing to do here. We drop the entries, they are now kept in memory.


## ServerSession - Modified entity

We can simply drop all entries.
