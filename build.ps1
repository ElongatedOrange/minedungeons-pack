# Builds the Mine Dungeons packs from art/ and items.json:
#   dist/minedungeons-pack.zip (+ .sha1)   Java resource pack (item_model, 1.21.4+)
#   dist/minedungeons-bedrock.mcpack       Bedrock resource pack, sent to Bedrock players by Geyser
#   dist/minedungeons-geyser.json          Geyser custom item mappings (format 2)
# The same inputs always give byte-identical files on any Windows machine with PowerShell 7 (the image checks need
# System.Drawing): entries in ordinal order, fixed timestamps, LF JSON, and stored without compression (Deflate output
# differs between .NET versions; the PNGs are compressed already).
#   ./build.ps1 [-Version 1.0.0]
param(
    [string]$Version = (Get-Content -Raw (Join-Path $PSScriptRoot 'VERSION')).Trim()
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing

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
    # [int] first: shifting a [byte] stays a byte, so 256 would read as 0.
    $width = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
    $height = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
    return @($width, $height)
}

function New-Zip([string]$Source, [string]$ZipPath) {
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
    try {
        $files = Get-ChildItem $Source -Recurse -File | ForEach-Object {
            [pscustomobject]@{ File = $_; Relative = [System.IO.Path]::GetRelativePath($Source, $_.FullName).Replace('\', '/') }
        }
        $sorted = [System.Collections.Generic.List[object]]::new([object[]]@($files))
        $sorted.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Relative, $b.Relative) })
        foreach ($f in $sorted) {
            $entry = $zip.CreateEntry($f.Relative, [System.IO.Compression.CompressionLevel]::NoCompression)
            $entry.LastWriteTime = [DateTimeOffset]::new(2026, 10, 21, 0, 0, 0, [TimeSpan]::Zero)
            $in = [System.IO.File]::OpenRead($f.File.FullName)
            $out = $entry.Open()
            try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
        }
    } finally { $zip.Dispose() }
}

$TrimGreys = @(224, 192, 160, 128, 96, 64, 32, 0)

# True if every visible pixel is one of the trim base greys and fully opaque (the client tints them per material).
function Test-TrimPalette([string]$Path) {
    $bitmap = [System.Drawing.Bitmap]::new($Path)
    try {
        for ($y = 0; $y -lt $bitmap.Height; $y++) {
            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                $c = $bitmap.GetPixel($x, $y)
                if ($c.A -eq 0) { continue }
                if ($c.A -ne 255 -or $c.R -ne $c.G -or $c.G -ne $c.B -or $TrimGreys -notcontains [int]$c.R) { return $false }
            }
        }
        return $true
    } finally { $bitmap.Dispose() }
}

