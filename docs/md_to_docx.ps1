# Fast markdown-to-docx via Python markdown → HTML → Word open + SaveAs
# Falls back to pure-Python docx if python-docx is available.
# Strategy: convert MD to HTML with a simple Python script, then Word opens HTML and saves as DOCX.

param(
    [string]$InputMd    = "$PSScriptRoot\..\repository_documentation.md",
    [string]$OutputDocx = "$PSScriptRoot\..\repository_documentation.docx"
)

$InputMd    = (Resolve-Path $InputMd).Path
$OutputDocx = [System.IO.Path]::GetFullPath($OutputDocx)
$HtmlFile   = [System.IO.Path]::ChangeExtension($OutputDocx, ".html")

Write-Host "Step 1: Convert Markdown -> HTML"

# ── Python: MD to HTML ─────────────────────────────────────────────────────────
$pythonScript = @'
import sys, re, html

def md_to_html(src):
    lines = src.split('\n')
    out   = []
    in_code   = False
    in_list_b = False
    in_list_n = False
    in_table  = False
    table_buf = []

    def flush_table(buf):
        rows = [r for r in buf if not re.match(r'^\s*\|[\s\-:|]+\|\s*$', r)]
        if not rows:
            return ''
        cols = len([c for c in rows[0].split('|') if c.strip()])
        h = '<table border="1" cellpadding="4" cellspacing="0" style="border-collapse:collapse;width:100%;font-size:10pt">\n'
        for i, row in enumerate(rows):
            cells = [c.strip() for c in row.split('|') if c.strip()]
            tag = 'th' if i == 0 else 'td'
            h += '<tr>' + ''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells) + '</tr>\n'
        h += '</table>\n'
        return h

    def inline(t):
        t = html.escape(t)
        t = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', t)
        t = re.sub(r'\*([^*]+)\*',     r'<i>\1</i>', t)
        t = re.sub(r'`([^`]+)`',       r'<code style="background:#f0f0f0;padding:1px 3px">\1</code>', t)
        t = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', t)
        return t

    for line in lines:
        # code fence
        if line.startswith('```'):
            if in_table:
                out.append(flush_table(table_buf)); table_buf = []; in_table = False
            if in_list_b: out.append('</ul>'); in_list_b = False
            if in_list_n: out.append('</ol>'); in_list_n = False
            if in_code:
                out.append('</pre>'); in_code = False
            else:
                out.append('<pre style="background:#f8f8f8;border:1px solid #ddd;padding:8px;font-size:9pt;white-space:pre-wrap">'); in_code = True
            continue

        if in_code:
            out.append(html.escape(line))
            continue

        # table row
        if line.startswith('|'):
            if in_list_b: out.append('</ul>'); in_list_b = False
            if in_list_n: out.append('</ol>'); in_list_n = False
            in_table = True
            table_buf.append(line)
            continue
        elif in_table:
            out.append(flush_table(table_buf)); table_buf = []; in_table = False

        # blank line
        if not line.strip():
            if in_list_b: out.append('</ul>'); in_list_b = False
            if in_list_n: out.append('</ol>'); in_list_n = False
            out.append('<br/>')
            continue

        # headings
        m = re.match(r'^(#{1,6})\s+(.+)', line)
        if m:
            if in_list_b: out.append('</ul>'); in_list_b = False
            if in_list_n: out.append('</ol>'); in_list_n = False
            lvl = len(m.group(1))
            sizes = {1:'18pt',2:'16pt',3:'14pt',4:'12pt',5:'11pt',6:'10pt'}
            colors = {1:'#1F3864',2:'#2E75B6',3:'#2E75B6',4:'#404040',5:'#404040',6:'#404040'}
            top_margin = '20pt' if lvl <= 2 else '12pt'
            out.append(f'<h{lvl} style="font-size:{sizes[lvl]};color:{colors[lvl]};margin-top:{top_margin};margin-bottom:4pt">{html.escape(m.group(2))}</h{lvl}>')
            continue

        # hr
        if re.match(r'^-{3,}$', line) or re.match(r'^\*{3,}$', line):
            if in_list_b: out.append('</ul>'); in_list_b = False
            if in_list_n: out.append('</ol>'); in_list_n = False
            out.append('<hr style="border:1px solid #ccc"/>')
            continue

        # bullet list
        m = re.match(r'^(\s*)[-*+]\s+(.+)', line)
        if m:
            if in_list_n: out.append('</ol>'); in_list_n = False
            if not in_list_b: out.append('<ul style="margin:4pt 0">'); in_list_b = True
            out.append(f'<li>{inline(m.group(2))}</li>')
            continue

        # numbered list
        m = re.match(r'^\d+\.\s+(.+)', line)
        if m:
            if in_list_b: out.append('</ul>'); in_list_b = False
            if not in_list_n: out.append('<ol style="margin:4pt 0">'); in_list_n = True
            out.append(f'<li>{inline(m.group(1))}</li>')
            continue

        # blockquote / normal paragraph
        if in_list_b: out.append('</ul>'); in_list_b = False
        if in_list_n: out.append('</ol>'); in_list_n = False
        text = re.sub(r'^>\s?', '', line)
        out.append(f'<p style="margin:4pt 0">{inline(text)}</p>')

    if in_table:
        out.append(flush_table(table_buf))
    if in_list_b: out.append('</ul>')
    if in_list_n: out.append('</ol>')
    if in_code:   out.append('</pre>')

    return '\n'.join(out)

with open(sys.argv[1], encoding='utf-8') as f:
    md = f.read()

body = md_to_html(md)

html_doc = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"/>
<style>
  body {{ font-family: Calibri, Arial, sans-serif; font-size: 11pt;
         max-width: 900px; margin: 40px auto; color: #222; line-height: 1.5; }}
  table {{ border-collapse: collapse; width: 100%; margin: 8pt 0; }}
  th, td {{ border: 1px solid #aaa; padding: 4px 8px; font-size: 10pt; text-align: left; }}
  th {{ background: #2E75B6; color: white; }}
  pre {{ background: #f8f8f8; border: 1px solid #ddd; padding: 8px;
         font-size: 9pt; white-space: pre-wrap; word-break: break-all; }}
  code {{ background: #f0f0f0; padding: 1px 3px; font-size: 9pt; }}
  h1 {{ page-break-before: auto; }}
</style>
</head>
<body>
{body}
</body>
</html>"""

with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write(html_doc)

print("HTML written to", sys.argv[2])
'@

$pyFile = [System.IO.Path]::GetTempFileName() + ".py"
Set-Content $pyFile $pythonScript -Encoding UTF8
python $pyFile $InputMd $HtmlFile
Remove-Item $pyFile -ErrorAction SilentlyContinue

if (-not (Test-Path $HtmlFile)) {
    Write-Error "HTML generation failed — aborting."
    exit 1
}

Write-Host "Step 2: Open HTML in Word and save as DOCX"

$word = New-Object -ComObject Word.Application
$word.Visible = $false

# Open HTML (Word can open HTML natively)
$doc = $word.Documents.Open($HtmlFile)

# Save as DOCX
$doc.SaveAs([ref]$OutputDocx, [ref]16)   # 16 = wdFormatDocumentDefault
$doc.Close($false)
$word.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null

Write-Host "Done. DOCX written to: $OutputDocx"
Write-Host "HTML intermediate kept at: $HtmlFile"
