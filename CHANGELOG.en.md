# Changelog

## [0.10.2 (519)] - 2022-05-01

- Want to see a nice view of all the photos and videos received in a discussion? Try the new gallery, available via the top right button of any discussion screen.
- When replying from a notification to the last received message, the response does not appear as a "reply" anymore.
- Fixes a bug preventing the detection of URLs, phone numbers, etc. within messages.
- Fixes a bug preventing badge to be properly updated when marking a message as read from a notification.
- Fixes a bug preventing read receipts to be sent when marking a message as read from a notification.
- Fixes an issue sometimes preventing read messages to be marked as "read".
- Fixes a bug where sharing an image as a file would not result in a nice preview in the discussion screen.
- Other minor bug fixes.

## [0.10.1 (501)] - 2022-03-24

- It is now possible to reply to a message or to mark it as read right from the notification!
- If you like a particular reaction made by another user, you can now easily add it to the list of your preferred reactions.
- Fixes a bug preventing a received message from being edited by the sender.
- Fixes an issue preventing the minimum supported and recommended Olvid version would not be properly updated.
- Background tasks are more reliable.

## [0.10.0 (495)] - 2022-03-21

- New behavior of your address book! Now, an Olvid user becomes a contact *only* if you explicitly agree. You are now in full control of your address book!
- A new list of "other" Olvid users is now accessible from the "Contacts" tab. Typically, these users are part of the same discussion groups as you. Inviting these users to be a contact of yours can be done in one tap!
- A group invite from a contact is now automatically accepted.
- You still need to explicitly accept group invites from Olvid users who are not part of your contacts.
- Sharing with Olvid is now easier and you can now share content into multiple discussions at once!
- Support for new emojis.
- The reactions are larger and easier to tap.
- Bugfix: The reactions were not properly refreshed (it required manual scrolling to actually see an update). This is fixed.
- Bugfix: Fixes an issue with user notifications that wouldn't show after an upgrade (until the first restart of the app)
- Bugfix: a double tap on an image would sometimes show a large version of the image instead of of the panel of reactions. This is fixed.
- Many important improvements made to calls, especially for group calls.
- The receipt indicator of sent messages is more reliable.
- If the app version is outdated, an alert recommends an upgrade.
- Upgrade of a third-party library.

## [0.9.18 (490)] - 2022-01-28

- Great improvements made to secure calls ! Including better quality in poor network conditions and reduced connecting time. Please note that your contact must also use the latest version of Olvid.
- A user notification is shown when a contact reacts to one of your messages.
- Adds supports for HEIC photos.
- The onboarding is now compatible with all majors MDM vendors.
- Updating the design of the group creation screens.
- Fixes issues concerning reactions and ephemeral messages.
- It is now easier to remove a reaction to a message.
- While recording a voice message, receiving a call cancels the recording and immediately attach it to the discussion draft.

## [0.9.17 (484)] - 2022-01-10

- Fixes a potential timing attack on the implementation of scalar multiplication on EC (many thanks to Ryad Benadjila for pointing it out to us!)
- It is possible to customize the quick emoji button of the new composition view, both globally and for each discussion.
- The fluidity of the new discussion screen is improved.
- Since Olvid will soon drop support for iOS 11 and 12, a new alert recommends users using an old iOS version to upgrade to the latest one.

## [0.9.16 (479)] - 2022-01-04

- Fix an important issue for our iOS12 users, preventing Olvid to launch.
- Should fix an issue sometimes preventing some messages to be marked as read.

## [0.9.15 (477)] - 2021-12-27

- It is possible to add a reaction to a message. Double tap a message to try this feature.
- The order of the buttons of the new composition view can be customized.
- Backups now include data concerning the app (contact nicknames, discussion and global settings).
- Improves the integration of the Bitmoji keyboard.
- Improves the settings screen concerning backups.
- When recording a long audio message, the screen does not dim anymore.
- For our pro users, introducing keycloak revocation, a new view showing the technical details about a contact, and better keycloak search.
- Simplified onboarding process.
- Improvements concerning secure calls when one of the interlocutor did not allow access to the microphone.
- Improvements made to backups, making it possible to list all iCloud backups, and to delete all (but the latest) backups.
- Fixes an issue with ephemeral messages and other bugfixes.

