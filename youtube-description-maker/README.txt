Make YouTube Description
========================

What it does
- Drop an MP3 or a lyrics .txt file on "Make YouTube Description.bat"
  (or a shortcut to it), or double-click the bat file and paste.
- It reads the song title and lyrics (from the MP3 tags when they are
  there, or from your text file / paste), asks Gemini to write a short
  YouTube blurb, and builds a complete description around your exact
  lyrics (the lyrics are never rewritten or cut).
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
5. Drop an MP3 or a lyrics .txt, check the title and lyrics, choose a
   playlist or leave it on Auto-pick, and click "Write my description".

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
