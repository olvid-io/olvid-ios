Several constraints were added on the v20 version of the model wrt to the v19.
For this reason, the migration process from v19 to v20 must enforce these constraints in code. Otherwise, the migration
would fail if any of these constraints is not natively satisfied. Here, we list the strategy adopted within the migration process.


## PersistedObvOwnedIdentity - ok
none --> identity
Validation strategy: We assume that there is only one owned identity per device, so we do nothing.


## PersistedObvContactIdentity - ok
none --> rawOwnedIdentityIdentity,identity
Validation strategy: None, we assume this does not happen.

## Fyle - ok
none --> sha256
Validation strategy: Delete the Fyle within the *source* context that have duplicated sha256.


## PersistedContactGroup - ok
none --> rawOwnedIdentityIdentity, ownerIdentity, groupUidRaw
Validation strategy: None, we assume this does not happen. It would be very hard and error prone to do it right.


## PersistedObvContactDevice - ok
none --> rawIdentityIdentity,identifier
Validation strategy: We delete any duplicate on the identifier only.


## PersistedPendingGroupMember
none --> identity,rawOwnedIdentityIdentity,rawGroupOwnerIdentity,rawGroupUidRaw
Validation strategy: None, we assume this does not happen. It would force to introduce several failable methods.