## [0.9.14 (468)] - 2021-12-06

- Fixes an issue preventing the auto-read setting to work with messages with limited existence.
- Fixes an issue with wiped messages where the list of discussion could still show information concerning the wiped message.
- Fixes an issue with the ephemerality indicator in the new discussion screen.
- Remotely wiped messages show with the appropriate sentence in the new discussion screen.

## [0.9.13 (462)] - 2021-12-02

- In the new discussion screen (available on iOS 15), a pencil now clearly indicates whether a message was edited.
- Improved user experience when trying to subscribe to secure calls when the payment is not authorized by the App Store.
- Better design of the screen allowing to add a contact for our pro users.
- Fixes an issue preventing the contact detail screen to show a large preview of the contact picture.
- Fixes an issue where the initial shown in the circle next to a contact name would not take the nickname into account.
- Fixes an issue related to ephemeral messages, where the "wiped message" would not always be deleted.
- Fixes an issue related to ephemeral messages, where the auto-read setting would also be applied to messages with a more restrictive ephemeral settings than that of the discussion.
- The app-level setting for deciding whether to auto-read or not was not taken into account. This is fixed.
- Read receipt were not always sent when auto-read was activated. This is fixed.
- When attaching a picture to a draft, it was possible to send the draft with a thumb up by pressing quickly on the send button. This is fixed.
- Fixes an issue with the "number of unread messages" system message within the new discussion screen.
- May fix a rare crash occurring in the background.
- Fixes performance issues when displaying a message with many (say, more than 60) images.
- May fix a potential crash when returning from a keycloak authentication (or when navigating to a deeplink right after returning to the app).
- Fixes a minor issue with calls.

## [0.9.12 (457)] - 2021-11-19

- Multicall is now available! Call a contact and add any other contact to the call at any time. Or call an entire group at once!
- In addition to the nickname, it is not possible to specify a custom picture for a contact.
- When receiving an incoming call, Olvid now check whether the user granted access to the microphone. If this is not the case, the calls fails and the user is notified.
- It is now possible to list and clean all iCloud backups, right from the backup settings.
- It is possible to make a manual backup to iCloud even if automatic backups are not enabled.
- The new discussion screen is now available under iPadOS 15.
- The new composition view (available on iOS 15) has evolved! It now adapts to all screen sizes and font sizes.
- It is now possible to introduce a contact to other contacts, right from the new discussion screen (when using iOS 15).
- The Olvid settings can be accessed from all tabs of Olvid.
- New snackbars should help all users to properly backup Olvid.
- A missing message indicator makes it clear when a message is about to arrive.
- It is now possible to call back a contact right from the call notification.
- Tap-to-read messages are easier to tap ;-)
- Fixes issues with ephemeral messages requiring user interaction and with the auto-read setting.
- Fixes an issue sometimes preventing iOS 13 and 14 users to receive incoming calls.

## [0.9.11 (445)] - 2021-10-13

- This new version is packed with new features!
- New mutual scan procedure for adding contacts ! It now takes less than 5 seconds to add a family member, a friend or a colleague to your contacts. Please make sure that your future contact upgraded to the latest version of Olvid ;-)
- New, fully redesigned, discussion screen for iOS15 users.
- At last, animated gifs are, well, animated right within the new discussion screen. Sending a gif is simple: just copy one anywhere and paste one in the composition bar.
- New voice message feature within the new discussion screen. Yes. At last!
- New slide-to-reply feature within the new discussion screen.
- It is now possible to select an ephemeral policy (like self-destructing messages) at the message level, right within the new discussion screen.
- New message notifications have a fresh new look.
- When downloading a message containing photos, a low resolution thumbnail of the photo is immediately available until the full resolution is downloaded. Note that your contact must have the latest Olvid version for this feature to work.
- It is now possible to mute user notifications for a specific discussion. For one hour, 8 hours, 7 days, or forever.
- Improved experience of the group creation process.
- Searching your contacts now accounts for nicknames.
- Improved reliability of the edition of sent messages.
- Improved reliability of enterprise features.
- Many improvements regarding stability.
- Other minor bugfixes.

