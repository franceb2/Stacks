# Stacks

A free, Kindle-style iPhone app for the comics, manga and books on your own computer.

Stacks reads from [Kavita](https://www.kavitareader.com), a free library server you run on your PC. Your comics stay on your computer; Stacks lets you browse and read them on your iPhone, at home or away, and keeps your place in sync with Kavita.

**Download Stacks:** <https://github.com/franceb2/Stacks/releases/latest/download/Stacks.ipa>

---

## What you can do

**Read**
- Comics and manga (CBZ/CBR), EPUB books and PDFs
- Left-to-right, right-to-left (manga), vertical and webtoon modes, plus two-page spreads when you turn the phone sideways
- Tap the sides or swipe to turn pages; pinch or double-tap to zoom
- Pick up exactly where you left off, on any device

**Browse**
- Home with Continue reading, Favorites, On Deck, Recently Updated and Newly Added
- Star series into **Favorites**, add them to Want to Read, collections and reading lists
- Search, bookmarks, reading stats, and mark things read or unread
- 25 color themes, with an option to switch themes automatically each time you open the app, every hour or every day
- Your library stays browsable with no connection

**Follow a reading order**
- Spawn's full reading order is built in
- Add any reading order from a Google Doc or Sheet, a Drive or Dropbox link, a web page, an Excel, CSV or Word file, or pasted text
- Skip optional issues by color (like the gray ones in most reading-order docs)
- Fix any match by hand, including issues inside an omnibus
- See what you're missing, and mark issues you read somewhere else

**Read offline**
- Download issues, page ranges or batches; the next few download automatically when you finish one
- What you read offline syncs back when you're online again
- Optionally delete finished downloads after a few days

**And**
- Face ID lock, a "Continue reading" shortcut on the app icon, and a heads-up in the app when a new version is out

---

## Install

### What you need
- A Windows PC (or Mac or Linux) that holds your comics and books
- An iPhone
- A signing service to install apps outside the App Store. Stacks is installed with **[Signulous](https://www.signulous.com)**; other services and Sideloadly work too

### 1. Set up Kavita on your computer
1. Download Kavita from <https://github.com/Kareadita/Kavita/releases/latest> (Windows: the `win-x64` file), extract it somewhere permanent like `C:\Kavita`, and run **Kavita.exe**.
2. Open <http://localhost:5000> in your browser and create your account. Stacks signs in with this username and password.
3. Go to **Settings → Libraries → Add** and point it at your folders. Set the type to match what's inside:
   - **Comic** for comics
   - **Manga** for manga (pages read right to left)
   - **Book** for EPUB and PDF
4. Keep one folder per series. Kavita reads issue and volume numbers from file names:
   ```
   D:\Comics\Saga\Saga #001.cbz
   D:\Comics\Brit One-Shot\Brit - One Shot 01.cbz
   D:\Manga\One Piece\One Piece Vol. 01.cbz
   D:\Books\Dune\Dune.epub
   ```
5. Turn on **Folder Watching** in Kavita's settings so new files show up on their own.

### 2. Make it reachable from your phone
- **At home only:** use your PC's local address, like `http://192.168.1.20:5000` (run `ipconfig` on Windows to find it).
- **Anywhere:** use a free [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to a domain you own, pointed at `http://localhost:5000`, or install [Tailscale](https://tailscale.com) on the PC and the phone.

Keep the PC on and awake. Running Kavita (and the tunnel) as a Windows service means it starts by itself after a restart.

### 3. Install Stacks with Signulous
1. On your iPhone, open the **Download Stacks** link at the top of this page, or copy it.
2. In Signulous, upload the IPA (or paste the link), sign it, and install it.
3. Open Stacks and enter your server address, Kavita username and password.

### Updating
When a new version is out, Stacks shows an alert. Tap **Download IPA** or **Copy download link**, then sign and install it in Signulous like before. Your sign-in, downloads and settings stay.

---

## Tips

- **New comic isn't showing:** in Stacks, go to the Library tab, tap ↻ and scan. If it still doesn't appear, use **Force scan**.
- **Comics open right to left:** that library's type is set to Manga in Kavita. Change it to Comic.
- **A one-shot gets merged into its main series:** give it its own folder without parentheses, like `Brit One-Shot`. Kavita ignores text in parentheses.
- **Old cover after changing a file:** pull down on the series page, or use **Settings → Offline library → Reload all covers**.
- **A reading-order issue points at the wrong comic:** long-press it and choose **Fix match**.
- **"Can't reach your server" (or Cloudflare error 1033):** the PC, Kavita or the tunnel is off or asleep.

---

Stacks is free. Kavita is free, open-source software (GPL-3.0); Stacks only talks to it. The built-in Spawn reading order is by Blake Whitlow.
