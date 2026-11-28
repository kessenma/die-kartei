# Android: what needs a person to test

Things the emulator checks can't cover: a real voice, a real phone, files from another
device. Each entry says how to test it and what should happen. Tick it off (`[x]`, with the
date and the phone) once it's done; add a line under it if it didn't behave.

The emulator is `Medium_Phone_API_37.0`; `cd DieKarteiAndroid && skip app launch --android`
installs the current build.

## Speaking to the tutor (since `6795c71`)

- [ ] **A real sentence.** Restart the emulator with the Mac's microphone
  (`emulator -avd Medium_Phone_API_37.0 -allow-host-audio`, allow the macOS prompt) or use a
  phone. Home ▸ Gespräch ▸ Gespräch beginnen, tap the mic, say "Ich habe heute einen Kaffee
  getrunken", tap stop. *Expect:* the words appear while you speak, and the tutor answers.
- [ ] **A pause mid-sentence.** Say "Ich glaube", wait two seconds, then "dass es regnet", stop.
  *Expect:* one turn, "Ich glaube dass es regnet": the first half isn't lost or sent alone.
- [ ] **Marks and redo.** While talking, tap "?" (the sentence ends in "?"), then "Neu sagen"
  (the text clears and it keeps listening).
- [ ] **On-device German.** On a phone with German speech downloaded (Settings ▸ System ▸
  Languages ▸ Speech / on-device recognition), turn on airplane mode and speak.
  *Expect:* it still works. Without the pack: it asks Android to download it and works online.
- [ ] **Permission denied.** Deny the microphone prompt. *Expect:* a message saying so, and
  typing still works.

## Decks from iOS (step 8, emulator-checked with a file in iOS's format)

- [ ] **A deck sent from the iPhone.** On iOS: Library ▸ a deck ▸ Share ▸ send the `.kartei`
  file to the phone (email, Drive, Nearby Share). Open it on the phone. *Expect:* Die Kartei is
  offered, the deck and its cards appear, and studied cards keep their schedule.
- [ ] **The same deck again.** Send it a second time. *Expect:* the choice to replace it or keep
  both, as on iOS.
- [ ] **A deck from Android to the iPhone.** On Android: Library ▸ the deck ▸ Share, send it to
  the iPhone and open it there. *Expect:* iOS imports it with the same cards and schedule.
- [ ] **Open with, while the app is open.** With Die Kartei already open, open a `.kartei` from
  Gmail or Files. *Expect:* the import sheet, not just the app coming to the front. (Checked on
  the emulator only with the app closed.)
- [ ] **Classic and Anki on a phone.** Library ▸ a deck, switch Classic/Anki in the top bar, run
  a session. *Expect:* Anki brings a "Didn't know" card back three cards later; ⓘ shows the result.
