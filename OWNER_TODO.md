# Things only you can do

Nothing here is blocking the work right now. Each item says when it starts to matter.

## 1. Try it on an iPad by sideloading (when you want to, from Windows)

Every green CI run makes an unsigned app file.

1. Open https://github.com/arielmz1234/Talis-Notes-iOS/actions, click the newest green run, and download
   **TalisNotes-unsigned-ipa** at the bottom (a zip holding `TalisNotes-unsigned.ipa`; unzip it).
2. Install **Sideloadly** (sideloadly.io) on the PC, and iTunes from Apple's site (not the Microsoft Store version) so Windows sees the iPad.
3. Plug in the iPad, trust the computer on the iPad, open Sideloadly, drop the `.ipa` in, enter your
   Apple ID, press Start. Sideloadly signs it with your free Apple ID.
4. On the iPad: Settings › General › VPN & Device Management › your Apple ID › Trust.
   On iPadOS 16 or later also turn on Settings › Privacy & Security › Developer Mode (the iPad restarts).
5. A free Apple ID's signature lasts 7 days: after that, run Sideloadly again (your notes stay).

With a free Apple ID, iCloud can't be switched on. The app will say so in Backups, and Google Drive and backup files still work.

## 2. Later: Apple Developer account ($99/year), when you want TestFlight or the App Store

Not needed yet. When you have it, I'll need: the Team ID, an App Store Connect API key (Issuer ID,
Key ID, the .p8 file) added as GitHub secrets, the bundle id `com.tali.notes` registered, and an
iCloud container `iCloud.com.tali.notes`. I'll write the exact steps when we get there.

## 3. Later: Google Drive on iPhone and iPad

In the Google Cloud project "Tali's Notes": Credentials › Create credentials › OAuth client ID ›
iOS, bundle id `com.tali.notes`. Send me the client ID (it isn't a secret, it goes in the app).
Needed when Drive backup is ported (milestone 4).
