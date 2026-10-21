# Builds the Mine Dungeons packs from art/ and items.json:
#   dist/minedungeons-pack.zip (+ .sha1)   Java resource pack (item_model, 1.21.4+)
#   dist/minedungeons-bedrock.mcpack       Bedrock resource pack, sent to Bedrock players by Geyser
#   dist/minedungeons-geyser.json          Geyser custom item mappings (format 2)
# The same inputs always give byte-identical files (sorted entries, fixed timestamps, LF JSON).
#   ./build.ps1 [-Version 1.0.0]
param(
    [string]$Version = (Get-Content -Raw (Join-Path $PSScriptRoot 'VERSION')).Trim()
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Root = $PSScriptRoot
$Namespace = 'minedungeons'
# Held like tools in the hand (Java item/handheld; Bedrock display_handheld).
$Handheld = @('drill', 'grapple')
# Fixed so Bedrock clients recognise the pack across versions; the version number makes them fetch a new one.
$BedrockHeader = '30679650-7aa4-4f99-aca6-1a632ac1d51e'
$BedrockModule = '6310a038-325b-4bdf-8467-993e9157013e'
$Utf8 = [System.Text.UTF8Encoding]::new($false)

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must be x.y.z, not '$Version'" }
$versionParts = @($Version.Split('.') | ForEach-Object { [int]$_ })

function Write-Json([string]$Path, $Value) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    $text = ($Value | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $text + "`n", $Utf8)
}

function Copy-File([string]$From, [string]$To) {
    New-Item -ItemType Directory -Force (Split-Path $To) | Out-Null
    Copy-Item -LiteralPath $From -Destination $To
}

