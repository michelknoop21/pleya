# Pleya release notes

What changed in each Pleya build, written for the people using it. Newest first.

Pleya has shipped as a private TestFlight beta since 2 July 2026, with continuously
numbered builds. The internal engineering log lives in
`docs/CHANGELOG.md`; this file is the public one.

Every published entry carries the commit it was cut at. `scripts/gen_release_notes.sh`
reads the topmost anchor and fills the block below with everything committed since.

Only `### New`, `### Improved`, `### Fixed` and `### Notes` render on pleya.app; any other
`###` heading is dropped there without a word (`website/src/lib/server/releases.ts`).
`fastlane notes` reads this file straight, so such a heading still reaches TestFlight. That
is how "Worth checking" is meant to work, and it is the reason a note for everyone belongs
under `Notes`.

## Unreleased

<!-- BEGIN GENERATED -->
Nothing user-facing since the last published build.
<!-- END GENERATED -->

### New

- **Pleya plays video files from Finder on the Mac.** Pleya shows up under Open With for video
  files such as mkv, mp4, mov and avi and starts the file in the player. On iPhone and iPad
  this is in build 355; it is not in a Mac build yet and has not been checked on a Mac.
- **Big P can use your Trakt history and watchlist.** With Trakt connected, Big P counts what
  you marked as watched there as seen and can tell you which watchlist titles are in your
  libraries. The code is in the builds from 355 on, but Trakt sign-in is not switched on in any
  build yet.
- **A Pleya Server can now be shared by a household.** The owner adds an account per person and
  decides which libraries each of them sees. A library somebody has no access to does not show
  up in their list, in their search results, or when they open a link straight to it. Watch
  position, resume and Continue Watching are per person, so two people watching the same film
  keep their own place in it.
- **Four roles, and one rung of access per library.** The owner and administrators see every
  library. A member sees the libraries they were given. A restricted account is a member with
  three differences: it cannot be given management rights, only an owner or administrator sets
  its password, and it sees no one but itself in the account list. Adding accounts and setting
  their libraries runs over the server API for now; `pleya_server/README.md` has the commands.
  The screen for it comes with the management interface.
- **Signing in registers the device, not just the account.** Each device gets its own session,
  which means signing out on a phone that was lost leaves the television logged in. The owner
  can see and end anyone's sessions; everyone else sees and ends their own.

### Improved

- **Opening a video file while a menu or sheet is open over the player replaces the film.** It
  used to start a second player under the first. A file whose start was cut short because the
  screen went away is kept for the next screen instead of being deleted unseen. On the Mac, a
  video file that arrives together with a sign-in link no longer hides that link from the app.
  Not checked on a device yet.
- **Ending a session takes effect while a film is playing.** A revoked session stops the stream
  it was feeding rather than letting it run to the end of the file. Measured at under half a
  second on the test rig, against a documented ceiling of two seconds.

## 2.8.1 · build 357 · 12 October 2026 · Apple TV

<!-- commit: 5b7a5efcb26e97a543337d15c73a85bbc5933bb9 -->

### New
- Big P has a memory. Tell Big P what it should know about you, for example "remember that I
  do not like horror", and it keeps that sentence and uses it when a later question touches on
  it. When Big P thinks something is worth keeping without you asking, it shows a card first:
  Shall I remember this? Outside your own request, nothing is stored, replaced or forgotten
  without your yes.
- Memories belong to one profile and stay on this Apple TV. They do not sync to your other
  devices.
- Settings, Big P, Memory shows what Big P knows about this profile as a short overview that
  Big P writes from your memories. From there you can ask or change something with the keyboard
  or dictation, open the list of memories to search, add, edit and delete them, switch the
  memory off, or clear everything.

### Fixed
- When you ask Big P for one film or show, such as "that film with Tom Hanks about death row",
  it shows the card of that title only, not every film with the same actor.
- When Plex refuses to delete a film or show, the message no longer tells you to switch on
  Allow media deletion when that setting is already on. It names the setting as the cause only
  when it is off. With the setting on it points at what usually blocks a delete: folder
  permissions or a drive that is not available on the server. When Pleya cannot read the
  setting, it mentions both.

### Notes
- With a cloud model, memories leave the device: the ones that match your question go along
  with it, and to write the overview Big P sends the memories of this profile.
- On a children's profile Big P uses no memory. You can still open the screen there to view
  and clear what was stored.
- Big P does not keep children's ages or a language preference in its memory; those stay under
  Children's profile and Language & subtitles. A memory is one sentence of at most 200
  characters, and a profile holds at most 200 of them.
- With the memory switched off Big P remembers nothing and uses nothing. What was stored stays
  until you clear it.
- The new delete message does not make Plex delete anything it refused before. If your server
  still refuses with the setting on, the cause is on the server.
- If you change a memory through Big P while the Memory screen is open behind it, the screen
  keeps showing the old state until you leave it and open it again.
- Trakt for Big P is not switched on in this build, so there is no Trakt sign-in to test yet.

### Worth checking
- Nothing in this build has been checked on an Apple TV yet. The memory is covered by automated
  tests and runs in the simulator; the overview Big P writes has not been run against a real
  language model.
- Big P: say or type "remember that I do not like horror". Big P should answer "Remembered: I
  do not like horror." Then summon Big P again and ask "Do I like horror?". Big P should know. A
  memory only goes along when your question shares a word with it, so "a film for tonight" will
  not bring this one up.
- Mention something in passing, such as "we usually watch on Friday evening", and check whether
  Big P offers the card. Check that you can reach both answers with the Siri Remote.
- Ask for one film by description, such as "that film with Tom Hanks about death row", and
  check that only the card of that film shows.
- Settings, Big P, Memory: check that the overview reads well, that every button can be reached
  with the Siri Remote, including Clear all memories at the bottom, and that Back closes one
  layer at a time.
- Open a memory, change its text and its category and save. Then delete one.
- Dictate a question in Ask or update and check that the answer stays readable while you move
  around.
- Switch the memory off, start a new conversation, ask Big P what it remembers about you, and
  check that it knows nothing.
- Switch to another profile and check that its memory is empty.

## 2.8.1 · build 356 · 12 October 2026 · iPhone and iPad

<!-- commit: 5b7a5efcb26e97a543337d15c73a85bbc5933bb9 -->

### New
- Big P has a memory. Tell Big P what it should know about you, for example "remember that I
  do not like horror", and it keeps that sentence and uses it when a later question touches on
  it. When Big P thinks something is worth keeping without you asking, it shows a card first:
  Shall I remember this? Outside your own request, nothing is stored, replaced or forgotten
  without your yes.
- Memories belong to one profile and stay on this device. They do not sync to your other
  devices.
- Settings, Big P, Memory shows what Big P knows about this profile as a short overview that
  Big P writes from your memories. You can ask or change something right there. On an iPhone
  the menu at the top right holds the rest, on an iPad it sits beside the text: Manage memories
  opens the list, where you search, add, edit and delete them, and from the same place you
  switch the memory off or clear everything.

### Improved
- A video file you opened no longer stays behind on your iPhone or iPad. Some ways of opening a
  film, AirDrop among them, copy it into Pleya; that copy is now removed when the player
  closes, where it used to stay until the next file arrived. For a file opened in place (Files,
  iCloud Drive) Pleya gives its access back at the same moment.

### Fixed
- When Plex refuses to delete a film or show, the message no longer tells you to switch on
  Allow media deletion when that setting is already on. It names the setting as the cause only
  when it is off. With the setting on it points at what usually blocks a delete: folder
  permissions or a drive that is not available on the server. When Pleya cannot read the
  setting, it mentions both.

### Notes
- With a cloud model, memories leave the device: the ones that match your question go along
  with it, and to write the overview Big P sends the memories of this profile.
- On a children's profile Big P uses no memory. You can still open the screen there to view
  and clear what was stored.
- Big P does not keep children's ages or a language preference in its memory; those stay under
  Children's profile and Language & subtitles. A memory is one sentence of at most 200
  characters, and a profile holds at most 200 of them.
- With the memory switched off Big P remembers nothing and uses nothing. What was stored stays
  until you clear it.
- The new delete message does not make Plex delete anything it refused before. If your server
  still refuses with the setting on, the cause is on the server.
- Trakt for Big P is not switched on in this build, so there is no Trakt sign-in to test yet.

### Worth checking
- Nothing in this build has been checked on an iPhone or iPad yet. The memory is covered by
  automated tests and runs in the simulator; the overview Big P writes has not been run against
  a real language model.
- Big P: type "remember that I do not like horror". Big P should answer "Remembered: I do not
  like horror." Then start a new conversation and ask "Do I like horror?". Big P should know. A
  memory only goes along when your question shares a word with it, so "a film for tonight" will
  not bring this one up.
- Mention something in passing, such as "we usually watch on Friday evening", and check whether
  Big P offers the card. Try both answers on it.
