#  Engine database migration from v67 to v68

## InboxMessage: Updated entity

+<attribute name="deletedFromServer" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Added mandatory attribute, with a default value. Does not prevent lightweight migration.

The default value of `NO` is the correct value for every pre-existing row: before this version, we never
requested the deletion of a message from the server before the app was done with it.

## Conclusion

A lightweight migration is sufficient.
