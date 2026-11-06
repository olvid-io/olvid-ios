#  Engine database migration from v68 to v69

## LinkBetweenProtocolInstances: Updated entity

-<attribute name="expectedChildStateRawId" attributeType="Integer 64" usesScalarValueType="YES"/>

Removed attribute. Does not prevent lightweight migration.

A parent protocol is now notified when its child reaches any final state, so the state it used to wait for is no
longer read. Pre-existing rows keep `messageToSendRawId`, which is all a parent still waiting on its child needs, so
dropping the column with its values loses nothing.

## Conclusion

A lightweight migration is sufficient.