- Settings, Big P, Memory: check that the overview reads well. Ask something in the field at
  the bottom with the keyboard open, on a small iPhone if you have one, and check that nothing
  is cut off and every button can be reached.
- Open Manage memories (on an iPhone through the menu), add a memory by hand, edit one and
  delete one. Search for a word.
- Switch the memory off, start a new conversation, ask Big P what it remembers about you, and
  check that it knows nothing.
- Switch to another profile and check that its memory is empty.
- Send a video to Pleya by AirDrop, close the player, and check in the Files app, in Pleya's
  own folder, that no copy of it stays behind.
- Only if your Plex server is known to refuse deletes: as the server owner, long-press a film,
  choose Delete from server and read the message. Do not try this to find out. A delete that
  goes through removes the film and its files from the server for good.

## 2.8.1 · build 355 · 11 October 2026 · iPhone and iPad

<!-- commit: 9e7648a46a705bfcf4b8119346ec5bdd53178a3e -->

### New
- Pleya plays video files from the Files app. Pleya now shows up under Open in and in the share
  sheet for video files such as mkv, mp4, mov and avi, and picking it starts the file in the
  Pleya player. Pleya does not make itself the default app for these files. A file opened this
  way is not added to a library, and Pleya does not remember where you stopped or which audio
  and subtitle track you picked. You need to be signed in with a profile: on the sign-in screen
  the file waits and starts once you are in.

### Fixed
- When you ask Big P for one film or show, such as "that film with Tom Hanks about death row",
  it shows the card of that title only, not every film with the same actor.

### Notes
- Subtitle files that sit next to the video are not picked up when you open a single file,
  because iOS hands Pleya that one file only. Subtitles inside the file should work.
- Audio files are not part of this.
- Trakt for Big P is not switched on in this build, so there is no Trakt sign-in to test yet.

### Worth checking
- Nothing in this build has been checked on an iPhone or iPad yet. Opening a file is covered by
  automated tests and one start of the app in the simulator. That Pleya appears under Open in
  and that the file plays has not been checked on a device.
- Open a video from Files with Pleya closed, and again with Pleya already open. Both should
  start the player.
- Open a video that sits in iCloud Drive and is not downloaded yet. It should start after the
  download, without an error.
- Send an mkv file to the iPhone with AirDrop and open it in Pleya, then do it again with
  another file. Check under On My iPhone, Pleya, Inbox that only the last one is still there.
- Open a video while the profile chooser is on screen. Nothing should play until you picked a
  profile. Then switch profile and open a video again; it should still start.
- Start a film from your server, then open a video from Files. The file should replace the
  film, with no sound from the first one.
- Big P: ask for one film by description, such as "that film with Tom Hanks about death row",
  and check that only the card of that film shows.

## 2.8.1 · build 354 · 11 October 2026 · Mac

<!-- commit: 89455da4a55e0b43ddc80e66b1858dfbda5fdc16 -->

### Improved
- Your recommendations recognise a title you watched on one server when the same
  title sits on another server.

### Fixed
- Pleya Share stays on your local network. After a short Wi-Fi or hotspot hiccup a guest could
  end up on the internet relay, where the share looked online but nothing played. Pleya Share
  no longer uses that relay, so it reconnects over the local network. Sharing between two
  different networks is gone with it.

### Notes
- Big P is not part of the Mac build.
- Two things were already in earlier builds without a note. Home shows movies and shows added
  while the app stays open, and refreshes quietly when you return to Home after two minutes and
  every five minutes while it is on screen. Hidden libraries and library order sync over iCloud
  for Plex Home profiles: the first device to sync sets them for that profile on every device,
  so if you arranged a profile differently on purpose on one device, check it.

### Worth checking
- Nothing in this build has been checked on a Mac yet; the change is covered by automated tests.
- Pleya Share as the host: start sharing, join from an iPad on the same Wi-Fi with the QR code
  and play a film. This is the first sandboxed Mac build to be checked for it, so macOS may ask
  once for permission to use the local network.

## 2.8.1 · build 353 · 11 October 2026 · Apple TV

<!-- commit: 89455da4a55e0b43ddc80e66b1858dfbda5fdc16 -->

### New
- Big P on Apple TV can list the films that have been sitting unwatched in your library. It
  reads up to 100 films per kind, longest-waiting first, and shows the date each film was added.
  When there are more than it read it says "at least 100" instead of giving a total, and the
  cards under the answer are the films named in the text.
- Big P is switched on in the Apple TV build, as it is on iPhone and iPad. Before it can answer
  you pick a model provider in its settings.

### Improved
- Big P and your recommendations recognise a title you watched on one server when the same
  title sits on another server.

### Fixed
- Pleya Share stays on your local network. After a short Wi-Fi or hotspot hiccup a guest could
  end up on the internet relay, where the share looked online but nothing played. Pleya Share
  no longer uses that relay, so it reconnects over the local network. Sharing between two
  different networks is gone with it.

### Notes
- Several things were already in earlier builds without a note. The context menu shows a line
  under the title with genre, runtime, sources and remaining time, the Resume row shows how
  much time is left, and every row has an icon. Live TV sits inside the same one-bar navigation
  as the rest of the app, the guide is denser with five channel rows, and a detail bar under it
  shows what is focused. Season selector labels and the row of extras on a series or movie page
  are laid out consistently. The top bar, player panel and search field can be glass, with a
  switch in Appearance that is off by default.
- Home shows movies and shows added while the app stays open, and refreshes quietly when you
  return to Home after two minutes and every five minutes while it is on screen. Hidden
  libraries and library order sync over iCloud for Plex Home profiles: the first device to sync
  sets them for that profile on every device, so if you arranged a profile differently on
  purpose on one device, check it.

### Worth checking
- Nothing in this build has been checked on an Apple TV yet; the changes are covered by
  automated tests and, for Big P, by one run of two language models against a test library.
- Big P: pick a model provider, then ask "Which films have been sitting unwatched in my library
  for a long time?". Check that the oldest additions come first and that the dates match the
  cards.
- Pleya Share as a guest: join a host on the same Wi-Fi or on a phone hotspot, browse its
  library and play a film. Nothing should ask for an internet connection.

## 2.8.1 · build 352 · 11 October 2026 · iPhone and iPad

<!-- commit: 19ad7e38779a8d5027e48997d295b0c9bf644335 -->

### New
- Ask Big P which films have been sitting unwatched in your library. It reads up to 100 films
  per kind, longest-waiting first, and shows the date each film was added. When there are more
  than it read it says "at least 100" instead of giving a total, and the cards under the answer
  are the films named in the text.

### Improved
- Big P and your recommendations recognise a title you watched on one server when the same
  title sits on another server.

### Fixed
- Pleya Share stays on your local network. After a short Wi-Fi or hotspot hiccup a guest could
  end up on the internet relay, where the share looked online but nothing played. Pleya Share
  no longer uses that relay, so it reconnects over the local network or Wi-Fi Aware. Sharing
  between two different networks is gone with it.
- "Which films have I not watched?" no longer gets twelve personal tips as its answer. A tip
  you ask for still comes from your own history.

### Notes
- Three things from late September were already in builds 348 and 350 without a note. Home
  shows movies and shows added while the app stays open, and refreshes quietly when you return
  to Home after two minutes and every five minutes while it is on screen. The tab bar, player
  controls and movie page on iPhone can be glass, with a switch in Appearance that is off by
  default and does not apply on iPad. Hidden libraries and library order sync over iCloud for
  Plex Home profiles: the first device to sync sets them for that profile on every device, so
  if you arranged a profile differently on purpose on one device, check it.

### Worth checking
- Nothing in this build has been checked on an iPhone or iPad yet; the changes are covered by
  automated tests and, for Big P, by one run of two language models against a test library.
- Pleya Share on a trip: put the host iPhone on its own hotspot, join with an iPad, pair with
  the QR code, play a film and seek. Lock the iPhone and check that the iPad keeps playing.
  Note Pleya's figure under Settings, Mobile Data on the iPhone before the trip and again
  after a whole film. It should have grown by a few megabytes at most, not by the size of the
  film.
- Pleya Share after a break: turn the iPad's Wi-Fi off and on during playback and check that
  it reconnects to the iPhone without a message about an internet connection.
- Big P: ask "Which films have been sitting unwatched in my library for a long time?" and check
  that the oldest additions come first, that the dates match the cards and that no film you
  watched elsewhere is listed.

## 2.8.1 · build 351 · 11 October 2026 · Apple TV

<!-- commit: 584f1e38302fbd944019a55f66b7521203f08ce7 -->

### New
- Ask Big P what was added to your libraries. It answers for the period you name, such as this
  week, up to a month back, and shows the date each title was added. A local folder has no such
  date. The cards under the answer are the same titles as the list in the text.
- When you ask Big P what was watched without saying by whom, such as "What was watched this
  week?", it asks whether you mean yourself, the others or everyone. The choices appear as
  buttons under the question.
- A question about you and the others in one sentence, such as what you watched and what the
  rest watched, is answered as two separate questions.

