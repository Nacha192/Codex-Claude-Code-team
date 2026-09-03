<#
  attendre.ps1 - watch for changes without pointless blocking.

  For whichever agent lacks background tasks. Instead of repeatedly sleeping,
  watch the disk and return control as soon as something changes or the
  timeout expires.

    .\attendre.ps1 -Chemin .duo\pour-claude -Delai 600
    .\attendre.ps1 -Chemin .duo\echanges -Motif "*-codex-*.md" -Delai 900

  Exit codes: 0 something arrived, 1 timeout, 2 missing path.
  Standard output contains only the new file's path, so the caller can
  pass it directly to the next step.
#>
param(
  [Parameter(Mandatory=$true)][string]$Chemin,
  [string]$Motif = '*',
  [ValidateRange(0, 86400)][int]$Delai = 600,
  [ValidateRange(1, 60)][int]$Pas = 3
)

if (-not (Test-Path -LiteralPath $Chemin -PathType Container)) { Write-Error 'path not found'; exit 2 }

# Snapshot existing files: only NEW activity should wake us.
$connus = @{}
Get-ChildItem -LiteralPath $Chemin -Filter $Motif -File -ErrorAction SilentlyContinue |
  ForEach-Object { $connus[$_.FullName] = $_.LastWriteTimeUtc }

$chrono = [Diagnostics.Stopwatch]::StartNew()
while ($chrono.Elapsed.TotalSeconds -lt $Delai) {
  $nouveaux = Get-ChildItem -LiteralPath $Chemin -Filter $Motif -File -ErrorAction SilentlyContinue |
    Where-Object { -not $connus.ContainsKey($_.FullName) -or $connus[$_.FullName] -ne $_.LastWriteTimeUtc }
  if ($nouveaux) {
    # A file may still be being written: wait for its size to stabilize
    # before returning, so we do not read half a response.
    $cible = $nouveaux | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    while ($chrono.Elapsed.TotalSeconds -lt $Delai) {
      $taille = $cible.Length
      $modifie = $cible.LastWriteTimeUtc
      $reste = ($Delai - $chrono.Elapsed.TotalSeconds) * 1000
      Start-Sleep -Milliseconds ([int][Math]::Max(1, [Math]::Min(700, $reste)))
      $cible.Refresh()
      if (-not $cible.Exists) { break }
      if ($chrono.Elapsed.TotalSeconds -ge $Delai) { break }
      if ($taille -eq $cible.Length -and $modifie -eq $cible.LastWriteTimeUtc) {
        Write-Output $cible.FullName
        exit 0
      }
    }
  }
  $reste = ($Delai - $chrono.Elapsed.TotalSeconds) * 1000
  if ($reste -gt 0) {
    Start-Sleep -Milliseconds ([int][Math]::Max(1, [Math]::Min($Pas * 1000, $reste)))
  }
}
Write-Error "nothing new in $Chemin after $Delai s"
exit 1
