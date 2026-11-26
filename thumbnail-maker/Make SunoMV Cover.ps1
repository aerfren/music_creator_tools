# SunoMV Cover and Thumbnail Maker
# Drop a PICTURE on the icon (or the bat file) -> makes "<name> - cover square.png" next to your picture, plus YouTube and Short thumbnails in your Music\thumbnails folder (whole picture in the middle band, blurred fill).
# Thumbnails: one options window for title, artist name, placement, style, and font. Balanced line sizes are the default (Big Accent Line is optional).
# Type a font name in the Font box to jump to it. Your installed fonts, including any you added yourself, are listed.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $env:USERPROFILE 'Music'
$defaultArtist = ''
$settingsPath = Join-Path $here 'Make SunoMV Cover.settings.json'

function Make-Cover($f){
  $src=Trim-Bars ([System.Drawing.Image]::FromFile($f))
  $S=1024; $bandH=576
  $out=New-Object System.Drawing.Bitmap $S,$S
  $g=[System.Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode='HighQualityBicubic'
  $tiny=New-Object System.Drawing.Bitmap 24,24
  $tg=[System.Drawing.Graphics]::FromImage($tiny); $tg.InterpolationMode='HighQualityBicubic'; $tg.DrawImage($src,0,0,24,24); $tg.Dispose()
  $g.DrawImage($tiny,-40,-40,$S+80,$S+80)
  $dark=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(110,0,0,0)); $g.FillRectangle($dark,0,0,$S,$S)
  $scale=[Math]::Min($S/$src.Width,$bandH/$src.Height)
  $w=[int]($src.Width*$scale); $h=[int]($src.Height*$scale)
  $g.DrawImage($src,[int](($S-$w)/2),[int](($S-$h)/2),$w,$h)
  $g.Dispose()
  $name=[IO.Path]::GetFileNameWithoutExtension($f)
  $dest=Join-Path ([IO.Path]::GetDirectoryName($f)) ($name+" - cover square.png")
  $out.Save($dest,[System.Drawing.Imaging.ImageFormat]::Png)
  $out.Dispose(); $src.Dispose()
  Write-Host "Cover made: $dest"
}

function Is-SymbolFont($name){
  return [bool]($name -match '(?i)Emoji|Icon|Icons|MDL2|Awesome|Math|Webdings|Wingdings|Marlett|^Symbol$|OpenSymbol|NotDef|MT Extra|Segoe Fluent|Segoe UI Historic|Segoe UI Symbol')
}

function Ensure-PrivateFonts{
  if($script:pfc){ return }
  $script:pfc=New-Object System.Drawing.Text.PrivateFontCollection
  $script:privateByName=@{}
  $oswald=Join-Path $here 'OswaldBold.ttf'
  if(Test-Path $oswald){
    try{ $script:pfc.AddFontFile($oswald) } catch {}
  }
  $installedNames=@([System.Drawing.Text.InstalledFontCollection]::new().Families | ForEach-Object { $_.Name })
  $userDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
  if(Test-Path $userDir){
    Get-ChildItem (Join-Path $userDir '*') -Include *.ttf,*.otf,*.ttc -ErrorAction SilentlyContinue | ForEach-Object {
      try{
        $probe=New-Object System.Drawing.Text.PrivateFontCollection
        $probe.AddFontFile($_.FullName)
        $n=$probe.Families[0].Name
        if($installedNames -notcontains $n){ $script:pfc.AddFontFile($_.FullName) }
      } catch {}
    }
  }
  foreach($fam in $script:pfc.Families){
    if(-not $script:privateByName.ContainsKey($fam.Name)){ $script:privateByName[$fam.Name]=$fam }
  }
}