### Fixed
- Menu on All requests and My requests takes you back to Requests. The remote could not leave
  that page. With the filter panel open, the first press closes the panel and the next one
  closes the page.
- "Request in 4K" on a title page shows only when the requests server has a default 4K
  instance. This corrects the gap noted in the previous build.
- A request sent without choosing a server can only go out when the requests server has a
  default instance for that quality. Without one the button is off and the form says "No default
  server for this quality". When the list of servers cannot be read, HD stays open and 4K is
  closed. This is stricter than the requests server itself.
- Messages in the request form stay in view and take only the room they need.
- "My requests" in the request form shows only when the earlier request is your own.
- Picking "All seasons" in the request form no longer renumbers the list of seasons.
- Search in Discover no longer shows a page of an earlier search twice when you search for the
  same text again.
- A start from the version menu together with an ordinary start of the same title, such as a
  double press, no longer opens the player twice.
- Big P keeps to the kind you ask for. Ask for films and you get films, ask for series and you
  get series. Asked which films are playing right now, it lists active streams of that kind only
  and says how many it left out because their kind is unknown.
- "Family" or "household" in a request for something to watch together no longer quietly
  means only you.
- When your access to a library changes while Big P is looking something up, it does not show
  that result.
- The focus ring stays visible on a light background, and buttons that are not focused stay
  readable while another one has the focus.
- The dialog for picking an option, such as a version or a sort order, has the same proportions
  as the other panels on Apple TV.

### Worth checking
- Passed in the Apple TV simulator: Menu on All requests, and the request form for an account
  that may request but not manage. The other items are covered by automated tests only. Nothing
  in this build has been checked on an Apple TV yet.
- Requests: open All requests or My requests and press Menu on a card. You should be back on
  Requests with the inbox button focused.
- Request form: open a title with an account that may request but not manage. Check that the
  4K switch is there only when the requests server has a default 4K instance, and that you can
  reach the button with the remote.
- This build was made with Big P switched on. That has not been confirmed on a device, so
  please check that you can open it on your Apple TV.

## 2.8.1 · build 350 · 11 October 2026 · iPhone and iPad

<!-- commit: 584f1e38302fbd944019a55f66b7521203f08ce7 -->

### New
- Ask Big P what was added to your libraries. It answers for the period you name, such as this
  week, up to a month back, and shows the date each title was added. A local folder has no such
  date. The cards under the answer are the same titles as the list in the text.
- When you ask Big P what was watched without saying by whom, such as "What was watched this
  week?", it asks whether you mean yourself, the others or everyone. The choices appear as
  buttons under the question.
- A question about you and the others in one sentence, such as what you watched and what the
  rest watched, is answered as two separate questions.

### Fixed
- "Request in 4K" on a title page shows only when the requests server has a default 4K
  instance. This corrects the gap noted in the previous build.
- A request sent without choosing a server can only go out when the requests server has a
  default instance for that quality. Without one the button is off and the form says "No default
  server for this quality". When the list of servers cannot be read, HD stays open and 4K is
  closed. This is stricter than the requests server itself.
- Messages in the request form stay in view and take only the room they need, also on a small
  screen with large text.
- "My requests" in the request form shows only when the earlier request is your own.
- Picking "All seasons" in the request form no longer renumbers the list of seasons.
- Search in Discover no longer shows a page of an earlier search twice when you search for the
  same text again.
- A start from the version menu together with an ordinary start of the same title, such as a
  double press, no longer opens the player twice.
- Big P keeps to the kind you ask for. Ask for films and you get films, ask for series and you
  get series. Asked which films are playing right now, it lists active streams of that kind only
  and says how many it left out because their kind is unknown.
- "Family" or "household" in a request for something to watch together no longer quietly
  means only you.
- When your access to a library changes while Big P is looking something up, it does not show
  that result.
- Big P's confirmation card stays inside the conversation with the keyboard up on a small
  iPhone.
- On iPad the header of a film or series page no longer grows past a fixed height, and the
  spacing between posters in a grid stays the same at every window size.

### Worth checking
- Nothing in this build has been checked on an iPhone or iPad yet. The request form was checked
  in the Apple TV simulator only; everything else is covered by automated tests.
- Request form: open a title with an account that may request but not manage. Check that the
  4K switch is there only when the requests server has a default 4K instance, and that HD can
  be sent.
- Big P on a small iPhone: ask for something Big P has to confirm and keep the keyboard up.
  Cancel and Create should both be fully visible.
- Big P: ask "What was watched this week?" and check that it asks whether you mean yourself,
  the others or everyone. This needs an account that can see what the household watched, and
  it does not happen on a kids profile.

## 2.8.1 · build 349 · 10 October 2026 · Apple TV

<!-- commit: 5a31f6c8d60f77c7c2d4391c812c8c2a88ea83ac -->

### New
- A title page in Requests can now offer "Request in 4K" next to the actions that were already
  there. It shows when your account may request 4K, the title has no 4K copy or 4K request yet,
  and the requests server has a 4K instance. The form opens with 4K selected.

### Fixed
- A film you already have in HD can be requested in 4K. The request form used to stay closed
  for a film that was available, requested or processing in HD. When the quality you picked
  cannot be requested the form says why, and when it was requested before you get "My requests"
  in place of a button that could not send anything.
- Search asks the requests server only for a query you chose. That is a submitted search, an
  entry from your search history, or moving down from the keyboard to the results. Typing alone
  no longer triggers it, and a profile switch or an emptied field drops the chosen query.
- Search in Discover keeps loading further results after a profile switch or a new search term.
- Losing the right to manage requests while the Scope panel is open closes that panel. Focus
  moves to the Status row.
- Big P no longer leaves a film out of its suggestions because you watched something else with
  the same title. A watched Dune from 1984 used to hide Dune from 2021, and a watched series
  used to hide a film of the same name.

### Notes
- Known in this build: "Request in 4K" also shows when the 4K instance is not the default one
  on the requests server. Such a request is created and goes nowhere after approval. The
  request form has the same gap, for 4K and for HD: a request sent without choosing a server
  goes nowhere when the requests server has no default instance for that quality. A correction
  follows in a later build.
- Known in this build: a start from the version menu together with an ordinary start of the
  same title, such as a double press, can still open the player twice. A correction follows in
  a later build.

### Worth checking
- Passed in the Apple TV simulator: "Request in 4K" being there when it should and absent when
  it should not, and moving down from the keyboard to the search results. The other items are
  covered by automated tests only. Nothing in this build has been checked on an Apple TV yet.
- Request in 4K: open a film you have in HD with an account that may request 4K. Check that
  the action is there, that you can reach it with the remote, and that the form opens on 4K.
- Search: type a title and watch the requests row. It should fill after you submit or move down
  to the results, not while you type.
- This build was made with Big P switched on. That has not been confirmed on a device, so
  please check that you can open it on your Apple TV.

## 2.8.1 · build 348 · 10 October 2026 · iPhone and iPad

<!-- commit: 5a31f6c8d60f77c7c2d4391c812c8c2a88ea83ac -->

### New
- A title page in Requests can now offer "Request in 4K" next to the actions that were already
  there. It shows when your account may request 4K, the title has no 4K copy or 4K request yet,
  and the requests server has a 4K instance. The form opens with 4K selected.

### Fixed
- A film you already have in HD can be requested in 4K. The request form used to stay closed
  for a film that was available, requested or processing in HD. When the quality you picked
  cannot be requested the form says why, and when it was requested before you get "My requests"
  in place of a button that could not send anything.
- Search in Discover keeps loading further results after a profile switch or a new search term.
- Big P no longer leaves a film out of its suggestions because you watched something else with
  the same title. A watched Dune from 1984 used to hide Dune from 2021, and a watched series
  used to hide a film of the same name.

### Notes
- Known in this build: "Request in 4K" also shows when the 4K instance is not the default one
  on the requests server. Such a request is created and goes nowhere after approval. The
  request form has the same gap, for 4K and for HD: a request sent without choosing a server
  goes nowhere when the requests server has no default instance for that quality. A correction
  follows in a later build.
- Known in this build: a start from the version menu together with an ordinary start of the
  same title, such as a double press, can still open the player twice. A correction follows in
  a later build.
- Known in this build: Big P's confirmation card can still run below the edge on a small
  iPhone with the keyboard up. In the iPhone SE simulator Cancel and Create stick out about
  4 points on the card with a password field. Not fixed in this build.

### Worth checking
- Passed in the iPhone simulator: "Request in 4K" being there and the form opening on 4K. The
  other items are covered by automated tests only. Nothing in this build has been checked on
  an iPhone or iPad yet.
- Request in 4K: open a film you have in HD with an account that may request 4K. Check that
  the action is there and that the form opens on 4K.
- Big P on a small iPhone: ask for something Big P has to confirm, keep the keyboard up, and
  report how far the card runs below the edge on your device. Keyboard height and safe area
  differ per device.
- Big P suggestions: if you watched an older film that shares its title with a newer one, ask
  for the newer one and check that it shows up.

