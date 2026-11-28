# YouTube Description helper
# Drop an MP3 or a lyrics .txt on the icon, or double-click to paste.
# For a regular (non-music) video, choose Type: Video and drop or paste a transcript, script, or notes.
# Gemini writes the title line, pull quote, blurb, scripture, playlist, and hashtags for a song,
# or a clear summary and hashtags for a regular video.
# In Song mode the lyrics themselves are copied exactly from your file or MP3 and are never rewritten.
# Optional extras (links, subscribe, timestamps, credits, licensing, contact, and anything else) are remembered.
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

function ConvertTo-BoolFlag($v, [bool]$default=$false){
  if($null -eq $v -or [string]$v -eq ''){ return $default }
  if($v -is [bool]){ return [bool]$v }
  $s = ([string]$v).Trim()
  if($s -match '^(?i)(1|true|yes|y|on)$'){ return $true }
  if($s -match '^(?i)(0|false|no|n|off)$'){ return $false }
  return $default
}

function ConvertTo-ContentType($v){
  $s = ([string]$v).Trim()
  if($s -match '(?i)^video'){ return 'Video' }
  return 'Song'
}

function ConvertTo-LinkList($raw){
  $links = @()
  if(-not $raw){ return $links }
  foreach($item in @($raw)){
    if($null -eq $item){ continue }
    $lab = ''
    $url = ''
    try { $lab = [string]$item.label } catch {}
    try { $url = [string]$item.url } catch {}
    if(-not $url){
      try { $url = [string]$item.Url } catch {}
    }
    $lab = ($lab + '').Trim()
    $url = ($url + '').Trim()
    if($lab -or $url){ $links += [pscustomobject]@{ label=$lab; url=$url } }
  }
  return @($links)
}

function Load-Settings{
  $d = @{
    artist = $defaultArtist
    credit = $defaultCredit
    email = $defaultEmail
    copyright = $defaultCopyright
    playlist = 'Auto-pick'
    contentType = 'Song'
    includeLyrics = $true
    includeSheetMusic = $false
    includeLinks = $false
    links = @()
    includeSubscribe = $false
    subscribeText = ''
    includeTimestamps = $false
    timestampsText = ''
    includeCredits = $false
    creditsText = ''
    includeLicensing = $false
    licensingText = ''
    includeContact = $false
    contactText = ''
    includeExtra = $false
    extraText = ''
  }
  if(Test-Path $settingsPath){
    try{
      $j = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach($k in 'artist','credit','email','copyright','playlist','subscribeText','timestampsText','creditsText','licensingText','contactText','extraText'){
        if($null -ne $j.$k -and [string]$j.$k -ne ''){ $d[$k] = [string]$j.$k }
      }
      if($null -ne $j.contentType -and [string]$j.contentType -ne ''){ $d.contentType = ConvertTo-ContentType $j.contentType }
      $d.includeLyrics = ConvertTo-BoolFlag $j.includeLyrics $true
      if($null -eq $j.PSObject.Properties['includeSheetMusic']){
        $d.includeSheetMusic = [bool](($d.email + '').Trim())
      } else {
        $d.includeSheetMusic = ConvertTo-BoolFlag $j.includeSheetMusic $false
      }
      foreach($pair in @(
        @{ k='includeLinks'; d=$false },
        @{ k='includeSubscribe'; d=$false },
        @{ k='includeTimestamps'; d=$false },
        @{ k='includeCredits'; d=$false },
        @{ k='includeLicensing'; d=$false },
        @{ k='includeContact'; d=$false },
        @{ k='includeExtra'; d=$false }
      )){
        $d[$pair.k] = ConvertTo-BoolFlag $j.($pair.k) $pair.d
      }
      $d.links = ConvertTo-LinkList $j.links
    } catch {}
  }
  if($env:YTDESC_INCLUDE_LYRICS){ $d.includeLyrics = ConvertTo-BoolFlag $env:YTDESC_INCLUDE_LYRICS $d.includeLyrics }
  if($env:YTDESC_TYPE){ $d.contentType = ConvertTo-ContentType $env:YTDESC_TYPE }
  return $d
}

function Save-Settings($s){
  $links = @()
  foreach($item in @(ConvertTo-LinkList $s.links)){
    $links += @{ label=[string]$item.label; url=[string]$item.url }
  }
  $obj = @{
    artist = [string]$s.artist
    credit = [string]$s.credit
    email = [string]$s.email
    copyright = [string]$s.copyright
    playlist = [string]$s.playlist
    contentType = (ConvertTo-ContentType $s.contentType)
    includeLyrics = [bool](ConvertTo-BoolFlag $s.includeLyrics $true)
    includeSheetMusic = [bool](ConvertTo-BoolFlag $s.includeSheetMusic $false)
    includeLinks = [bool](ConvertTo-BoolFlag $s.includeLinks $false)
    links = $links
    includeSubscribe = [bool](ConvertTo-BoolFlag $s.includeSubscribe $false)
    subscribeText = [string]$s.subscribeText
    includeTimestamps = [bool](ConvertTo-BoolFlag $s.includeTimestamps $false)
    timestampsText = [string]$s.timestampsText
    includeCredits = [bool](ConvertTo-BoolFlag $s.includeCredits $false)
    creditsText = [string]$s.creditsText
    includeLicensing = [bool](ConvertTo-BoolFlag $s.includeLicensing $false)
    licensingText = [string]$s.licensingText
    includeContact = [bool](ConvertTo-BoolFlag $s.includeContact $false)
    contactText = [string]$s.contactText
    includeExtra = [bool](ConvertTo-BoolFlag $s.includeExtra $false)
    extraText = [string]$s.extraText
  }
  $obj | ConvertTo-Json -Depth 6 | Set-Content $settingsPath -Encoding UTF8
}