function Get-PreferredStyle($familyName){
  # Single-cut / already-heavy / decorative faces stay Regular so they are not faux-bolded
  if($familyName -match '(?i)Bold|Black|Semibold|SemiBold|Semi-Bold|Heavy|ExtraBold|Ultra|Fatface|Light|Thin|Medium|Semilight|Italic|Condensed|Narrow|Kingthings|Oswald|Impact|Alatsi|Sail|Carrington|Chantelli|Cloister|Florante|Gabriola|Ink Free|Segoe Print|Segoe Script|Calligraph'){
    return 0
  }
  return 1
}

function Get-ThumbFontChoices{
  Ensure-PrivateFonts
  $byName=@{}
  foreach($fam in [System.Drawing.Text.InstalledFontCollection]::new().Families){
    if(-not (Is-SymbolFont $fam.Name)){ $byName[$fam.Name]=@{ Family=$fam.Name; Private=$false } }
  }
  foreach($name in @($script:privateByName.Keys)){
    if(-not (Is-SymbolFont $name) -and -not $byName.ContainsKey($name) -and $name -notlike 'Oswald*'){
      $byName[$name]=@{ Family=$name; Private=$true }
    }
  }
  $choices=[System.Collections.Generic.List[object]]::new()
  $choices.Add([pscustomobject]@{ Name='Oswald Bold (default)'; Family='Oswald ThumbBold'; Style=0; Private=$true; Separator=$false })
  if($byName.ContainsKey('Kingthings Foundation')){
    $kf=$byName['Kingthings Foundation']
    $choices.Add([pscustomobject]@{ Name='Kingthings Foundation'; Family='Kingthings Foundation'; Style=0; Private=[bool]$kf.Private; Separator=$false })
  }
  $choices.Add([pscustomobject]@{ Name='---------- All fonts ----------'; Family=''; Style=0; Private=$false; Separator=$true })
  foreach($name in ($byName.Keys | Sort-Object)){
    $info=$byName[$name]
    $choices.Add([pscustomobject]@{ Name=$name; Family=$name; Style=(Get-PreferredStyle $name); Private=[bool]$info.Private; Separator=$false })
  }
  return $choices.ToArray()
}

function Normalize-FontChoice($text){
  $t=($text+'').Trim()
  if(-not $t -or $t -match 'All fonts'){ return 'Oswald Bold (default)' }
  if($t -match '(?i)^oswald'){ return 'Oswald Bold (default)' }
  if($t -match '(?i)kingsthings|kingsthing(\s+foundation)?$|^kingthings$'){ return 'Kingthings Foundation' }
  return $t
}

function Resolve-ThumbFont($choiceName){
  Ensure-PrivateFonts
  $choices=Get-ThumbFontChoices
  $name=Normalize-FontChoice $choiceName
  $item=$choices | Where-Object { -not $_.Separator -and ($_.Name -eq $name) } | Select-Object -First 1
  if(-not $item){ $item=$choices | Where-Object { -not $_.Separator -and ($_.Family -eq $name -or $_.Name -eq $choiceName) } | Select-Object -First 1 }
  if(-not $item){ $item=$choices | Where-Object { -not $_.Separator -and ($_.Name -like "$name*" -or $_.Family -like "$name*") } | Select-Object -First 1 }
  if(-not $item){ $item=$choices[0] }
  $script:fontStyle=[int]$item.Style
  if($item.Private -or $item.Family -like 'Oswald*' -or $item.Name -like 'Oswald*'){
    $script:fontStyle=0
    $fam=$script:privateByName[$item.Family]
    if(-not $fam){ $fam=$script:privateByName['Oswald ThumbBold'] }
    if(-not $fam){ $fam=$script:pfc.Families | Where-Object { $_.Name -like 'Oswald*' } | Select-Object -First 1 }
    return $fam
  }
  return (New-Object System.Drawing.FontFamily $item.Family)
}

function Load-ThumbSettings{
  $d=@{ pos='M'; place='B'; side='C'; style='Balanced'; font='Oswald Bold (default)'; artist=$defaultArtist }
  if(Test-Path $settingsPath){
    try{
      $j=Get-Content $settingsPath -Raw | ConvertFrom-Json
      foreach($k in 'pos','place','side','style','font','artist'){ if($null -ne $j.$k){ $d[$k]=[string]$j.$k } }
    } catch {}
  }
  return $d
}