## [0.9.10 (424)] - 2021-09-21

- Bugfix release

## [0.9.9 (385)] - 2021-07-24

- When Olvid is up and running, messages arrive even faster than before.
- The download of attachments is much more efficient and reliable, especially when there is a large number of simultaneous downloads.
- The secure channel creation is more reliable and now works even if the participants don't launch Olvid during the process.
- Fixes a bug that could prevent the proper reception of remote notifications for new messages.
- Improved call experience. In particular, secure calls should not fail anymore when connectivity is poor or when changing network.
- New design of the call view.
- Less latency during secure calls.
- Fixes a reconnect issue for secure calls.
- Fixes a bug related to one-to-one discussion titles.
- Other bugfixes and improvements.

## [0.9.8 (370)] - 2021-06-04

- In some circumstances, Incoming secure call could not be received. This is fixed.
- Improved reliability when downloading many attachments in parallel.

## [0.9.7 (368)] - 2021-05-20

- Bugfixes

## [0.9.6 (366)] - 2021-05-18

- It is now possible to change the sort order of the contacts.
- Tapping on a contact profile picture displays a large version of the picture.
- Introducing the compatibility with enterprise identity providers.
- Remote delete and edit are even more reliable.
- Improved deletion of temporary directories on disk.
- Improvements were made to the new initialization procedure, allowing more reliable Olvid updates. A progress bar is shown at startup if a long task is required during an update.
- Replying to a message containing only attachments now displays an appropriate message above the draft.
- System messages for groups now display a date.
- New system messages for call allow to track which call were made, answered, etc.
- Replying to a read once message that is not already read is no longer possible.
- Fixes a bug preventing some messages to be marked as not new.
- Fixes a bug where drafts attachments where not immediately deleted from disk when sending or deleting a draft.
- Fixes a bug related to the setting granting some time before the next Face ID/Touch ID login.
- Other minor improvements.

## [0.9.5 (356)] - 2021-04-26

- Two new, long-awaited features! It is now possible to edit a message sent, and to perform a global deletion of a message and/or a discussion.
- New global settings available for ephemeral messages aficionados! It is now possible to set default values for the "Auto read" and for the "Retain wiped ephemeral outbound messages" settings.
- New setting making it possible to allow custom keyboards.
- When biometrics is available but not used by the user on her iPhone/iPad, we make it clear that it is the passcode that will used to protect Olvid.
- Better look and feel of ephemeral messages.
- Full redesign of the contact identity view under iOS13+.
- Immediate and consistent cleaning of attachments on disk when deleting a message or an entire discussion.
- Reception/read receipts are more reliable.
- The onboarding procedure allows to specify a specific message distribution server and an API key.
- Fixes a bug preventing return receipt to be deleted although they should be. In rare circumstances, this could freeze Olvid during the startup process.
- Fixes an issue preventing the proper display of the configuration menu under iPad.
- Fixes a bug causing the automatic opening of an ephemeral message received in a discussion left open while leaving Olvid (when auto-read was true).
- Other minor bugfixes and improvements.

## [0.9.4 (348)] - 2021-03-15

- This update brings profile and group pictures to iOS!
- New, redesigned contact and group views under iOS 13+.
- New system message allowing to be notified of missed calls.
- Improved onboarding.
- Fixes a bug the could prevent unread messages to be marked as read.
- Choosing a reply-to message used to clear the composition view. This is fixed.
- Other minor improvements

## [0.9.3 (340)] - 2021-01-13

- New, long-awaited feature! Self destructing messages are here! You can mix and match 3 flavors:
- Flavor 1 -> Read once: Messages and attachments are displayed only once, and deleted when exiting the discussion.
- Flavor 2 -> Visibility duration: Messages and attachments are visible for a limited period of time after they have been read.
- Flavor 3 -> Existence duration:  Messages and attachments are automatically deleted after a limited period of time. They are then deleted from all devices.
- Please have a look at https://olvid.io/faq/ to learn more.
- Sending a message is even faster than before ;-)
- Much less ?? Olvid requires your attention ?? notifications!
- The user notifications are more reliable.
- Better information screens for sent and received messages.

## [0.9.2 (336)] - 2021-01-01

