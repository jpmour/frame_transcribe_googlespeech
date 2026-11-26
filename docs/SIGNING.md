# One-time signing setup (Windows, no Android Studio)

Why: Android only installs an update over an app signed with the same key. Without a fixed key, every
GitHub build has a different signature, and you would have to uninstall (and lose your saved settings)
each time. This repo is public, so the key and passwords go into GitHub secrets only, never into the repo.

1. Install Java (needed only for the `keytool` command). In PowerShell:
   `winget install EclipseAdoptium.Temurin.17.JDK`
   Close and reopen PowerShell, then check with `keytool -help`.
2. Make a private folder outside any Git repo:
   `mkdir $HOME\frame-keys`
3. Create the key. Answer the questions with anything. Choose one long password and remember it:
   `keytool -genkeypair -v -storetype PKCS12 -keystore $HOME\frame-keys\frame-release.jks -alias frame -keyalg RSA -keysize 2048 -validity 10000`
4. **Back it up now.** Copy `frame-release.jks` and the password into your password manager or onto an
   encrypted drive. Keep it private.
   - If you lose it: one uninstall and reinstall, and you re-enter your settings once.
   - If it leaks: someone could sign a fake update. Never post the file or password anywhere public,
     including chat and this repo.
5. Convert the key to text and copy it:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\frame-keys\frame-release.jks")) | Set-Clipboard`
6. On GitHub open `jpmour/frame_transcribe_googlespeech`, then Settings, Secrets and variables, Actions,
   New repository secret. Add four secrets:
   - `ANDROID_KEYSTORE_BASE64`: paste from the clipboard
   - `ANDROID_KEYSTORE_PASSWORD`: your password
   - `ANDROID_KEY_ALIAS`: `frame`
   - `ANDROID_KEY_PASSWORD`: the same password
7. Clear the clipboard (copy any short text). Never paste the secrets into chat.

After this, the next push to `main` builds an APK signed with your key.

Note: if you already have this app installed from a different build, the first signed APK needs one
uninstall. After that, every update installs in place and keeps your settings.