function Save-ThumbSettings($s){
  @{ pos=$s.pos; place=$s.place; side=$s.side; style=$s.style; font=$s.font; artist=$s.artist } | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
}

function Add-RadioRow($parent,$label,$y,$options,$defaultKey){
  $lbl=New-Object System.Windows.Forms.Label; $lbl.Text=$label; $lbl.Left=20; $lbl.Top=($y+3); $lbl.AutoSize=$true
  $parent.Controls.Add($lbl)
  $panel=New-Object System.Windows.Forms.Panel
  $panel.Left=160; $panel.Top=$y; $panel.Width=380; $panel.Height=28
  $radios=@{}
  $x=0
  foreach($opt in $options){
    $r=New-Object System.Windows.Forms.RadioButton
    $r.Text=$opt.Text; $r.Left=$x; $r.Top=2; $r.AutoSize=$true; $r.Checked=($opt.Key -eq $defaultKey)
    $panel.Controls.Add($r)
    $radios[$opt.Key]=$r
    $x += [Math]::Max(90, ($opt.Text.Length * 9 + 36))
  }
  $parent.Controls.Add($panel)
  return $radios
}

function Selected-Key($radios,$fallback){
  foreach($k in $radios.Keys){ if($radios[$k].Checked){ return $k } }
  return $fallback
}

