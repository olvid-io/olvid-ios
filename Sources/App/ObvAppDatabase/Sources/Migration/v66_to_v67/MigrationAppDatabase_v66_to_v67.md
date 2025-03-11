# App database migration from v66 to v67


## ReceivedFyleMessageJoinWithStatus - Updated entity

-<attribute name="downsizedThumbnail" optional="YES" attributeType="Binary"/>

The value of this attribute to populate the same attribute in FyleMessageJoinWithStatus.
This is done automatically by the migration manager.


## FyleMessageJoinWithStatus - Modified entity

+<attribute name="downsizedThumbnail" optional="YES" attributeType="Binary"/>

Optional, does not prevent lightweight migration. We should use the value found in ReceivedFyleMessageJoinWithStatus.
This is done automatically by the migration manager.
And we deleted the attribute for the migration of SentFyleMessageJoinWithStatus entities as a nil value is appropriate.


## PendingMessageReaction - Deleted entity

We will drop the entries.


## PendingRepliedTo - Updated entity

We will drop the entries.


## PersistedContactGroup - Updated entity

+<attribute name="note" optional="YES" attributeType="String"/>

Optional attribute, that does not require any work.


## PersistedDiscussion - Updated entity

+<relationship name="remoteRequestsSavedForLater" toMany="YES" deletionRule="Cascade" destinationEntity="RemoteRequestSavedForLater" inverseName="discussion" inverseEntity="RemoteRequestSavedForLater"/>
-<relationship name="remoteDeleteAndEditRequests" toMany="YES" deletionRule="Cascade" destinationEntity="RemoteDeleteAndEditRequest" inverseName="discussion" inverseEntity="RemoteDeleteAndEditRequest"/>

No work to do.


## PersistedMessage - Updated entity

<relationship name="discussion" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="PersistedDiscussion" inverseName="messages" inverseEntity="PersistedDiscussion"/>

The discussion relationship is now optional (required to perform an efficient deletion)

+<relationship name="messageRepliedToIdentifier" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PendingRepliedTo" inverseName="message" inverseEntity="PendingRepliedTo"/>

We shall use the value found in `PersistedMessageReceived` if this message is actually a received one. This attribute is actually a PendingRepliedTo.
In practice, we delete the mapping from all PersistedMessage subclasses and create a simple custom policy for PersistedMessageReceived instances.


## PersistedMessageReceived - Updated entity

-<relationship name="messageRepliedToIdentifier" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PendingRepliedTo" inverseName="message" inverseEntity="PendingRepliedTo"/>

The value found, if any, must be set on the same attribute at the PersistedMessage level.
In practice, we won't do it (as we had to drop the PendingRepliedTo entries)


## PersistedMessageSent - Updated entity

+<attribute name="messageIdentifierFromEngine" optional="YES" attributeType="Binary"/>

Requires no work as this is used for messages sent from another owned device.

+<attribute name="senderThreadIdentifier" attributeType="UUID" usesScalarValueType="NO"/>

We must copy the value found in the senderThreadIdentifier attribute of the associated discussion.
This is the case because we know that all existing messages sent were sent from the current device.


## PersistedMessageSystem - Updated entity

+<attribute name="optionalOwnedIdentityIdentity" optional="YES" attributeType="Binary"/>

Nothing to do here (this is only used in new system messages).


## PersistedObvContactDevice - Updated entity

+<attribute name="rawSecureChannelStatus" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>

To be set to 1 (channel created). This value will by synced during bootstrap.


## PersistedObvContactIdentity - Updated entity

+<attribute name="atLeastOneDeviceAllowsThisContactToReceiveMessages" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>

To be set to true. This value will by synced during bootstrap.


## PersistedObvOwnedDevice - New entity

Nothing to do, this will be set during bootstrap.


## RemoteDeleteAndEditRequest - Deleted entity
## RemoteRequestSavedForLater - New entity

We won't try to migrate those entries.
