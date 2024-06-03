#  Engine database migration from v52 to v53

## ContactIdentity: Updated entity

+<attribute name="rawOneToOneStatus" optional="YES" attributeType="Integer 16" usesScalarValueType="YES"/>
-<attribute name="isOneToOne" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Because we now want to keep more information about the one2one status of a contact, we replace the isOneToOne Boolean by a rawOneToOneStatus accepting 3 values:
- 0: not one2one
- 1: one2one
- 2: to be defined

This attribute needs a heavyweight migration so as to choose between the appropriate value (0 or 1, never 2) depending on the value of isOneToOne.

## Conclusion

A heavyweight migration is necessary.