## 2.8.1 · build 347 · 9 October 2026 · Apple TV

<!-- commit: 055844ce11d2ee43a087a32639b62d464cb6d25b -->

### Fixed
- Big P writes a name such as Spider-Man with a hyphen when its answer joined the two parts
  with a long dash.
- Big P answers a short story question that names no title, such as "what about him", without
  the earlier conversation. The spoiler filter cannot see a question like that, so the earlier
  conversation could carry a spoiler into the answer.

### Worth checking
- This build was made with Big P switched on. That has not been confirmed on a device, so
  please check that you can open it on your Apple TV.
- Still to be checked on an Apple TV: both fixes. They are covered by automated tests only.

## 2.8.1 · build 346 · 9 October 2026 · iPhone and iPad

<!-- commit: 055844ce11d2ee43a087a32639b62d464cb6d25b -->

### Fixed
- Big P writes a name such as Spider-Man with a hyphen when its answer joined the two parts
  with a long dash.
- Big P answers a short story question that names no title, such as "what about him", without
  the earlier conversation. The spoiler filter cannot see a question like that, so the earlier
  conversation could carry a spoiler into the answer.

### Worth checking
- Ask Big P about a title with a hyphen in its name and read how the name is written.
- Talk with Big P about a series you have not finished, then ask a short follow-up without the
  title in it. The answer should not give away what happens later.
- Still to be checked on an iPhone or iPad: both fixes. They are covered by automated tests
  only.

## 2.8.1 · build 345 · 8 October 2026 · iOS

<!-- commit: 1358eb0fa7af29f65c3ef8d4853cf048c0028435 -->

### Fixed
- Big P is enabled again in the iOS TestFlight build. The release lane now includes its rollout flag by default.

### Worth checking
- Open My Pleya and confirm that Big P is available with your existing profile. Check an ordinary question and returning to your content.
- This corrects the release configuration of build 344; physical iPhone acceptance remains open.

## 2.8.1 · build 344 · 8 October 2026

<!-- commit: b392a2e82f8f67e415e51e6c5434f53a98e8f351 -->

### Improved
- Search and discovery distinguish titles you can watch from titles you can request.
- Requests show clearer statuses, filters and recovery after actions. Managers can edit season selections and access the actions allowed by their role.
- Apple TV server tiles open connection information. Disconnect and remove remain separate, confirmed actions.

### Fixed
- Starting playback shows progress immediately and prevents a second start while the first is preparing.
- Request forms preserve existing server options and handle uncertain saves without reporting a false success.
- Changing request-service credentials clears the previous connection test before saving.
- Live TV schedule labels follow the selected language. Shared-session screens prioritise the available positive action.

### Worth checking
- This is an internal test build. Please check playback and resume on Apple TV, request management with your server and account permissions, and returning to the same item after an action.
- Physical Apple TV acceptance, real-server coverage and the complete Requests design matrix remain open. Passing simulator journeys cover selected states only.

## 2.8.0 · build 298 · 24 September 2026 · Apple TV

<!-- commit: 53e2704a -->

### Improved

- **Search on Apple TV has a new field.** It is narrower, starts on the same edge as the
  results below it, and shows the result count in the middle. The hint text stays on one line.
- **The season selector on a series page now sits on the "Episodes" heading line**, next to
  the count of episodes and how many you have watched. The seasons are filled pills with the
  active one in white, and the row steps aside when you move to the cast or extras below.
- **The Appearance settings page has clearer focus movement.** Left from any row returns to the
  active category, and right from a category opens it with the first row selected.

### Fixed

- **Reconnecting a server for the profile you are already using no longer throws you back to
  the start of My Pleya.** The section you had open stays open. It only closes when the server
  behind it (Seerr or Tautulli) went away.
- **The profile button now opens the "Who's watching?" screen** instead of the plain profile
  list. Menu closes it and returns to the button. Managing profiles still opens the list.
- **Full durations now have a space between number and unit**, for example "5 minutes" in the
  sleep timer.

## 2.8.0 · build 296 · 24 September 2026 · iPhone, iPad and Mac

<!-- commit: 5b937630 -->

### Fixed

- **Signing in with Plex from your own Home profile no longer lands on an empty "Nothing to
  borrow yet" page.** The app now recognizes when the target profile already has that Plex
  account, through its own Home profile or a saved connection, and reconnects it directly
  instead of routing through the borrow step.
- **The collapsed sidebar on Mac now fades out the server name and arrow next to a server
  icon**, the same way every other row already does when the sidebar is collapsed, instead of
  leaving clipped text behind.

## 2.8.0 · build 297 · 24 September 2026 · Apple TV

<!-- commit: 5b937630 -->

### Fixed

- **Signing in with Plex from your own Home profile no longer lands on an empty "Nothing to
  borrow yet" page.** The app now recognizes when the target profile already has that Plex
  account, through its own Home profile or a saved connection, and reconnects it directly
  instead of routing through the borrow step.

### Notes

- The collapsed-sidebar fix in build 296 is for the Mac and iPad rail; Apple TV does not use
  that layout.

## 2.8.0 · build 295 · 24 September 2026 · iPhone and iPad

<!-- commit: 81b8be59 -->

### Improved

- **Watchlist filters now open in one sheet**, so you can choose the type and availability together.
- **Marking a title watched while its server is offline updates the screen immediately** and queues the change for that server.

### Fixed

- **A 4K request now picks a matching Overseerr server** instead of retaining the standard-quality server and its profile.
- **Audio and subtitle language choices you set yourself stay saved**, even if server profile data arrives later.

### Worth checking

- On iPhone or iPad, filter the Watchlist, mark a title watched while one server is unavailable,
  and switch a request between standard and 4K quality if your account supports it.

### Notes

- This iOS build includes shared reliability fixes. The latest Home hero and settings redesign
  in build 294 is for Apple TV; the iPhone and iPad layout has not been changed to match it.

## 2.8.0 · build 294 · 23 September 2026 · Apple TV

<!-- commit: 3e46c035 -->

### New

- **Home can feature up to twelve recent films**, and each hero title shows whether it is
  unwatched, in progress (with a percentage), or watched.
- **Collections and Playlists have their own entries in My Pleya** where the connected Plex or
  Jellyfin server provides them. Each overview keeps its source visible.

### Improved

- **Appearance settings are grouped into four TV-friendly categories** while keeping the
  existing options and saved preferences.
- **Home layout makes similar recent rows easier to tell apart** by naming the media type and
  keeps their existing ordering and visibility controls.
- **Add Connection shows all six existing routes in a two-column TV picker** with remote focus
  and a clear way back to Servers.

### Worth checking

- On Apple TV, move through the Home hero with the remote and compare unwatched, in-progress,
  and watched titles. Check that Play, Resume, and Details stay reachable.
- Open Collections, Playlists, Appearance, Home layout, and Add Connection from My Pleya; use
  Back to confirm focus returns to the tile you came from.

### Notes

- This build is for Apple TV. The connection forms and other remaining windows are still being
  redesigned; their existing routes and actions remain available.

## 2.8.0 · build 282 · 16 September 2026

<!-- commit: 69da51d -->

### New

- **Collections open in the same redesigned look as the rest of the catalog on Apple TV**, with
  the same hero artwork, cards, and grid you already browse the rest of your library in.
- **An actor or crew member's page on Apple TV now matches the new design**, with a circular
  photo at the top and their other titles laid out as browsable cards below.
- **The Apple TV player shows resolution, codec, and audio and subtitle language under the
  title**, along with whether it is playing directly or transcoding.
- **Apple TV Home works again when the server is unreachable**, showing the servers this device
  knows about with a status for each, a way to reconnect, and a path into Settings.

### Fixed

- **The on-screen keyboard on Apple TV could leave Select dead across the whole app** until you
  force-quit and reopened it.
- **Typing on the Apple TV keyboard and pressing Select right after could get eaten** instead of
  submitting what you typed.
- **A double press on Apple TV could close a menu or panel you had just opened.**

## 2.8.0 · build 280 · 14 September 2026

<!-- commit: 4364327 -->

### New

- **Film and series detail pages get a top-to-bottom redesign on Apple TV.** They always open
  full screen, a season's episodes sit in a single scrollable rail with your place on the
  current season remembered when you switch, and a long cast or extras row no longer runs into
  the fixed information band above it.
- **The player's info panel on Apple TV is now the one place for audio, subtitles, and
  quality**, redesigned to match the rest of the app. Each source line shows which backend it
  plays from. Rating a title needs a press to open the row before left and right can change the
  score, so a stray remote press can no longer change a rating by accident.
- **A single context menu on Apple TV poster tiles** now covers resume, play from the
  beginning, jump to the info page, and switching source, with the poster shown at the top of
  the menu.
- **Libraries doubles as source management on Apple TV**: manage your Plex, Jellyfin, and Pleya
  Server connections from the same screen you already browse them in.