- The system message indicating new messages is re-displayed each time the discussion appears on screen. This allows to properly see new messages even if Olvid was dismissed while it was showing a discussion.
- Fixes a bug related to the count based retention policy. It should now work as expected.

## [0.9.1 (334)] - 2020-12-30

- New, long-awaited feature! Expiration settings are now available! You can mix and match two message retention policies: count based and time based.
- A count base policy indicates that you want Olvid to delete old messages when their number exceed the number you specify.
- The time based policy indicates that messages older than the time interval you specify should be deleted.
- And of course, you can choose default policies, that apply to all discussions, and override these policies on a per discussion basis.
- When entering a discussion, the scrolling to the first new message should work perfectly now.
- Redesign of the information displayed for sent messages.
- The indicator of the number of new messages now updates itself when deleting one of the new messages.
- System messages (such as those displayed in case of a missed call) can now be deleted, just as any received/sent message.
- The discussion excerpt shown within each cell of the discussion list is much more informative now.
- The previous update introduced a bug preventing the display of all information concerning sent messages within groups. This is fixed.
- Fixes a bug introduced by the previous update preventing the proper display of certain sent messages. No more empy cells ;-)
- Less "Olvid requires your attention" notifications ;-)
- Fixes a bug sometimes preventing the ring sound for an outgoing call.
- Fixes a dialog requesting the user to tap on an orange button that does not exist anymore.
- Fixes a bug that would prevent new messages to be marked as new when putting in the background while being in a discussion.

## [0.9.0 (328)] - 2020-12-16

- Preparing for a huge Christmas release ;-)
- Minor updates to the secure calls feature.
- Bug fixes and minor improvements.

## [0.8.13 (324)] - 2020-12-01

- Bug fixes and minor improvements.

## [0.8.12 (322)] - 2020-11-15

- The backup restore procedure and the backup key verification are much more reliable.
- Fixes a bug causing a wrong renaming of a one-to-one discussions with a contact having a nickname.
- Fixes an issue related to the phone ring sound. It can be heard now ;-)
- Fixes an issue that could cause a premature hangup of secure calls.
- After switching from a Bluetooth headset to the internal speaker during a secure call, it wasn't possible to switch back to the headset. This is fixed.
- A tap on an invite or on a configuration link no longer opens Safari but navigates directly to the appropriate screen within Olvid.

## [0.8.11 (312)] - 2020-11-06

- The secure call establishment procedure is more robust.
- Introducing in-app purchases for premium features.
- It is now possible to request a free trial of premium features of Olvid.
- The invitation workflows displays appropriately on iPhone SE (2016).
- Fixes the My Id (and other) screens layout when switching to landscape.
- Many visual improvements, including a new color palette and improved layouts on smaller screens.

## [0.8.10 (298)] - 2020-10-26

- The "My Id" page has been redesigned completely! Not only it looks much better, but it displays more information.
- The "My Id" edition screens has been redesigned completely!
- It is now possible to share Wallet items with Olvid.
- The initial secure channel creation process is much more reliable now.
- Various small bugfixes of the new invitation screens. In particular, iOS 13 users should no longer experience any issue.
- The previous release introduced a bug preventing certain iOS 13 users to send videos. This is fixed.
- The previous release introduced a bug preventing the share of VCF cards. This is fixed.
- Fixes issues encountered with the new Photo picker under iOS 14.

## [0.8.9 (296)] - 2020-10-21

- It is now possible to share *any* type of file. Any kind. Any size.
- Fixes issues encountered with the new Photo picker under iOS 14.

## [0.8.8 (292)] - 2020-10-16

- It is now possible to present a contact to many contacts at once!
- Tapping the QR code enlarges the code.
- Fixes a bug that could prevent the export of a manual backup.

## [0.8.7 (290)] - 2020-10-10

- Introducing a brand new navigation and invitation flow! Inviting a new contact is much more intuitive now. Just tap the central "+" button and let us guide you!
- Fixes a bug where the user notification activation switch would not show in the app settings.

## [0.8.6 (283)] - 2020-10-05