function Ask-ThumbOptions($guess){
  $saved=Load-ThumbSettings
  $form=New-Object System.Windows.Forms.Form
  $form.Text='Thumbnail maker'
  $form.Width=560; $form.Height=540
  $form.StartPosition='CenterScreen'
  $form.FormBorderStyle='FixedDialog'
  $form.MaximizeBox=$false; $form.MinimizeBox=$false
  $form.Font=New-Object System.Drawing.Font('Segoe UI',10)
  $form.Topmost=$true

  $y=16
  $lbl=New-Object System.Windows.Forms.Label; $lbl.Text='Song title for the thumbnails:'; $lbl.Left=20; $lbl.Top=$y; $lbl.AutoSize=$true
  $form.Controls.Add($lbl)
  $y=40
  $titleBox=New-Object System.Windows.Forms.TextBox
  $titleBox.Left=20; $titleBox.Top=$y; $titleBox.Width=504; $titleBox.Text=$guess
  $form.Controls.Add($titleBox)
  $y=70
  $hint=New-Object System.Windows.Forms.Label
  $hint.Text='Leave blank to skip. To pick your own line breaks, type a slash:  SMOKE AND / MIRRORS'
  $hint.Left=20; $hint.Top=$y; $hint.Width=504; $hint.Height=20
  $hint.ForeColor=[System.Drawing.Color]::FromArgb(80,80,80)
  $form.Controls.Add($hint)

  $y=100
  $l2=New-Object System.Windows.Forms.Label; $l2.Text='For the Short: where is the person or main thing?'; $l2.Left=20; $l2.Top=$y; $l2.Width=504; $l2.Height=22
  $form.Controls.Add($l2)
  $posDefault= if($saved.pos -in 'L','R'){ $saved.pos } else { 'M' }
  $posRadios=Add-RadioRow $form '' 122 @([pscustomobject]@{Key='L';Text='Left'},[pscustomobject]@{Key='M';Text='Middle'},[pscustomobject]@{Key='R';Text='Right'}) $posDefault
  # nudge this row's radios left, since there is no side label
  $posPanel=$posRadios['L'].Parent; $posPanel.Left=20

  $placeDefault= if($saved.place -eq 'T'){'T'} else {'B'}
  $placeRadios=Add-RadioRow $form 'Title placement:' 158 @([pscustomobject]@{Key='B';Text='Bottom'},[pscustomobject]@{Key='T';Text='Top'}) $placeDefault

  $sideDefault= if($saved.side -in 'L','R'){ $saved.side } else { 'C' }
  $sideRadios=Add-RadioRow $form 'Title side:' 194 @([pscustomobject]@{Key='L';Text='Left'},[pscustomobject]@{Key='C';Text='Center'},[pscustomobject]@{Key='R';Text='Right'}) $sideDefault

  $styleDefault= if($saved.style -eq 'Accent'){'Accent'} else {'Balanced'}
  $styleRadios=Add-RadioRow $form 'Title style:' 230 @([pscustomobject]@{Key='Balanced';Text='Balanced'},[pscustomobject]@{Key='Accent';Text='Big Accent Line'}) $styleDefault
  $y=258
  $styleHint=New-Object System.Windows.Forms.Label
  $styleHint.Text='Balanced keeps every title line the same size. Big Accent Line makes the last word larger, like before.'
  $styleHint.Left=20; $styleHint.Top=$y; $styleHint.Width=504; $styleHint.Height=20
  $styleHint.ForeColor=[System.Drawing.Color]::FromArgb(80,80,80)
  $form.Controls.Add($styleHint)

  $y=286
  $lArt=New-Object System.Windows.Forms.Label; $lArt.Text='Artist name:'; $lArt.Left=20; $lArt.Top=($y+3); $lArt.AutoSize=$true
  $form.Controls.Add($lArt)
  $artistBox=New-Object System.Windows.Forms.TextBox
  $artistBox.Left=160; $artistBox.Top=$y; $artistBox.Width=364; $artistBox.Text=$saved.artist
  $form.Controls.Add($artistBox)

  $y=322
  $l6=New-Object System.Windows.Forms.Label; $l6.Text='Font:'; $l6.Left=20; $l6.Top=($y+3); $l6.AutoSize=$true
  $form.Controls.Add($l6)
  $fontBox=New-Object System.Windows.Forms.ComboBox
  $fontBox.Left=160; $fontBox.Top=$y; $fontBox.Width=364
  $fontBox.DropDownStyle='DropDown'
  $fontBox.AutoCompleteMode='SuggestAppend'
  $fontBox.AutoCompleteSource='ListItems'
  $fontBox.DropDownHeight=360
  $fontChoices=Get-ThumbFontChoices
  foreach($c in $fontChoices){ [void]$fontBox.Items.Add($c.Name) }
  $want=Normalize-FontChoice $saved.font
  $idx=$fontBox.Items.IndexOf($want)
  if($idx -lt 0){ $idx=0 }
  $fontBox.SelectedIndex=$idx
  $fontBox.Add_SelectedIndexChanged({
    if($fontBox.SelectedItem -and ([string]$fontBox.SelectedItem -match 'All fonts')){
      $fontBox.SelectedIndex=0
    }
  })
  $form.Controls.Add($fontBox)
  $fontHint=New-Object System.Windows.Forms.Label
  $fontHint.Text='Type a name to find it. Kingthings Foundation and all your other fonts are in the list.'
  $fontHint.Left=160; $fontHint.Top=($y+28); $fontHint.Width=364; $fontHint.Height=36
  $fontHint.ForeColor=[System.Drawing.Color]::FromArgb(80,80,80)
  $form.Controls.Add($fontHint)

  $ok=New-Object System.Windows.Forms.Button
  $ok.Text='Make thumbnails'; $ok.Width=160; $ok.Height=36; $ok.Left=160; $ok.Top=410
  $ok.DialogResult=[System.Windows.Forms.DialogResult]::OK
  $skip=New-Object System.Windows.Forms.Button
  $skip.Text='Skip'; $skip.Width=90; $skip.Height=36; $skip.Left=334; $skip.Top=410
  $skip.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
  $form.Controls.Add($ok); $form.Controls.Add($skip)
  $form.AcceptButton=$ok; $form.CancelButton=$skip

  $dr=$form.ShowDialog()
  if($dr -ne [System.Windows.Forms.DialogResult]::OK){ return $null }
  $pos=Selected-Key $posRadios 'M'
  $place=Selected-Key $placeRadios 'B'
  $side=Selected-Key $sideRadios 'C'
  $style=Selected-Key $styleRadios 'Balanced'
  $font=Normalize-FontChoice $(if($fontBox.SelectedItem -and ([string]$fontBox.SelectedItem -notmatch 'All fonts')){ [string]$fontBox.SelectedItem } else { $fontBox.Text })
  $artist=($artistBox.Text+'').Trim()
  $opts=@{ title=$titleBox.Text; pos=$pos; place=$place; side=$side; style=$style; font=$font; artist=$artist }
  Save-ThumbSettings $opts
  return $opts
}

