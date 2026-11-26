# YouTube Description helper
# Drop an MP3 or a lyrics .txt on the icon, or double-click to paste.
# Gemini writes the title line, pull quote, blurb, scripture, playlist, and hashtags.
# The lyrics themselves are copied exactly from your file or MP3 and are never rewritten.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Windows.Forms.Application]::EnableVisualStyles()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Edition = 'Share'
$defaultArtist = ''
$defaultCredit = ''
$defaultEmail = ''
$defaultCopyright = ''
$defaultDescDir = Join-Path $env:USERPROFILE 'Documents\YouTube Descriptions'
$settingsPath = Join-Path $here 'Make YouTube Description.settings.json'
$keyPath = Join-Path $here 'gemini.key'
$playlists = @('Auto-pick','1- Worship','2- Faith','4- Heartstrings','5- Watchman','Humor')

$noUi = [bool]$env:YTDESC_NOUI
$noNotepad = [bool]$env:YTDESC_NONOTEPAD
$noClip = [bool]$env:YTDESC_NOCLIP
$extractOnly = [bool]$env:YTDESC_EXTRACTONLY
if($env:YTDESC_OUTDIR){ $defaultDescDir = $env:YTDESC_OUTDIR }

function Get-SafeTitle([string]$title){
  $s = ($title + '').Trim() -replace "[’']",'' -replace '[^\w\s-]+','' -replace '[-\s]+','_'
  if(-not $s){ $s = 'Song' }
  return $s
}

function Read-TextFile([string]$path){
  $bytes = [IO.File]::ReadAllBytes($path)
  if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){
    return [Text.Encoding]::UTF8.GetString($bytes,3,$bytes.Length-3)
  }
  if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE){
    return [Text.Encoding]::Unicode.GetString($bytes,2,$bytes.Length-2)
  }
  if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF){
    return [Text.Encoding]::BigEndianUnicode.GetString($bytes,2,$bytes.Length-2)
  }
  # UTF-16 without BOM (lots of NUL in even or odd positions)
  if($bytes.Length -ge 8){
    $nuls = 0
    $take = [Math]::Min($bytes.Length, 400)
    for($i=0;$i -lt $take;$i++){ if($bytes[$i] -eq 0){ $nuls++ } }
    if($nuls -gt ($take / 5)){
      if($take -ge 2 -and $bytes[0] -eq 0){ return [Text.Encoding]::BigEndianUnicode.GetString($bytes) }
      return [Text.Encoding]::Unicode.GetString($bytes)
    }
  }
  $utf8 = New-Object System.Text.UTF8Encoding $false,$true
  try { return $utf8.GetString($bytes) } catch { return [Text.Encoding]::GetEncoding(28591).GetString($bytes) }
}

function Clean-Lyrics([string]$text){
  if($null -eq $text){ return '' }
  $t = $text -replace "`r`n","`n" -replace "`r","`n"
  $t = $t -replace "[\u0000]+",''
  $lines = foreach($ln in ($t -split "`n")){
    $s = $ln -replace '[ \t]+$',''
    if($s -match '(?i)made with suno'){ continue }
    if($s -match '(?i)^created=\d'){ continue }
    if($s -match '(?i)^id=[0-9a-f-]{8,}$'){ continue }
    $s
  }
  $joined = ($lines -join "`n")
  while($joined -match "`n{3,}"){ $joined = $joined -replace "`n{3,}","`n`n" }
  return (Add-SectionSpacing $joined.Trim())
}

function Add-SectionSpacing([string]$text){
  if(-not $text){ return '' }
  $out = New-Object System.Collections.Generic.List[string]
  foreach($ln in ($text -split "`n")){
    if($ln -match '^\s*\[[^\]]+\]\s*$' -and $out.Count -gt 0 -and $out[-1].Trim() -ne ''){
      $out.Add('')
    }
    $out.Add($ln)
  }
  return ($out -join "`n")
}

function Normalize-Newlines([string]$text){
  return (($text -replace "`r`n","`n" -replace "`r","`n") -replace "`n","`r`n")
}

function Get-UInt32BE([byte[]]$b,[int]$o){
  return (([int]$b[$o] -shl 24) -bor ([int]$b[$o+1] -shl 16) -bor ([int]$b[$o+2] -shl 8) -bor [int]$b[$o+3])
}
function Get-SyncSafe([byte[]]$b,[int]$o){
  return (([int]$b[$o] -shl 21) -bor ([int]$b[$o+1] -shl 14) -bor ([int]$b[$o+2] -shl 7) -bor [int]$b[$o+3])
}

function Remove-Id3Unsync([byte[]]$data){
  $out = New-Object System.Collections.Generic.List[byte]
  for($i=0;$i -lt $data.Length;$i++){
    [void]$out.Add($data[$i])
    if($data[$i] -eq 0xFF -and ($i+1) -lt $data.Length -and $data[$i+1] -eq 0){ $i++ }
  }
  return $out.ToArray()
}

function Decode-Id3Text([byte[]]$b,[int]$enc,[int]$start,[int]$len){
  if($len -le 0 -or $start -ge $b.Length){ return '' }
  $max = [Math]::Min($len, $b.Length - $start)
  $slice = New-Object byte[] $max
  [Array]::Copy($b,$start,$slice,0,$max)
  $s = switch($enc){
    0 { [Text.Encoding]::GetEncoding(28591).GetString($slice) }
    1 { [Text.Encoding]::Unicode.GetString($slice) }
    2 { [Text.Encoding]::BigEndianUnicode.GetString($slice) }
    3 { [Text.Encoding]::UTF8.GetString($slice) }
    default { [Text.Encoding]::UTF8.GetString($slice) }
  }
  return ($s -replace "[\u0000]+",'').Trim()
}