- New photo/video picker under iOS 14. It is now possible to choose multiple photos/videos at once!
- When making an outgoing call, a ringing sound is played as soon as the callee's phone rings.
- New design for the call view! The experience is *much* better that before on iOS 14.
- Improved handling of the "do not disturb" mode.
- It is now possible to receive a call while another call is in progress: one can either reject the call or hangup the current call and pick up the new one.
- The new call view shows whether the contact is muted or not during a call.
- If automatic backups are enabled, changing the backup key automatically triggers a new backup.
- From now on, database entries are securely deleted.
- Deleting a contact now appropriately prevents any previous tentative to send her messages. This means that if a group message had this contact among its recipients, then deleting this contact remove her from the list of recipients (potentially marking the message as "sent").
- Improved banner when navigating the app during a call.
- A quick action allowing to launch the QR code scanner is now available right from the App icon.
- Missed incoming calls are now displayed within the appropriate discussion.
- Fixes a bug making posting a message into a group much more reliable.
- Fixes a bug that would prevent the proper display of the contact list when introducing a contact to another.
- The "sent" indicator of a message within a discussion changed! A message is now marked as "sent" only when the message and *all* its attachments have been uploaded to the server, for *all* recipients (one for one to one discussions, potentially many for group discussions). In other words, once the "sent" status is shown, one can shutdown the iPhone, knowing that the message and its attachments will eventually be delivered.
- Deleting a discussion and all its messages is now performed very efficiently.
- Attachments are now properly cleaned at each launch.
- Deleting a message while one of its attachments is still uploading behaves appropriately on the recipient's device.

## [0.8.5 (276)] - 2020-09-07

- Breaking news! You can now make secure, end-to-end encrypted voice calls. Welcome to the most secure voice calls in the world!
- Note that voice calls are only possible with users using the latest Olvid version.
- Note also that this feature is still under active development and is available as a beta. If you encounter any bug, please give us some feedback at feedback@olvid.io.
- During this beta, the feature will remain free for all Olvid users. Once the beta is over, placing calls will require a paid subscription, but all Olvid users will still be able to receive calls from users with a subscription.
- Adds a Help/FAQ button within the settings.
- Fixes a bug where a selected contact (e.g. when creating a group) would look as being deselected after a scroll.
- Fixes a rare bug that would require users to restart a channel establishment.
- Fixes a bug that would prevent to share content with the share extension when Face ID or Touch ID was activated
- Fixes a crash under iOS 13.x (for x smaller than 4) occurring when decrypting an attachment.

## [0.8.4 (255)] - 2020-05-26

- This new version includes *huge* improvements related to uploading and downloading photos, videos and files!
- Sharing using Olvid is now much more reliable, even when sharing large videos! Sharing is no longer restricted to small 70MB files. You can now share huge files with Olvid. Yes, uploading files larger than 500MB is not an issue ;-)
- Upload/Download progress bars are more reliable. And they also look better!
- The secure channel creation process is now much more reliable.
- Olvid used to not properly delete certain (encrypted) temporary files that could end up filling too much disk space. This is fixed.
- Fixes a bug preventing to restore a backup from a file that was stored on Google Drive (or similar).
- Fixes the animation that could, on some occasions, prevent a backup restore.
- Fixes a bug that could prevent Olvid from launching fast enough, and thus leading to occasional crashes at launch.
- Deleting a message now appropriately remove its content from all cells that were a reply to this message.
- And many other minor bug fixes and improvements.
- Caution: this version includes a complete refactor of the network stack. Please report any bug to feedback@olvid.io. Thank you for your support!

## [0.8.3 (232)] - 2020-05-17

- Fixes a bug that could crash the app when performing a manual backup on the iPad Pro.
- Fixes a bug that could crash the app when trying to regenerate a backup key on the iPad Pro.

## [0.8.2 (228)] - 2020-04-20

- Full ratchet updates are now regularly performed on the secure channels.
- Fixes a bug preventing the activation/deactivation of Face ID or Touch ID.
- Fixes a bug preventing to globally choose whether to send read receipts.
- Fixes a bug that could lead to a crash when re-opening Olvid right after sharing.
- Several UI/UX improvements.

## [0.8.1 (223)] - 2020-04-08

- Improvements were made to the text field allowing to enter a backup key.
- A confirmation is bow asked before regenerating a backup key.
- Fixes a bug preventing to actually see the backup key in dark mode.
- Fixes an occasional bug occurring when choosing an iCloud backup to restore.