function Add-Text($g,$fam,$text,$size,$y,$color,$W){
  $sf=New-Object System.Drawing.StringFormat
  $path=New-Object System.Drawing.Drawing2D.GraphicsPath
  $style=0; if($script:fontStyle){ $style=[int]$script:fontStyle }
  $path.AddString($text,$fam,$style,[single]$size,(New-Object System.Drawing.PointF 0,0),$sf)
  $b=$path.GetBounds()
  $side=$script:titleSide; if(-not $side){ $side='C' }
  $maxW= if($side -eq 'C'){ $W*0.92 } else { $W*0.55 }
  if($b.Width -gt $maxW){ $path.Dispose(); return (Add-Text $g $fam $text ($size*($maxW*0.98)/$b.Width) $y $color $W) }
  $mg=[int]($W*0.04)
  $x= switch($side){ 'L' { $mg-$b.X } 'R' { $W-$mg-$b.Width-$b.X } default { (($W-$b.Width)/2)-$b.X } }
  $m=New-Object System.Drawing.Drawing2D.Matrix; $m.Translate($x, $y-$b.Y); $path.Transform($m)
  $sh=$path.Clone(); $m2=New-Object System.Drawing.Drawing2D.Matrix; $m2.Translate(7,9); $sh.Transform($m2)
  $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150,0,0,0))),$sh)
  $pen=New-Object System.Drawing.Pen ([System.Drawing.Color]::Black),([Math]::Max(6,$size/11)); $pen.LineJoin='Round'
  $g.DrawPath($pen,$path)
  $g.FillPath((New-Object System.Drawing.SolidBrush $color),$path)
  return $b.Height
}

function Measure-TextWidth($fam,$text,$size){
  $sf=New-Object System.Drawing.StringFormat
  $path=New-Object System.Drawing.Drawing2D.GraphicsPath
  $style=0; if($script:fontStyle){ $style=[int]$script:fontStyle }
  $path.AddString($text,$fam,$style,[single]$size,(New-Object System.Drawing.PointF 0,0),$sf)
  $w=$path.GetBounds().Width
  $path.Dispose()
  return $w
}

function Fit-Size($fam,$lines,$startSize,$W){
  $side=$script:titleSide; if(-not $side){ $side='C' }
  $maxW= if($side -eq 'C'){ $W*0.92 } else { $W*0.55 }
  $size=[single]$startSize
  foreach($text in $lines){
    $w=Measure-TextWidth $fam $text $startSize
    if($w -gt $maxW){
      $s=$startSize*($maxW*0.98)/$w
      if($s -lt $size){ $size=$s }
    }
  }
  return $size
}

function Fill-Crop($src,$W,$H,$fx=0.5,$atTop=$false,$fy=0.5){
  $bmp=New-Object System.Drawing.Bitmap $W,$H
  $g=[System.Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode='HighQualityBicubic'; $g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAlias'
  $sc=[Math]::Max($W/$src.Width,$H/$src.Height); $iw=$src.Width*$sc; $ih=$src.Height*$sc
  $x=[Math]::Min(0,[Math]::Max($W-$iw, $W/2-$iw*$fx))
  $g.DrawImage($src,[single]$x,[single](($H-$ih)*$fy),[single]$iw,[single]$ih)
  if($atTop){
    $gh=[int]($H*0.5)
    $gb=New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0,0),(New-Object System.Drawing.Point 0,($gh+1)),([System.Drawing.Color]::FromArgb(225,0,0,0)),([System.Drawing.Color]::FromArgb(0,0,0,0))
    $g.FillRectangle($gb,0,0,$W,$gh)
  } else {
    $top=[int]($H*0.5)
    $gb=New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0,($top-1)),(New-Object System.Drawing.Point 0,$H),([System.Drawing.Color]::FromArgb(0,0,0,0)),([System.Drawing.Color]::FromArgb(225,0,0,0))
    $g.FillRectangle($gb,0,$top,$W,$H-$top)
  }
  return @($bmp,$g)
}

