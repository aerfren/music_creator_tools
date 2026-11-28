# Music Creator Tools

Two free Windows tools for independent musicians and YouTube creators, made by **[Penni (Fyuri) LeBlanc](https://www.youtube.com/@fyurileblanc7206)**.

Both tools also work for video makers. The Thumbnail & Cover Maker can make thumbnails and a square cover for any video, not just songs. The YouTube Description Maker has a **Video** mode for regular (non-music) videos.

They are small, portable, and open source. Unzip a folder anywhere you like, keep the files in that folder together, and drag a picture, a song, or a notes file onto the `.bat` file. There is nothing to install.

A one-page download site is published from this repository at [aerfren.github.io/music_creator_tools](https://aerfren.github.io/music_creator_tools/).

## Thumbnail & Cover Maker

Drop a picture on `Make SunoMV Cover.bat`. From that one picture the tool makes:

- A **1024×1024 square cover**, saved beside your original photo, named like `My Picture - cover square.png`.
- A **YouTube thumbnail (16:9)**, saved in your `Music\thumbnails` folder.
- A **YouTube Shorts thumbnail (9:16)**, saved in `Music\thumbnails\shorts`.

The picture sits in a clear band, with a soft blurred fill around it. In the window you can:

- Type the **Title**. Leave it blank and the tool still makes the square cover, and skips the thumbnails.
- Optionally type an **artist name, channel name, or subtitle**. The tool remembers it for next time. Leave it blank and that line is not drawn on the thumbnail.
- Keep **Balanced** title lines, so every line is the same size, or choose **Big Accent Line** when you want the last word larger.
- Choose where a Short should crop (the person or main subject on the left, in the middle, or on the right), and where the title sits (top or bottom, left, center, or right).
- Open a searchable list of every font installed on your Windows PC. Type part of a name to jump to it. **Oswald Bold** ships in the folder (`OswaldBold.ttf`) and is the default.
- Set **White**, **Gold**, or **Black** for the top title lines, the last line, and the artist name. The artist color can stay on **Auto**.
- Choose background shading: **Auto**, **Dark fade**, **Light fade**, or **None**. Auto uses a dark fade for light text and a light fade for black text. Black text gets a light outline so it stays readable on a bright photo.

To choose your own line breaks, type a slash: `SMOKE AND / MIRRORS`.

PNG, JPG, WEBP, and BMP pictures all work. Covers and thumbnails are drawn on your computer, so this tool works offline. The same window works for a song or for any other video.

Folder: [`thumbnail-maker/`](thumbnail-maker/)  
Download: [`docs/downloads/thumbnail-maker.zip`](docs/downloads/thumbnail-maker.zip)

### Quick start

1. Unzip `thumbnail-maker.zip` and leave every file in that folder together.
2. Optional: right-click `Make SunoMV Cover.bat` and choose **Send to → Desktop (create shortcut)**, so you can drop pictures on the shortcut.
3. Drop a picture onto the bat file or the shortcut, set the title (and an optional artist, channel name, or subtitle), colors, and font, then click **Make thumbnails**.

If Windows blocks the script, right-click `Make SunoMV Cover.ps1`, open **Properties**, tick **Unblock** if you see it, and click **OK**.

## YouTube Description Maker

Drop an MP3 or a `.txt` file on `Make YouTube Description.bat`. You can also double-click the bat file and paste the text yourself. Choose **Type: Song** or **Type: Video** (the tool remembers your last choice).

In **Song** mode the tool:

- Reads the song **title** and the **embedded lyrics** from the MP3's ID3 tags when those tags are present.
- Reads a lyrics text file, or the words you paste into the window.
- Uses **your own free Gemini API key** to write a clean introduction around those lyrics. Your lyrics are copied exactly, including section tags such as `[Verse 1]` and `[Chorus]`, unless you choose **Include lyrics: No**. That Yes/No choice is remembered.
- Lets you pick a playlist or leave it on **Auto-pick** (Worship, Faith, Heartstrings, Watchman, Humor, or another short honest name).

In **Video** mode, for regular (non-music) videos, drop or paste a `.txt` transcript, script, or notes, or just type the video title and a few notes. Gemini writes a short summary of the video and fitting hashtags. The transcript is not copied into the description, and music-only lines such as "Written and performed by" are left out.

In either mode you can open **Options...** to turn on extras and type your own wording: a links list (a label plus a web address, with **Add** and **Paste link**), a subscribe line, timestamps or chapters, extra credits, a licensing or permission note, a contact or business line, a sheet-music line (Song mode), and an "anything else" box that is placed just above the hashtags. These stay off until you turn them on, and they are remembered for next time.

The tool then:

- Saves the finished description as a text file in `Documents\YouTube Descriptions`.
- Copies that description to your clipboard.
- Opens it in Notepad, ready to paste into YouTube.

The first time you run it, paste a free key from [Google AI Studio](https://aistudio.google.com/apikey) (a Google account is required). In AI Studio, choose **Create API key**, copy it, and paste it into the window. The key is stored only on that computer, in a file named `gemini.key` beside the script. Keep that file on your computer. It is listed in `.gitignore` so a normal commit will leave it out.

The same window remembers your artist name, an optional email for sheet-music requests, and the name on the copyright line.

If the description is longer than YouTube's 5,000-character limit, the tool warns you and, in Song mode, leaves the lyrics whole. When you write a new description with the same title, the previous file is moved into an `old` folder with a date stamp, and kept.

This tool needs the internet, because Gemini writes the introduction.

Folder: [`youtube-description-maker/`](youtube-description-maker/)  
Download: [`docs/downloads/youtube-description-maker.zip`](docs/downloads/youtube-description-maker.zip)

### Quick start

1. Unzip `youtube-description-maker.zip` and leave the files together.
2. Double-click `Make YouTube Description.bat`, paste your free Gemini API key, and fill in your artist name.
3. Choose **Song** or **Video**, drop an MP3 or a `.txt` file onto the bat file (or paste the text), check the title, and click **Write my description**. Open **Options...** if you want links or other extras.

If Windows blocks the script, right-click `Make YouTube Description.ps1`, open **Properties**, tick **Unblock** if you see it, and click **OK**.

## How to Contribute / Share Improvements

These tools are shared so other musicians can use them, and so improvements can come back to everyone.

- Open a [Pull Request](https://github.com/aerfren/music_creator_tools/pulls) when you have a fix or an improvement ready.
- Open an [Issue](https://github.com/aerfren/music_creator_tools/issues) when something breaks, or when you wish a tool did something new.

Penni and anyone else who uses the tools can then learn from what you share. Small, clear changes are welcome, including better wording for people who are new to Windows. If you change a script, rebuild the download zips from the repository root so the buttons stay in step with the source:

```bash
rm -f docs/downloads/thumbnail-maker.zip docs/downloads/youtube-description-maker.zip
zip -r -X docs/downloads/thumbnail-maker.zip thumbnail-maker
zip -r -X docs/downloads/youtube-description-maker.zip youtube-description-maker
```

Leave personal files on your own computer. `gemini.key` and the `.settings.json` files the tools write can hold an API key, an email address, or other private details. They are ignored by git. Please keep them out of issues, pull requests, and screenshots.

## License

The scripts, batch files, this README, and the download page are free software under the **GNU General Public License v3.0**. The full license text is in [`LICENSE`](LICENSE).

You can use, study, share, and improve these tools. If you pass a changed version on to someone else, that version stays free and open source under GPL-3.0, and you include the source of your changes. That is how an improvement made by one musician remains available to Penni and to everyone else.

The bundled typeface `thumbnail-maker/OswaldBold.ttf` (family name **Oswald ThumbBold**) is a separate work. Copyright 2016 The Oswald Project Authors. It is designed by Vernon Adams and stays under the [SIL Open Font License 1.1](thumbnail-maker/OFL.txt). The GPL covers the tools. The font keeps its own license. Pictures you make with the font are yours.

Copyright (C) 2026 Penni (Fyuri) LeBlanc.

## Website

The site is the plain HTML in [`docs/`](docs/). [`.github/workflows/pages.yml`](.github/workflows/pages.yml) publishes that folder to GitHub Pages on every push to `main`.

In the repository on GitHub, set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**. The next push to `main` then updates [https://aerfren.github.io/music_creator_tools/](https://aerfren.github.io/music_creator_tools/).
