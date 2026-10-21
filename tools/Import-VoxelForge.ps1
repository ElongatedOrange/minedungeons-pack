# Copies item textures from a VoxelForge Java export into art/items/<id>.png (and the pack icon into pack.png).
#   ./tools/Import-VoxelForge.ps1 -Zip <path to ...-voxelforge-java.zip>
# provenance/voxelforge.json maps each item id to its VoxelForge asset id. The export names textures after the asset
# (assets/voxelforge/textures/item/<name>_<first 8 of the asset id>/main.png); only the PNG is taken, so the studio's
# own namespace and names never reach the pack.
param(
    [Parameter(Mandatory)][string]$Zip
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$provenance = Get-Content -Raw (Join-Path $root 'provenance/voxelforge.json') | ConvertFrom-Json -AsHashtable
$out = Join-Path $root 'art/items'
New-Item -ItemType Directory -Force $out | Out-Null

$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Zip))
try {
    $imported = 0
    foreach ($id in ($provenance.Keys | Sort-Object)) {
        $prefix = $provenance[$id].asset.Substring(0, 8)
        $entry = $archive.Entries | Where-Object { $_.FullName -match "^assets/voxelforge/textures/(item/)?.+_$prefix/main\.png$" } |
            Select-Object -First 1
        if (-not $entry) { continue }
        # pack_icon is the pack's own icon (pack.png); everything else is an item.
        $target = if ($id -eq 'pack_icon') { Join-Path $root 'pack.png' } else { Join-Path $out "$id.png" }
        $stream = $entry.Open()
        $file = [System.IO.File]::Create($target)
        try { $stream.CopyTo($file) } finally { $file.Dispose(); $stream.Dispose() }
        $imported++
        "imported $id"
    }
    "$imported texture(s) imported."
} finally {
    $archive.Dispose()
}
