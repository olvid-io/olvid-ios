#  Engine database migration from v40 to v41

## PendingServerQuery - Modified serialization

This is tricky as we modified certain serializations of the server queries. The following queries were modified:
- putUserData
- getUserData
The raw values did not change. The label was a String, it is now an UID. See the ServerQuery.swift file for more details.

## ContactGroupDetails - Modified entity

The photoServerLabel of type string becomes a rawPhotoServerLabel of type Data, that should be deserializable into an UID. We will implement a specific migration policy for this.

## ContactIdentityDetails - Modified entity

The photoServerLabel of type string becomes a rawPhotoServerLabel of type Data, that should be deserializable into an UID. We will implement a specific migration policy for this.


## OwnedIdentityDetailsPublished - Modified entity

The photoServerLabel of type string becomes a rawPhotoServerLabel of type Data, that should be deserializable into an UID. We will implement a specific migration policy for this.


## ContactIdentity - Modified entity

Adds a mandatory 'ownedIdentityIdentity' attribute. This prevents a lightweight migration. Since the 'ownedIdentity' relationship is not optional, we can rely on it to populate this new attribute.

New to-many groupMemberships relationship. Nothing to do here.


## ServerUserData - Modified entity

The label attribute of type String becomes is replaced by the rawLabel attribute of type Binary. This requires heavyweight migration.


## OwnedIdentity - Modified entity

Adds a to-many contactGroupsV2 relationship, nothing to do here.


## PersistedTrustOrigin - Modified entity

Adds a 'PersistedTrustOrigin' attribute. It is optional, nothing to do here.


## ContactGroupV2, ContactGroupV2Details, ContactGroupV2Member, ContactGroupV2PendingMember, GroupV2SignatureReceived - New entities

New entities, nothing to do during migration


## Conclusion

A heavyweight migration is mandatory.