function Draw-Block($g,$fam,$items,$W,$bottom,$topY=-1){
  $scratch=New-Object System.Drawing.Bitmap 10,10; $sg=[System.Drawing.Graphics]::FromImage($scratch)
  $total=0; foreach($it in $items){ $total+= (Add-Text $sg $fam $it[0] $it[1] -5000 $it[2] $W) + $it[3] }
  $sg.Dispose(); $scratch.Dispose()
  if($topY -ge 0){ $y=$topY } else { $y=$bottom-$total }
  foreach($it in $items){ $y+= (Add-Text $g $fam $it[0] $it[1] $y $it[2] $W) + $it[3] }
}

function Trim-Bars($img){
  $b=New-Object System.Drawing.Bitmap $img
  function Plain($b,$horiz,$i){
    $n= if($horiz){$b.Width}else{$b.Height}; $vals=@()
    for($k=0;$k -lt 24;$k++){ $p=[int]($n*($k+0.5)/24); $c= if($horiz){$b.GetPixel($p,$i)}else{$b.GetPixel($i,$p)}; $vals+=($c.R+$c.G+$c.B) }
    $flat=@($vals | Where-Object { $_ -gt 735 -or $_ -lt 12 }).Count
    return ($flat -ge 20)
  }
  $t=0; while($t -lt $b.Height/4 -and (Plain $b $true $t)){ $t++ }
  $bt=$b.Height-1; while($bt -gt $b.Height*3/4 -and (Plain $b $true $bt)){ $bt-- }
  $l=0; while($l -lt $b.Width/4 -and (Plain $b $false $l)){ $l++ }
  $r=$b.Width-1; while($r -gt $b.Width*3/4 -and (Plain $b $false $r)){ $r-- }
  if($t -eq 0 -and $l -eq 0 -and $bt -eq $b.Height-1 -and $r -eq $b.Width-1){ return $b }
  $rect=New-Object System.Drawing.Rectangle ($l+2),($t+2),($r-$l-4),($bt-$t-4)
  return $b.Clone($rect,$b.PixelFormat)
}

function Split-Lines($words,$max){
  $lines=@(); $cur=''
  foreach($w in $words){ if(($cur+' '+$w).Trim().Length -gt $max -and $cur){ $lines+=$cur; $cur=$w } else { $cur=($cur+' '+$w).Trim() } }
  if($cur){ $lines+=$cur }; return $lines
}

function Split-Balanced($words){
  $words=@($words | Where-Object { $_ })
  if($words.Count -le 1){ return ,@(($words -join ' ')) }
  $all=($words -join ' ')
  if($all.Length -le 12){ return ,@($all) }
  $n=2
  if($words.Count -ge 5 -or $all.Length -gt 28){ $n=[Math]::Min(3,$words.Count) }
  if($n -eq 2){
    $best=1; $bestDiff=9999
    for($i=1;$i -lt $words.Count;$i++){
      $a=($words[0..($i-1)] -join ' ').Length
      $b=($words[$i..($words.Count-1)] -join ' ').Length
      $d=[Math]::Abs($a-$b)
      if($d -lt $bestDiff){ $bestDiff=$d; $best=$i }
    }
    return @(($words[0..($best-1)] -join ' '), ($words[$best..($words.Count-1)] -join ' '))
  }
  $bestI=1; $bestJ=2; $bestScore=9999
  for($i=1;$i -le $words.Count-2;$i++){
    for($j=$i+1;$j -le $words.Count-1;$j++){
      $a=($words[0..($i-1)] -join ' ').Length
      $b=($words[$i..($j-1)] -join ' ').Length
      $c=($words[$j..($words.Count-1)] -join ' ').Length
      $avg=($a+$b+$c)/3.0
      $score=[Math]::Abs($a-$avg)+[Math]::Abs($b-$avg)+[Math]::Abs($c-$avg)
      if($score -lt $bestScore){ $bestScore=$score; $bestI=$i; $bestJ=$j }
    }
  }
  return @(($words[0..($bestI-1)] -join ' '), ($words[$bestI..($bestJ-1)] -join ' '), ($words[$bestJ..($words.Count-1)] -join ' '))
}

