#  App database migration from v33 to v34


## PersistedObvContactIdentity

Change customPhotoURL: URL? into customPhotoFilename: String? since the photo is stored on app side only, we can only store the filename.

## PersistedContactGroup

Delete customPhotoURL: URL? to move it into PersistedContactGroupJoined. This field value was unused.

## PersistedContactGroupJoined

Add customPhotoFilename: String? that was customPhotoURL in PersistedContactGroup, since is make no sense to define customPhoto for PersistedContactGroupOwned.

See PersistedObvContactIdentity remark for String instead of URL.

## Conclusion

A lightweight migration is sufficient, since we didn't have value before.