function Read-Id3Terminated([byte[]]$b,[int]$enc,[int]$start,[int]$end,[ref]$nextPos){
  if($enc -eq 1 -or $enc -eq 2){
    $i = $start
    while(($i+1) -lt $end -and -not ($b[$i] -eq 0 -and $b[$i+1] -eq 0)){ $i += 2 }
    $text = Decode-Id3Text $b $enc $start ($i - $start)
    $n = $i + 2
    if($n -gt $end){ $n = $end }
    $nextPos.Value = $n
    return $text
  } else {
    $i = $start
    while($i -lt $end -and $b[$i] -ne 0){ $i++ }
    $text = Decode-Id3Text $b $enc $start ($i - $start)
    $n = $i + 1
    if($n -gt $end){ $n = $end }
    $nextPos.Value = $n
    return $text
  }
}

function Get-Id3Frames([byte[]]$fileBytes){
  $frames = @()
  if($fileBytes.Length -lt 10){ return $frames }
  if([Text.Encoding]::ASCII.GetString($fileBytes,0,3) -ne 'ID3'){ return $frames }
  $ver = [int]$fileBytes[3]
  $flags = [int]$fileBytes[5]
  $tagSize = Get-SyncSafe $fileBytes 6
  $start = 10
  $end = [Math]::Min($fileBytes.Length, 10 + $tagSize)
  if($end -le $start){ return $frames }
  $tag = New-Object byte[] ($end - $start)
  [Array]::Copy($fileBytes,$start,$tag,0,$tag.Length)
  if( ($flags -band 0x80) -ne 0 ){ $tag = Remove-Id3Unsync $tag }
  $i = 0
  if( ($flags -band 0x40) -ne 0 -and $tag.Length -ge 4 ){
    if($ver -ge 4){ $ext = Get-SyncSafe $tag 0 } else { $ext = Get-UInt32BE $tag 0 }
    if($ext -lt 4){ $ext = 4 }
    $i = [Math]::Min($ext, $tag.Length)
  }
  while($i -lt $tag.Length){
    if($tag[$i] -eq 0){ break }
    if($ver -eq 2){
      if(($i + 6) -gt $tag.Length){ break }
      $id = [Text.Encoding]::ASCII.GetString($tag,$i,3)
      if($id -notmatch '^[A-Z0-9]{3}$'){ break }
      $fsz = (([int]$tag[$i+3] -shl 16) -bor ([int]$tag[$i+4] -shl 8) -bor [int]$tag[$i+5])
      $i += 6
      if($fsz -lt 0 -or ($i + $fsz) -gt $tag.Length){ break }
      $data = New-Object byte[] $fsz
      [Array]::Copy($tag,$i,$data,0,$fsz)
      $frames += [pscustomobject]@{ Id=$id; Data=$data }
      $i += $fsz
    } else {
      if(($i + 10) -gt $tag.Length){ break }
      $id = [Text.Encoding]::ASCII.GetString($tag,$i,4)
      if($id -notmatch '^[A-Z0-9]{4}$'){ break }
      if($ver -ge 4){ $fsz = Get-SyncSafe $tag ($i+4) } else { $fsz = Get-UInt32BE $tag ($i+4) }
      $fflags = (([int]$tag[$i+8] -shl 8) -bor [int]$tag[$i+9])
      $i += 10
      if($fsz -lt 0 -or ($i + $fsz) -gt $tag.Length){ break }
      $data = New-Object byte[] $fsz
      [Array]::Copy($tag,$i,$data,0,$fsz)
      # v2.4 frame unsync flag
      if($ver -ge 4 -and ($fflags -band 0x0002) -ne 0){ $data = Remove-Id3Unsync $data }
      # skip optional data-length indicator (v2.4)
      if($ver -ge 4 -and ($fflags -band 0x0001) -ne 0 -and $data.Length -ge 4){
        $trim = New-Object byte[] ($data.Length-4)
        [Array]::Copy($data,4,$trim,0,$trim.Length)
        $data = $trim
      }
      $frames += [pscustomobject]@{ Id=$id; Data=$data }
      $i += $fsz
    }
  }
  return $frames
}

function Get-Id3TextFrame($frames,[string]$idV3,[string]$idV2){
  foreach($f in $frames){
    if($f.Id -eq $idV3 -or $f.Id -eq $idV2){
      if($f.Data.Length -lt 2){ continue }
      $enc = [int]$f.Data[0]
      return (Decode-Id3Text $f.Data $enc 1 ($f.Data.Length-1))
    }
  }
  return ''
}

function Get-Id3Lyrics($frames){
  $found = @()
  foreach($f in $frames){
    if($f.Id -notin 'USLT','ULT','COMM','COM','TXXX'){ continue }
    if($f.Data.Length -lt 5){ continue }
    $enc = [int]$f.Data[0]
    $next = 0
    if($f.Id -in 'USLT','ULT'){
      # enc + lang(3) + descriptor + lyrics
      $afterLang = 4
      if($afterLang -ge $f.Data.Length){ continue }
      [void](Read-Id3Terminated $f.Data $enc $afterLang $f.Data.Length ([ref]$next))
      $lyr = Decode-Id3Text $f.Data $enc $next ($f.Data.Length - $next)
      if($lyr){ $found += $lyr }
    } elseif($f.Id -in 'TXXX'){
      $desc = Read-Id3Terminated $f.Data $enc 1 $f.Data.Length ([ref]$next)
      if($desc -match '(?i)^(lyrics|unsyncedlyrics|unsynced lyrics|sync lyrics)$'){
        $lyr = Decode-Id3Text $f.Data $enc $next ($f.Data.Length - $next)
        if($lyr){ $found += $lyr }
      }
    } elseif($f.Id -in 'COMM','COM'){
      $afterLang = 4
      $desc = Read-Id3Terminated $f.Data $enc $afterLang $f.Data.Length ([ref]$next)
      $val = Decode-Id3Text $f.Data $enc $next ($f.Data.Length - $next)
      if($val -match '(?i)made with suno'){ continue }
      if($desc -match '(?i)lyric' -or $val -match '(?i)\[(Verse|Chorus|Bridge|Intro|Outro|Pre-Chorus)'){
        if($val){ $found += $val }
      }
    }
  }
  if($found.Count){ return ($found | Sort-Object { $_.Length } -Descending | Select-Object -First 1) }
  return ''
}

