# Copies art out of a VoxelForge Java export into art/ (Windows: uses System.Drawing for the trims).
#   ./tools/Import-VoxelForge.ps1 -Zip <path to ...-voxelforge-java.zip>
# provenance/voxelforge.json maps what we need to VoxelForge asset ids. The export names files after the asset
# (<name>_<first 8 of the asset id>); only the images are taken, so the studio's own namespace and names never reach
# the pack. Keys:
#   <item id>              the item's icon -> art/items/<id>.png (a skin_ item also gives art/equipment/<id>.png)
#   pack_icon              -> pack.png
#   gui:<id>               a menu background -> art/gui/<id>.png
#   trim_pattern:<id>      { head, chest, legs, feet } armour layers, merged and turned into the eight trim greys ->
#                          art/trims/<id>_humanoid.png and art/trims/<id>_humanoid_leggings.png
param(
    [Parameter(Mandatory)][string]$Zip
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$provenance = Get-Content -Raw (Join-Path $root 'provenance/voxelforge.json') | ConvertFrom-Json -AsHashtable
# Vanilla's trim base palette (textures/palettes/trim_base.png): the client tints these per trim material.
$TrimGreys = @(224, 192, 160, 128, 96, 64, 32, 0)

function Find-Entry($Archive, [string]$Asset, [string]$Pattern) {
    $prefix = $Asset.Substring(0, 8)
    return $Archive.Entries | Where-Object { $_.FullName -match ($Pattern -replace '\{p\}', $prefix) } | Select-Object -First 1
}

function Save-Entry($Entry, [string]$Target) {
    New-Item -ItemType Directory -Force (Split-Path $Target) | Out-Null
    $stream = $Entry.Open()
    $file = [System.IO.File]::Create($Target)
    try { $stream.CopyTo($file) } finally { $file.Dispose(); $stream.Dispose() }
}

function Read-Bitmap($Entry) {
    $stream = $Entry.Open()
    $memory = [System.IO.MemoryStream]::new()
    try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
    $memory.Position = 0
    return [System.Drawing.Bitmap]::new($memory)
}

# Merges armour layers (later ones on top) and maps every visible pixel to the nearest trim grey.
function Save-Trim([System.Drawing.Bitmap[]]$Layers, [string]$Target) {
    $out = [System.Drawing.Bitmap]::new(64, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        for ($y = 0; $y -lt 32; $y++) {
            for ($x = 0; $x -lt 64; $x++) {
                $pixel = $null
                foreach ($layer in $Layers) {
                    $c = $layer.GetPixel($x, $y)
                    if ($c.A -ge 128) { $pixel = $c }
                }
                if ($null -eq $pixel) { continue }
                $lum = 0.299 * $pixel.R + 0.587 * $pixel.G + 0.114 * $pixel.B
                $grey = $TrimGreys | Sort-Object { [math]::Abs($_ - $lum) } | Select-Object -First 1
                $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $grey, $grey, $grey))
            }
        }
        New-Item -ItemType Directory -Force (Split-Path $Target) | Out-Null
        $out.Save($Target, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $out.Dispose() }
}

$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Zip))
$missing = [System.Collections.Generic.List[string]]::new()
try {
    $imported = 0
    foreach ($key in ($provenance.Keys | Sort-Object)) {
        $value = $provenance[$key]
        if ($key -like 'trim_pattern:*') {
            $id = $key.Substring('trim_pattern:'.Length)
            $parts = @{}
            foreach ($part in @('head', 'chest', 'legs', 'feet')) {
                $entry = Find-Entry $archive $value[$part] '^assets/voxelforge/textures/entity/equipment/humanoid(_leggings)?/.+_{p}\.png$'
                if ($entry) { $parts[$part] = Read-Bitmap $entry }
            }
            if ($parts.Count -eq 0) { continue }
            if ($parts.Count -ne 4) { $missing.Add("$key (some armour parts)"); continue }
            try {
                Save-Trim @($parts.head, $parts.chest, $parts.feet) (Join-Path $root "art/trims/${id}_humanoid.png")
                Save-Trim @($parts.legs) (Join-Path $root "art/trims/${id}_humanoid_leggings.png")
            } finally { $parts.Values | ForEach-Object { $_.Dispose() } }
            $imported++
            "imported $key"
            continue
        }
        $asset = $value.asset
        if ($key -like 'gui:*') {
            $entry = Find-Entry $archive $asset '^assets/voxelforge/textures/.+_{p}/main\.png$'
            if (-not $entry) { continue }
            Save-Entry $entry (Join-Path $root "art/gui/$($key.Substring(4)).png")
        } elseif ($key -eq 'pack_icon') {
            $entry = Find-Entry $archive $asset '^assets/voxelforge/textures/(item/)?.+_{p}/main\.png$'
            if (-not $entry) { continue }
            Save-Entry $entry (Join-Path $root 'pack.png')
        } else {
            $entry = Find-Entry $archive $asset '^assets/voxelforge/textures/item/.+_{p}(/main)?\.png$'
            if (-not $entry) { continue }
            Save-Entry $entry (Join-Path $root "art/items/$key.png")
            if ($key -like 'skin_*') {
                $worn = Find-Entry $archive $asset '^assets/voxelforge/textures/entity/equipment/humanoid/.+_{p}\.png$'
                if (-not $worn) { $missing.Add("$key (worn texture)"); continue }
                Save-Entry $worn (Join-Path $root "art/equipment/$key.png")
            }
        }
        $imported++
        "imported $key"
    }
    "$imported entr(ies) imported."
    if ($missing.Count -gt 0) { Write-Warning ("Incomplete in this export: " + ($missing -join ', ')) }
} finally {
    $archive.Dispose()
}
