Make SunoMV Cover and Thumbnails
================================

What it does
- Drop a picture on "Make SunoMV Cover.bat" (or a shortcut to it).
- It makes a square cover picture saved next to your original photo,
  named like "My Picture - cover square.png".
- It also makes a YouTube thumbnail (16:9) and a Short thumbnail (9:16)
  in your Music\thumbnails folder (the Short goes in Music\thumbnails\shorts).
- The same tool works for songs and for regular videos. Type a Title,
  and optionally an artist name, channel name, or subtitle. Leave that
  optional line blank if you do not want it drawn on the thumbnail.

How to set it up
1. Unzip this folder anywhere you like, and keep the files together:
     Make SunoMV Cover.bat
     Make SunoMV Cover.ps1
     OswaldBold.ttf
     OFL.txt
     README.txt
2. Optional: right-click the .bat file, choose Send to > Desktop (create shortcut)
   so you can drop pictures on the shortcut.
3. Drop a picture (PNG, JPG, or similar) onto the bat file or the shortcut.
4. In the window that opens:
     - Type the title (or leave blank to skip thumbnails).
     - Optionally type an artist name, channel name, or subtitle
       (it is remembered for next time). Leave it blank to leave
       that line off the thumbnail.
     - Choose where the Short should crop, and where the title should sit.
     - Title style: Balanced keeps every title line the same size (recommended).
       Big Accent Line makes the last word larger, if you ever want that.
     - Pick a font, or type part of the font name to jump to it.
       Oswald Bold is the built-in default. The list also includes the fonts
       installed on your PC, so a font such as Kingthings Foundation will
       appear if you have it installed.
     - Colors: set Top lines, Last line, and Artist to White, Gold, or Black
       (Artist can also be Auto). This lets the whole title be one color, or
       lets you choose which line is gold, white, or black.
     - Shading: Auto picks a dark fade for light text and a light fade for
       black text (best on bright photos). You can also choose Dark fade,
       Light fade, or None.

Tips
- To pick your own line breaks in the title, type a slash:
    SMOKE AND / MIRRORS
- Black text automatically gets a crisp light outline so it stays readable
  on a light background.
- Your last font, colors, artist / channel / subtitle, and layout choices
  are saved automatically.
- You do not need any extra apps or an internet connection to make covers
  and thumbnails. Windows already has everything this uses.

If Windows blocks the script
- Right-click Make SunoMV Cover.ps1, choose Properties, and if you see
  an Unblock checkbox, tick it and click OK. Then try again.