function Get-Id3v1Title([byte[]]$b){
  if($b.Length -lt 128){ return '' }
  $off = $b.Length - 128
  if([Text.Encoding]::ASCII.GetString($b,$off,3) -ne 'TAG'){ return '' }
  $t = [Text.Encoding]::GetEncoding(28591).GetString($b,$off+3,30)
  return ($t -replace "[\u0000]+",'').Trim()
}

function Read-Mp3Tags([string]$path){
  $bytes = [IO.File]::ReadAllBytes($path)
  $frames = Get-Id3Frames $bytes
  $title = Get-Id3TextFrame $frames 'TIT2' 'TT2'
  if(-not $title){ $title = Get-Id3v1Title $bytes }
  $lyrics = Get-Id3Lyrics $frames
  return [pscustomobject]@{ Title=$title; Lyrics=(Clean-Lyrics $lyrics) }
}

function Guess-TitleFromFile([string]$path){
  $name = [IO.Path]::GetFileNameWithoutExtension($path)
  $name = $name -replace '(?i)\s*-?\s*sunomv(\s*[-_].*)?$','' -replace '(?i)_sunomv[-_].*$','' -replace '(?i)\s*-\s*lyrics$',''
  $name = $name -replace '_+',' '
  return $name.Trim()
}

function Split-TitleAndLyrics([string]$raw,[string]$fallbackTitle){
  $text = Clean-Lyrics $raw
  $title = $fallbackTitle
  $lyrics = $text
  if(-not $text){ return [pscustomobject]@{ Title=$title; Lyrics='' } }

  # If this is already a YouTube description, pull title + lyrics block
  if($text -match '(?im)^LYRICS\s*$'){
    $first = ($text -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
    if($first -match '^\s*(.+?)\s*\|\s*'){ $title = $Matches[1].Trim() }
    elseif($first -and $first.Length -lt 80){ $title = $first }
    $idx = $text.IndexOf("LYRICS")
    $after = $text.Substring($idx + 6) -replace '^\s+',''
    # stop before scripture / playlist / hashtags / copyright if present
    $cut = [regex]::Match($after, '(?m)^(?:This song belongs in the |"© |© |\u00a9 |#\w+)')
    # better: cut at the playlist / scripture-after-lyrics / copyright typically after a blank line following lyrics
    $parts = [regex]::Split($after, '(?m)\n(?=(?:"[A-Z][^"]{10,}"\s*\([1-9][A-Za-z0-9 .:]+\)$|This song belongs in the |© |\u00a9 |#\w+\s+#))')
    $lyrics = Clean-Lyrics $parts[0]
    return [pscustomobject]@{ Title=$title; Lyrics=$lyrics }
  }

  $lines = $text -split "`n"
  $first = ($lines | Where-Object { $_.Trim() } | Select-Object -First 1)
  if($first){
    $ft = $first.Trim()
    if($ft -match '^(?i)(title\s*[:=]\s*)(.+)$'){
      $title = $Matches[2].Trim()
      $lyrics = Clean-Lyrics (($text -replace ('^\s*'+[regex]::Escape($first)+'\s*'),''))
    } elseif($ft -notmatch '^\[' -and $ft.Length -le 80 -and $ft -notmatch '[.!?]$' -and $lines.Count -gt 2){
      # short first line with no end punctuation: treat as title, not lyrics
      if(-not $title -or $title -eq $ft){ $title = $ft }
      if(-not $fallbackTitle -or $ft -eq $fallbackTitle -or $ft -eq $title){
        $skip = 1; for($si=0;$si -lt @($lines).Count;$si++){ if($lines[$si] -eq $first){ $skip = $si+1; break } }
        $rest = ((@($lines) | Select-Object -Skip $skip) -join "`n")
        $lyrics = Clean-Lyrics $rest
        $title = $ft
      }
    }
  }
  if(-not $title){ $title = $fallbackTitle }
  return [pscustomobject]@{ Title=$title; Lyrics=(Clean-Lyrics $lyrics) }
}

function Load-Settings{
  $d = @{
    artist = $defaultArtist
    credit = $defaultCredit
    email = $defaultEmail
    copyright = $defaultCopyright
    playlist = 'Auto-pick'
  }
  if(Test-Path $settingsPath){
    try{
      $j = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach($k in 'artist','credit','email','copyright','playlist'){
        if($null -ne $j.$k -and [string]$j.$k -ne ''){ $d[$k] = [string]$j.$k }
      }
    } catch {}
  }
  return $d
}

function Save-Settings($s){
  @{ artist=$s.artist; credit=$s.credit; email=$s.email; copyright=$s.copyright; playlist=$s.playlist } | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
}

function Show-Note([string]$msg,[string]$title='Make YouTube Description',[string]$icon='Information'){
  if($noUi){ Write-Host $msg; return }
  [System.Windows.Forms.MessageBox]::Show($msg,$title,'OK',$icon) | Out-Null
}

function Get-GeminiKey{
  if(Test-Path $keyPath){
    $k = $null
    try { $k = (Get-Content $keyPath -Raw -ErrorAction Stop) } catch {}
    if($k){ $k = $k.Trim() }
    if($k){ return $k }
  }
  if($Edition -ne 'Share'){
    Show-Note "I can't find the Gemini key file (gemini.key) in the tools folder." 'Make YouTube Description' 'Warning'
    return $null
  }
  if($noUi){
    Write-Host "No Gemini API key found. On first run, open the app and paste your free key from Google AI Studio."
    return $null
  }
  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Gemini API key'
  $form.Width = 560; $form.Height = 280; $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Left = 20; $lbl.Top = 15; $lbl.Width = 510; $lbl.Height = 70
  $lbl.Text = "This tool uses a free Gemini API key from Google AI Studio.`nPaste your key below. It is saved only on this computer, as gemini.key, next to the script."
  $box = New-Object System.Windows.Forms.TextBox
  $box.Left = 20; $box.Top = 95; $box.Width = 510; $box.UseSystemPasswordChar = $true
  $link = New-Object System.Windows.Forms.LinkLabel
  $link.Text = 'Open Google AI Studio to get a free key'
  $link.Left = 20; $link.Top = 130; $link.Width = 510; $link.AutoSize = $true
  $link.Add_LinkClicked({ Start-Process 'https://aistudio.google.com/apikey' })
  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = 'Save key'; $ok.Left = 280; $ok.Top = 185; $ok.Width = 120; $ok.Height = 32
  $ok.Add_Click({
    if(-not $box.Text.Trim()){ return }
    $form.DialogResult = 'OK'; $form.Close()
  })
  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'Cancel'; $cancel.Left = 410; $cancel.Top = 185; $cancel.Width = 120; $cancel.Height = 32
  $cancel.Add_Click({ $form.DialogResult = 'Cancel'; $form.Close() })
  $form.AcceptButton = $ok; $form.CancelButton = $cancel
  $form.Controls.AddRange(@($lbl,$box,$link,$ok,$cancel))
  $form.Topmost = $true
  if($form.ShowDialog() -eq 'OK'){
    $k = $box.Text.Trim()
    Set-Content -Path $keyPath -Value $k -Encoding ASCII
    return $k
  }
  return $null
}

function Map-Playlist([string]$raw){
  $s = ($raw + '').Trim()
  if($s -match '(?i)worship'){ return '1- Worship' }
  if($s -match '(?i)heartstring'){ return '4- Heartstrings' }
  if($s -match '(?i)watchman'){ return '5- Watchman' }
  if($s -match '(?i)humor|comedy|funny|parody'){ return 'Humor' }
  if($s -match '(?i)faith'){ return '2- Faith' }
  if($s -in $playlists -and $s -ne 'Auto-pick'){ return $s }
  if($s){ return $s }
  return '2- Faith'
}

function Get-ArtistTag([string]$artist){
  $s = ($artist + '') -replace "[’']",'' -replace '[^\w]+',''
  if(-not $s){ $s = 'OriginalMusic' }
  return "#$s"
}

function Ask-LyricsFile{
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Filter = 'Songs and lyrics|*.mp3;*.txt|MP3 songs|*.mp3|Lyrics text|*.txt|All files|*.*'
  $dlg.Title = 'Choose an MP3 or a lyrics .txt file'
  if($dlg.ShowDialog() -eq 'OK'){ return $dlg.FileName }
  return $null
}

function Read-SongSource([string]$path){
  $title = ''
  $lyrics = ''
  if($path -and (Test-Path -LiteralPath $path)){
    $ext = [IO.Path]::GetExtension($path).ToLower()
    $title = Guess-TitleFromFile $path
    if($ext -eq '.mp3'){
      $tags = Read-Mp3Tags $path
      if($tags.Title){ $title = $tags.Title.Trim() }
      $lyrics = $tags.Lyrics
    } elseif($ext -eq '.txt'){
      $parsed = Split-TitleAndLyrics (Read-TextFile $path) $title
      if($parsed.Title){ $title = $parsed.Title }
      $lyrics = $parsed.Lyrics
    } else {
      return $null
    }
  }
  return [pscustomobject]@{ Title=$title; Lyrics=$lyrics; Path=$path }
}

function Ask-DescriptionForm([string]$preTitle,[string]$preLyrics,[string]$sourcePath){
  $saved = Load-Settings
  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Make YouTube Description'
  $form.Width = 760
  $form.StartPosition = 'CenterScreen'
  $form.MinimumSize = New-Object System.Drawing.Size(640,560)
  $form.Font = New-Object System.Drawing.Font('Segoe UI',10)

  $y = 15
  $lTitle = New-Object System.Windows.Forms.Label
  $lTitle.Text = 'Song title:'; $lTitle.Left = 20; $lTitle.Top = ($y+3); $lTitle.AutoSize = $true
  $titleBox = New-Object System.Windows.Forms.TextBox
  $titleBox.Left = 120; $titleBox.Top = $y; $titleBox.Width = 430; $titleBox.Text = $preTitle
  $browse = New-Object System.Windows.Forms.Button
  $browse.Text = 'Browse...'; $browse.Left = 560; $browse.Top = ($y-2); $browse.Width = 160; $browse.Height = 28
  $form.Controls.AddRange(@($lTitle,$titleBox,$browse))
  $y += 36

  $shareExtra = ($Edition -eq 'Share')
  $artistBox = $null; $creditBox = $null; $emailBox = $null; $copyBox = $null
  if($shareExtra){
    $lArt = New-Object System.Windows.Forms.Label; $lArt.Text = 'Artist name:'; $lArt.Left = 20; $lArt.Top = ($y+3); $lArt.AutoSize = $true
    $artistBox = New-Object System.Windows.Forms.TextBox; $artistBox.Left = 120; $artistBox.Top = $y; $artistBox.Width = 250; $artistBox.Text = $saved.artist
    $lCred = New-Object System.Windows.Forms.Label; $lCred.Text = 'Credit line name:'; $lCred.Left = 385; $lCred.Top = ($y+3); $lCred.AutoSize = $true
    $creditBox = New-Object System.Windows.Forms.TextBox; $creditBox.Left = 520; $creditBox.Top = $y; $creditBox.Width = 200; $creditBox.Text = $saved.credit
    $form.Controls.AddRange(@($lArt,$artistBox,$lCred,$creditBox))
    $y += 32
    $lEm = New-Object System.Windows.Forms.Label; $lEm.Text = 'Sheet-music email:'; $lEm.Left = 20; $lEm.Top = ($y+3); $lEm.AutoSize = $true
    $emailBox = New-Object System.Windows.Forms.TextBox; $emailBox.Left = 155; $emailBox.Top = $y; $emailBox.Width = 250; $emailBox.Text = $saved.email
    $lCopy = New-Object System.Windows.Forms.Label; $lCopy.Text = 'Copyright name:'; $lCopy.Left = 415; $lCopy.Top = ($y+3); $lCopy.AutoSize = $true
    $copyBox = New-Object System.Windows.Forms.TextBox; $copyBox.Left = 540; $copyBox.Top = $y; $copyBox.Width = 180; $copyBox.Text = $saved.copyright
    $form.Controls.AddRange(@($lEm,$emailBox,$lCopy,$copyBox))
    $y += 32
  }

  $lPlay = New-Object System.Windows.Forms.Label; $lPlay.Text = 'Playlist:'; $lPlay.Left = 20; $lPlay.Top = ($y+3); $lPlay.AutoSize = $true
  $playBox = New-Object System.Windows.Forms.ComboBox
  $playBox.Left = 120; $playBox.Top = $y; $playBox.Width = 220; $playBox.DropDownStyle = 'DropDown'
  [void]$playBox.Items.AddRange($playlists)
  if($playBox.Items.Contains($saved.playlist)){ $playBox.SelectedItem = $saved.playlist } else { $playBox.Text = $saved.playlist }
  if(-not $playBox.Text){ $playBox.SelectedItem = 'Auto-pick' }
  $lCred2 = New-Object System.Windows.Forms.Label; $lCred2.Text = 'Credit:'; $lCred2.Left = 360; $lCred2.Top = ($y+3); $lCred2.AutoSize = $true
  $creditMain = New-Object System.Windows.Forms.TextBox
  $creditMain.Left = 420; $creditMain.Top = $y; $creditMain.Width = 300
  if($shareExtra){ $creditMain.Visible = $false; $lCred2.Visible = $false } else { $creditMain.Text = $(if($saved.credit){ $saved.credit } else { $defaultCredit }) }
  $form.Controls.AddRange(@($lPlay,$playBox,$lCred2,$creditMain))
  $y += 36

  $lLyr = New-Object System.Windows.Forms.Label
  $lLyr.Text = 'Lyrics (section tags like [Verse 1] and [Chorus] are kept):'
  $lLyr.Left = 20; $lLyr.Top = $y; $lLyr.AutoSize = $true
  $form.Controls.Add($lLyr)
  $y += 24

  $btn = New-Object System.Windows.Forms.Button
  $btn.Text = 'Write my description'
  $btn.Dock = 'Bottom'; $btn.Height = 48
  $btn.Font = New-Object System.Drawing.Font('Segoe UI',12)
  $form.Controls.Add($btn)

  $lyrBox = New-Object System.Windows.Forms.TextBox
  $lyrBox.Multiline = $true; $lyrBox.ScrollBars = 'Vertical'
  $lyrBox.AcceptsReturn = $true; $lyrBox.Font = New-Object System.Drawing.Font('Consolas',10)
  $lyrBox.Text = ($preLyrics -replace "`n","`r`n")
  $lyrBox.Anchor = 'Top,Left,Right,Bottom'
  $lyrBox.Left = 20; $lyrBox.Top = $y
  $lyrBox.Width = ($form.ClientSize.Width - 40)
  $lyrBox.Height = ($form.ClientSize.Height - $y - $btn.Height - 20)
  $form.Controls.Add($lyrBox)
  $script:chosenPath = $sourcePath
  $script:descTitleBox = $titleBox
  $script:descLyrBox = $lyrBox
  $script:descPlayBox = $playBox
  $script:descArtistBox = $artistBox
  $script:descCreditBox = $creditBox
  $script:descEmailBox = $emailBox
  $script:descCopyBox = $copyBox
  $script:descCreditMain = $creditMain
  $script:descBtn = $btn
  $form.Add_Resize({
    $script:descLyrBox.Width = ($form.ClientSize.Width - 40)
    $script:descLyrBox.Height = ($form.ClientSize.Height - $script:descLyrBox.Top - $script:descBtn.Height - 20)
  })
  $form.Height = 720

  $browse.Add_Click({
    $p = Ask-LyricsFile
    if(-not $p){ return }
    $song = Read-SongSource $p
    if(-not $song){ Show-Note "Please choose an MP3 or a lyrics .txt file." 'Make YouTube Description' 'Warning'; return }
    $script:chosenPath = $p
    if($song.Title){ $script:descTitleBox.Text = $song.Title }
    $script:descLyrBox.Text = ($song.Lyrics -replace "`n","`r`n")
    if(-not $song.Lyrics){
      Show-Note "I couldn't find lyrics inside that MP3. You can paste them here, or browse for a lyrics .txt file." 'No lyrics in this MP3' 'Information'
    }
  })

  $result = $null
  $btn.Add_Click({
    if(-not $script:descTitleBox.Text.Trim()){ Show-Note "Please enter the song title." 'Make YouTube Description' 'Warning'; return }
    if(-not $script:descLyrBox.Text.Trim()){ Show-Note "Please paste the lyrics, or browse for an MP3 / lyrics file that has them." 'Make YouTube Description' 'Warning'; return }
    $artist = $defaultArtist
    $credit = $defaultCredit
    $email = $defaultEmail
    $copy = $defaultCopyright
    if($Edition -eq 'Share'){
      $artist = $script:descArtistBox.Text.Trim()
      $credit = $script:descCreditBox.Text.Trim()
      if(-not $credit){ $credit = $artist }
      $email = $script:descEmailBox.Text.Trim()
      $copy = $script:descCopyBox.Text.Trim()
      if(-not $copy){ $copy = $artist }
      if(-not $artist){ Show-Note "Please enter your artist name (it goes in the title line and the copyright)." 'Make YouTube Description' 'Warning'; return }
    } else {
      $credit = $script:descCreditMain.Text.Trim()
      if(-not $credit){ $credit = $defaultCredit }
    }
    $opts = @{ artist=$artist; credit=$credit; email=$email; copyright=$copy; playlist=$script:descPlayBox.Text }
    Save-Settings $opts
    $script:formResult = [pscustomobject]@{
      Title = $script:descTitleBox.Text.Trim()
      Lyrics = (Clean-Lyrics $script:descLyrBox.Text)
      Artist = $artist
      Credit = $credit
      Email = $email
      Copyright = $copy
      Playlist = $script:descPlayBox.Text
      Path = $script:chosenPath
    }
    $form.DialogResult = 'OK'
    $form.Close()
  })
  $form.Topmost = $true
  $script:formResult = $null
  if($form.ShowDialog() -eq 'OK'){ return $script:formResult }
  return $null
}

function Parse-GeminiJson([string]$text){
  $t = ($text + '').Trim()
  $t = $t -replace '^```(?:json)?\s*','' -replace '\s*```$',''
  $t = $t.Trim()
  # grab the first {...} block if extra prose slipped in
  $m = [regex]::Match($t, '(?s)\{.*\}')
  if($m.Success){ $t = $m.Value }
  try { return ($t | ConvertFrom-Json) } catch { return $null }
}

function Invoke-GeminiMeta([string]$title,[string]$lyrics,[string]$artist){
  $key = Get-GeminiKey
  if(-not $key){ return $null }
  $artistName = $artist
  if(-not $artistName){ $artistName = 'the artist' }
  $rules = @"
You write metadata for a YouTube description of an original song by $artistName.
Read the lyrics carefully. Return ONLY valid JSON, with no markdown and no extra text, using exactly these keys:
{
  "subtitle": "A short genre/theme phrase such as A Folk-Rock Song About Truth",
  "pullQuote": "One real line or short phrase copied from the lyrics",
  "blurb": "3 to 5 warm sentences, plus an optional short closing line",
  "scripture": "KJV verse in this exact shape: \"quote\" (Book Chapter:Verse)  OR an empty string",
  "playlist": "one of: 1- Worship, 2- Faith, 4- Heartstrings, 5- Watchman, Humor, or another short honest name",
  "hashtags": "5 to 7 space-separated hashtags"
}

Style rules:
- The subtitle should sound like: "A Watchman Song About Seeing Past the Noise" or "A Heartland Rock Anthem" or "A Soft Acoustic Evening Prayer". Do not repeat the song title in the subtitle. Do not include the artist name in the subtitle.
- The pull quote MUST be words that actually appear in the lyrics (a line or a short natural combination of a line). Do not invent a quote. Do not add quote marks in the JSON value; just the words.
- The blurb is warm, respectful, specific, and clear. Use correct grammar. Write it the way a songwriter would introduce the song, not like a review or a sermon. Start from a real image or moment in the lyrics (a fleece on the floor, a letter in a shoebox, a wobbly grocery-cart wheel), not from a general line like "In a world filled with..." or "This song serves as..." or "May this music encourage you." Do not talk down to the listener. Never use the word "child". Never mention AI, Suno, or how the music was made. Never use graphic violence language or the word "suicide". Avoid occult-sounding wording. If the song is about faith in Jesus or Scripture, let that show naturally and sincerely. If it is a Watchman / discernment / signs-of-the-times song, write it in that lens. If it is tender or everyday, keep it tender and everyday. A short, human closing line is welcome when it fits (a gentle nudge or a leftover spoken line from the song), but do not force one.
- Scripture: include one only when the song is clearly faith, worship, prayer, or watchman, AND you are sure of a well-known, accurate King James (KJV) verse that truly fits. Prefer a short verse. Do not choose a verse that uses the words "child" or "children". If you are not sure of the exact wording or reference, or the best-known fit uses those words, return an empty string. Never invent a verse. Never use a modern paraphrase.
- Playlist: pick the best fit from the list. Worship for songs to the Lord. Faith for testimony and everyday trust. Heartstrings for story, home, love, and tender memory. Watchman for discernment, truth, warning, and staying awake. Humor when the song is clearly funny. Use another short name only if none of those fit.
- Hashtags: 5 to 7 tags, each starting with #, no commas. Start with a hashtag made from the song title. End with $(Get-ArtistTag $artistName). Include a genre or theme tag. If you used a scripture, a short book tag like #John1 is welcome.
"@
  $prompt = $rules + "`n`nSONG TITLE:`n" + $title + "`n`nLYRICS:`n" + $lyrics
  $payload = @{
    contents = @(@{ parts = @(@{ text = $prompt }) })
    generationConfig = @{ temperature = 0.35; maxOutputTokens = 2048 }
  }
  $body = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 8))
  $models = 'gemini-3.1-flash-lite','gemini-3.5-flash-lite','gemini-flash-latest','gemini-3.5-flash','gemini-2.5-flash','gemini-2.5-flash-lite'
  $lastErr = ''
  foreach($try in 1..3){
    foreach($m in $models){
      try{
        Write-Host "Asking Gemini ($m)..."
        $r = Invoke-RestMethod -Method Post -Uri "https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent" -Headers @{ 'x-goog-api-key' = $key } -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 90
        $t = ($r.candidates[0].content.parts | ForEach-Object { $_.text }) -join ''
        if(-not $t -or -not $t.Trim()){
          $reason = ''
          try { $reason = [string]$r.candidates[0].finishReason } catch {}
          if($reason){ Write-Host "  no text ($reason), trying another..." } else { Write-Host "  empty reply, trying another..." }
          continue
        }
        $json = Parse-GeminiJson $t
        if($json -and $json.blurb){ return $json }
        Write-Host "  reply was not usable JSON, trying another..."
      } catch {
        $lastErr = $_.Exception.Message
        if($lastErr -match '404|not found'){ Write-Host "  model not available, trying another..." }
        elseif($lastErr -match '429|Too Many|Resource has been exhausted'){ Write-Host "  busy, trying another..." }
        else { Write-Host "  didn't work, trying another..." }
      }
    }
    Start-Sleep -Seconds 5
  }
  return $null
}

