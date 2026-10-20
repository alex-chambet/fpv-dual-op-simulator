<#
.SYNOPSIS
  Transforme un enregistrement brut en boucle utilisable par le jeu.

.DESCRIPTION
  Les voix du jeu (SubjectVoice, DroneVoice) empilent des boucles et les mélangent en temps réel :
  chaque fichier doit donc être MONO, SANS SILENCE, et surtout boucler sans claquer. Ce script fait
  les quatre opérations, dans cet ordre :

    1. extrait une fenêtre stable (-Start, -Duration) ;
    2. recolle la boucle : la queue est fondue sur la tête sur -Fade secondes, donc le fichier
       produit dure (Duration - Fade) et se referme sur lui-même sans discontinuité ;
    3. normalise en SONIE à -20 LUFS (EBU R128, deux passes, linéaire : aucune compression) ;
    4. convertit en OGG Vorbis mono 32 kHz, qui est ce que Godot lit le mieux en boucle.

  Un son qui ne boucle pas proprement s'entend tout de suite : un clic une fois par seconde. C'est
  la raison d'être de l'étape 2, et c'est elle qu'il faut rallonger (-Fade) si ça claque encore.

.EXAMPLE
  .\make_sfx.ps1 -In "$HOME\Documents\fpv_sfx\wind_mid.wav" -Name wind_mid -Start 2 -Duration 6
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$In,
    [Parameter(Mandatory = $true)][string]$Name,
    [double]$Start = 0.0,
    [double]$Duration = 5.0,
    [double]$Fade = 0.75,
    [double]$Lufs = -20.0,
    [int]$Rate = 32000,
    [int]$Quality = 4,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\audio" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { throw "ffmpeg introuvable dans le PATH." }
if (-not (Test-Path $In)) { throw "fichier introuvable : $In" }
if ($Fade -ge $Duration) { throw "-Fade ($Fade s) doit etre plus court que -Duration ($Duration s)." }

$body = $Duration - $Fade
$tmp = Join-Path $env:TEMP "sfx_$Name.wav"

# 1 et 2 : fenetre, puis queue fondue sur la tete -> boucle sans couture
$filter = @(
    "[0:a]atrim=start=$Start`:duration=$Duration,asetpts=N/SR/TB,aformat=channel_layouts=mono[c]",
    "[c]asplit=2[c1][c2]",
    "[c1]atrim=0:$body,asetpts=N/SR/TB,afade=t=in:st=0:d=$Fade[body]",
    "[c2]atrim=$body`:$Duration,asetpts=N/SR/TB,afade=t=out:st=0:d=$Fade,apad=whole_dur=$body[tail]",
    "[body][tail]amix=inputs=2:normalize=0:dropout_transition=0[out]"
) -join ";"
& $ffmpeg -v error -y -i $In -filter_complex $filter -map "[out]" -ar $Rate -ac 1 $tmp
if ($LASTEXITCODE -ne 0) { throw "ffmpeg a echoue au bouclage." }

# 3 : normalisation en SONIE (EBU R128), pas en crete.
# Une normalisation en crete ne dit rien de ce qu'on entend : sur ces douze sons elle laissait
# 12 dB d'ecart de sonie entre le moteur et les helices, donc les niveaux ecrits dans les couches
# ne voulaient plus rien dire. loudnorm en DEUX passes (mesure, puis application lineaire) amene
# tout le monde a la meme sonie sans pomper et sans ecreter.
# ffmpeg ecrit sa mesure sur stderr ; en PowerShell 5.1 un "2>&1" sur un exe natif emballe chaque
# ligne dans un ErrorRecord et fait echouer la commande, d'ou Start-Process.
$ln = "I=$Lufs`:TP=-1.5:LRA=11"
$probeFile = Join-Path $env:TEMP "sfx_probe_$Name.txt"
$pp = Start-Process -FilePath $ffmpeg -ArgumentList @("-v", "info", "-i", "`"$tmp`"", "-af",
    "loudnorm=$ln`:print_format=json", "-f", "null", "NUL") -NoNewWindow -PassThru `
    -RedirectStandardError $probeFile -RedirectStandardOutput ([IO.Path]::GetTempFileName())
$pp.WaitForExit()
$probe = Get-Content $probeFile -Raw
Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
$m = [regex]::Match($probe, '\{[^{}]*"input_i"[\s\S]*?\}')
if (-not $m.Success) { throw "sonie non mesurable." }
$j = $m.Value | ConvertFrom-Json
$af = "loudnorm=$ln`:measured_I=$($j.input_i):measured_TP=$($j.input_tp)" +
      ":measured_LRA=$($j.input_lra):measured_thresh=$($j.input_thresh):linear=true:print_format=summary"

# 4 : OGG mono, ce que Godot boucle le mieux
$out = Join-Path $OutDir "$Name.ogg"
& $ffmpeg -v error -y -i $tmp -af $af -c:a libvorbis -q:a $Quality -ac 1 -ar $Rate $out
if ($LASTEXITCODE -ne 0) { throw "ffmpeg a echoue a la conversion." }
Remove-Item $tmp -Force

$len = & (Get-Command ffprobe).Source -v error -show_entries format=duration -of csv=p=0 $out
"{0,-14} {1,6:N2} s  sonie {2,6:N1} -> {3} LUFS  {4,8:N0} octets" -f `
    $Name, [double]$len, [double]$j.input_i, $Lufs, (Get-Item $out).Length
