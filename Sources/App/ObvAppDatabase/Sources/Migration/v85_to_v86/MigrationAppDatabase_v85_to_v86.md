# App database migration from v85 to v86

Everything below serves one feature: contacts suggestions, a deck of the users the reader shares a group with but who are not yet
one-to-one contacts, from which each can be invited or set aside. The app needs to remember, per contact, two things that only the reader's
own actions decide.

## PersistedObvContactIdentity - Updated entity

```xml
+<attribute name="stopSuggesting" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
+<attribute name="suggestionSeen" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
```

`stopSuggesting` is set when the reader declines a suggestion, and when a contact stops being one-to-one, whichever side removed the other:
that contact is never offered again. A contact removed before this version is not set aside: nothing in v85 records that it ever was
one-to-one. `suggestionSeen` is set once the contact's suggestion card was in a deck the reader opened, and only serves the colour of the
badge on the contacts tab, which is red while the deck holds a card not seen yet.

Both are non-optional with a default of `NO`, which is what every existing contact should read after the migration — nobody has been set aside,
and nobody has been shown. `suggestionSeen` is local to the device: it is part of neither a backup nor the sync snapshot.

## PersistedInvitation - Updated entity

```xml
+<attribute name="suggestionSeen" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
```

The same flag for a card that is an invitation: a one-to-one invitation received, or an introduction. Such a card can be about somebody who
is not a contact, so the flag cannot live on the contact. Non-optional with a default of `NO`, local to the device.

## Conclusion

A lightweight migration is sufficient.
