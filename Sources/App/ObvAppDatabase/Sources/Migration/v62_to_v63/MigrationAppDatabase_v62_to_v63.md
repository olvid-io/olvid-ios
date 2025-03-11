# App database migration from v62 to v63

## PersistedDiscussion - Updated entity

+<attribute name="isArchived" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Adds one attribute, with a default value. This does not prevent lightweight migration. Yet, setting the isArchived attribute to NO for all discussions would lead to a situation where all discussions would show in the list of recent discussions, since we now filter on this isArchived attribute (and show those that are not archived). So we need to perform a heavyweight migration to set this attribute to YES for all discussions that have no message (as this is the way we filter out discussions today).
This heavyweight will be "easy". We can rely on the mapping generated for all values and simply modify the isArchived if necessary.

## Conclusion

A heavyweight migration is necessary.
