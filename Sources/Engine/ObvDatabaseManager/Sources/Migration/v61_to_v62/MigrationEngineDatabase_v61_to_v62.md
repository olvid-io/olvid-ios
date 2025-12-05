#  Engine database migration from v61 to v62

## ChannelCreationWithContactDeviceProtocolInstance: Updated entity

-<attribute name="contactDeviceUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawContactDeviceUid" attributeType="Binary"/>

-<attribute name="contactIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawContactIdentity" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* contactDeviceUid (UID) --> rawContactDeviceUid (Binary)
* contactIdentity (ObvCryptoIdentity) --> rawContactIdentity (Binary)



## ContactDevice: Updated entity

-<attribute name="uid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawUID" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* uid (UID) --> rawUID (Binary)



## ContactGroup (ContactGroupJoined, ContactGroupOwned): Updated entity

-<attribute name="groupUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawGroupUid" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* groupUid (UID) --> rawGroupUid (Binary)



## InboxMessage: Updated entity

-<attribute name="rawEncryptedContent" attributeType="Binary" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>
+<attribute name="rawEncryptedContent" attributeType="Binary"/>

-<attribute name="rawFromIdentity" optional="YES" attributeType="Binary" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawFromIdentity" optional="YES" attributeType="Binary"/>

-<attribute name="rawMessageIdOwnedIdentity" attributeType="Binary" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawMessageIdOwnedIdentity" attributeType="Binary"/>

-<attribute name="rawMessageIdUid" attributeType="Binary" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawMessageIdUid" attributeType="Binary"/>

-<attribute name="rawWrappedKey" attributeType="Binary" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>
+<attribute name="rawWrappedKey" attributeType="Binary"/>

Nothing to migrate.



## KeyMaterial: Updated entity

-<attribute name="cryptoKeyId" attributeType="Binary"/>
+<attribute name="rawCryptoKeyId" attributeType="Binary"/>

Renamed attribute.



## LinkBetweenProtocolInstances: Updated entity

-<attribute name="childProtocolInstanceUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawChildProtocolInstanceUid" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* childProtocolInstanceUid (UID) --> rawChildProtocolInstanceUid (Binary)



## MessageHeader: Updated entity

-<attribute name="deviceUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawDeviceUid" attributeType="Binary"/>

-<attribute name="toCryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawToCryptoIdentity" attributeType="Binary"/>

-<attribute name="wrappedKey" attributeType="Transformable" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>
+<attribute name="rawWrappedKey" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* deviceUid (UID) --> rawDeviceUid (Binary)
* toCryptoIdentity (ObvCryptoIdentity) --> rawToCryptoIdentity (Binary)
* wrappedKey (EncryptedData) --> rawWrappedKey (Binary)



## ObvObliviousChannel: Updated entity

-<attribute name="currentDeviceUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawCurrentDeviceUID" attributeType="Binary"/>

-<attribute name="remoteCryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawRemoteCryptoId" attributeType="Binary"/>

-<attribute name="remoteDeviceUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawRemoteDeviceUID" attributeType="Binary"/>

-<attribute name="seedForNextSendKey" optional="YES" attributeType="Transformable" valueTransformerName="SeedTransformer" customClassName="Seed"/>
+<attribute name="rawSeedForNextSendKey" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* currentDeviceUid (UID) --> rawCurrentDeviceUID (Binary)
* remoteCryptoIdentity (ObvCryptoIdentity) --> rawRemoteCryptoId (Binary)
* remoteDeviceUid (UID) -->  rawRemoteDeviceUID (Binary)
* seedForNextSendKey (Seed, optional) --> rawSeedForNextSendKey (Binary)



## OutboxAttachmentChunk: Updated entity

-<attribute name="dummyVariableForMigration" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>

Removed attribute.



## OutboxMessage: Updated entity

-<attribute name="encryptedContent" attributeType="Transformable" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>
+<attribute name="rawEncryptedContent" attributeType="Binary"/>

-<attribute name="rawMessageIdOwnedIdentity" attributeType="Binary" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawMessageIdOwnedIdentity" attributeType="Binary"/>

-<attribute name="rawMessageUidFromServer" optional="YES" attributeType="Binary" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawMessageUidFromServer" optional="YES" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* encryptedContent (EncryptedData) --> rawEncryptedContent (Binary)

The other attributes require no migration.



## OwnedDevice: Updated entity

-<attribute name="uid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawUID" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* uid (UID) --> rawUID (Binary)



## OwnedIdentity: Updated entity

-<attribute name="cryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawCryptoIdentity" attributeType="Binary"/>

-<attribute name="ownedCryptoIdentity" attributeType="Transformable" valueTransformerName="ObvOwnedCryptoIdentityTransformer" customClassName="ObvOwnedCryptoIdentity"/>
+<attribute name="rawOwnedCryptoIdentity" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* cryptoIdentity (ObvCryptoIdentity) --> rawCryptoIdentity (Binary)
* ownedCryptoIdentity (ObvOwnedCryptoIdentity) --> rawOwnedCryptoIdentity (Binary)



