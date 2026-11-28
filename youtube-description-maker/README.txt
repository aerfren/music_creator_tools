Make YouTube Description
========================

What it does
- Drop an MP3 or a lyrics .txt file on "Make YouTube Description.bat"
  (or a shortcut to it), or double-click the bat file and paste.
- Choose Type: Song or Type: Video. The tool remembers your last choice.
- In Song mode it reads the song title and lyrics (from the MP3 tags when
  they are there, or from your text file / paste), asks Gemini to write a
  short YouTube blurb, and builds a complete description around your exact
  lyrics (the lyrics are never rewritten or cut). You can choose
  Include lyrics: Yes or No each time; that choice is remembered too.
- In Video mode it is for regular (non-music) videos. Drop or paste a
  .txt transcript, script, or notes, or just type the video title and a
  few notes. Gemini writes a short summary and fitting hashtags. The
  transcript is not copied into the description, and music-only lines
  such as "Written and performed by" and the playlist line are left out.
- The Options window lets you turn on extras and type your own wording:
  a links list (a label plus a web address, with Add and Paste link),
  a subscribe line, timestamps / chapters, extra credits, a licensing
  or permission note, a contact / business line, a sheet-music line
  (Song mode), and an "anything else" box that is placed just above
  the hashtags. These stay off until you turn them on, and they are
  remembered for next time.
- The finished description is saved, copied to the clipboard, and
  opened in Notepad so you can paste it into YouTube.

How to set it up
1. Unzip this folder anywhere you like, and keep the files together:
     Make YouTube Description.bat
     Make YouTube Description.ps1
     README.txt
2. Optional: right-click the .bat file, choose Send to > Desktop
   (create shortcut) so you can drop songs on the shortcut.
3. The first time you run it, you will be asked for a free Gemini API
   key. Get one here (Google account required):
     https://aistudio.google.com/apikey
   In Google AI Studio, click "Create API key", copy the key, and paste
   it into the window. It is saved only on this computer, as gemini.key
   next to the script. You will not have to paste it again.
4. Fill in your artist name, sheet-music / contact email (optional),
   and copyright name. These are remembered for next time.
5. Choose Song or Video, drop a file or paste your text, check the
   title, and click "Write my description". Open Options... if you want
   links or other extras.

Tips
- If an MP3 has no lyrics in its tags, the window lets you paste them
  or browse for a lyrics .txt file.
- Older descriptions with the same name are moved to an "old" folder
  with a date stamp; they are not deleted.
- If a description is over YouTube's 5,000-character limit, you will
  get a warning. Lyrics are never silently cut.
- You need an internet connection so Gemini can write the blurb.

If Windows blocks the script
- Right-click Make YouTube Description.ps1, choose Properties, and if
  you see an Unblock checkbox, tick it and click OK. Then try again.
