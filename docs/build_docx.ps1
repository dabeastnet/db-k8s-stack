# Build repository_documentation.docx
# Step 1: PowerShell converts .md -> .html
# Step 2: Word opens the HTML and saves as .docx (fast, single operation)

param(
    [string]$InputMd    = "$PSScriptRoot\..\repository_documentation.md",
    [string]$OutputDocx = "$PSScriptRoot\..\repository_documentation.docx"
)

$InputMd    = (Resolve-Path $InputMd).Path
$HtmlFile   = [System.IO.Path]::ChangeExtension($InputMd, ".html")
$OutputDocx = [System.IO.Path]::GetFullPath($OutputDocx)

# ── Helpers ────────────────────────────────────────────────────────────────────
function Escape-Html([string]$t) {
    $t -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}
function Inline([string]$t) {
    $t = Escape-Html $t
    $t = [regex]::Replace($t, '\*\*([^*]+)\*\*', '<b>$1</b>')
    $t = [regex]::Replace($t, '\*([^*]+)\*',     '<i>$1</i>')
    $t = [regex]::Replace($t, '`([^`]+)`',        '<code>$1</code>')
    $t = [regex]::Replace($t, '\[([^\]]+)\]\([^)]+\)', '$1')
    return $t
}
function Flush-Table([System.Collections.Generic.List[string]]$buf) {
    $rows = $buf | Where-Object { $_ -notmatch '^\s*\|[\s\-:|]+\|\s*$' }
    if (-not $rows) { return '' }
    $lines2 = [System.Collections.Generic.List[string]]::new()
    $lines2.Add('<table>')
    $first = $true
    foreach ($row in $rows) {
        $cells = ($row -split '\|') | Where-Object { $_.Length -gt 0 } | ForEach-Object { $_.Trim() }
        $tag = if ($first) { 'th' } else { 'td' }
        $first = $false
        $cellHtml = ($cells | ForEach-Object { "<$tag>$(Inline $_)</$tag>" }) -join ''
        $lines2.Add("<tr>$cellHtml</tr>")
    }
    $lines2.Add('</table>')
    return $lines2 -join "`n"
}

# ── CSS ────────────────────────────────────────────────────────────────────────
$css = @"
body{font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#222;line-height:1.5;margin:40px 60px}
h1{font-size:18pt;color:#1F3864;margin-top:24pt;margin-bottom:6pt}
h2{font-size:15pt;color:#2E75B6;margin-top:18pt;margin-bottom:4pt}
h3{font-size:13pt;color:#2E75B6;margin-top:14pt;margin-bottom:4pt}
h4,h5,h6{font-size:11pt;color:#404040;margin-top:10pt;margin-bottom:2pt;font-weight:bold}
p{margin:4pt 0}
pre{background:#f5f5f5;border:1px solid #ddd;padding:8px 10px;font-family:'Courier New',monospace;font-size:9pt;white-space:pre-wrap;word-break:break-all;margin:6pt 0}
code{font-family:'Courier New',monospace;font-size:9pt;background:#f0f0f0;padding:1px 3px}
table{border-collapse:collapse;width:100%;margin:8pt 0;font-size:10pt}
th{background:#2E75B6;color:white;font-weight:bold;padding:4px 8px;border:1px solid #999;text-align:left}
td{padding:3px 8px;border:1px solid #bbb;vertical-align:top}
tr:nth-child(even) td{background:#f2f7fc}
ul,ol{margin:4pt 0 4pt 24pt;padding:0}
li{margin:2pt 0}
hr{border:0;border-top:1px solid #ccc;margin:12pt 0}
"@

# ── Convert MD -> HTML ─────────────────────────────────────────────────────────
Write-Host "Step 1: Converting MD to HTML..."
$src    = Get-Content $InputMd -Raw -Encoding UTF8
$lines  = $src -split "`r?`n"
$body   = [System.Text.StringBuilder]::new(512000)

$inCode    = $false
$inListB   = $false
$inListN   = $false
$inTable   = $false
$tableBuf  = [System.Collections.Generic.List[string]]::new()

function Close-Lists {
    if ($script:inListB) { [void]$script:body.AppendLine('</ul>'); $script:inListB = $false }
    if ($script:inListN) { [void]$script:body.AppendLine('</ol>'); $script:inListN = $false }
}

foreach ($line in $lines) {

    # Code fence
    if ($line -match '^```') {
        Close-Lists
        if ($inTable) {
            [void]$body.AppendLine((Flush-Table $tableBuf))
            $tableBuf.Clear(); $inTable = $false
        }
        if ($inCode) { [void]$body.AppendLine('</pre>'); $inCode = $false }
        else         { [void]$body.AppendLine('<pre>');  $inCode = $true  }
        continue
    }
    if ($inCode) { [void]$body.AppendLine((Escape-Html $line)); continue }

    # Table row
    if ($line -match '^\s*\|') {
        Close-Lists; $inTable = $true; $tableBuf.Add($line); continue
    } elseif ($inTable) {
        [void]$body.AppendLine((Flush-Table $tableBuf))
        $tableBuf.Clear(); $inTable = $false
    }

    # Blank line
    if ($line -match '^\s*$') {
        Close-Lists; [void]$body.AppendLine('<p>&nbsp;</p>'); continue
    }

    # Headings
    if ($line -match '^(#{1,6})\s+(.+)$') {
        Close-Lists
        $lvl  = $matches[1].Length
        $text = Escape-Html $matches[2].Trim()
        [void]$body.AppendLine("<h$lvl>$text</h$lvl>"); continue
    }

    # HR
    if ($line -match '^-{3,}$' -or $line -match '^\*{3,}$') {
        Close-Lists; [void]$body.AppendLine('<hr/>'); continue
    }

    # Bullet list
    if ($line -match '^\s*[-*+]\s+(.+)$') {
        if ($inListN) { [void]$body.AppendLine('</ol>'); $inListN = $false }
        if (-not $inListB) { [void]$body.AppendLine('<ul>'); $inListB = $true }
        [void]$body.AppendLine("<li>$(Inline $matches[1])</li>"); continue
    }

    # Numbered list
    if ($line -match '^\d+\.\s+(.+)$') {
        if ($inListB) { [void]$body.AppendLine('</ul>'); $inListB = $false }
        if (-not $inListN) { [void]$body.AppendLine('<ol>'); $inListN = $true }
        [void]$body.AppendLine("<li>$(Inline $matches[1])</li>"); continue
    }

    # Normal paragraph
    Close-Lists
    $text = $line -replace '^>\s?', ''
    [void]$body.AppendLine("<p>$(Inline $text)</p>")
}
if ($inTable) { [void]$body.AppendLine((Flush-Table $tableBuf)) }
if ($inListB) { [void]$body.AppendLine('</ul>') }
if ($inListN) { [void]$body.AppendLine('</ol>') }
if ($inCode)  { [void]$body.AppendLine('</pre>') }

$htmlDoc = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"/>
<style>$css</style>
</head>
<body>
$($body.ToString())
</body>
</html>
"@

[System.IO.File]::WriteAllText($HtmlFile, $htmlDoc, [System.Text.Encoding]::UTF8)
Write-Host "  HTML written to $HtmlFile"

# ── Word: open HTML, save as DOCX ─────────────────────────────────────────────
Write-Host "Step 2: Opening in Word and saving as DOCX..."
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc  = $word.Documents.Open($HtmlFile)
$doc.SaveAs([ref]$OutputDocx, [ref]16)   # wdFormatDocumentDefault = 16
$doc.Close($false)
$word.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null

Write-Host "Done. DOCX: $OutputDocx"