# Width and height from a PNG's IHDR chunk; $null if the file isn't a PNG.
function Get-PngSize([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $signature = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    if ($bytes.Length -lt 24 -or -not [System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes[0..7], $signature)) {
        return $null
    }
    $width = ($bytes[16] -shl 24) -bor ($bytes[17] -shl 16) -bor ($bytes[18] -shl 8) -bor $bytes[19]
    $height = ($bytes[20] -shl 24) -bor ($bytes[21] -shl 16) -bor ($bytes[22] -shl 8) -bor $bytes[23]
    return @($width, $height)
}

function New-Zip([string]$Source, [string]$ZipPath) {
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
    try {
        $files = Get-ChildItem $Source -Recurse -File | ForEach-Object {
            [pscustomobject]@{ File = $_; Relative = [System.IO.Path]::GetRelativePath($Source, $_.FullName).Replace('\', '/') }
        } | Sort-Object Relative -Culture ''
        foreach ($f in $files) {
            $entry = $zip.CreateEntry($f.Relative, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new(2026, 10, 21, 0, 0, 0, [TimeSpan]::Zero)
            $in = [System.IO.File]::OpenRead($f.File.FullName)
            $out = $entry.Open()
            try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
        }
    } finally { $zip.Dispose() }
}

# --- check the inputs -------------------------------------------------------------------------------------------
$items = @((Get-Content -Raw (Join-Path $Root 'items.json') | ConvertFrom-Json).items)
$problems = [System.Collections.Generic.List[string]]::new()
$seen = @{}
foreach ($item in $items) {
    if ($item.id -notmatch '^[a-z0-9_]+$') { $problems.Add("bad id '$($item.id)'") }
    if ($seen.ContainsKey($item.id)) { $problems.Add("duplicate id $($item.id)") }
    $seen[$item.id] = $true
    if ($item.base -notmatch '^minecraft:[a-z0-9_]+$') { $problems.Add("$($item.id): bad base item '$($item.base)'") }
    $art = Join-Path $Root "art/items/$($item.id).png"
    if (-not (Test-Path -LiteralPath $art)) {
        $problems.Add("$($item.id): no texture (art/items/$($item.id).png)")
        continue
    }
    $size = Get-PngSize $art
    if (-not $size -or $size[0] -ne 16 -or $size[1] -ne 16) { $problems.Add("$($item.id): texture must be a 16x16 PNG") }
}
if (-not (Test-Path (Join-Path $Root 'pack.png'))) { $problems.Add('pack.png is missing') }
if ($problems.Count -gt 0) { throw "Pack not built:`n  " + ($problems -join "`n  ") }

# --- generate --------------------------------------------------------------------------------------------------
$build = Join-Path $Root 'build'
$dist = Join-Path $Root 'dist'
if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force $dist | Out-Null
$java = Join-Path $build 'java'
$bedrock = Join-Path $build 'bedrock'

Copy-File (Join-Path $Root 'pack.mcmeta') (Join-Path $java 'pack.mcmeta')
Copy-File (Join-Path $Root 'pack.png') (Join-Path $java 'pack.png')
$textureData = [ordered]@{}
$mappings = [ordered]@{}
foreach ($item in ($items | Sort-Object id -Culture '')) {
    $id = $item.id
    $art = Join-Path $Root "art/items/$id.png"
    $parent = if ($Handheld -contains $id) { 'minecraft:item/handheld' } else { 'minecraft:item/generated' }
    Copy-File $art (Join-Path $java "assets/$Namespace/textures/item/$id.png")
    Write-Json (Join-Path $java "assets/$Namespace/models/item/$id.json") ([ordered]@{
            parent = $parent; textures = [ordered]@{ layer0 = "${Namespace}:item/$id" } })
    Write-Json (Join-Path $java "assets/$Namespace/items/$id.json") ([ordered]@{
            model = [ordered]@{ type = 'minecraft:model'; model = "${Namespace}:item/$id" } })

    Copy-File $art (Join-Path $bedrock "textures/items/$Namespace/$id.png")
    $textureData["$Namespace.$id"] = [ordered]@{ textures = "textures/items/$Namespace/$id" }
    $definition = [ordered]@{
        type = 'definition'
        model = "${Namespace}:$id"
        bedrock_identifier = "${Namespace}:$id"
        display_name = $item.name
        bedrock_options = [ordered]@{ icon = "$Namespace.$id"; display_handheld = ($Handheld -contains $id) }
    }
    if (-not $mappings.Contains($item.base)) { $mappings[$item.base] = [System.Collections.Generic.List[object]]::new() }
    $mappings[$item.base].Add($definition)
}
Copy-File (Join-Path $Root 'pack.png') (Join-Path $bedrock 'pack_icon.png')
Write-Json (Join-Path $bedrock 'manifest.json') ([ordered]@{
        format_version = 2
        header = [ordered]@{
            name = 'Mine Dungeons'; description = 'Mine Dungeons items'; uuid = $BedrockHeader
            version = $versionParts; min_engine_version = @(1, 21, 0)
        }
        modules = @([ordered]@{ type = 'resources'; uuid = $BedrockModule; version = $versionParts })
    })
Write-Json (Join-Path $bedrock 'textures/item_texture.json') ([ordered]@{
        resource_pack_name = $Namespace; texture_name = 'atlas.items'; texture_data = $textureData })

$sortedMappings = [ordered]@{}
foreach ($base in ($mappings.Keys | Sort-Object -Culture '')) { $sortedMappings[$base] = @($mappings[$base]) }
Write-Json (Join-Path $dist 'minedungeons-geyser.json') ([ordered]@{ format_version = 2; items = $sortedMappings })

$javaZip = Join-Path $dist 'minedungeons-pack.zip'
New-Zip $java $javaZip
New-Zip $bedrock (Join-Path $dist 'minedungeons-bedrock.mcpack')
$hash = (Get-FileHash -LiteralPath $javaZip -Algorithm SHA1).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText("$javaZip.sha1", $hash, [System.Text.Encoding]::ASCII)
"Built Mine Dungeons pack ${Version}: $($items.Count) items (Java SHA-1 $hash)"