- **Watchlist, Requests, and Search on Apple TV use the same catalog layout as the rest of the
  app**, filters included. Search keeps its results heading on screen instead of losing it while
  you scroll, and a request keeps showing its real status from Seerr or Overseerr.
- **Activity on Apple TV shows what is actually playing right now**, and only appears for
  accounts allowed to see it.
- **Audio loudness is measured and matched across titles and sources**, on Apple TV and Android,
  so volume no longer jumps between an old film mixed quietly and a new episode mixed loud.
- **iPhone gets the same unified Home, catalog, and detail redesign Apple TV already had.**
  Films and Series are landing pages of their own, with a dedicated "all films" / "all series"
  catalog behind the "›" button and its own filter and sort sheet.
- **Custom rows on Home**: save any filter you can build (a genre, a studio, anything else) as
  its own row, and reorder your rows without leaving Home. A row now survives exporting and
  reimporting your settings.
- **A title available on more than one of your servers now shows once**, with the source you
  last watched it from remembered, and marking it watched applies to every source it exists on,
  not only the one you played.
- **Search on iPhone has dedicated sections for films, series, and people**, matching the
  redesigned catalog.
- My Pleya and Settings are reorganized on iPhone to match the new design.

### Improved

- Home and the catalog landing screens share one underlying layout instead of separate copies,
  so scrolling and rows behave the same way everywhere.
- The hero banner on mobile Home no longer keeps auto-scrolling while you are reading it.
- Catalog tiles use the same code as the rest of the catalog, so filters and sorting stay
  consistent between screens.

### Fixed

- Marking a title as played no longer credits a source you never actually watched it from.
- Tapping an already-selected filter chip on Home switches back to the default view instead of
  doing nothing.
- "Play on [server name]" is translated instead of always showing in English.
- Search remembers which tab you searched from when you come back to it.
- The down button on the player panel no longer falls out of the remote's focus order, and the
  panel asks for its own redraw when it moves focus instead of waiting on something else to.
- A new custom Home row no longer lands at the bottom the moment you have ever reordered rows,
  and a source change made while a row is still loading no longer gets lost.
- A slow library now gets a fair chance to load into a custom row instead of being silently
  skipped, and a Plex server that fails to parse is logged instead of disappearing without a
  trace.
- An empty Home screen no longer blocks access to your own custom rows, and the selection ring
  no longer lingers on a row you just deleted.
- The catalog grid keeps its focus ring after scrolling, and the filter sidebar stays reachable
  after picking a sort order.
- An empty catalog leaves the remote on a control you can actually use, and stepping left out of
  the filter rail no longer jumps you to the wrong catalog.
- Offline mode on Apple TV drops its dead navigation tabs and offers to reconnect once you are
  back online.

## 2.8.0 · build 262 · 5 September 2026

<!-- commit: 06b2cc0 -->

### Notes

- The same Apple TV build as 260, with the release notes below it. Build 261 sits between the two
  and is not this app: it is the code of build 245, rebuilt so a tester who had ended up on an
  Apple TV build they were not meant to see could be moved back to what they already knew. It
  went to one tester group and to nobody else.

## 2.8.0 · build 261 · 5 September 2026

<!-- commit: 55035a2 -->

### Notes

- Build 245 rebuilt under a new number, for one tester group. No code changed between the two, so
  there is nothing here that build 245 did not already have.

## 2.8.0 · build 260 · 5 September 2026

<!-- commit: 72227db -->

### New

- **The Apple TV home screen is a billboard with a feed under it.** The navigation moved to a
  horizontal bar across the top, so nothing takes width away from the artwork. A featured film
  fills the frame, and the first row peeks up from the bottom edge to say the page continues.
  Walking through the rows no longer pushes the billboard around.
- **My Pleya is a destination of its own.** Watchlist, requests, libraries, servers, settings,
  logs, watch together and about sit on one page frame instead of behind a sidebar.
- **Films and Series have their own landing pages, with a catalog behind them.** A title that
  lives on more than one of your servers appears once. Pressing play asks which source to use
  only when that choice makes a difference.
- **Language and subtitles can be set per series.** A show you watch subtitled stays subtitled,
  including the episodes you have not opened yet, and a change offers to apply to the whole
  series rather than to the episode in front of you.

### Improved

- **"Recently released" on the home screen means the last 90 days.** It had no lower bound at
  all, so a library that had just been filled with older films put a 1998 title under a heading
  promising the opposite.
- **The player overlay keeps its distance from the left edge.** Title, season and episode, and
  the timeline sat against the very edge of the picture, which is where a television crops.
- **Artwork is requested at the resolution of the screen it lands on.** The detail backdrop was
  being enlarged from a smaller image.

### Fixed

- **One press on the remote ring is one step.** A press was arriving twice, so the top bar
  skipped a tab and a step down skipped a row. A press on the ring is a touch and a press at the
  same time, and tvOS reports those over two separate paths.
- **Coming back to the home screen after playing something shows the artwork again.** The
  buttons of the billboard could take the remote while the picture itself had scrolled off the
  top, which left two buttons floating over the navigation bar with nothing behind them.
- **Up from the first row brings the billboard back into view**, rather than only back into the
  focus order.
- **A vertical step arrives in the column it left from**, and the last tile of a row has room to
  expand into instead of running off the page.
- **Leaving the player gives you the library back straight away.** Closing a title used to wait
  for the server to confirm where you stopped, and on a slow or unreachable connection that was
  several seconds of black screen. The position is written in the background now, and if it does
  not reach the server it is kept on the device and sent with the next sync.
- **Playback keeps reporting to Plex after the app has been in the background.** Coming back to
  Pleya on Apple TV could close the reporting session for good: nothing showed in Plex or
  Tautulli for the rest of the film, and the resume position stayed frozen at the moment you put
  the app away. Coming back opens a fresh session, and the position you actually stopped at is
  written.
- **"Now playing" in the sidebar can be reached with a remote.** It was drawn but skipped by
  D-pad navigation, so on Apple TV you could see it and never select it.
- **Sending a log no longer runs into the same refusal again and again.** The relay accepts one
  upload per minute. A second press inside that minute now says how much of the minute is left
  instead of firing another request that comes back refused.
- Overlays and context menus stay inside the area a television actually shows.
- The top row of the catalog no longer touches the safe top edge, and the header actions stay
  reachable after stepping left out of the grid.
- A library that disappeared no longer leaves the Libraries page blank, and switching libraries
  quickly no longer lets a slow one overwrite the choice you just made.
- The back button is gone from surfaces a remote could never reach it on.

### Worth checking

This build is the Apple TV redesign, so it is the remote that needs the mileage rather than the
screenshots. Four things in particular:

1. Walk the top bar left and right, landing on Home included. Every press should move exactly
   one tab.
2. Menu on Home should leave the app. Menu anywhere else, a My Pleya section included, should
   stay in it.
3. Scroll the home screen down, open a title, play it, and come back with Menu. The billboard
   should be on screen, not two buttons over the navigation bar.
4. Look at what the home billboard offers. Films released in the last three months, nothing
   older.

### Notes

- iOS and macOS are unchanged in this build. Everything above is Apple TV.
- Build 259 was withdrawn and this one replaces it, with the same code behind it. 259 took the
  number of a build that had been installed straight from Xcode earlier that day and never
  reached TestFlight, which left two different builds wearing one number. It was expired to end
  that, and expiring cannot be undone.

## 2.8.0 · build 242 · 23 August 2026

<!-- commit: aa74004 -->

### New

- **A "Maximum Resolution" setting for playback.** Under Settings → Playback → Maximum
  Resolution, you can cap what the app asks a server for, even when the file itself is larger.
  Useful on a connection where 4K would be more than the link should carry.
- **A Pleya Server can be disconnected from Settings → Connections.** It had no entry there at
  all before; removing one meant going two screens deeper into a profile's management screen,
  and if the session there had expired, that screen only offered to sign back in.

### Improved

- **Jellyfin now plays TrueHD audio tracks directly instead of transcoding them**, on desktop,
  iPhone, iPad and Apple TV. Nothing about the video or the audio changes: the app simply stops
  asking the server to re-encode a track it could already decode itself.

### Fixed

- **A "Session expired" banner that kept coming back after every restart is gone.** Reconnecting
  cleared it once, but the very next launch showed it again, with re-entering the server address
  from scratch as the only way out. A session that was not actually dead now recovers on its own.
- **Disconnecting a Pleya Server now removes it for good.** It could keep the connection around
  behind the scenes, so a stale reconnect banner came back, sometimes only after restarting the
  app.
- **The sidebar no longer gets stuck open with nothing selected.** It could happen when the row
  you were focused on, such as the reconnect prompt or "Now watching", disappeared on its own
  while you were on it.

## 2.8.0 · build 240 · 21 August 2026

<!-- commit: 6f28619 -->

### New

