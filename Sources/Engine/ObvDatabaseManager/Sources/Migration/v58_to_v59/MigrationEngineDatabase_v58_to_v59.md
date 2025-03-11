#  Engine database migration from v58 to v59

This migration replaces a few "Transformable" attributes by their "raw" equivalent and adds a new attribute

## InboxMessage: Updated entity

-<attribute name="encryptedContent" attributeType="Transformable" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>
+<attribute name="rawEncryptedContent" attributeType="Binary" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>

Replaces the transformable "encryptedContent" attribute by the "rawEncryptedContent" attribute. Requires a heaviweight migration.

-<attribute name="fromCryptoIdentity" optional="YES" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
+<attribute name="rawFromIdentity" optional="YES" attributeType="Binary" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>

Replaces the transformable "fromCryptoIdentity" attribute by the "rawFromIdentity" attribute. Requires a heaviweight migration.

-<attribute name="wrappedKey" attributeType="Transformable" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>
+<attribute name="rawWrappedKey" attributeType="Binary" valueTransformerName="EncryptedDataTransformer" customClassName="EncryptedData"/>

Replaces the transformable "wrappedKey" attribute by the "rawWrappedKey" attribute. Requires a heaviweight migration.

+<attribute name="fromRawDeviceUID" optional="YES" attributeType="Binary"/>

Adds an optional attribute, does not prevent lightweight migration.

## Conclusion

A heaviweight migration is required.
