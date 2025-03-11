The v30 version adds a new entity:

    <entity name="CachedWellKnown" representedClassName="CachedWellKnown" syncable="YES">
        <attribute name="downloadTimestamp" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="serverURL" attributeType="URI"/>
        <attribute name="wellKnownData" attributeType="Binary"/>
        <uniquenessConstraints>
            <uniquenessConstraint>
                <constraint value="serverURL"/>
            </uniquenessConstraint>
        </uniquenessConstraints>
    </entity>