function Format-Scripture([string]$raw){
  $s = ($raw + '').Trim()
  if(-not $s){ return '' }
  if($s -match '(?i)^(n/?a|none|no verse|not applicable)$'){ return '' }
  # already in "quote" (Ref) form
  if($s -match '^".+"\s*\([^)]+\)$'){ return $s }
  # quote then reference without outer quotes
  if($s -match '^(?:"|“)(.+?)(?:"|”)\s*\(([^)]+)\)$'){ return '"' + $Matches[1].Trim() + '" (' + $Matches[2].Trim() + ')' }
  if($s -match '^\(([^)]+)\)\s*(?:"|“)?(.+?)(?:"|”)?$'){ return '"' + $Matches[2].Trim().Trim('"') + '" (' + $Matches[1].Trim() + ')' }
  if($s -match '^(?:"|“)?(.+?)(?:"|”)?\s*[-–—]\s*([1-9]?[A-Za-z][A-Za-z0-9 .]+ \d+:\d+(?:-\d+)?)$'){
    return '"' + $Matches[1].Trim().Trim('"') + '" (' + $Matches[2].Trim() + ')'
  }
  if($s -match '^([1-9]?[A-Za-z][A-Za-z0-9 .]+ \d+:\d+(?:-\d+)?)\s*[-–—:]\s*(?:"|“)?(.+?)(?:"|”)?$'){
    return '"' + $Matches[2].Trim().Trim('"') + '" (' + $Matches[1].Trim() + ')'
  }
  return $s
}

