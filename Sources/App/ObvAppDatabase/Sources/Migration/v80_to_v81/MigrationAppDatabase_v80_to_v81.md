# App database migration from v80 to v81

## PersistedMessageReceived

+<attribute name="isDeliveredReceiptSent" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
+<attribute name="isReadReceiptSentOrNotToBeSent" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>

Adds two attributes with default values. Does not prevent lightweight migration. Note that the default values are set to "true" to ensure we will never
send receipts for old messages. In the init of PersistedMessageReceived, they are set to false for new entries.

## ReceivedFyleMessageJoinWithStatus

+<attribute name="isDeliveredReceiptSent" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
+<attribute name="isReadReceiptSentOrNotToBeSent" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>

Adds two attributes with default values. Does not prevent lightweight migration. Note that the default values are set to "true" to ensure we will never
send receipts for old messages. In the init of PersistedMessageReceived, they are set to false for new entries.

## Conclusion

A lightweight migration is sufficient.