## OwnedIdentityMaskingUID: Updated entity

-<attribute name="maskingUID" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawMaskingUID" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* maskingUID (UID) --> rawMaskingUID (Binary)



## PendingGroupMember: Updated entity

-<attribute name="cryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawCryptoIdentity" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* cryptoIdentity (ObvCryptoIdentity) --> rawCryptoIdentity (Binary)



## PendingServerQuery: Updated entity

-<attribute name="rawOwnedIdentity" attributeType="Binary" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawOwnedIdentity" attributeType="Binary"/>

Nothing to migrate.



## PersistedEngineDialog: Updated entity

-<attribute name="encodedObvDialog" attributeType="Transformable" valueTransformerName="ObvEncodedTransformer" customClassName="ObvEncoded"/>
+<attribute name="rawEncodedObvDialog" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* encodedObvDialog (ObvEncoded) --> rawEncodedObvDialog (Binary)



## PersistedTrustOrigin: Updated entity

-<attribute name="mediatorOrGroupOwnerCryptoIdentity" optional="YES" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawMediatorOrGroupOwnerCryptoIdentity" optional="YES" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* mediatorOrGroupOwnerCryptoIdentity (ObvCryptoIdentity, optional) --> rawMediatorOrGroupOwnerCryptoIdentity (Binary, optional)



## ProtocolInstance: Updated entity

-<attribute name="encodedCurrentState" attributeType="Transformable" valueTransformerName="ObvEncodedTransformer" customClassName="ObvEncoded"/>
+<attribute name="rawEncodedCurrentState" attributeType="Binary"/>

-<attribute name="ownedCryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawOwnedCryptoIdentity" attributeType="Binary"/>

-<attribute name="uid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawUID" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* encodedCurrentState (ObvEncoded) --> rawEncodedCurrentState (Binary)
* ownedCryptoIdentity (ObvCryptoIdentity) --> rawOwnedCryptoIdentity (Binary)
* uid (UID) --> rawUID (Binary)



## ProtocolInstanceWaitingForContactUpgradeToOneToOne: Updated entity

-<attribute name="contactCryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawContactCryptoIdentity" attributeType="Binary"/>

-<attribute name="ownedCryptoIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawOwnedCryptoIdentity" attributeType="Binary"/>

-<attribute name="messageToSendRawId" attributeType="Integer 64" valueTransformerName="UIDTransformer" usesScalarValueType="YES" customClassName="UID"/>
+<attribute name="messageToSendRawId" attributeType="Integer 64" usesScalarValueType="YES"/>

Updates attributes to remove the Transformable type:
* contactCryptoIdentity (ObvCryptoIdentity) --> rawContactCryptoIdentity (Binary)
* ownedCryptoIdentity (ObvCryptoIdentity) --> rawOwnedCryptoIdentity (Binary)

The other attributes require no migration.



## Provision: Updated entity

-<attribute name="seedForNextProvisionedReceiveKey" attributeType="Transformable" valueTransformerName="SeedTransformer" customClassName="Seed"/>
+<attribute name="rawSeedForNextProvisionedReceiveKey" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* seedForNextProvisionedReceiveKey (Seed) --> rawSeedForNextProvisionedReceiveKey (Binary)



## ReceivedMessage: Updated entity

-<attribute name="encodedEncodedInputs" attributeType="Transformable" valueTransformerName="ObvEncodedTransformer" customClassName="ObvEncoded"/>
+<attribute name="rawEncodedEncodedInputs" attributeType="Binary"/>

-<attribute name="encodedUserDialogResponse" optional="YES" attributeType="Transformable" valueTransformerName="ObvEncodedTransformer" customClassName="ObvEncoded"/>
+<attribute name="rawEncodedUserDialogResponse" optional="YES" attributeType="Binary"/>

-<attribute name="protocolInstanceUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/>
+<attribute name="rawProtocolInstanceUid" attributeType="Binary"/>

-<attribute name="receptionChannelInfo" attributeType="Binary"/>
+<attribute name="rawReceptionChannelInfo" attributeType="Binary"/>

Updates attributes to remove the Transformable type:
* encodedEncodedInputs (ObvEncoded) --> rawEncodedEncodedInputs (Binary)
* encodedUserDialogResponse (ObvEncoded, optional) --> rawEncodedUserDialogResponse (Binary, optional)
* protocolInstanceUid (UID) --> rawProtocolInstanceUid (Binary)

The other attributes require no migration.



## ServerSession: Updated entity

-<attribute name="rawOwnedCryptoId" attributeType="Binary" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawOwnedCryptoId" attributeType="Binary"/>

Nothing to migrate.



## Conclusion

A heavyweight migration is required.
