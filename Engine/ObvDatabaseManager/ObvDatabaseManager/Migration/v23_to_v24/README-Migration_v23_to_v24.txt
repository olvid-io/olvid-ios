The network send manager requires a table to store informations about deleted messages, so as to keep track of the sent timestamp. This could be implemented using Persistent History Tracking, using tombstones, but a bug in Xcode prevents all heavyweight migrations if we use this technique. For this reason, we create a simple table to keep track of the messageId, messageUidFromServer, and timestamp from server.

Since we are only creating a new table, we perform a lightweight migration.