- **Recommendations can start from what you watched before you had Pleya.** The taste engine
  only ever learned from what you played in Pleya itself, so a server you had used for years
  through other clients still left you with an empty profile. If that server is monitored by
  Tautulli, you can connect it and import that history into the same engine. It reads your own
  watch history only, and the profile it builds stays on your device.

### Improved

- **The home billboard no longer crops its artwork.** It is drawn in two layers: a blurred,
  darkened copy fills the canvas and the artwork itself sits on top in its own shape, so nothing
  is cut off and no bare panel shows around it. Both layers come from one image, so this costs
  no second download. On iPhone the artwork clears the Dynamic Island and runs the full width of
  the screen. On iPad in portrait the title is drawn at the size that screen deserves instead of
  at phone size.
- **Settings changed on another device now show up while the app is open.** Hiding a library or
  reordering your libraries on your Mac reaches the Apple TV without restarting it. The same
  happens after importing a settings file or resetting settings.
- **Coming back to Pleya checks for settings changed elsewhere.** A device that was asleep or in
  the background no longer waits for the next launch to catch up.
- **Switching profile loads that profile's own settings.** Each profile has had its own place in
  iCloud since the previous build; now switching also fetches it.
- **The iCloud switch says what the sync is doing.** One line under it: syncing, when something
  was last sent, whether iCloud has run out of room for settings, and whether a setting is too
  large to send. It says what this device sent, never what your other devices received, because
  iCloud does not report that.

### Fixed

- Resume no longer jumps backwards when the same title is open on two devices. A player left
  paused used to keep writing its own position over a device that was still watching.
- Jumping to a new position is saved right away instead of at the next ten-second update, so
  closing straight after a seek keeps the position you jumped to.
- Playing a downloaded file while online now resumes from whichever position is actually the
  most recent, rather than always preferring the one stored on this device.
- A position you jumped to during a network hiccup is no longer lost. It used to be dropped
  while the app was backing off from a failed update, which left the server on the position
  from before the jump until playback happened to continue.
- Turning a setting off on one device now turns it off on your other Apple devices too.
  Switching something on already travelled; switching it off did not.
- Hidden libraries could come back on your other devices. A list that only held local folders
  was read as empty by the sync and removed from iCloud, which put the libraries back on every
  device that read it afterwards.
- Signing out of iCloud while Pleya is open is noticed right away. Settings sync used to keep
  reporting itself as healthy while nothing was actually being sent.
- Importing history from Tautulli brought in nothing at all, or counted episodes twice. Every
  row was checked against a value that names the player rather than the server, so on a real
  server each one was skipped and the import quietly did nothing. Episodes you had also watched
  in Pleya were looked up under the wrong key and came in a second time.
- A saved Tautulli connection stayed idle after a cold start. Discover finished before the
  stored connection had been read, concluded nothing was connected, and did not ask again until
  the next launch.
- Importing history could reach beyond your own account. A profile without admin rights was
  handed the full connection record, key included, and could name whose history to fetch. On a
  shared server that meant one profile could be pointed at another person's viewing. The import
  now decides that itself, and the key never leaves the integration.
- The home screen hero prefers a wide backdrop again on narrow phones. Square art is used only
  when a title has no backdrop at all, where it used to be blown up to fill the box with the
  clear logo drawn on top of it.

### Notes

- **Settings that describe a device now stay on that device.** Volume, download folder,
  hardware decoding, HDR and the last used remote-control address were being copied between
  your Apple devices, where they either meant nothing or were plainly wrong. They are yours
  per device from now on. Everything that is a genuine preference, like subtitle appearance,
  theme and playback behaviour, keeps syncing as before.
- **TestFlight builds carry these notes themselves now.** Attaching a build fills its "What to
  Test" from this file, and the App Store version page gets the same text, so you do not have to
  open the site to see what a build changed.

## 2.8.0 · build 234 · 20 August 2026

<!-- commit: cdeda9c -->

### Improved

- **Error and status messages are easier to read, and the important ones now offer a way to
  act on them.** They used to be plain text on a flat red or green bar, which fell short of
  comfortable reading in the dark theme. They now match the rest of the app's cards, stay
  readable in dark, OLED and light, and a failed action can carry a Retry button right on the
  message instead of leaving you to find one elsewhere. A repeated failure, like a server that
  keeps timing out, now folds into a single message with a counter instead of stacking a new
  one on screen every time.

### Fixed

- **The home screen's hero image no longer crops out the sides on narrower phones.** The app
  was asking the server for a wide picture even when the artwork itself is a tall poster or a
  square, so the server centred and cropped it to fit, cutting off whatever sat at the edges.
  It now asks for the image in its own shape, so the full picture shows.

### Notes

- **Twenty translated error messages had a gap where the underlying, untranslated text used to
  leak in.** That gap is gone across all fifteen supported languages, so a network or login
  failure always shows in your own language now.

## 2.8.0 · build 233 · 19 August 2026

<!-- commit: a15a230 -->

### Fixed

- **A row opens the title you were looking at, not the one that took its place.** Rows reload
  while you are looking at them, and a reload can reorder or drop a card. Until now the app
  remembered a position, so a title that slid into that slot between the frame you saw and
  the moment you pressed was the one that opened. It now remembers the title itself. If that
  title has gone, the press opens nothing rather than the wrong thing, and the next press
  acts on the card you can see. This applies to phone, tablet and desktop rows; the Apple TV
  home rows use a different row and are covered by the next build.
- **Select could stop working on a row entirely.** When a row lost its **View All** card
  during a refresh, or gained a title while the cursor sat on that card, the row kept
  pointing at something that was no longer there. Pressing Select then did nothing at all, or
  opened the whole category instead of the poster under the cursor, until you moved left or
  right.
- **The filter line in Requests can be reached with the remote**, and pressing down from it
  while a search is running now reaches the results instead of doing nothing.

### Notes

- **Groundwork for the wrong-title reports on Apple TV.** Those reports could not be answered
  from a log, because nothing recorded which card a press resolved to or what happened to it
  on the way to the screen that opened. A press now leaves a single line covering that whole
  path, and an unusual one leaves a short timeline instead. Nothing about this changes what
  you see; it is there so the next report can be answered instead of guessed at.


## 2.8.0 · build 232 · 19 August 2026

<!-- commit: 38efe8a -->

### Fixed

- **Controls beside the sidebar respond again.** Moving a mouse or trackpad towards the rail
  handed it the whole strip up to its open width, so a control the page puts there, such as
  **Recommended** on a library page, opened the menu instead of doing its own job, and the
  menu then swallowed the click. The rail claims that strip only once you have actually
  entered over it, and gives it back as it closes. Everything the previous build fixed stays
  fixed: coming in over the rail and moving straight to a label still works, and a click
  aimed at the menu still cannot start the billboard.

### Worth checking

- The sidebar with a mouse or trackpad, both ways round. From the middle of the screen
  straight onto **Recommended** on a library page: it should switch tabs and the menu should
  stay shut. Then in over the rail and quickly on to a menu label without pausing: the menu
  should stay open and respond.
- The two checks from build 231 are still open: the request list with real titles and posters
  on a phone, and subtitle language on Apple TV while Plex is transcoding.

## 2.8.0 · build 231 · 19 August 2026

<!-- commit: 7c3d47e -->

### Fixed

- **Your subtitle and audio language is remembered when Plex transcodes.** Picking a language
  only stuck when the file played directly. As soon as Plex re-encoded, which it always does
  for burned-in or image-based subtitles and for anything streamed over the internet, the
  choice went straight to the server and Pleya never saw it. The next episode then started in
  whatever the server preferred, so you got a different language rather than no language,
  which made it easy to miss. The choice now also lands on the series itself, the way it
  already did on direct play. That is the only thing that can work when the subtitles are
  burned into the picture. Switching no longer waits for that to be written, and a failed
  write can no longer make the switch itself fail.
- **The quick buttons on a hover preview no longer black out the app.** Play, add and info on
  the preview that appears over a card opened their screen outside the profile you were in,
  leaving an error across the whole window. The plus also left the preview standing on top of
  the menu it had just opened, where it swallowed the clicks meant for that menu.
- **A click on the sidebar no longer starts whatever sits behind it.** The rail switches to
  its wide state at once while the width takes 200 ms to catch up, and in that gap a click
  aimed at a menu item could land on the billboard and start playing. The rail now owns the
  strip it is about to fill, from the first frame of opening until the last frame of closing.
  Tapping the billboard opens the title; the play button still plays.
- Filters, Sort and Group open in the middle of the window instead of in the corner you
  clicked them from. They used to open at the mouse, which is right for a context menu and
  for nothing else, so on a desktop window a panel of 700 by 400 ended up clamped against the
  right edge with most of the height unused.

### Improved

- Discover on Requests uses the same header as a library page: film and series as tabs, genre
  as an action beside them. It was a double row of outlined pills that took more room than the
  posters underneath, 92 pixels of it against 42 now.
- Choosing a type on Discover selects that type instead of falling back to All, and clearing a
  genre is a row in the panel rather than a second tap on the chip you just picked.

### Worth checking