function Format-Hashtags([string]$raw,[string]$title,[string]$artist){
  $end = Get-ArtistTag $artist
  $parts = @()
  foreach($p in (($raw + '') -split '[,;\s]+')){
    $t = $p.Trim()
    if(-not $t){ continue }
    if($t[0] -ne '#'){ $t = '#' + $t }
    $t = '#' + ($t.Substring(1) -replace '[^A-Za-z0-9]','')
    if($t.Length -lt 3){ continue }
    if($parts -notcontains $t){ $parts += $t }
  }
  $titleTag = '#' + ((Get-SafeTitle $title) -replace '_','')
  if($titleTag.Length -ge 3 -and $parts -notcontains $titleTag){ $parts = @($titleTag) + $parts }
  $parts = @($parts | Where-Object { $_ -ne $end })
  if($parts.Count -gt 6){ $parts = $parts[0..5] }
  $parts += $end
  return ($parts -join ' ')
}

function Build-Description($job,$meta){
  $title = $job.Title.Trim()
  $artist = $job.Artist.Trim()
  if(-not $artist){ $artist = $defaultArtist }
  $credit = $job.Credit.Trim()
  if(-not $credit){ $credit = $artist }
  $email = ($job.Email + '').Trim()
  $copy = $job.Copyright.Trim()
  if(-not $copy){ $copy = $artist }
  $subtitle = ([string]$meta.subtitle).Trim().Trim('"').Trim()
  $titleLine = if($subtitle){ "$title | $subtitle | $artist" } else { "$title | $artist" }
  $quote = ([string]$meta.pullQuote).Trim().Trim('"').Trim([char]0x201C).Trim([char]0x201D)
  $blurb = ([string]$meta.blurb).Trim()
  $scripture = Format-Scripture ([string]$meta.scripture)
  $chosenPlay = ($job.Playlist + '').Trim()
  if(-not $chosenPlay -or $chosenPlay -eq 'Auto-pick'){ $playlist = Map-Playlist ([string]$meta.playlist) }
  else { $playlist = Map-Playlist $chosenPlay }
  $tags = Format-Hashtags ([string]$meta.hashtags) $title $artist
  $lyrics = Normalize-Newlines (Clean-Lyrics $job.Lyrics)
  $nl = "`r`n"
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append($titleLine); [void]$sb.Append($nl); [void]$sb.Append($nl)
  [void]$sb.Append('"' + $quote + '"'); [void]$sb.Append($nl); [void]$sb.Append($nl)
  [void]$sb.Append($blurb); [void]$sb.Append($nl); [void]$sb.Append($nl)
  [void]$sb.Append("Written and performed by $credit"); [void]$sb.Append($nl)
  if($email){ [void]$sb.Append("For sheet music, please contact me at $email"); [void]$sb.Append($nl) }
  [void]$sb.Append($nl)
  [void]$sb.Append('LYRICS'); [void]$sb.Append($nl); [void]$sb.Append($nl)
  [void]$sb.Append($lyrics); [void]$sb.Append($nl); [void]$sb.Append($nl)
  if($scripture){ [void]$sb.Append($scripture); [void]$sb.Append($nl); [void]$sb.Append($nl) }
  [void]$sb.Append("This song belongs in the $playlist playlist."); [void]$sb.Append($nl); [void]$sb.Append($nl)
  $year = Get-Date -Format 'yyyy'
  [void]$sb.Append(("© {0} {1}. All rights reserved." -f $year,$copy)); [void]$sb.Append($nl); [void]$sb.Append($nl)
  [void]$sb.Append($tags); [void]$sb.Append($nl)
  return $sb.ToString()
}

