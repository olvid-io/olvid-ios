ENGINE DATABASE
---------------

En prod: v28
En dev: v29

InboxMessage
+<attribute name="localDownloadTimestamp" attributeType="Date" usesScalarValueType="NO"/>
Requires migration ? Yes. But a simple one as we can copy another timestamp: $source.downloadTimestampFromServer


2 tables used within protocols

+TrustEstablishmentCommitmentReceived
No migration needed

+ChannelCreationPingSignatureReceived
No migration needed


Adds 3 tables for managing identity/group server user data (such as profile pictures)

ContactIdentityDetails
+photoServerKeyEncoded, nillable, was in ContactIdentityDetailsPublished, now moved to ContactIdentityDetails
+photoServerLabel, nillable, was in ContactIdentityDetailsPublished, now moved to ContactIdentityDetails
No migration needed for ContactIdentityDetailsPublished. But we want to copy those values (if non nil) to ContactIdentityDetailsTrusted. This requires a manual migration.

ContactIdentityDetailsPublished
-photoServerKeyEncoded, moved to ContactIdentityDetails
-photoServerLabel, moved to ContactIdentityDetails

+ServerUserData abstract
+<attribute name="label" optional="YES" attributeType="String"/> (not optional)
+<attribute name="nextRefreshTimestamp" attributeType="Date" usesScalarValueType="NO"/>
+<attribute name="ownedIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/> (Warning: We won't use a transformer)
No migration needed

+GroupServerUserData (ServerUserData subclass)
+<attribute name="groupDetailsVersion" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
+<attribute name="groupUid" attributeType="Transformable" valueTransformerName="UIDTransformer" customClassName="UID"/> (Warning: We won't use a transformer)
No migration needed

+IdentityServerUserData (ServerUserData subclass)
+<attribute name="ownedIdentityDetailsVersion" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
No migration needed