## [0.8.0 (220)] - 2020-04-06

- Introducing encrypted backups of your address book!
- Take a look at the settings tab, then tap on Backup. Generate your secret backup key, write it down and store it somewhere safe, activate automatic backups, and you are good to go. If you prefer, you can also manually export the encrypted backup.

## [0.7.23 (213)] - 2020-03-26

- Olvid is ready for iOS 13.4 !
- All the procedures relating to group management have been made more robust.
- Better internal management of attachments.
- Fixes a few occasional bugs.

## [0.7.22 (197)] - 2020-03-04

- Olvid now forces the exchange of the digits in both directions before entering any of the contacts within the address book.
- A group administrator could not remove a member from a group with whom she had no secure channel. This is fixed.
- Fixes a bug that lead to occasional crashes when deleting a contact.
- Fixes a bug related to image previews of files. This also fixes a bug preventing the opening of certain files.

## [0.7.21 (195)] - 2020-02-26

- New privacy setting allowing to choose between three levels of privacy for user notifications content.
- Updated splash screen that looks great both in light and dark mode.
- Better filtering of user notifications while using Olvid.
- Fixes a bug preventing sharing on iOS 12 when Touch ID is activated.
- Fixes a bug that could lead to a crash at launch.
- Several UI/UX improvements.

## [0.7.20 (186)] - 2020-02-05

- Adds a preliminary version of the "Drop" feature on iPad. It is now possible to drag-and-drop files, photos, etc. from another app directly into a discussion by dropping the attachments onto the text zone allowing to type a message.
- Adds a search functionality when introducing a contact to another contact.
- Fixes a bug that would launch Olvid when tapping on a .docx file in the Files App.
- Minor graphical improvements.

## [0.7.19 (182)] - 2020-01-27

- New App Icon!
- New App Splash screen!
- Minor graphical improvements when adding/removing group members.
- Introducing two contacts to one another could, in rare situations, crash the app. This is fixed.
- Improvements were made to the upload/download strategy when network conditions are bad.

## [0.7.18 (178)] - 2020-01-20

- Olvid is now available under iPad ????. This is huge!
- Discussions now display rich link previews! A global setting allows to choose whether this option should be activated for all discussions or not. This option can be found within the app settings, under "Discussions", then "Rich link preview". This global setting can then be overridden within each discussion.
- Olvid now supports iPhone rotation. Very handy for previewing photos and videos.
- The identity QR code scanner is now faster.
- Minor change: Within a group discussion, the keyboard is not shown until there is someone to write to.
- Several UI/UX improvements.

## [0.7.17 (155)] - 2019-11-26

- Full AirDrop support! Olvid is now a valid target when sending files from your Mac. If a discussion is already opened within Olvid, AirDrop'ed files will be attached to the current draft. If no discussion is opened, you will get the chance to choose one.
- Improves the reliability of the delivery and read receipts.
- Fixes a bug that could lead to a systematic crash at launch.

## [0.7.16 (150)] - 2019-11-19

- You asked for it, here it is! New setting allowing to lock Olvid using Face ID and/or Touch ID and/or passcode, depending on what's available on your device.
- You asked for this one too: your Olvid screen does not show anymore when switching from one app to another.
- It is now possible to share all the photos received within a message, at once.
- A few UI/UX improvements.

## [0.7.15 (144)] - 2019-11-10

- Better layouts, especially on smaller screens.
- Fixes a bug that could prevent receipts from being sent properly.
- Fixes an animation bug that occurs in iOS 13.2 when showing the info menu on a message sent.
- Fixes a bug that would freeze Olvid when transferring an attachment from one discussion to another.

## [0.7.14 (140)] - 2019-10-28

