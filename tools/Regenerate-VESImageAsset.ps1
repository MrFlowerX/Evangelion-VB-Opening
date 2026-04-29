param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$OutputPath,

    [string]$GritPath
)

$ErrorActionPreference = 'Stop'

function Get-BoolValue {
    param(
        $Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) {
        return $Default
    }

    return [bool]$Value
}

function Get-ConfigValue {
    param(
        $Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Get-FrameOrderIndex {
    param(
        [string]$Name
    )

    $match = [regex]::Match($Name, '(\d+)(?=\.[^.]+$)')

    if (-not $match.Success) {
        return [int]::MaxValue
    }

    return [int]$match.Groups[1].Value
}

function Format-HexArray {
    param(
        [string[]]$Values,
        [int]$ItemsPerLine
    )

    if ($null -eq $Values -or $Values.Count -eq 0) {
        return "`t0x00000000,"
    }

    $lines = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $Values.Count; $i += $ItemsPerLine) {
        $end = [Math]::Min($i + $ItemsPerLine - 1, $Values.Count - 1)
        $chunk = $Values[$i..$end]
        $lines.Add("`t" + (($chunk | ForEach-Object { "0x$_" }) -join ',') + ',')
    }

    return ($lines -join "`r`n")
}

function Format-UInt32Offsets {
    param(
        [int[]]$Values,
        [int]$ItemsPerLine = 8
    )

    $hexValues = @($Values | ForEach-Object { '{0:X8}' -f $_ })
    return Format-HexArray -Values $hexValues -ItemsPerLine $ItemsPerLine
}

function Get-SectionAttribute {
    param([string]$Section)

    if ($null -eq $Section) {
        $Section = ''
    }

    switch ($Section.ToLowerInvariant()) {
        'exp' { return ' __attribute((section(".expdata")))' }
        'rom' { return ' __attribute((section(".rodata")))' }
        default { return '' }
    }
}

function Resolve-GritPath {
    param([string]$ExplicitPath)

    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates += $ExplicitPath
    }

    if (-not [string]::IsNullOrWhiteSpace($env:VUENGINE_GRIT_PATH)) {
        $candidates += $env:VUENGINE_GRIT_PATH
    }

    $pathCommand = Get-Command 'grit.exe' -ErrorAction SilentlyContinue
    if ($null -ne $pathCommand) {
        $candidates += $pathCommand.Source
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'No se encuentra grit.exe. Indica su ruta con -GritPath, define VUENGINE_GRIT_PATH o anade grit.exe al PATH.'
}

if (-not ('VBPaletteIndexer' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class VBPaletteIndexer
{
    public static void Convert(string inputPath, string outputPath)
    {
        using (var sourceOriginal = (Bitmap)Image.FromFile(inputPath))
        using (var source = new Bitmap(sourceOriginal.Width, sourceOriginal.Height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(source))
            {
                graphics.DrawImage(sourceOriginal, 0, 0, sourceOriginal.Width, sourceOriginal.Height);
            }

            using (var target = new Bitmap(source.Width, source.Height, PixelFormat.Format8bppIndexed))
            {
                var palette = target.Palette;
                palette.Entries[0] = Color.FromArgb(0, 0, 0);
                palette.Entries[1] = Color.FromArgb(85, 0, 0);
                palette.Entries[2] = Color.FromArgb(170, 0, 0);
                palette.Entries[3] = Color.FromArgb(255, 0, 0);

                for (int i = 4; i < palette.Entries.Length; i++)
                {
                    palette.Entries[i] = Color.FromArgb(0, 0, 0);
                }

                target.Palette = palette;

                var rect = new Rectangle(0, 0, source.Width, source.Height);
                var sourceData = source.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                var targetData = target.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format8bppIndexed);

                try
                {
                    var sourceBytes = new byte[sourceData.Stride * source.Height];
                    var targetBytes = new byte[targetData.Stride * target.Height];

                    Marshal.Copy(sourceData.Scan0, sourceBytes, 0, sourceBytes.Length);

                    for (int y = 0; y < source.Height; y++)
                    {
                        int sourceRow = y * sourceData.Stride;
                        int targetRow = y * targetData.Stride;

                        for (int x = 0; x < source.Width; x++)
                        {
                            int sourceIndex = sourceRow + (x * 4);
                            byte alpha = sourceBytes[sourceIndex + 3];
                            byte red = sourceBytes[sourceIndex + 2];

                            byte paletteIndex;

                            if (alpha == 0 || red < 43)
                            {
                                paletteIndex = 0;
                            }
                            else if (red < 128)
                            {
                                paletteIndex = 1;
                            }
                            else if (red < 213)
                            {
                                paletteIndex = 2;
                            }
                            else
                            {
                                paletteIndex = 3;
                            }

                            targetBytes[targetRow + x] = paletteIndex;
                        }
                    }

                    Marshal.Copy(targetBytes, 0, targetData.Scan0, targetBytes.Length);
                }
                finally
                {
                    source.UnlockBits(sourceData);
                    target.UnlockBits(targetData);
                }

                target.Save(outputPath, ImageFormat.Png);
            }
        }
    }
}
"@
}

$resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$assetDirectory = Split-Path -Parent $resolvedConfigPath
$config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json

$assetName = Get-ConfigValue -Object $config -Name 'name'
if ([string]::IsNullOrWhiteSpace($assetName)) {
    $assetName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedConfigPath)
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = Join-Path $assetDirectory 'Converted'
    $OutputPath = Join-Path $outputDirectory ($assetName + '.c')
}

$resolvedOutputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $resolvedOutputDirectory)) {
    New-Item -ItemType Directory -Path $resolvedOutputDirectory | Out-Null
}

$pngFiles = @(Get-ChildItem -LiteralPath $assetDirectory -Filter '*.png' | Sort-Object @{ Expression = { Get-FrameOrderIndex $_.Name } }, Name)
if ($pngFiles.Count -eq 0) {
    throw "No se han encontrado PNGs en $assetDirectory"
}

$gritPath = Resolve-GritPath -ExplicitPath $GritPath

$tempDirectory = Join-Path (Join-Path $PSScriptRoot '..\build') ('grit-' + [guid]::NewGuid().ToString('N'))
$tempDirectory = [System.IO.Path]::GetFullPath($tempDirectory)

if (Test-Path -LiteralPath $tempDirectory) {
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force
}

New-Item -ItemType Directory -Path $tempDirectory | Out-Null

try {
    foreach ($pngFile in $pngFiles) {
        $tempPngPath = Join-Path $tempDirectory $pngFile.Name
        [VBPaletteIndexer]::Convert($pngFile.FullName, $tempPngPath)
    }

    $mapConfig = Get-ConfigValue -Object $config -Name 'map'
    $reduceConfig = Get-ConfigValue -Object $mapConfig -Name 'reduce'
    $tilesetConfig = Get-ConfigValue -Object $config -Name 'tileset'
    $animationConfig = Get-ConfigValue -Object $config -Name 'animation'

    $gritArgs = New-Object System.Collections.Generic.List[string]
    foreach ($pngFile in $pngFiles) {
        $gritArgs.Add($pngFile.Name)
    }

    @('-fh!', '-ftc', '-gB2', '-p!', '-mB16:hv_i11') | ForEach-Object { $gritArgs.Add($_) }

    $generateMap = Get-BoolValue (Get-ConfigValue -Object $mapConfig -Name 'generate') $true
    $reduceUnique = Get-BoolValue (Get-ConfigValue -Object $reduceConfig -Name 'unique') $true
    $reduceFlipped = Get-BoolValue (Get-ConfigValue -Object $reduceConfig -Name 'flipped') $true
    $sharedTiles = Get-BoolValue (Get-ConfigValue -Object $tilesetConfig -Name 'shared') $false
    $isAnimation = Get-BoolValue (Get-ConfigValue -Object $animationConfig -Name 'isAnimation') $false
    $individualFiles = Get-BoolValue (Get-ConfigValue -Object $animationConfig -Name 'individualFiles') $false

    if ($generateMap) {
        if (((-not $isAnimation) -or $individualFiles) -and
            ($reduceUnique -or $reduceFlipped)) {
            $mapReduceArg = '-mR'
            if ($reduceUnique) {
                $mapReduceArg += 't'
            }
            if ($reduceFlipped) {
                $mapReduceArg += 'f'
            }
            $gritArgs.Add($mapReduceArg)
        } else {
            $gritArgs.Add('-mR!')
        }
    } else {
        $gritArgs.Add('-m!')
    }

    if ($sharedTiles) {
        $gritArgs.Add('-gS')
        $gritArgs.Add('-O')
        $gritArgs.Add('__sharedTiles')
        $gritArgs.Add('-S')
        $gritArgs.Add($assetName)
    }

    Push-Location $tempDirectory
    try {
        & $gritPath @gritArgs
    } finally {
        Pop-Location
    }

    $generatedFiles = @(Get-ChildItem -LiteralPath $tempDirectory -Filter '*.c' | Sort-Object @{ Expression = { Get-FrameOrderIndex $_.Name } }, Name)
    if ($generatedFiles.Count -eq 0) {
        throw "grit no ha generado ningun .c temporal"
    }

    $convertedFiles = New-Object System.Collections.Generic.List[object]

    foreach ($generatedFile in $generatedFiles) {
        $content = Get-Content -LiteralPath $generatedFile.FullName -Raw

        $blockName = [regex]::Match($content, '//\{\{BLOCK\(([^)]+)\)').Groups[1].Value
        $mapDimensions = [regex]::Match($content, ', not compressed, ([0-9]+)x([0-9]+)')
        $tilesBlock = [regex]::Match($content, 'const\s+unsigned\s+int\s+\w+Tiles\[\d+\][^{]*\{(?<values>.*?)\};', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $mapBlock = [regex]::Match($content, 'const\s+unsigned\s+short\s+\w+Map\[\d+\][^{]*\{(?<values>.*?)\};', [System.Text.RegularExpressions.RegexOptions]::Singleline)

        if (-not $tilesBlock.Success) {
            throw "No se ha podido extraer el bloque Tiles de $($generatedFile.Name)"
        }

        if (-not $mapBlock.Success) {
            throw "No se ha podido extraer el bloque Map de $($generatedFile.Name)"
        }

        if (-not $mapDimensions.Success) {
            throw "No se han podido extraer las dimensiones del mapa de $($generatedFile.Name)"
        }

        $tileMatches = [regex]::Matches($tilesBlock.Groups['values'].Value, '0x([0-9A-Fa-f]{8}),')
        $mapMatches = [regex]::Matches($mapBlock.Groups['values'].Value, '0x([0-9A-Fa-f]{4}),')

        $tileWords = @($tileMatches | ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() })
        $mapWords = @($mapMatches | ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() })
        $mapWidth = [int]$mapDimensions.Groups[1].Value
        $mapHeight = [int]$mapDimensions.Groups[2].Value

        if ($mapWords.Count -gt ($mapWidth * $mapHeight)) {
            $mapWords = @($mapWords[0..(($mapWidth * $mapHeight) - 1)])
        }

        $convertedFiles.Add([pscustomobject]@{
            Name = $blockName
            TileWords = $tileWords
            TileCount = [int]($tileWords.Count / 4)
            MapWords = $mapWords
            Width = $mapWidth
            Height = $mapHeight
        })
    }

    $forceCleanup = $generateMap -and (-not $reduceFlipped) -and (-not $reduceUnique)
    $emptyCharIsUsed = $sharedTiles -and (($convertedFiles | Where-Object { $_.MapWords -contains '0000' }).Count -gt 0)

    if ($generateMap -and ($forceCleanup -or -not $emptyCharIsUsed)) {
        foreach ($fileData in $convertedFiles) {
            if ((-not $sharedTiles) -and (-not $forceCleanup) -and ($fileData.MapWords -contains '0000')) {
                continue
            }

            if ($fileData.TileWords.Count -gt 4) {
                $fileData.TileWords = @($fileData.TileWords[4..($fileData.TileWords.Count - 1)])
            } elseif ($fileData.TileWords.Count -eq 4) {
                $fileData.TileWords = @()
            }

            $fileData.TileCount = [int]($fileData.TileWords.Count / 4)
            $fileData.MapWords = @($fileData.MapWords | ForEach-Object {
                '{0:X4}' -f ([Convert]::ToInt32($_, 16) - 1)
            })
        }
    }

    $allTileWords = New-Object System.Collections.Generic.List[string]
    $allMapWords = New-Object System.Collections.Generic.List[string]
    $frameOffsets = New-Object System.Collections.Generic.List[int]
    $frameOffsets.Add(1)

    $largestFrame = 0
    $totalTileCount = 0
    $frameCount = 0
    $width = 0
    $height = 0

    foreach ($fileData in $convertedFiles) {
        $totalTileCount += $fileData.TileCount
        $width = $fileData.Width
        $height = $fileData.Height
        $frameCount++

        if ($fileData.TileCount -gt $largestFrame) {
            $largestFrame = $fileData.TileCount
        }

        foreach ($tileWord in $fileData.TileWords) {
            $allTileWords.Add($tileWord)
        }

        foreach ($mapWord in $fileData.MapWords) {
            $allMapWords.Add($mapWord)
        }

        $frameOffsets.Add($allTileWords.Count + 1)
    }

    if ($frameOffsets.Count -gt 0) {
        $frameOffsets.RemoveAt($frameOffsets.Count - 1)
    }

    $sectionAttribute = Get-SectionAttribute -Section (Get-ConfigValue -Object $config -Name 'section')
    $tilesOutputWords = New-Object System.Collections.Generic.List[string]
    $tilesOutputWords.Add('00000000')
    foreach ($tileWord in $allTileWords) {
        $tilesOutputWords.Add($tileWord)
    }
    $pixelsWidth = $width * 8
    $pixelsHeight = $height * 8
    $tilesBytes = $tilesOutputWords.Count * 4
    $mapBytes = $allMapWords.Count * 2
    $totalBytes = $tilesBytes + $mapBytes

    $text = @(
        ''
        '//------------------------------------------------------------------------------'
        '//'
        "//  $assetName"
        "//  - ${pixelsWidth}x${pixelsHeight} pixels"
        "//  - $totalTileCount tiles, reduced by non-unique and flipped tiles, not compressed"
        "//  - ${width}x${height} map, not compressed"
        "//  - $frameCount animation frames, individual files, largest frame: $largestFrame tiles"
        "//  Size: $tilesBytes + $mapBytes = $totalBytes"
        '//'
        '//------------------------------------------------------------------------------'
        ''
        "const uint32 ${assetName}Tiles[$($tilesOutputWords.Count)] __attribute__((aligned(4)))$sectionAttribute ="
        '{'
        (Format-HexArray -Values $tilesOutputWords.ToArray() -ItemsPerLine 8)
        '};'
        ''
        "const uint16 ${assetName}Map[$($allMapWords.Count)] __attribute__((aligned(4)))$sectionAttribute ="
        '{'
        (Format-HexArray -Values $allMapWords.ToArray() -ItemsPerLine 8)
        '};'
        ''
        "const uint32 ${assetName}TilesFrameOffsets[$($frameOffsets.Count)] __attribute__((aligned(4)))$sectionAttribute ="
        '{'
        (Format-UInt32Offsets -Values $frameOffsets.ToArray())
        '};'
        ''
    ) -join "`r`n"

    Set-Content -LiteralPath $OutputPath -Value $text -Encoding ASCII
    Write-Output "Regenerated $OutputPath from $($pngFiles.Count) PNG files"
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}