function Merge-SettingFields($target, $source){
  if(-not $target){ $target = @{} }
  if(-not $source){ return $target }
  foreach($k in @(
    'artist','credit','email','copyright','playlist','contentType','includeLyrics','includeSheetMusic',
    'includeLinks','links','includeSubscribe','subscribeText','includeTimestamps','timestampsText',
    'includeCredits','creditsText','includeLicensing','licensingText','includeContact','contactText',
    'includeExtra','extraText'
  )){
    if($source -is [hashtable]){
      if($source.ContainsKey($k)){ $target[$k] = $source[$k] }
    } else {
      $prop = $source.PSObject.Properties[$k]
      if($prop){ $target[$k] = $prop.Value }
    }
  }
  return $target
}

function Guess-LinkLabel([string]$url){
  $u = ($url + '').Trim()
  if($u -match '(?i)open\.spotify\.com|spotify\.com'){ return 'Spotify' }
  if($u -match '(?i)music\.apple\.com|itunes\.apple\.com'){ return 'Apple Music' }
  if($u -match '(?i)music\.amazon\.|amazon\.com/.+music'){ return 'Amazon Music' }
  if($u -match '(?i)bandcamp\.com'){ return 'Bandcamp' }
  if($u -match '(?i)soundcloud\.com'){ return 'SoundCloud' }
  if($u -match '(?i)youtu\.be|youtube\.com'){ return 'YouTube' }
  if($u -match '(?i)instagram\.com'){ return 'Instagram' }
  if($u -match '(?i)facebook\.com|fb\.me|fb\.com'){ return 'Facebook' }
  if($u -match '(?i)tiktok\.com'){ return 'TikTok' }
  if($u -match '(?i)(?:^https?://)?(?:www\.)?(?:x\.com|twitter\.com)/'){ return 'X' }
  if($u -match '(?i)deezer\.com'){ return 'Deezer' }
  if($u -match '(?i)pandora\.com'){ return 'Pandora' }
  if($u -match '(?i)tidal\.com'){ return 'Tidal' }
  if($u -match '(?i)audiomack\.com'){ return 'Audiomack' }
  if($u -match '(?i)patreon\.com'){ return 'Patreon' }
  if($u -match '(?i)ko-fi\.com'){ return 'Ko-fi' }
  if($u -match '(?i)linktr\.ee'){ return 'Linktree' }
  if($u -match '(?i)discord\.gg|discord\.com'){ return 'Discord' }
  if($u -match '(?i)twitch\.tv'){ return 'Twitch' }
  if($u -match '(?i)rumble\.com'){ return 'Rumble' }
  if($u -match '(?i)bitchute\.com'){ return 'BitChute' }
  if($u -match '(?i)odysee\.com'){ return 'Odysee' }
  if($u -match '(?i)substack\.com'){ return 'Substack' }
  if($u -match '(?i)^mailto:'){ return 'Email' }
  return ''
}

function Parse-PastedLink([string]$clip){
  $s = ($clip + '').Trim()
  if(-not $s){ return $null }
  $lab = ''
  $url = ''
  if($s -match '^(?i)(https?://\S+)$'){
    $url = $Matches[1].Trim()
    $lab = Guess-LinkLabel $url
  } elseif($s -match '(?s)^(.+?)\s*[:|–-]\s*(https?://\S+)'){
    $lab = $Matches[1].Trim()
    $url = $Matches[2].Trim()
  } elseif($s -match '(?i)(https?://\S+)'){
    $url = $Matches[1].Trim()
    $lab = Guess-LinkLabel $url
  } else {
    return $null
  }
  return [pscustomobject]@{ label=$lab; url=$url }
}

function Format-LinkLines($links){
  $lines = @()
  foreach($item in @(ConvertTo-LinkList $links)){
    $lab = ($item.label + '').Trim()
    $url = ($item.url + '').Trim()
    if(-not $url){ continue }
    if($lab){ $lines += ($lab + ': ' + $url) } else { $lines += $url }
  }
  return ($lines -join "`r`n")
}

function Read-GridLinks($grid){
  $links = @()
  if(-not $grid){ return $links }
  foreach($row in $grid.Rows){
    if($row.IsNewRow){ continue }
    $lab = ''
    $url = ''
    try { $lab = [string]$row.Cells['Label'].Value } catch {}
    try { $url = [string]$row.Cells['Url'].Value } catch {}
    $lab = ($lab + '').Trim()
    $url = ($url + '').Trim()
    if($lab -or $url){ $links += [pscustomobject]@{ label=$lab; url=$url } }
  }
  return @($links)
}