- Introducing delivery confirmations on iOS 13! This feature makes it possible to know whether a message sent was successfully delivered to the recipient's device. Note that these receipts do *not* imply that your recipient has read the message. Also note that these receipts only work if your recipient has updated to (at least) this version of Olvid.
- Introducing read confirmations on iOS 13! This feature allows to know whether your recipient has read your message. Unlike delivery receipts, read confirmations are opt-in and turned off by default. This setting can be changed within the "Settings" tab. This choice can then be overridden on a per discussion basis.
- Within a discussion, tapping the title navigates to the details of the contact or of the group. A new indicators allows to configure the discussion. This is the place to go for changing the "read receipt" setting for that particular discussion.
- Olvid uploads files even faster, and in a more reliable way.
- Introducing WebSockets on iOS 13: Olvid is now much faster when in the foreground!
- Fixes a bug where progression bars (well, circles) would not show on attachments.
- Fixes the colors of the screens of the onboarding procedure in dark mode under iOS 13.
- Fixes a bug related to colors of the onboarding under iOS 12.
- Several UI/UX improvements.

## [0.7.12 (132)] - 2019-10-03

- Fixes a bug where no confirmation was required to open a link in Safari.
- Several UI/UX improvements.

## [0.7.11 (128)] - 2019-09-25

- New beautiful thumbnails for your attachments, especially under iOS 13.
- No more ugly animation when entering a discussion. Nice and clean.
- As before, tapping a message notification brings you right into the discussion. But now, the message displays immediately. No more waiting!
- Searching within contacts is now diacritic-agnostic.
- When inviting another user by mail, the subject field is now populated.
- Appropriate handling of Memojis
- Under iOS 13, it is now possible to scan a document right from within a discussion.
- A few iOS 13 related bugs were fixed.
- Several UI/UX improvements.

## [0.7.9 (118)] - 2019-09-13

- Full iOS 13 Compatibility
- The color palette has changed. Olvid is ready for dark mode in iOS 13!
- There is a new file viewer within Olvid ! Pictures, movies and pdf display much better than before. We also added support for many other formats, including iWork documents, Microsoft Office documents (Office ???97 and newer), Rich Text Format (RTF) documents, Comma-separated value (csv) files, and more.
- The new viewer allows to flick through all the attachments of a particular message.
- The Discussions tab now shows a segmented control allowing to filter/sort the discussions in 3 different ways : latest discussions, one2one discussions with contacts (sorted alphabetically), and group discussions (sorted alphabetically).
- Under iOS 13, the discussion screen can be dismissed by pulling down the window. This technique can be used in many other places.
- A contact can now be deleted from the her contact sheet, even if this sheet was accessed directly from a discussion. This is also fixed for groups.
- Several UI/UX improvements.

## [0.7.8 (108)] - 2019-07-26

- Attachments downloads and uploads are *much* faster now! They can safely be canceled (in upload and in download) or paused (in download).
- Compatibility with the new web invitations links.
- Within the compose view, deleting an attachments can now be done by tapping. A small red cross shown on each file should make this clear.
- It is now possible to choose Olvid as a share method from the iOS "Contacts" application.
- Videos can now be shared directly from the internal video viewer.
- Bug fixes and performance improvements.
- Several UI/UX improvements.

## [0.7.7 (103)] - 2019-07-18

- Tapping on the "Click here" link on an Olvid invitation web page works as expected.
- Bug fixes and performance improvements
- Several UI/UX improvements

## [0.7.6 (102)] - 2019-07-14

- The first on-boarding screen is now clear about the fact that we do *not* have access to the identification data (first name, name, etc.) entered by our users.
- It is now possible to delete a contact!
- It is now possible to send/receive any type of attachment. Word, Zip, RTF, you name it.
- The user experience for sharing attachments and text received within Olvid has been completely refactored and is much more consistent across the whole app.
- A new "Advanced" allows to copy/paste ones identity. This menu can be accessed from the "Contacts" and the "Invitations" tabs, by tapping on the "Add" button in the bottom right corner.
- A tap on a reply scrolls directly to the original message (with a cool effect).
- A message informing the user that all discussions within Olvid are end-to-end encrypted now always appear in empty (new) discussions.

- The message cells have been refactored. Big previews for pictures, and more descriptive cells for attachments.
- When entering a discussion, an automatic scroll to the first unread message is performed.
- When introducing a contact to another, a confirmation dialog is displayed.
- It is now possible to reply to a message composed of pictures only.
- Bugfix: The badges now display the correct number of unread messages and are updated appropriately.
- Bug fixes and performance improvements
- Several UI/UX improvements
