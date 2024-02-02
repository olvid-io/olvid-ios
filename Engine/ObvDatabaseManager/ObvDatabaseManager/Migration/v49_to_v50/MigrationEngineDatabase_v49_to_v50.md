#  Engine database migration from v49 to v50

## PendingServerQuery: many modifications

The model was changed from this:

    <entity name="PendingServerQuery" representedClassName="PendingServerQuery" syncable="YES">
        <attribute name="encodedElements" attributeType="Binary"/>
        <attribute name="encodedQueryType" attributeType="Binary"/>
        <attribute name="encodedResponseType" optional="YES" attributeType="Binary"/>
        <attribute name="ownedIdentity" attributeType="Transformable" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
    </entity>

to this:

    <entity name="PendingServerQuery" representedClassName="PendingServerQuery" syncable="YES">
        <attribute name="isWebSocket" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="rawEncodedElements" attributeType="Binary" elementID="encodedElements"/>
        <attribute name="rawEncodedQueryType" attributeType="Binary" elementID="encodedQueryType"/>
        <attribute name="rawEncodedResponseType" optional="YES" attributeType="Binary" elementID="encodedResponseType"/>
        <attribute name="rawOwnedIdentity" attributeType="Binary" valueTransformerName="ObvCryptoIdentityTransformer" customClassName="ObvCryptoIdentity"/>
    </entity>

- The `isWebSocket` attribute is new but has a default value which is ok for old server queries. This does not prevent migration.

- The `encodedElements` attribute is now called `rawEncodedElements`. The `elementID` allows to perform a lightweight migration.

- The `encodedQueryType` attribute is now called `rawEncodedQueryType`. The `elementID` allows to perform a lightweight migration.

- The `encodedResponseType` attribute is now called `rawEncodedResponseType`. The `elementID` allows to perform a lightweight migration.

- The `ownedIdentity` attribute is now called `rawOwnedIdentity` and its type changed from OwnedCryptoId (that used a Core Data transformer) to Binary. This requires a heavyweight migration.

## Conclusion

A heavyweight migration is required.