Two things in this build are easier to break than to notice, so a look at them helps.

- Your list of requests, on a phone. Every row should carry the real title and poster, and the
  status beside it should agree with what Overseerr says. Then send one request with a
  different server, quality profile and root folder than the defaults: all three should arrive
  in Radarr or Sonarr exactly as you set them.
- Subtitle language on Apple TV, on a series Plex is transcoding rather than playing directly.
  Pick a language partway through an episode, then start the next one. It should open in the
  language you picked.

### Notes

Moving a mouse or trackpad towards the sidebar claims the strip beside it as soon as the
pointer arrives, so a control the page puts there, such as **Recommended** on a library page,
opens the menu instead of responding. Fixed in the next build; on this one, reach those
controls from further right or use the keyboard.

## 2.8.0 · build 228 · 18 August 2026

<!-- commit: 04f1411 -->

### New

- **Pick the quality profile and root folder when you request something.** The advanced
  options on a request only let you choose which Radarr or Sonarr server to send it to, so a
  profile you had set up yourself was out of reach. Both pickers open on whatever that server
  would have used anyway, and changing server clears them rather than carrying the previous
  server's choices over.

### Improved

- **Requests show what was actually requested.** The list used to head every row with
  "Movie" or "Show", above a grey placeholder, because the request itself carries only an id
  and an availability state. Pleya now resolves each title once and remembers it, so the real
  name, year and poster appear, with the kind and year on their own line underneath.
- Seasons on a request fit on one line. A run of consecutive seasons reads as a range, gaps
  stay visible rather than being smoothed into one, and a request spread over too many
  separate runs says how many there are.
- A request no longer shows "Available" next to "Completed". Where the two say different
  things, such as approved but only partly downloaded, both still appear.
- The filter tabs on Requests and on your watchlist keep their margin when you scroll them,
  and the active filter scrolls itself into view. The last chip is no longer faded out
  halfway through its own word.
- The search field on Requests has room for its sentence again instead of being pushed onto
  two lines by a button that repeated what the whole field already did.
- Your watchlist says what it is sorted by, on the button itself. It used to be in a tooltip,
  and tooltips never open on a touchscreen.

### Fixed

- **Sorting your watchlist no longer blanks the screen.** Choosing an order closed the app
  behind the sheet instead of the sheet, leaving nothing on screen and the sort unapplied.
  The same fault sat behind Request, Remove and Cancel on a watchlist title.
- **The audio priority setting responds again.** Choosing between even volume and original
  Dolby Atmos did save your choice, but the selected option looked exactly like the
  unselected one, so there was no way to tell. Every setting of that shape was affected.
- The skip intro button no longer appears on films. Films rarely carry a real intro marker,
  so the button was working off a chapter title and could sit there for minutes, returning
  every time you touched the screen. Skipping the credits is unchanged, on films as much as
  on episodes.
- A status label on a poster stays inside the poster instead of being cut off at its edge.
- Connecting to Tautulli says so when something other than Tautulli answers. Behind a login
  page or a reverse proxy the reply came back as a Tautulli error, which sent you looking in
  the wrong place.

## 2.8.0 · build 227 · 18 August 2026

<!-- commit: 68ad70d -->

### New

- **Who watched this, and who is watching now.** Connect a Tautulli server and a title shows
  who has seen it and how often, with a separate screen for the streams playing at this
  moment. Plex only, and only if you run the server yourself: a Tautulli key opens that
  server's entire admin API, so Pleya keeps it in the vault of the profile you added it to
  and leaves it out of settings export and iCloud sync.
- **Levelling the volume and taming loud effects are two switches now.** They used to be one
  setting with three positions, so softening the bangs late at night also flattened the rest
  of the film. An existing choice carries over to the new pair. While Dolby passthrough is
  running, levelling is not possible and the player says so instead of failing quietly.
- Pleya remembers your audio and subtitle language per title rather than per session, so the
  next episode starts the way you left the last one. On Apple devices that memory follows you
  over iCloud, and an optional switch writes the language onto the show in Plex so the
  official Plex apps pick it up too.
- On the Requests screen a row of posters expands into a full grid, so you can take it in at
  once instead of scrolling sideways.

### Improved

- Settings, tabs and requests follow one layout instead of three.
- The refresh button on the home screen shows that it is working, instead of looking like
  nothing happened.
- Library pages put the library name in the page header and the tabs and filters on one
  line. On Apple TV the artwork above them takes the room the row below leaves unused.
- On Apple TV everything is drawn a little smaller, at scale 1.85 instead of 2.00. A
  settings page fits six rows where five fitted before, and a poster row gains about a card.

### Fixed

- Posters on a phone. A composed list put four cards of roughly 85 points next to each
  other, which cut off nearly every title. That is three columns on a normal phone now, two
  on a small one, and a title may run to two lines without making its neighbours taller. A
  status label that does not fit shows its icon instead of clipping mid-word.
- Cards in a grid have real spacing again, in both directions. A focused card grew over the
  three pixels of padding that were separating it from its neighbour, and the caption came
  out of one ratio that left too little room for two lines of text in a narrow column. The
  caption follows the system text size, so a larger font makes the grid taller instead of
  cutting the year off.
- The first row of a grid no longer sits against the hairline under the heading.
- On Apple TV, the text over the artwork on Libraries ran into the heading of the first row.
- On Apple TV, a focused row in Settings was invisible. Navigating always worked; the
  highlight was painted over by the card behind it.
- iCloud sync is visible in Settings on Apple TV.
- The download location stays on the device you set it on, instead of following iCloud to
  another one.
- A settings page no longer shows a divider with nothing under it. Two playback options are
  Android only, and hiding them left their separator behind.
- Connecting Tautulli: the screen keeps the connection method you were using, and a rejected
  key says whether the token expired or the wrong method is selected. Both used to read as
  "token expired", which sent people off generating tokens they did not need.
- Secrets stay out of the log you can send in for support. Keys in web addresses and
  authorization headers are stripped before a line is written.
- An intro marker is only skipped automatically for an episode. In a film, a chapter called
  "Intro" was skipping real film.

## 2.8.0 · build 221 · 17 August 2026

<!-- commit: 2cb7ae8 -->

### Fixed

- Watchlist cards no longer overlap. On TV, the title of a playable card ran into the row
  below it and posters in the same row came out at different heights. The card was drawn
  32 pixels taller than the cell holding it, in both the Watchlist grid and the watchlist
  row on My Pleya.

### Improved

- On phones, My Pleya is the only personal entry point. The avatar menu in the top right of
  the home screen is gone there; Profiles, Settings and Sign out sit at the bottom of My
  Pleya instead, and the My Pleya tab now shows your actual profile picture. Desktop and
  Apple TV keep the header menu, because they never show a My Pleya tab.
- The two-person icon on the home screen is Watch Together and the phone icon is the
  Companion Remote. Neither one changed.

## 2.8.0 · build 220 · 16 August 2026

<!-- commit: dd75c69 -->

### New

- **Your watchlist, from both sides.** Titles you add to your Plex watchlist on your phone,
  and anything you favourite in Jellyfin, now show up in Pleya as one list. It has its own
  spot in the sidebar on desktop and Apple TV.
- **My Pleya**, a personal tab on phones that gathers your watchlist, downloads, requests
  and settings in one place instead of spreading them across the bottom bar.
- Add and remove from the detail screen, the long-press menu and the sheet. The action only
  appears for movies and shows, and only while you are online: a watchlist change is
  refused rather than silently queued when there is no connection.

### Notes

- The same film can be a Plex watchlist entry and a Jellyfin favourite at once. Removing it
  takes it off both. If one side fails, Pleya re-reads the list instead of guessing what
  happened.

## 2.8.0 · build 219 · 15 August 2026

<!-- commit: 4e9b76b -->

### Fixed

- **Clicking a letter on the Apple TV keyboard does something again.** Swiping worked,
  dictation worked, typing from an iPhone worked, but pressing the touchpad on a letter did
  nothing at all. The press was being claimed before tvOS ever got to see it. Search, sign
  in, server addresses and the Requests screens all use that keyboard, so all four were
  affected.

## 2.8.0 · build 218 · 14 August 2026

<!-- commit: 717ed46 -->

### New

- **Pick a spot on the timeline with the remote.** Press select on the focused progress bar
  and playback pauses on a preview frame; left and right move the preview, select jumps
  there, back cancels. The thumbnail stays pinned while you move.
- **Seeking speeds up as you keep swiping.** The 1.5x to 10x acceleration used to need a
  held D-pad, so swipes on the Siri Remote touchpad were stuck at ten seconds a step
  forever. Scrub thumbnails now show up during swipes too.

### Fixed

- The skip-intro and next-episode buttons were nearly unreachable with a remote. Pressing up
  opened the player controls instead, and the only route to the button ran through the
  timeline. Up now goes straight to it while it is on screen, and it no longer disappears
  while it has focus.
