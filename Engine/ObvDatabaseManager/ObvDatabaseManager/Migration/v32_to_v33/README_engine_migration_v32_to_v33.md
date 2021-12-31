#  Engine database migration from v32 to v33


## InboxMessage

### Adds

<attribute name="extendedMessagePayload" optional="YES" attributeType="Binary"/>
<attribute name="hasEncryptedExtendedMessagePayload" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
<attribute name="rawExtendedMessagePayloadKey" optional="YES" attributeType="Binary"/>


## OutboxMessage

### Adds

<attribute name="rawEncryptedExtendedMessagePayload" optional="YES" attributeType="Binary"/>


## Conclusion

We are only adding optional attributes, or attributes with an appropriate default value. We can perform a lightweight migration.
