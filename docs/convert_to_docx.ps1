# Convert repository_documentation.md to repository_documentation.docx
# Uses Microsoft Word COM automation with built-in style constants (locale-independent).

param(
    [string]$InputMd    = "$PSScriptRoot\..\repository_documentation.md",
    [string]$OutputDocx = "$PSScriptRoot\..\repository_documentation.docx"
)

$InputMd    = (Resolve-Path $InputMd).Path
$OutputDocx = [System.IO.Path]::GetFullPath($OutputDocx)

Write-Host "Source : $InputMd"
Write-Host "Target : $OutputDocx"

# WdBuiltinStyle constants (locale-independent integers)
$wdStyleNormal      =   0
$wdStyleHeading1    =  -2
$wdStyleHeading2    =  -3
$wdStyleHeading3    =  -4
$wdStyleHeading4    =  -5
$wdStyleHeading5    =  -6
$wdStyleListBullet  = -13
$wdStyleListNumber  = -14
$wdStyleNoSpacing   = -158  # "No Spacing" / "Geen afstand"

$wdFormatDocx = 16   # wdFormatDocumentDefault

# ── Launch Word ────────────────────────────────────────────────────────────────
$word = New-Object -ComObject Word.Application
$word.Visible = $false

$doc = $word.Documents.Add()
$sel = $word.Selection

function Set-BuiltinStyle([int]$styleId) {
    try { $sel.Style = $styleId }
    catch { $sel.Style = $wdStyleNormal }
}

function Set-CodeFont {
    $sel.Font.Name = "Courier New"
    $sel.Font.Size = 9
    $sel.Font.Bold  = $false
}

function Reset-Font {
    $sel.Font.Name   = "Calibri"
    $sel.Font.Size   = 11
    $sel.Font.Bold   = $false
    $sel.Font.Italic = $false
}

# ── Flush accumulated table rows into a Word table ────────────────────────────
$script:tableRows = [System.Collections.Generic.List[string]]::new()
$script:inTable   = $false

function Flush-Table {
    if ($script:tableRows.Count -eq 0) { return }

    # Remove pure-separator rows (---|---|---)
    $dataRows = $script:tableRows | Where-Object { $_ -notmatch '^\s*\|[\s\-:|]+\|\s*$' }
    if ($dataRows.Count -eq 0) {
        $script:tableRows = [System.Collections.Generic.List[string]]::new()
        $script:inTable   = $false
        return
    }

    # Count columns from the first data row
    $cols = (($dataRows[0] -split '\|') | Where-Object { $_.Length -gt 0 }).Count

    $tbl = $doc.Tables.Add($sel.Range, $dataRows.Count, $cols)
    try { $tbl.Style = $doc.Styles.Item("Table Grid") } catch {}
    $tbl.AutoFitBehavior(1)   # wdAutoFitContent = 1

    $r = 1
    foreach ($row in $dataRows) {
        $cells = ($row -split '\|') | Where-Object { $_.Length -gt 0 } | ForEach-Object { $_.Trim() }
        # Strip inline markdown
        $cells = $cells | ForEach-Object { $_ -replace '`([^`]+)`','$1' -replace '\*\*([^*]+)\*\*','$1' -replace '\*([^*]+)\*','$1' }

        for ($c = 1; $c -le $cols -and ($c - 1) -lt $cells.Count; $c++) {
            $tbl.Cell($r, $c).Range.Text = $cells[$c - 1]
            if ($r -eq 1) { $tbl.Cell($r, $c).Range.Bold = $true }
        }
        $r++
    }

    $sel.MoveDown(5, 1) | Out-Null   # move past table
    $sel.TypeParagraph()

    $script:tableRows = [System.Collections.Generic.List[string]]::new()
    $script:inTable   = $false
}

# ── Strip inline markdown to plain text ───────────────────────────────────────
function Strip-Inline([string]$text) {
    $text = $text -replace '\*\*([^*]+)\*\*', '$1'
    $text = $text -replace '\*([^*]+)\*',     '$1'
    $text = $text -replace '`([^`]+)`',       '$1'
    $text = $text -replace '\[([^\]]+)\]\([^)]+\)', '$1'
    $text = $text -replace '^>\s?', ''
    return $text
}

# ── Main loop ─────────────────────────────────────────────────────────────────
$lines  = (Get-Content $InputMd -Raw -Encoding UTF8) -split "`r?`n"
$inCode = $false

foreach ($line in $lines) {

    # Code fence toggle
    if ($line -match '^```') {
        if ($script:inTable) { Flush-Table }
        if ($inCode) {
            $inCode = $false
            $sel.TypeParagraph()
            Reset-Font
            Set-BuiltinStyle $wdStyleNormal
        } else {
            $inCode = $true
            Set-BuiltinStyle $wdStyleNoSpacing
            Set-CodeFont
        }
        continue
    }

    if ($inCode) {
        $sel.TypeText($line)
        $sel.TypeParagraph()
        continue
    }

    # Table row
    if ($line -match '^\s*\|') {
        $script:inTable = $true
        $script:tableRows.Add($line)
        continue
    } elseif ($script:inTable) {
        Flush-Table
    }

    # Blank line
    if ($line -match '^\s*$') {
        Set-BuiltinStyle $wdStyleNormal
        Reset-Font
        $sel.TypeParagraph()
        continue
    }

    # Headings
    if ($line -match '^(#{1,5})\s+(.+)$') {
        $level   = $matches[1].Length
        $text    = (Strip-Inline $matches[2]).Trim()
        $styleMap = @{ 1=$wdStyleHeading1; 2=$wdStyleHeading2; 3=$wdStyleHeading3;
                       4=$wdStyleHeading4; 5=$wdStyleHeading5 }
        Set-BuiltinStyle $styleMap[$level]
        $sel.TypeText($text)
        $sel.TypeParagraph()
        Reset-Font
        Set-BuiltinStyle $wdStyleNormal
        continue
    }

    # Horizontal rule
    if ($line -match '^-{3,}$' -or $line -match '^\*{3,}$') {
        Set-BuiltinStyle $wdStyleNormal
        $sel.TypeParagraph()
        continue
    }

    # Bullet list
    if ($line -match '^(\s*)[-*+]\s+(.+)$') {
        Set-BuiltinStyle $wdStyleListBullet
        $sel.TypeText((Strip-Inline $matches[2]))
        $sel.TypeParagraph()
        Reset-Font
        Set-BuiltinStyle $wdStyleNormal
        continue
    }

    # Numbered list
    if ($line -match '^\d+\.\s+(.+)$') {
        Set-BuiltinStyle $wdStyleListNumber
        $sel.TypeText((Strip-Inline $matches[1]))
        $sel.TypeParagraph()
        Reset-Font
        Set-BuiltinStyle $wdStyleNormal
        continue
    }

    # Normal paragraph
    Set-BuiltinStyle $wdStyleNormal
    Reset-Font
    $plain = Strip-Inline $line
    if ($plain -ne "") {
        $sel.TypeText($plain)
    }
    $sel.TypeParagraph()
}

# Flush any trailing table
if ($script:inTable) { Flush-Table }

# ── Save ──────────────────────────────────────────────────────────────────────
Write-Host "Saving to $OutputDocx ..."
$doc.SaveAs([ref]$OutputDocx, [ref]$wdFormatDocx)
$doc.Close($false)
$word.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null

Write-Host "Done. Written to: $OutputDocx"