- During the credits, two next-episode buttons could appear at almost the same spot.
- **Autoplay silently skipped episodes.** Three separate faults: a stuck loading flag that
  killed every later attempt in the session, an end-of-file signal that was lost if it
  arrived during a transition or behind the "still watching?" prompt, and a short episode
  that ended before the next one was known. Every decision the countdown makes is now in
  the log.
- Uploading a log always failed with the same unhelpful message. The relay was fine; Pleya
  was sending up to 5 MB at a server that accepts 1 MB, and never read the reply. Logs are
  now trimmed to the newest lines with a marker, and every outcome (too large, too soon,
  refused, server error, no connection) says what it actually was.
- **No macOS build in TestFlight was installable since build 196.** An export-compliance key
  was missing from the macOS app, so Apple hid every upload from testers while the upload
  itself reported success. Builds 214 and 216 were released retroactively.

## 2.8.0 · build 214 · 10 August 2026

<!-- commit: aac9a24 -->

### Fixed

- **The way out to Jellyfin arrived five minutes too late.** On the "Sign in with Plex"
  screen, the "Using a Jellyfin server?" button only appeared after the PIN timed out, so
  anyone who picked Plex by mistake stared at a code for five minutes first. It now sits
  under the PIN itself, in both the QR and the browser flow, and it properly cancels the
  Plex attempt instead of leaving it running in the background.
- **The profile screen on macOS was blank until you pressed Esc.** Two things at once: the
  screen could not tell "still loading" from "empty" from "stalled", and the add-profile
  button sat below the fold with nothing to scroll it into view. There are three distinct
  states now, and the button lives inside the empty state.

## 2.8.0 · build 212 · 9 August 2026

<!-- commit: b1cb51b -->

### Fixed

- **Audio could cut out entirely on Apple TV over HDMI.** With audio output on `auto` and a
  Dolby track, Pleya would send a bitstream to a receiver that never agreed to take one, and
  the audio renderer stalled. `auto` no longer bitstreams at all; passthrough stays a
  deliberate choice.

### New

- **Passthrough that corrects itself.** If a bitstream fails, Pleya falls back to PCM within
  a second, says so, and remembers the route so the next episode does not stall the same
  way. A watchdog covers the case where playback simply stops moving.
- The performance overlay shows the active audio output and its format, which is the only
  way from inside the app to tell whether a bitstream is really leaving the device or mpv is
  quietly decoding it.

## 2.8.0 · build 209 · 8 August 2026

<!-- commit: de48dbb -->

### New

- **Blu-ray ISOs and unpacked BDMV folders play.** An `.iso` is a filesystem rather than a
  stream, so until now it was simply invisible in the app. Pleya recognises both shapes and
  hands them to the player as a disc.

## 2.8.0 · build 209 · 7 August 2026

<!-- commit: bec37b2 -->

### New

- **Dolby Atmos and spatial audio on iPhone, iPad and Apple TV.** On AirPods, Pleya gave you
  stereo where other players gave Atmos. The missing piece was one opt-in: without it the
  audio route reports two channels and everything is mixed down before spatial audio can do
  anything. Passthrough was also closed off on Apple platforms and is now available.

### Fixed

- Discover in Requests always said "Something went wrong. Try again." An expired session or
  a missing permission read the same as a network hiccup, so retrying could never help.
  Each cause now gets its own message.

## 2.8.0 · build 205 · 6 August 2026

<!-- commit: de652d4 -->

### Fixed

- **One swipe moves the focus one poster.** On Apple TV a single swipe sometimes jumped two
  cells, and a diagonal swipe could move in a direction you had not swiped at all. Two
  independent input paths were both turning the same finger movement into arrow presses.
  The first one to produce a direction now owns the whole gesture.
- The same physical swipe gave one step one time and three the next, because the distance
  travelled past the threshold was thrown away. The step count is now simply distance
  divided by threshold.
- **Text entry on Apple TV was unusable and could not be dismissed.** Pleya now opens the
  tvOS system keyboard, which is also the surface the Siri Remote's microphone dictates
  into, so the extra screen in between is gone. Menu closes it. If the keyboard does not
  come up within four seconds, Pleya falls back to the on-screen D-pad keyboard instead of
  leaving you with a dead overlay.
- The D-pad no longer drives the screen behind an open keyboard.

## 2.8.0 · build 202 · 5 August 2026

<!-- commit: 3148604 -->

### New

- **Dictate a search on Apple TV.** The search field was decoration before: it could not be
  selected. Pressing it now opens the system keyboard pre-filled with your query, results
  update while you dictate, and Done focuses the first result.

### Fixed

- Recent searches could not be reached with a remote at all, and "Clear history" threw an
  error and did nothing on every platform.
- Starting a search left the remote dead, because the skeleton placeholders that replaced
  the results had nothing to focus.
- Back could escape out of an open sheet and land on the sidebar in the same press.
- Sheets opened from the Requests detail screen came up with nothing focused.
- On Android, "search X in Pleya" through the Assistant landed on an empty screen when the
  app had been fully closed.

## 2.8.0 · build 201 · 3 August 2026

<!-- commit: a6218ad -->

### New

- **Voice search on Android and Android TV**, using the system recogniser, so it needs no
  microphone permission of its own. Assistant searches and the leanback search row work too.
- An on-screen keyboard built into the TV search page instead of a pop-up over it.

### Fixed

- Plex and Jellyfin are equal starting points when you sign in. Choosing one no longer leaves
  you without a way back to the other.
- The featured hero on Discover could crash the screen while it was laying out.

## 2.8.0 · build 195 · 29 July 2026

<!-- commit: 1b58f73 -->

### New

- **Subtitle tracks are named properly.** When a file plays untouched, the track list only
  carries what the container itself says, which for an untagged track meant "Track 1". Pleya
  now borrows the language and title your server already knows.
- A "Recently Added Shows" row on the home screen.
- Downloads resume after the system pauses them, after the network drops, and on retry.

### Fixed

- The aspect ratio and zoom settings did nothing on iPhone, iPad and Apple TV.
- On Apple TV, the details button on the hero was unreachable with the D-pad, and subtitles
  disappeared when zoomed.
- The billboard on the home screen fetches missing artwork instead of showing a gap, and
  stays readable while you scroll past it.
- Changes to the home screen layout apply immediately rather than after a restart.

## 2.8.0 · build 186 · 23 July 2026

<!-- commit: 71f9d7d -->

### New

- **Pleya Share**, which turns one device into a small media server for your other Pleya
  devices. Pair once with a QR code and stream over Wi-Fi, a personal hotspot, or a cable.
  On iOS 26 and most Android phones it can also connect directly through Wi-Fi Aware, with
  no router or hotspot involved, and when both devices are online it falls back to an
  end-to-end encrypted relay. Several devices can stream from one host at once.
- A locked iPhone keeps serving while it is the host.
- Shared items borrow posters, metadata and watch progress from your Plex or Jellyfin
  account, per episode as well as per title, the same way local folders do.

### Fixed

- Starting a title from the home screen hero began at zero instead of where you left off.
- Watch progress synced through iCloud took the last write rather than the furthest point,
  so a device that was behind could undo one that was ahead.
- Audio kept playing on iOS when the screen locked, episodes in a share sorted correctly,
  local posters appeared on a cold start, and a host restart no longer breaks live streams.

### Improved

- The screen is kept awake only on desktop and TV now, and discovery beacons and polling
  back off when nothing is happening.

## 2.8.0 · build 138 · 4 July 2026

<!-- commit: 3c160b5 -->

### New

- **Requests, through Jellyseerr and Overseerr.** Browse, search and request movies and shows
  without leaving Pleya, and follow each request from pending to available. Without a
  requests server configured, the feature stays hidden.
- The tvOS system keyboard, including typing from a nearby iPhone, and a hero that follows
  your focus. The home billboard is much larger.
- Discover leads with the newest released films across all your servers instead of with
  continue-watching.
- Settings sync through iCloud.

### Fixed

- Signing in to a requests server with a Plex account failed with an "unsupported media
  type" error.
- On Apple TV, the zoom button was reachable again and the AirPlay button (which does
  nothing there) is gone.

## 2.8.0 · build 131 · 3 July 2026

<!-- commit: 394005e -->

### New

- **Recommendations that never leave your device.** Pleya builds a taste profile locally,
  with a 90-day decay, and uses it for "Recommended for you", "Because you watched" and
  "Hidden gems". Nothing about what you watch is uploaded. There is a switch to turn it off.
- Richer home rows on Jellyfin servers: "Top Rated" and "Something Different".
- Empty, error and offline states across the app instead of blank screens.

### Improved

- **The app is called Pleya.** New name, new logo, and the red-to-amber accent that runs
  through the interface. The progress bar under half-watched titles was rebuilt to match.

## 2.8.0 · build 122 · 2 July 2026

<!-- commit: 8a008f0 -->

### New

- First build. Pleya starts as a fork of [Plezy](https://github.com/edde746/plezy) by
  edde746, under the GPL-3.0.
