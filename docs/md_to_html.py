"""Convert repository_documentation.md to a styled HTML file for Word import."""
import sys
import re
import html as html_mod

def inline(t):
    t = html_mod.escape(t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', t)
    t = re.sub(r'\*([^*]+)\*',     r'<i>\1</i>', t)
    t = re.sub(r'`([^`]+)`',       r'<code>\1</code>', t)
    t = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', t)
    return t

def flush_table(buf):
    rows = [r for r in buf if not re.match(r'^\s*\|[\s\-:|]+\|\s*$', r)]
    if not rows:
        return ''
    out = ['<table>']
    for i, row in enumerate(rows):
        cells = [c.strip() for c in row.split('|') if c.strip()]
        tag = 'th' if i == 0 else 'td'
        out.append('<tr>' + ''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells) + '</tr>')
    out.append('</table>')
    return '\n'.join(out)

def convert(src):
    lines = src.split('\n')
    out = []
    in_code = in_list_b = in_list_n = in_table = False
    table_buf = []

    def close_lists():
        nonlocal in_list_b, in_list_n
        if in_list_b:
            out.append('</ul>'); in_list_b = False
        if in_list_n:
            out.append('</ol>'); in_list_n = False

    for line in lines:
        # code fence
        if line.startswith('```'):
            close_lists()
            if in_table:
                out.append(flush_table(table_buf)); table_buf = []; in_table = False
            if in_code:
                out.append('</pre>'); in_code = False
            else:
                out.append('<pre>'); in_code = True
            continue

        if in_code:
            out.append(html_mod.escape(line))
            continue

        # table row
        if line.startswith('|'):
            close_lists()
            in_table = True
            table_buf.append(line)
            continue
        elif in_table:
            out.append(flush_table(table_buf)); table_buf = []; in_table = False

        # blank line
        if not line.strip():
            close_lists()
            out.append('<p>&nbsp;</p>')
            continue

        # headings
        m = re.match(r'^(#{1,6})\s+(.+)', line)
        if m:
            close_lists()
            lvl = len(m.group(1))
            out.append(f'<h{lvl}>{html_mod.escape(m.group(2))}</h{lvl}>')
            continue

        # hr
        if re.match(r'^-{3,}$', line) or re.match(r'^\*{3,}$', line):
            close_lists()
            out.append('<hr/>')
            continue

        # bullet list
        m = re.match(r'^\s*[-*+]\s+(.+)', line)
        if m:
            if in_list_n:
                out.append('</ol>'); in_list_n = False
            if not in_list_b:
                out.append('<ul>'); in_list_b = True
            out.append(f'<li>{inline(m.group(1))}</li>')
            continue

        # numbered list
        m = re.match(r'^\d+\.\s+(.+)', line)
        if m:
            if in_list_b:
                out.append('</ul>'); in_list_b = False
            if not in_list_n:
                out.append('<ol>'); in_list_n = True
            out.append(f'<li>{inline(m.group(1))}</li>')
            continue

        # normal paragraph
        close_lists()
        text = re.sub(r'^>\s?', '', line)
        out.append(f'<p>{inline(text)}</p>')

    if in_table:
        out.append(flush_table(table_buf))
    if in_list_b:
        out.append('</ul>')
    if in_list_n:
        out.append('</ol>')
    if in_code:
        out.append('</pre>')

    return '\n'.join(out)


CSS = """
body {
  font-family: Calibri, Arial, sans-serif;
  font-size: 11pt;
  color: #222;
  line-height: 1.5;
  margin: 40px 60px;
}
h1 { font-size: 18pt; color: #1F3864; margin-top: 24pt; margin-bottom: 6pt; }
h2 { font-size: 15pt; color: #2E75B6; margin-top: 18pt; margin-bottom: 4pt; }
h3 { font-size: 13pt; color: #2E75B6; margin-top: 14pt; margin-bottom: 4pt; }
h4, h5, h6 { font-size: 11pt; color: #404040; margin-top: 10pt; margin-bottom: 2pt; font-weight: bold; }
p  { margin: 4pt 0; }
pre {
  background: #f5f5f5;
  border: 1px solid #ddd;
  padding: 8px 10px;
  font-family: Courier New, monospace;
  font-size: 9pt;
  white-space: pre-wrap;
  word-break: break-all;
  margin: 6pt 0;
}
code {
  font-family: Courier New, monospace;
  font-size: 9pt;
  background: #f0f0f0;
  padding: 1px 3px;
}
table {
  border-collapse: collapse;
  width: 100%;
  margin: 8pt 0;
  font-size: 10pt;
}
th {
  background: #2E75B6;
  color: white;
  font-weight: bold;
  padding: 4px 8px;
  border: 1px solid #999;
  text-align: left;
}
td {
  padding: 3px 8px;
  border: 1px solid #bbb;
  vertical-align: top;
}
tr:nth-child(even) td { background: #f2f7fc; }
ul, ol { margin: 4pt 0 4pt 24pt; padding: 0; }
li { margin: 2pt 0; }
hr { border: 0; border-top: 1px solid #ccc; margin: 12pt 0; }
"""

with open(sys.argv[1], encoding='utf-8') as f:
    md = f.read()

body = convert(md)

doc = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"/>
<style>{CSS}</style>
</head>
<body>
{body}
</body>
</html>"""

with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write(doc)

print(f"HTML written to {sys.argv[2]}")