function Save-Description([string]$text,[string]$title,[string]$outDir){
  if(-not (Test-Path -LiteralPath $outDir)){ New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
  $safe = Get-SafeTitle $title
  $dest = Join-Path $outDir ($safe + '_YouTube_Description.txt')
  if(Test-Path -LiteralPath $dest){
    $oldDir = Join-Path $outDir 'old'
    New-Item -ItemType Directory -Force -Path $oldDir | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $backup = Join-Path $oldDir ($safe + '_YouTube_Description_' + $stamp + '.txt')
    Move-Item -LiteralPath $dest -Destination $backup -Force
    Write-Host "Previous description moved to $backup"
  }
  $charCount = $text.Length
  $toWrite = $text
  if($charCount -gt 5000){
    $note = "*** NOTE (delete this line before pasting): This description is $charCount characters, which is over YouTube's 5,000-character limit. The lyrics were not cut. ***`r`n`r`n"
    $toWrite = $note + $text
    Write-Host "Warning: $charCount characters (YouTube's limit is 5,000). Lyrics were not cut."
  } else {
    Write-Host "Length: $charCount characters (YouTube's limit is 5,000)."
  }
  $utf8 = New-Object System.Text.UTF8Encoding $true
  [IO.File]::WriteAllText($dest, $toWrite, $utf8)
  return [pscustomobject]@{ Path=$dest; Length=$charCount; OverLimit=($charCount -gt 5000) }
}

function Make-Description($job){
  if(-not $job -or -not $job.Title -or -not $job.Lyrics){ return }
  if($extractOnly){
    Write-Host "EXTRACT ONLY"
    Write-Host ("TITLE: " + $job.Title)
    Write-Host ("LYRICS_LINES: " + @($job.Lyrics -split "`n").Count)
    Write-Host ("LYRICS_CHARS: " + $job.Lyrics.Length)
    $preview = ($job.Lyrics -split "`n" | Select-Object -First 8) -join "`n"
    Write-Host "FIRST_LINES:"
    Write-Host $preview
    $last = ($job.Lyrics -split "`n" | Select-Object -Last 5) -join "`n"
    Write-Host "LAST_LINES:"
    Write-Host $last
    return
  }
  $meta = Invoke-GeminiMeta $job.Title $job.Lyrics $job.Artist
  if(-not $meta){
    Show-Note "Gemini is too busy right now, or the reply wasn't usable. Try again in a few minutes." 'Make YouTube Description' 'Warning'
    return
  }
  $text = Build-Description $job $meta
  $saved = Save-Description $text $job.Title $defaultDescDir
  $copied = $false
  if(-not $noClip){
    try { Set-Clipboard -Value $text; $copied = $true } catch { Write-Host "Couldn't copy to the clipboard, but the file was saved." }
  }
  if($copied){ Write-Host "Description saved: $($saved.Path) (also copied - just paste it into YouTube)" }
  else { Write-Host "Description saved: $($saved.Path)" }
  if($saved.OverLimit){
    Show-Note "The description was saved, but it is $($saved.Length) characters. YouTube's limit is 5,000, so you'll need to trim it a little before pasting. The lyrics were not cut." "Over YouTube's 5,000-character limit" 'Warning'
  }
  if(-not $noNotepad){ Start-Process notepad.exe $saved.Path }
}

# --- main ---
$files = @()
foreach($a in $args){ if($a){ $files += $a } }

if($files.Count -eq 0){
  if($noUi){
    Write-Host "No file was given, and the window is turned off for this test run."
    return
  }
  $job = Ask-DescriptionForm '' '' $null
  if($job){ Make-Description $job }
  return
}

foreach($f in $files){
  try{
    if(-not (Test-Path -LiteralPath $f)){ Write-Host "Couldn't find: $f"; continue }
    $ext = [IO.Path]::GetExtension($f).ToLower()
    if($ext -notin '.mp3','.txt'){ Write-Host "Please drop an MP3 song or a lyrics .txt file: $f"; continue }
    $song = Read-SongSource $f
    if($noUi){
      $saved = Load-Settings
      if(-not $song.Lyrics){ Write-Host "No lyrics found in $f"; continue }
      $job = [pscustomobject]@{
        Title = $song.Title
        Lyrics = $song.Lyrics
        Artist = $(if($saved.artist){ $saved.artist } else { $defaultArtist })
        Credit = $(if($saved.credit){ $saved.credit } else { $defaultCredit })
        Email = $(if($saved.email){ $saved.email } else { $defaultEmail })
        Copyright = $(if($saved.copyright){ $saved.copyright } else { $defaultCopyright })
        Playlist = 'Auto-pick'
        Path = $f
      }
      Make-Description $job
      continue
    }
    $preLyrics = $song.Lyrics
    if(-not $preLyrics){
      Show-Note "I couldn't find lyrics inside that MP3. You can paste them in the next window, or browse for a lyrics .txt file." 'No lyrics in this MP3' 'Information'
    }
    $job = Ask-DescriptionForm $song.Title $preLyrics $f
    if($job){ Make-Description $job }
  } catch {
    $msg = $_.Exception.Message
    Write-Host "Problem with $f : $msg"
    if(-not $noUi){ Show-Note "There was a problem with that file:`n$msg" 'Make YouTube Description' 'Error' }
  }
}
