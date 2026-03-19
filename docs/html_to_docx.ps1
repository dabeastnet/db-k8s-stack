param(
    [string]$HtmlFile   = "$PSScriptRoot\..\repository_documentation.html",
    [string]$OutputDocx = "$PSScriptRoot\..\repository_documentation.docx"
)
$HtmlFile   = (Resolve-Path $HtmlFile).Path
$OutputDocx = [System.IO.Path]::GetFullPath($OutputDocx)

Write-Host "Opening $HtmlFile in Word..."
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Open($HtmlFile)
Write-Host "Saving as $OutputDocx ..."
$doc.SaveAs([ref]$OutputDocx, [ref]16)
$doc.Close($false)
$word.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
Write-Host "Done: $OutputDocx"