function Build-TitleItems($fam,$title,$k,$W,$nameSize,$gap,$nameGap,$accent,$artist){
  $white=[System.Drawing.Color]::FromArgb(245,240,230); $gold=[System.Drawing.Color]::FromArgb(255,196,60); $grey=[System.Drawing.Color]::FromArgb(225,225,225)
  $raw=$title.ToUpper()
  $manual=$false
  if($raw -match '/'){
    $titleLines=@($raw -split '/' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $manual=$true
  } else {
    $words=@($raw -split '\s+' | Where-Object { $_ })
  }
  $items=@()
  if($accent -and -not $manual){
    $words=@($raw -split '\s+' | Where-Object { $_ })
    $last=$words[-1]; $rest=@(); if($words.Count -gt 1){ $rest=$words[0..($words.Count-2)] }
    $restSize= if($W -ge 1600){ 110*$k } else { 130*$k }
    $lastSize= if($W -ge 1600){ 190*$k } else { 230*$k }
    if($rest.Count){
      $restLines= if($W -ge 1600){ @(($rest -join ' ')) } else { @(Split-Lines $rest 10) }
      foreach($ln in $restLines){ $items+=,@($ln,$restSize,$white,$gap) }
    }
    $items+=,@($last,$lastSize,$gold,$nameGap)
  } else {
    if(-not $manual){ $titleLines=@(Split-Balanced $words) }
    $start= if($W -ge 1600){ if($titleLines.Count -ge 3){ 135*$k } else { 165*$k } } else { if($titleLines.Count -ge 3){ 160*$k } else { 200*$k } }
    $size=Fit-Size $fam $titleLines $start $W
    for($i=0;$i -lt $titleLines.Count;$i++){
      $color= if($i -eq $titleLines.Count-1){ $gold } else { $white }
      $sp= if($i -eq $titleLines.Count-1){ $nameGap } else { $gap }
      $items+=,@($titleLines[$i],$size,$color,$sp)
    }
  }
  if($artist -and $artist.Trim()){ $items+=,@($artist.ToUpper(),$nameSize,$grey,0) }
  return $items
}

function Make-Thumbs($f){
  Add-Type -AssemblyName Microsoft.VisualBasic
  $guess=[IO.Path]::GetFileNameWithoutExtension($f) -replace ' - cover.*',''
  if($env:THUMB_TITLE){
    $title=$env:THUMB_TITLE
    $pos= if($env:THUMB_POS){ $env:THUMB_POS } else { 'M' }
    $tp= if($env:THUMB_TEXT){ $env:THUMB_TEXT } else { 'B' }
    $sd= if($env:THUMB_SIDE){ $env:THUMB_SIDE } else { 'C' }
    $styleName= if($env:THUMB_STYLE){ $env:THUMB_STYLE } else { 'Balanced' }
    $fontName= if($env:THUMB_FONT){ $env:THUMB_FONT } else { 'Oswald Bold (default)' }
    $artist= if($env:THUMB_ARTIST){ $env:THUMB_ARTIST } else { $defaultArtist }
  } else {
    $opts=Ask-ThumbOptions $guess
    if(-not $opts){ return }
    $title=$opts.title; $pos=$opts.pos; $tp=$opts.place; $sd=$opts.side; $styleName=$opts.style; $fontName=$opts.font; $artist=$opts.artist
  }
  if(-not $title -or -not $title.Trim()){ return }
  $pos=($pos+'M').Trim().ToUpper().Substring(0,1)
  $script:titleTop=(($tp+'B').Trim().ToUpper().Substring(0,1) -eq 'T')
  $script:titleSide=($sd+'C').Trim().ToUpper().Substring(0,1); if($script:titleSide -notin 'L','C','R'){ $script:titleSide='C' }
  $accent=($styleName -match 'Accent')
  $k=1.0; if($title.Length -gt 30){ $k=0.65 } elseif($title.Length -gt 20){ $k=0.8 }
  $script:shortX=switch($pos){ 'L' {0.3} 'R' {0.7} default {0.5} }
  $script:fontStyle=0
  $fam=Resolve-ThumbFont $fontName
  $src=Trim-Bars ([System.Drawing.Image]::FromFile($f))
  $td= if($env:THUMB_DIR){ $env:THUMB_DIR } else { Join-Path $outDir 'thumbnails' }
  New-Item -ItemType Directory -Force $td | Out-Null
  $safe=(($title -replace '[\\/:*?"<>|]',' ' -replace '\s+',' ').Trim()); $pic=(([IO.Path]::GetFileNameWithoutExtension($f) -replace '[\\/:*?"<>|]',' ' -replace '\s+',' ').Trim())
  $enc=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $ep=New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality),([long]92)
  # wide YouTube thumbnail
  $fyW=0.2; if($script:titleTop){ $fyW=0.3 }; if($env:THUMB_FY){ $fyW=[double]$env:THUMB_FY }
  $r=Fill-Crop $src 1920 1080 0.5 $script:titleTop $fyW; $bmp=$r[0]; $g=$r[1]
  $items=Build-TitleItems $fam $title $k 1920 (64*$k) 18 24 $accent $artist
  if($script:titleTop){ Draw-Block $g $fam $items 1920 0 45 } else { Draw-Block $g $fam $items 1920 1035 }
  $g.Dispose(); $bmp.Save((Join-Path $td "$safe - YouTube Thumbnail ($pic).jpg"),$enc,$ep); $bmp.Dispose()
  # short thumbnail
  $r=Fill-Crop $src 1080 1920 $script:shortX $script:titleTop; $bmp=$r[0]; $g=$r[1]
  $items=Build-TitleItems $fam $title $k 1080 (76*$k) 22 32 $accent $artist
  if($script:titleTop){ Draw-Block $g $fam $items 1080 0 150 } else { Draw-Block $g $fam $items 1080 1560 }
  $g.Dispose(); $tds=Join-Path $td 'shorts'; New-Item -ItemType Directory -Force $tds | Out-Null; $bmp.Save((Join-Path $tds "$safe - Short Thumbnail ($pic).jpg"),$enc,$ep); $bmp.Dispose()
  $src.Dispose()
  Write-Host "Thumbnails made in $td (Short thumbnail in $td\shorts)"
}

function Show-HowTo{
  [System.Windows.Forms.MessageBox]::Show(
    "Drop a picture onto 'Make SunoMV Cover' (this bat file, or a shortcut to it) to make a square cover and YouTube / Short thumbnails.`n`nIn the window that opens, you can type the song title, your artist name, pick a font, and choose Balanced (default) or Big Accent Line.","Make SunoMV Cover"
  ) | Out-Null
}

if($args.Count -eq 0){ Show-HowTo }
foreach($f in $args){
  try{
    $ext=[IO.Path]::GetExtension($f).ToLower()
    if($ext -in '.png','.jpg','.jpeg','.webp','.bmp'){ Make-Cover $f; Make-Thumbs $f }
    else { Write-Host "Not a picture: $f" }
  } catch { Write-Host "Problem with $f : $_" }
}
