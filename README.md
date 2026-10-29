# Stacks

A free, Kindle-style iPhone reader for the comics and books on your own PC.

- Browses your libraries, series, volumes, issues and chapters
- Reads **CBZ/CBR comics and manga**, **EPUB** books and **PDFs**
- Tracks what you've read: each issue, chapter and volume shows read, in progress, or unread
- Remembers your last page and reopens there, on any device (progress is stored on your PC)
- Swipe a row to mark it read or unread; mark whole volumes or series from their menus
- "Continue reading" shelf, search, pinch-to-zoom, right-to-left mode for manga, EPUB text size and table of contents

Your PC runs [Kavita](https://www.kavitareader.com), a free open-source library server. Stacks is the iPhone app that talks to it. Everything here is $0.

---

## 1. Set up Kavita on your PC (about 10 minutes)

1. Download **`kavita-win-x64.tar.gz`** from <https://github.com/Kareadita/Kavita/releases/latest>.
2. Extract it to a permanent spot, for example `C:\Kavita`. (Windows 11 can extract it with right-click → Extract All; otherwise use 7-Zip.)
3. Double-click **`Kavita.exe`**. When Windows Firewall asks, allow it on **Private networks**.
4. Open <http://localhost:5000> in your browser and create your account. Remember the username and password; the app uses them.
5. Add your libraries (Settings → Libraries → Add). Pick the type that matches:
   - **Comic** for western comics (CBZ/CBR)
   - **Manga** for manga
   - **Book** for EPUB and PDF
6. Organize files as one folder per series. Kavita reads issue and volume numbers from file names:

   ```
   D:\Comics\Saga\Saga #001.cbz
   D:\Comics\Saga\Saga #002.cbz
   D:\Manga\One Piece\One Piece Vol. 01.cbz
   D:\Books\Dune\Dune.epub
   ```

7. Find your PC's address: open Command Prompt, run `ipconfig`, and note the **IPv4 Address** (like `192.168.1.20`). Your server address is `http://192.168.1.20:5000`.

**Keep Kavita running at startup:** press Win+R, type `shell:startup`, and put a shortcut to `Kavita.exe` in that folder.

### Reading away from home (optional, free)

Install [Tailscale](https://tailscale.com) on the PC and the iPhone and sign in to the same account on both. In the app, use the PC's Tailscale address instead, like `http://100.64.12.34:5000`. It works on cellular, and nothing is exposed to the public internet.

---

## 2. Build the app on GitHub (free, no Mac needed)

1. Create a free account at <https://github.com>.
2. Click **New repository**, name it `stacks`, choose **Public** (public repos get unlimited free build time), and create it.
3. Click **uploading an existing file** and drag in **everything inside this folder**: the `.github` folder, the `Stacks` folder, `project.yml` and this README. `project.yml` must sit at the top level of the repo. Click **Commit changes**.
4. Open the **Actions** tab. A "Build iPhone app" run starts on its own and takes about 5–10 minutes.
5. When it shows a green check, open the run and download **Stacks-ipa** under *Artifacts*. Unzip it to get **`Stacks.ipa`**.

If the run fails, download the **build-log** artifact from the same page and send me the lines that contain `error:`.

---

## 3. Install with Sideloadly

1. Install [Sideloadly](https://sideloadly.io) on your PC. It needs the **web installer** versions of iTunes and iCloud, not the Microsoft Store versions (uninstall the Store versions first; Sideloadly's site links the right ones).
2. Plug in your iPhone with a cable and tap **Trust This Computer** on the phone.
3. Open Sideloadly, drag in `Stacks.ipa`, enter your Apple ID, and click **Start**.
4. On the iPhone:
   - **Settings → Privacy & Security → Developer Mode** → turn on and restart (one time only).
   - **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
5. Open Stacks, enter `http://YOUR-PC-IP:5000` and your Kavita username and password, and tap **Connect**. Allow **Local Network** access when asked.

### The 7-day limit

Apps signed with a free Apple ID stop opening after 7 days. Turn on **Auto Refresh** for Stacks in Sideloadly. As long as Sideloadly is running on the PC and the phone is on the same Wi-Fi now and then, it re-signs the app before it expires. Your reading progress is never lost because it lives in Kavita on your PC.

---

## How read tracking works

| You do | Stacks saves |
|---|---|
| Turn a page | Your current page, sent to Kavita right away |
| Reach the last page of an issue/chapter or PDF | That issue/chapter is marked **read** |
| Scroll to the end of an EPUB's last section, or tap **Finish** | The book is marked **read** |
| Swipe a row → Read / Unread | That issue or chapter |
| Volume header menu | The whole volume |
| ••• menu on a series | The whole series |

Opening something you've finished starts it from the beginning, and just opening it doesn't change its status.

The same progress shows up in Kavita's web reader on your PC, and vice versa.

---

## Troubleshooting

- **"Couldn't reach the server":** Kavita isn't running, the address is wrong, or the phone isn't on the same Wi-Fi (or Tailscale). Try opening the address in Safari on the phone first; you should see Kavita's login page.
- **Library is empty:** In Kavita on the PC, open the library's menu and choose **Scan Library**.
- **App won't open after a week:** The free signature expired. Re-sign it in Sideloadly (or turn on Auto Refresh).
- **Manga pages go the wrong way:** Tap the page, tap the ⇄ button, and turn on **Right to left**.

## Updating the app

Edit files in the GitHub repo (or upload new versions). Each change builds a new `Stacks.ipa`. Install it over the old one with Sideloadly using the same Apple ID; your sign-in stays.

## Project layout

```
project.yml                 XcodeGen spec (GitHub turns it into an Xcode project)
.github/workflows/build.yml Free macOS build that produces Stacks.ipa
Stacks/KavitaClient.swift   All Kavita API calls
Stacks/Models.swift         Data types
Stacks/Views/               Login, home, library grid, series page
Stacks/Reader/              Comic, PDF and EPUB readers + progress saving
```

Built against Kavita 0.9.1. Kavita is GPL-3.0 open source; Stacks only talks to its public API.