function Add-DescriptionBlock([System.Text.StringBuilder]$sb, [string]$text, [string]$nl){
  $t = Normalize-Newlines (($text + '').Trim())
  if(-not $t){ return }
  [void]$sb.Append($t)
  [void]$sb.Append($nl)
  [void]$sb.Append($nl)
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

function Ask-LyricsFile([string]$contentType='Song'){
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  if($contentType -eq 'Video'){
    $dlg.Filter = 'Transcript, script, or notes|*.txt|All files|*.*'
    $dlg.Title = 'Choose a .txt transcript, script, or notes file'
  } else {
    $dlg.Filter = 'Songs and lyrics|*.mp3;*.txt|MP3 songs|*.mp3|Lyrics text|*.txt|All files|*.*'
    $dlg.Title = 'Choose an MP3 or a lyrics .txt file'
  }
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

function Ask-OptionsForm($saved, [string]$email, [bool]$isVideo=$false){
  if($noUi){ return $saved }
  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Description options'
  $form.Width = 760
  $form.Height = 760
  $form.StartPosition = 'CenterScreen'
  $form.MinimumSize = New-Object System.Drawing.Size(700,560)
  $form.Font = New-Object System.Drawing.Font('Segoe UI',10)
  $form.MinimizeBox = $false

  $btnPanel = New-Object System.Windows.Forms.Panel
  $btnPanel.Dock = 'Bottom'
  $btnPanel.Height = 58
  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = 'Save options'
  $ok.Width = 140
  $ok.Height = 34
  $ok.Anchor = 'Right'
  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'Cancel'
  $cancel.Width = 120
  $cancel.Height = 34
  $cancel.Anchor = 'Right'
  $btnPanel.Controls.AddRange(@($ok,$cancel))
  $btnPanel.Add_Resize({
    $cancel.Left = $btnPanel.ClientSize.Width - $cancel.Width - 20
    $cancel.Top = 12
    $ok.Left = $cancel.Left - $ok.Width - 10
    $ok.Top = 12
  })
  $form.Controls.Add($btnPanel)

  $panel = New-Object System.Windows.Forms.Panel
  $panel.Dock = 'Fill'
  $panel.AutoScroll = $true
  $form.Controls.Add($panel)
  $form.Controls.SetChildIndex($panel, 0)

  $y = 12
  $intro = New-Object System.Windows.Forms.Label
  $intro.Text = 'Turn on any extras you want in the description. Your choices and wording are remembered for next time. If these stay off, a song description comes out just like it does now.'
  $intro.Left = 20; $intro.Top = $y; $intro.Width = 690; $intro.Height = 48
  $panel.Controls.Add($intro)
  $y += 52

  $chkLinks = New-Object System.Windows.Forms.CheckBox
  $chkLinks.Text = 'Include links'
  $chkLinks.Left = 20; $chkLinks.Top = $y; $chkLinks.AutoSize = $true
  $chkLinks.Checked = [bool](ConvertTo-BoolFlag $saved.includeLinks $false)
  $panel.Controls.Add($chkLinks)
  $pasteBtn = New-Object System.Windows.Forms.Button
  $pasteBtn.Text = 'Paste link'
  $pasteBtn.Left = 160; $pasteBtn.Top = ($y-3); $pasteBtn.Width = 110; $pasteBtn.Height = 28
  $addBtn = New-Object System.Windows.Forms.Button
  $addBtn.Text = 'Add row'
  $addBtn.Left = 278; $addBtn.Top = ($y-3); $addBtn.Width = 100; $addBtn.Height = 28
  $panel.Controls.AddRange(@($pasteBtn,$addBtn))
  $y += 30
  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = 'Type a name (for example Spotify) and paste the web address next to it. Paste link can also fill both from a copied address.'
  $hint.Left = 40; $hint.Top = $y; $hint.Width = 670; $hint.Height = 36
  $panel.Controls.Add($hint)
  $y += 36
  $grid = New-Object System.Windows.Forms.DataGridView
  $grid.Left = 40; $grid.Top = $y; $grid.Width = 670; $grid.Height = 140
  $grid.AllowUserToAddRows = $true
  $grid.AllowUserToDeleteRows = $true
  $grid.RowHeadersVisible = $false
  $grid.SelectionMode = 'FullRowSelect'
  $grid.MultiSelect = $false
  $grid.AutoSizeColumnsMode = 'Fill'
  $grid.BackgroundColor = [System.Drawing.Color]::White
  $grid.BorderStyle = 'FixedSingle'
  $colLab = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $colLab.HeaderText = 'Label'
  $colLab.Name = 'Label'
  $colLab.FillWeight = 30
  $colUrl = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $colUrl.HeaderText = 'Web address'
  $colUrl.Name = 'Url'
  $colUrl.FillWeight = 70
  [void]$grid.Columns.Add($colLab)
  [void]$grid.Columns.Add($colUrl)
  foreach($item in @(ConvertTo-LinkList $saved.links)){
    [void]$grid.Rows.Add($item.label, $item.url)
  }
  $panel.Controls.Add($grid)
  $script:optLinkGrid = $grid
  $pasteBtn.Add_Click({
    $clip = ''
    try { $clip = [string](Get-Clipboard -Raw -ErrorAction Stop) } catch {
      try { $clip = [string](Get-Clipboard -ErrorAction Stop) } catch { $clip = '' }
    }
    $parsed = Parse-PastedLink $clip
    if(-not $parsed){
      Show-Note "Copy a web address first, then click Paste link. You can also type a name and address in the list." 'Description options' 'Information'
      return
    }
    $placed = $false
    foreach($row in $script:optLinkGrid.Rows){
      if($row.IsNewRow){ continue }
      $hasLab = ([string]$row.Cells['Label'].Value).Trim()
      $hasUrl = ([string]$row.Cells['Url'].Value).Trim()
      if(-not $hasLab -and -not $hasUrl){
        $row.Cells['Label'].Value = $parsed.label
        $row.Cells['Url'].Value = $parsed.url
        $placed = $true
        break
      }
    }
    if(-not $placed){ [void]$script:optLinkGrid.Rows.Add($parsed.label, $parsed.url) }
    $script:optChkLinks.Checked = $true
  })
  $addBtn.Add_Click({ [void]$script:optLinkGrid.Rows.Add('', '') })
  $y += 154

  function Add-OptionPair([string]$chkText,[bool]$checked,[string]$hintText,[string]$value,[bool]$multiline,$yRef){
    $y0 = $yRef.Value
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $chkText
    $chk.Left = 20; $chk.Top = $y0; $chk.AutoSize = $true
    $chk.Checked = $checked
    $panel.Controls.Add($chk)
    $y0 += 26
    if($hintText){
      $h = New-Object System.Windows.Forms.Label
      $h.Text = $hintText
      $h.Left = 40; $h.Top = $y0; $h.Width = 670; $h.Height = 22
      $panel.Controls.Add($h)
      $y0 += 22
    }
    $box = New-Object System.Windows.Forms.TextBox
    $box.Left = 40; $box.Top = $y0; $box.Width = 670
    $box.Text = ($value -replace "`n","`r`n")
    if($multiline){
      $box.Multiline = $true
      $box.ScrollBars = 'Vertical'
      $box.AcceptsReturn = $true
      $box.Height = 80
      $y0 += 90
    } else {
      $box.Height = 26
      $y0 += 36
    }
    $panel.Controls.Add($box)
    $yRef.Value = $y0
    return @{ chk=$chk; box=$box }
  }

  $yRef = [ref]$y
  $script:optChkLinks = $chkLinks
  $sub = Add-OptionPair 'Include a subscribe line' ([bool](ConvertTo-BoolFlag $saved.includeSubscribe $false)) 'Example: If this blessed you, please subscribe and share it with a friend.' ([string]$saved.subscribeText) $false $yRef
  $ts = Add-OptionPair 'Include timestamps / chapters' ([bool](ConvertTo-BoolFlag $saved.includeTimestamps $false)) 'One per line, such as 0:00 Intro' ([string]$saved.timestampsText) $true $yRef
  $crd = Add-OptionPair 'Include extra credits' ([bool](ConvertTo-BoolFlag $saved.includeCredits $false)) 'Co-writers, artwork, video help, or anyone else you want to thank.' ([string]$saved.creditsText) $true $yRef
  $lic = Add-OptionPair 'Include a licensing / permission note' ([bool](ConvertTo-BoolFlag $saved.includeLicensing $false)) 'Example: All rights reserved. Please ask before using this in your own project.' ([string]$saved.licensingText) $false $yRef
  $con = Add-OptionPair 'Include a contact / business line' ([bool](ConvertTo-BoolFlag $saved.includeContact $false)) 'Example: For bookings or collaborations, please contact me at...' ([string]$saved.contactText) $false $yRef

  $chkSheet = $null
  $emailBox = $null
  if(-not $isVideo){
    $y = $yRef.Value
    $chkSheet = New-Object System.Windows.Forms.CheckBox
    $chkSheet.Text = 'Include the sheet-music line'
    $chkSheet.Left = 20; $chkSheet.Top = $y; $chkSheet.AutoSize = $true
    $chkSheet.Checked = [bool](ConvertTo-BoolFlag $saved.includeSheetMusic $false)
    $panel.Controls.Add($chkSheet)
    $y += 26
    $emLbl = New-Object System.Windows.Forms.Label
    $emLbl.Text = 'Sheet-music email:'
    $emLbl.Left = 40; $emLbl.Top = ($y+3); $emLbl.AutoSize = $true
    $emailBox = New-Object System.Windows.Forms.TextBox
    $emailBox.Left = 190; $emailBox.Top = $y; $emailBox.Width = 520
    $emailBox.Text = ($email + '')
    $panel.Controls.AddRange(@($emLbl,$emailBox))
    $y += 40
    $yRef.Value = $y
  }

  $ex = Add-OptionPair 'Include anything else' ([bool](ConvertTo-BoolFlag $saved.includeExtra $false)) 'Extra notes or links. This block is placed just above the hashtags.' ([string]$saved.extraText) $true $yRef
  $pad = New-Object System.Windows.Forms.Label
  $pad.Left = 20; $pad.Top = ($yRef.Value + 8); $pad.Width = 10; $pad.Height = 20
  $panel.Controls.Add($pad)

  $script:optResult = $null
  $ok.Add_Click({
    $out = @{}
    $out = Merge-SettingFields $out $saved
    $out.includeLinks = [bool]$script:optChkLinks.Checked
    $out.links = @(Read-GridLinks $script:optLinkGrid)
    $out.includeSubscribe = [bool]$script:optSubChk.Checked
    $out.subscribeText = [string]$script:optSubBox.Text
    $out.includeTimestamps = [bool]$script:optTsChk.Checked
    $out.timestampsText = [string]$script:optTsBox.Text
    $out.includeCredits = [bool]$script:optCrdChk.Checked
    $out.creditsText = [string]$script:optCrdBox.Text
    $out.includeLicensing = [bool]$script:optLicChk.Checked
    $out.licensingText = [string]$script:optLicBox.Text
    $out.includeContact = [bool]$script:optConChk.Checked
    $out.contactText = [string]$script:optConBox.Text
    $out.includeExtra = [bool]$script:optExChk.Checked
    $out.extraText = [string]$script:optExBox.Text
    if($script:optSheetChk){
      $out.includeSheetMusic = [bool]$script:optSheetChk.Checked
    }
    if($script:optEmailBox){
      $out.email = $script:optEmailBox.Text.Trim()
    }
    $script:optResult = $out
    $form.DialogResult = 'OK'
    $form.Close()
  })
  $cancel.Add_Click({ $form.DialogResult = 'Cancel'; $form.Close() })
  $form.AcceptButton = $ok
  $form.CancelButton = $cancel
  $script:optSubChk = $sub.chk; $script:optSubBox = $sub.box
  $script:optTsChk = $ts.chk; $script:optTsBox = $ts.box
  $script:optCrdChk = $crd.chk; $script:optCrdBox = $crd.box
  $script:optLicChk = $lic.chk; $script:optLicBox = $lic.box
  $script:optConChk = $con.chk; $script:optConBox = $con.box
  $script:optExChk = $ex.chk; $script:optExBox = $ex.box
  $script:optSheetChk = $chkSheet
  $script:optEmailBox = $emailBox
  $form.Topmost = $true
  $btnPanel.PerformLayout()
  if($form.ShowDialog() -eq 'OK'){ return $script:optResult }
  return $null
}

function New-DescriptionJob([string]$title,[string]$lyrics,[string]$path,$opts,[string]$contentType,[bool]$includeLyrics){
  if(-not $opts){ $opts = Load-Settings }
  $artist = ([string]$opts.artist).Trim()
  if(-not $artist){ $artist = $defaultArtist }
  $credit = ([string]$opts.credit).Trim()
  if(-not $credit){ $credit = $(if($defaultCredit){ $defaultCredit } else { $artist }) }
  $email = ([string]$opts.email).Trim()
  $copy = ([string]$opts.copyright).Trim()
  if(-not $copy){ $copy = $(if($defaultCopyright){ $defaultCopyright } else { $artist }) }
  $playlist = ([string]$opts.playlist)
  if(-not $playlist){ $playlist = 'Auto-pick' }
  return [pscustomobject]@{
    Title = $title
    Lyrics = $lyrics
    Artist = $artist
    Credit = $credit
    Email = $email
    Copyright = $copy
    Playlist = $playlist
    Path = $path
    ContentType = (ConvertTo-ContentType $contentType)
    IncludeLyrics = [bool]$includeLyrics
    IncludeSheetMusic = [bool](ConvertTo-BoolFlag $opts.includeSheetMusic $false)
    IncludeLinks = [bool](ConvertTo-BoolFlag $opts.includeLinks $false)
    Links = @(ConvertTo-LinkList $opts.links)
    IncludeSubscribe = [bool](ConvertTo-BoolFlag $opts.includeSubscribe $false)
    SubscribeText = [string]$opts.subscribeText
    IncludeTimestamps = [bool](ConvertTo-BoolFlag $opts.includeTimestamps $false)
    TimestampsText = [string]$opts.timestampsText
    IncludeCredits = [bool](ConvertTo-BoolFlag $opts.includeCredits $false)
    CreditsText = [string]$opts.creditsText
    IncludeLicensing = [bool](ConvertTo-BoolFlag $opts.includeLicensing $false)
    LicensingText = [string]$opts.licensingText
    IncludeContact = [bool](ConvertTo-BoolFlag $opts.includeContact $false)
    ContactText = [string]$opts.contactText
    IncludeExtra = [bool](ConvertTo-BoolFlag $opts.includeExtra $false)
    ExtraText = [string]$opts.extraText
  }
}

function Ask-DescriptionForm([string]$preTitle,[string]$preLyrics,[string]$sourcePath,[string]$preType=''){
  $saved = Load-Settings
  if($preType){ $saved.contentType = ConvertTo-ContentType $preType }
  $script:currentOpts = $saved
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

  $lType = New-Object System.Windows.Forms.Label
  $lType.Text = 'Type:'; $lType.Left = 20; $lType.Top = ($y+3); $lType.AutoSize = $true
  $typeSong = New-Object System.Windows.Forms.RadioButton
  $typeSong.Text = 'Song'; $typeSong.Left = 120; $typeSong.Top = ($y+1); $typeSong.AutoSize = $true
  $typeVideo = New-Object System.Windows.Forms.RadioButton
  $typeVideo.Text = 'Video'; $typeVideo.Left = 200; $typeVideo.Top = ($y+1); $typeVideo.AutoSize = $true
  if((ConvertTo-ContentType $saved.contentType) -eq 'Video'){ $typeVideo.Checked = $true } else { $typeSong.Checked = $true }
  $optsBtn = New-Object System.Windows.Forms.Button
  $optsBtn.Text = 'Options...'
  $optsBtn.Left = 560; $optsBtn.Top = ($y-2); $optsBtn.Width = 160; $optsBtn.Height = 28
  $form.Controls.AddRange(@($lType,$typeSong,$typeVideo,$optsBtn))
  $y += 36

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

  $lIncl = New-Object System.Windows.Forms.Label
  $lIncl.Text = 'Include lyrics:'; $lIncl.Left = 20; $lIncl.Top = ($y+3); $lIncl.AutoSize = $true
  $inclYes = New-Object System.Windows.Forms.RadioButton
  $inclYes.Text = 'Yes'; $inclYes.Left = 150; $inclYes.Top = ($y+1); $inclYes.AutoSize = $true
  $inclNo = New-Object System.Windows.Forms.RadioButton
  $inclNo.Text = 'No'; $inclNo.Left = 220; $inclNo.Top = ($y+1); $inclNo.AutoSize = $true
  if(ConvertTo-BoolFlag $saved.includeLyrics $true){ $inclYes.Checked = $true } else { $inclNo.Checked = $true }
  $form.Controls.AddRange(@($lIncl,$inclYes,$inclNo))
  $y += 32

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
  $script:descPlayLabel = $lPlay
  $script:descArtistBox = $artistBox
  $script:descCreditBox = $creditBox
  $script:descEmailBox = $emailBox
  $script:descCopyBox = $copyBox
  $script:descCreditMain = $creditMain
  $script:descCred2 = $lCred2
  $script:descBtn = $btn
  $script:descTypeSong = $typeSong
  $script:descTypeVideo = $typeVideo
  $script:descInclLyrLabel = $lIncl
  $script:descInclLyrYes = $inclYes
  $script:descInclLyrNo = $inclNo
  $script:descLyrLabel = $lLyr
  $script:descTitleLabel = $lTitle
  $script:updateDescMode = {
    $isSong = [bool]$script:descTypeSong.Checked
    if($isSong){ $script:descTitleLabel.Text = 'Song title:' } else { $script:descTitleLabel.Text = 'Video title:' }
    $script:descPlayBox.Visible = $isSong
    $script:descPlayLabel.Visible = $isSong
    $script:descInclLyrLabel.Visible = $isSong
    $script:descInclLyrYes.Visible = $isSong
    $script:descInclLyrNo.Visible = $isSong
    if($Edition -ne 'Share'){
      $script:descCreditMain.Visible = $isSong
      $script:descCred2.Visible = $isSong
    }
    if($isSong){
      $script:descLyrLabel.Text = 'Lyrics (section tags like [Verse 1] and [Chorus] are kept):'
    } else {
      $script:descLyrLabel.Text = 'Transcript, script, or notes (a title plus a few notes is enough):'
    }
  }
  $typeSong.Add_CheckedChanged({ & $script:updateDescMode })
  $typeVideo.Add_CheckedChanged({ & $script:updateDescMode })
  & $script:updateDescMode
  $form.Add_Resize({
    $script:descLyrBox.Width = ($form.ClientSize.Width - 40)
    $script:descLyrBox.Height = ($form.ClientSize.Height - $script:descLyrBox.Top - $script:descBtn.Height - 20)
  })
  $form.Height = 760

  $optsBtn.Add_Click({
    $curEmail = ''
    if($script:descEmailBox){ $curEmail = $script:descEmailBox.Text }
    elseif($script:currentOpts.email){ $curEmail = [string]$script:currentOpts.email }
    else { $curEmail = $defaultEmail }
    $r = Ask-OptionsForm $script:currentOpts $curEmail ([bool]$script:descTypeVideo.Checked)
    if($r){
      $script:currentOpts = $r
      if($script:descEmailBox -and $null -ne $r.email){ $script:descEmailBox.Text = [string]$r.email }
      Save-Settings $r
    }
  })

  $browse.Add_Click({
    $mode = $(if($script:descTypeVideo.Checked){ 'Video' } else { 'Song' })
    $p = Ask-LyricsFile $mode
    if(-not $p){ return }
    $ext = [IO.Path]::GetExtension($p).ToLower()
    if($ext -eq '.mp3' -and $script:descTypeVideo.Checked){ $script:descTypeSong.Checked = $true }
    $song = Read-SongSource $p
    if(-not $song){ Show-Note "Please choose an MP3 or a .txt file." 'Make YouTube Description' 'Warning'; return }
    $script:chosenPath = $p
    if($song.Title){ $script:descTitleBox.Text = $song.Title }
    $script:descLyrBox.Text = ($song.Lyrics -replace "`n","`r`n")
    if($script:descTypeSong.Checked -and -not $song.Lyrics){
      Show-Note "I couldn't find lyrics inside that MP3. You can paste them here, or browse for a lyrics .txt file." 'No lyrics in this MP3' 'Information'
    }
  })

  $result = $null
  $btn.Add_Click({
    if(-not $script:descTitleBox.Text.Trim()){ Show-Note "Please enter the title." 'Make YouTube Description' 'Warning'; return }
    $isSong = [bool]$script:descTypeSong.Checked
    if($isSong -and -not $script:descLyrBox.Text.Trim()){ Show-Note "Please paste the lyrics, or browse for an MP3 / lyrics file that has them." 'Make YouTube Description' 'Warning'; return }
    $artist = $defaultArtist
    $credit = $defaultCredit
    $email = $defaultEmail
    $copy = $defaultCopyright
    if($script:currentOpts.email){ $email = [string]$script:currentOpts.email }
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
    $opts = $script:currentOpts
    if(-not $opts){ $opts = Load-Settings }
    $opts = Merge-SettingFields @{} $opts
    $opts.artist = $artist
    $opts.credit = $credit
    $opts.email = $email
    $opts.copyright = $copy
    $opts.playlist = $script:descPlayBox.Text
    $opts.contentType = $(if($isSong){ 'Song' } else { 'Video' })
    $opts.includeLyrics = [bool]$script:descInclLyrYes.Checked
    Save-Settings $opts
    $script:currentOpts = $opts
    $script:formResult = New-DescriptionJob ($script:descTitleBox.Text.Trim()) (Clean-Lyrics $script:descLyrBox.Text) $script:chosenPath $opts $opts.contentType ([bool]$opts.includeLyrics)
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

function Invoke-GeminiMeta([string]$title,[string]$lyrics,[string]$artist,[bool]$includeLyrics=$true,[string]$contentType='Song'){
  $key = Get-GeminiKey
  if(-not $key){ return $null }
  $artistName = $artist
  if(-not $artistName){ $artistName = 'the artist' }
  $isVideo = ((ConvertTo-ContentType $contentType) -eq 'Video')
  if($isVideo){
    $rules = @"
You write metadata for a YouTube description of a video by $artistName.
Read the title and any transcript, script, or notes carefully. Return ONLY valid JSON, with no markdown and no extra text, using exactly these keys:
{
  "subtitle": "A short theme phrase such as A Plain Talk About Everyday Faith",
  "pullQuote": "",
  "blurb": "3 to 5 clear sentences summarizing what the video is about, plus an optional short closing line",
  "scripture": "KJV verse in this exact shape: \"quote\" (Book Chapter:Verse)  OR an empty string",
  "playlist": "",
  "hashtags": "5 to 7 space-separated hashtags"
}

Style rules:
- The subtitle should sound like: "A Quiet Conversation About Hope" or "A Walk Through the News With Discernment". Do not repeat the video title in the subtitle. Do not include the artist or channel name in the subtitle.
- Leave pullQuote as an empty string. Do not quote or copy lines from the transcript, script, or notes in any field.
- The blurb is warm, respectful, specific, and clear. Use correct grammar. Write it the way the creator would introduce the video, not like a review or a sermon. Summarize what the video covers. You may start from a real moment or idea in the notes, described in your own wording, not in the source's wording. Do not invent facts that are not in the title or notes. Do not talk down to the listener. Never use the word "child". Never mention AI, Suno, or how the video was made. Never use graphic violence language or the word "suicide". Avoid occult-sounding wording. If the video is about faith in Jesus or Scripture, let that show naturally and sincerely. If it is a Watchman / discernment / signs-of-the-times video, write it in that lens. If it is tender or everyday, keep it tender and everyday. A short, human closing line is welcome when it fits, but do not force one.
- Scripture: include one only when the video is clearly faith, worship, prayer, or watchman, AND you are sure of a well-known, accurate King James (KJV) verse that truly fits. Prefer a short verse. Do not choose a verse that uses the words "child" or "children". If you are not sure of the exact wording or reference, or the best-known fit uses those words, return an empty string. Never invent a verse. Never use a modern paraphrase.
- Leave playlist as an empty string.
- Hashtags: 5 to 7 tags, each starting with #, no commas. Start with a hashtag made from the video title. End with $(Get-ArtistTag $artistName). Include a theme tag that fits the video. If you used a scripture, a short book tag like #John1 is welcome. Do not use music-only tags such as #Lyrics or #OriginalSong unless the video is clearly about a song.
"@
    $prompt = $rules + "`n`nVIDEO TITLE:`n" + $title + "`n`nTRANSCRIPT, SCRIPT, OR NOTES:`n" + $(if($lyrics){ $lyrics } else { '(none given; write from the title only)' })
  } else {
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
    if(-not $includeLyrics){
      $rules = $rules + @"

The finished YouTube description will NOT include the lyrics and will NOT include a lyric pull-quote. You may still read the lyrics to understand the song.
- Leave pullQuote as an empty string.
- In the blurb, do not quote, copy, or closely repeat lines or phrases from the lyrics. Paraphrase the song's meaning and feeling in your own words. You may still start from a real image or moment, described in your own wording, not in the song's wording.
"@
    }
    $prompt = $rules + "`n`nSONG TITLE:`n" + $title + "`n`nLYRICS:`n" + $lyrics
  }
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

function Build-Description($job,$meta){
  $title = $job.Title.Trim()
  $artist = $job.Artist.Trim()
  if(-not $artist){ $artist = $defaultArtist }
  $credit = $job.Credit.Trim()
  if(-not $credit){ $credit = $artist }
  $email = ($job.Email + '').Trim()
  $copy = $job.Copyright.Trim()
  if(-not $copy){ $copy = $artist }
  $isVideo = ((ConvertTo-ContentType $job.ContentType) -eq 'Video')
  $includeLyrics = $true
  if($null -ne $job.PSObject.Properties['IncludeLyrics'] -and $null -ne $job.IncludeLyrics){
    $includeLyrics = [bool]$job.IncludeLyrics
  }
  if($isVideo){ $includeLyrics = $false }
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
  if(-not $isVideo -and $includeLyrics -and $quote){
    [void]$sb.Append('"' + $quote + '"'); [void]$sb.Append($nl); [void]$sb.Append($nl)
  }
  [void]$sb.Append($blurb); [void]$sb.Append($nl); [void]$sb.Append($nl)
  if(-not $isVideo){
    [void]$sb.Append("Written and performed by $credit"); [void]$sb.Append($nl)
    $sheetOn = $true
    if($null -ne $job.PSObject.Properties['IncludeSheetMusic'] -and $null -ne $job.IncludeSheetMusic){
      $sheetOn = [bool]$job.IncludeSheetMusic
    } elseif(-not $email){ $sheetOn = $false }
    if($sheetOn -and $email){ [void]$sb.Append("For sheet music, please contact me at $email"); [void]$sb.Append($nl) }
    [void]$sb.Append($nl)
  }
  if([bool]$job.IncludeLinks){
    Add-DescriptionBlock $sb (Format-LinkLines $job.Links) $nl
  }
  if([bool]$job.IncludeSubscribe){
    Add-DescriptionBlock $sb $job.SubscribeText $nl
  }
  if([bool]$job.IncludeTimestamps){
    Add-DescriptionBlock $sb $job.TimestampsText $nl
  }
  if(-not $isVideo -and $includeLyrics){
    [void]$sb.Append('LYRICS'); [void]$sb.Append($nl); [void]$sb.Append($nl)
    [void]$sb.Append($lyrics); [void]$sb.Append($nl); [void]$sb.Append($nl)
  }
  if($scripture){ [void]$sb.Append($scripture); [void]$sb.Append($nl); [void]$sb.Append($nl) }
  if(-not $isVideo){
    [void]$sb.Append("This song belongs in the $playlist playlist."); [void]$sb.Append($nl); [void]$sb.Append($nl)
  }
  if([bool]$job.IncludeCredits){
    Add-DescriptionBlock $sb $job.CreditsText $nl
  }
  if([bool]$job.IncludeLicensing){
    Add-DescriptionBlock $sb $job.LicensingText $nl
  }
  if([bool]$job.IncludeContact){
    Add-DescriptionBlock $sb $job.ContactText $nl
  }
  $year = Get-Date -Format 'yyyy'
  [void]$sb.Append(("© {0} {1}. All rights reserved." -f $year,$copy)); [void]$sb.Append($nl); [void]$sb.Append($nl)
  if([bool]$job.IncludeExtra){
    Add-DescriptionBlock $sb $job.ExtraText $nl
  }
  [void]$sb.Append($tags); [void]$sb.Append($nl)
  return $sb.ToString()
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

function Save-Description([string]$text,[string]$title,[string]$outDir,[string]$limitExtra){
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
    $extra = $limitExtra
    if(-not $extra){ $extra = 'The lyrics were not cut.' }
    $note = "*** NOTE (delete this line before pasting): This description is $charCount characters, which is over YouTube's 5,000-character limit. $extra ***`r`n`r`n"
    $toWrite = $note + $text
    Write-Host "Warning: $charCount characters (YouTube's limit is 5,000). $extra"
  } else {
    Write-Host "Length: $charCount characters (YouTube's limit is 5,000)."
  }
  $utf8 = New-Object System.Text.UTF8Encoding $true
  [IO.File]::WriteAllText($dest, $toWrite, $utf8)
  return [pscustomobject]@{ Path=$dest; Length=$charCount; OverLimit=($charCount -gt 5000) }
}

function Make-Description($job){
  if(-not $job -or -not $job.Title){ return }
  $isVideo = ((ConvertTo-ContentType $job.ContentType) -eq 'Video')
  if(-not $isVideo -and -not $job.Lyrics){ return }
  if($extractOnly){
    Write-Host "EXTRACT ONLY"
    Write-Host ("TYPE: " + (ConvertTo-ContentType $job.ContentType))
    Write-Host ("TITLE: " + $job.Title)
    Write-Host ("LYRICS_LINES: " + @(($job.Lyrics + '') -split "`n").Count)
    Write-Host ("LYRICS_CHARS: " + ($job.Lyrics + '').Length)
    $preview = (($job.Lyrics + '') -split "`n" | Select-Object -First 8) -join "`n"
    Write-Host "FIRST_LINES:"
    Write-Host $preview
    $last = (($job.Lyrics + '') -split "`n" | Select-Object -Last 5) -join "`n"
    Write-Host "LAST_LINES:"
    Write-Host $last
    return
  }
  $includeLyrics = $true
  if($null -ne $job.PSObject.Properties['IncludeLyrics'] -and $null -ne $job.IncludeLyrics){
    $includeLyrics = [bool]$job.IncludeLyrics
  }
  if($isVideo){ $includeLyrics = $false }
  $meta = Invoke-GeminiMeta $job.Title $job.Lyrics $job.Artist $includeLyrics $job.ContentType
  if(-not $meta){
    Show-Note "Gemini is too busy right now, or the reply wasn't usable. Try again in a few minutes." 'Make YouTube Description' 'Warning'
    return
  }
  $text = Build-Description $job $meta
  $limitExtra = ''
  if($includeLyrics){ $limitExtra = 'The lyrics were not cut.' }
  $saved = Save-Description $text $job.Title $defaultDescDir $limitExtra
  $copied = $false
  if(-not $noClip){
    try { Set-Clipboard -Value $text; $copied = $true } catch { Write-Host "Couldn't copy to the clipboard, but the file was saved." }
  }
  if($copied){ Write-Host "Description saved: $($saved.Path) (also copied - just paste it into YouTube)" }
  else { Write-Host "Description saved: $($saved.Path)" }
  if($saved.OverLimit){
    $warn = "The description was saved, but it is $($saved.Length) characters. YouTube's limit is 5,000, so you'll need to trim it a little before pasting."
    if($includeLyrics){ $warn = $warn + ' The lyrics were not cut.' }
    Show-Note $warn "Over YouTube's 5,000-character limit" 'Warning'
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
    $saved = Load-Settings
    $contentType = ConvertTo-ContentType $saved.contentType
    if($ext -eq '.mp3'){ $contentType = 'Song' }
    if($ext -eq '.mp3' -or $ext -eq '.txt'){
      # ok
    } else {
      Write-Host "Please drop an MP3 song or a .txt file: $f"
      continue
    }
    $song = Read-SongSource $f
    if($noUi){
      if($contentType -eq 'Song' -and -not $song.Lyrics){ Write-Host "No lyrics found in $f"; continue }
      $includeLyrics = [bool](ConvertTo-BoolFlag $saved.includeLyrics $true)
      if($contentType -eq 'Video'){ $includeLyrics = $false }
      $job = New-DescriptionJob $song.Title $song.Lyrics $f $saved $contentType $includeLyrics
      Make-Description $job
      continue
    }
    $preLyrics = $song.Lyrics
    if($contentType -eq 'Song' -and -not $preLyrics -and $ext -eq '.mp3'){
      Show-Note "I couldn't find lyrics inside that MP3. You can paste them in the next window, or browse for a lyrics .txt file." 'No lyrics in this MP3' 'Information'
    }
    # Remember the type from this drop so the form opens in the right mode
    $saved.contentType = $contentType
    $script:currentOpts = $saved
    $job = Ask-DescriptionForm $song.Title $preLyrics $f $contentType
    if($job){ Make-Description $job }
  } catch {
    $msg = $_.Exception.Message
    Write-Host "Problem with $f : $msg"
    if(-not $noUi){ Show-Note "There was a problem with that file:`n$msg" 'Make YouTube Description' 'Error' }
  }
}