# The top-left Width x Height of a PNG, saved as a new PNG.
function Save-Crop([string]$From, [string]$To, [int]$Width, [int]$Height) {
    $source = [System.Drawing.Bitmap]::new($From)
    try {
        $crop = $source.Clone([System.Drawing.Rectangle]::new(0, 0, $Width, $Height), $source.PixelFormat)
        try {
            New-Item -ItemType Directory -Force (Split-Path $To) | Out-Null
            $crop.Save($To, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $crop.Dispose() }
    } finally { $source.Dispose() }
}

# --- check the inputs -------------------------------------------------------------------------------------------
$items = @((Get-Content -Raw (Join-Path $Root 'items.json') | ConvertFrom-Json).items)
$gui = Get-Content -Raw (Join-Path $Root 'gui.json') | ConvertFrom-Json
$skins = @($items | Where-Object { $_.id -like 'skin_*' } | ForEach-Object id)
$patterns = @($items | Where-Object { $_.id -like 'trim_*' } | ForEach-Object { $_.id.Substring(5) })
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
    $sizes = if ($item.id -like 'skin_*') { @(16, 32) } else { @(16) }
    if (-not $size -or $size[0] -ne $size[1] -or $sizes -notcontains $size[0]) {
        $problems.Add("$($item.id): texture must be a $(($sizes | ForEach-Object { "${_}x$_" }) -join ' or ') PNG")
    }
}
foreach ($skin in $skins) {
    $worn = Join-Path $Root "art/equipment/$skin.png"
    $size = if (Test-Path -LiteralPath $worn) { Get-PngSize $worn } else { $null }
    if (-not $size -or $size[0] -ne 64 -or $size[1] -ne 32) { $problems.Add("${skin}: needs a 64x32 worn texture (art/equipment/$skin.png)") }
}
foreach ($pattern in $patterns) {
    foreach ($layer in @('humanoid', 'humanoid_leggings')) {
        $file = Join-Path $Root "art/trims/${pattern}_$layer.png"
        $size = if (Test-Path -LiteralPath $file) { Get-PngSize $file } else { $null }
        if (-not $size -or $size[0] -ne 64 -or $size[1] -ne 32) {
            $problems.Add("trim ${pattern}: needs a 64x32 $layer texture (art/trims/${pattern}_$layer.png)")
        } elseif (-not (Test-TrimPalette $file)) {
            $problems.Add("trim ${pattern}: $layer uses colours outside the trim palette")
        }
    }
}
foreach ($bg in $gui.backgrounds) {
    $file = Join-Path $Root "art/gui/$($bg.id).png"
    $size = if (Test-Path -LiteralPath $file) { Get-PngSize $file } else { $null }
    if (-not $size -or $size[0] -lt $gui.width -or $size[1] -lt $bg.height) {
        $problems.Add("gui $($bg.id): needs at least $($gui.width)x$($bg.height) (art/gui/$($bg.id).png)")
    } else {
        # The title glyph's advance (and so the -169 shift back) assumes the art reaches its last column.
        $bitmap = [System.Drawing.Bitmap]::new($file)
        try {
            # @(): a single match at row 0 would otherwise be the scalar 0, which reads as "none".
            $edge = @(0..($bg.height - 1) | Where-Object { $bitmap.GetPixel($gui.width - 1, $_).A -gt 0 })
            if ($edge.Count -eq 0) { $problems.Add("gui $($bg.id): column $($gui.width - 1) must have opaque pixels") }
        } finally { $bitmap.Dispose() }
    }
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
# Helmet skins: the worn look (equipment asset) under the same id as the skin's item model.
foreach ($skin in ($skins | Sort-Object -Culture '')) {
    Copy-File (Join-Path $Root "art/equipment/$skin.png") (Join-Path $java "assets/$Namespace/textures/entity/equipment/humanoid/$skin.png")
    Write-Json (Join-Path $java "assets/$Namespace/equipment/$skin.json") ([ordered]@{
            layers = [ordered]@{ humanoid = @([ordered]@{ texture = "${Namespace}:$skin" }) } })
}
# Trim patterns. 26.x finds them from each pattern's asset_id (minedungeons:<pattern>) and tints them through the
# palette named in each texture's .mcmeta (without it they'd show as plain grey). 1.21.4-1.21.11 clients (through
# ViaVersion) build them from the armor_trims atlas instead; our entries add to vanilla's there, and 26.x ignores it.
$trimTextures = [System.Collections.Generic.List[string]]::new()
foreach ($pattern in ($patterns | Sort-Object -Culture '')) {
    foreach ($layer in @('humanoid', 'humanoid_leggings')) {
        $texture = Join-Path $java "assets/$Namespace/textures/trims/entity/$layer/$pattern.png"
        Copy-File (Join-Path $Root "art/trims/${pattern}_$layer.png") $texture
        Write-Json "$texture.mcmeta" ([ordered]@{ palette = [ordered]@{ base_palette = 'minecraft:trim_base' } })
        $trimTextures.Add("${Namespace}:trims/entity/$layer/$pattern")
    }
}
if ($trimTextures.Count -gt 0) {
    $permutations = [ordered]@{}
    foreach ($material in @('amethyst', 'copper', 'diamond', 'diamond_darker', 'emerald', 'gold', 'gold_darker', 'iron',
            'iron_darker', 'lapis', 'netherite', 'netherite_darker', 'quartz', 'redstone', 'resin')) {
        $permutations[$material] = "minecraft:trims/color_palettes/$material"
    }
    Write-Json (Join-Path $java 'assets/minecraft/atlases/armor_trims.json') ([ordered]@{
            sources = @([ordered]@{
                    type = 'minecraft:paletted_permutations'
                    palette_key = 'minecraft:trims/color_palettes/trim_palette'
                    permutations = $permutations
                    textures = @($trimTextures)
                })
        })
}
# Menu backgrounds: bitmap glyphs in the minedungeons:gui font, plus negative spaces to position them.
$providers = [System.Collections.Generic.List[object]]::new()
$advances = [ordered]@{}
foreach ($space in ($gui.spaces.PSObject.Properties | Sort-Object Name -Culture '')) { $advances[$space.Name] = [int]$space.Value }
$providers.Add([ordered]@{ type = 'space'; advances = $advances })
foreach ($bg in ($gui.backgrounds | Sort-Object id -Culture '')) {
    Save-Crop (Join-Path $Root "art/gui/$($bg.id).png") (Join-Path $java "assets/$Namespace/textures/gui/$($bg.id).png") $gui.width $bg.height
    $providers.Add([ordered]@{ type = 'bitmap'; file = "${Namespace}:gui/$($bg.id).png"; ascent = [int]$gui.ascent
            height = [int]$bg.height; chars = @($bg.char) })
}
Write-Json (Join-Path $java "assets/$Namespace/font/gui.json") ([ordered]@{ providers = $providers })

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
