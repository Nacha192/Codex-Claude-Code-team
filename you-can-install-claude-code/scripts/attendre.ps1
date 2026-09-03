<#
  attendre.ps1 - surveiller sans bloquer betement.

  Sert a celui des deux agents qui n a pas de taches en arriere-plan. Au lieu
  de dormir en boucle, on surveille le disque et on rend la main des que
  quelque chose bouge, ou au bout du delai.

    .\attendre.ps1 -Chemin .duo\pour-claude -Delai 600
    .\attendre.ps1 -Chemin .duo\echanges -Motif "*-codex-*.md" -Delai 900

  Code de sortie : 0 quelque chose est arrive, 1 delai depasse, 2 chemin absent.
  Sur la sortie standard : le chemin du fichier apparu, rien d autre, pour que
  l appelant puisse l enchainer directement.
#>
param(
  [Parameter(Mandatory=$true)][string]$Chemin,
  [string]$Motif = '*',
  [ValidateRange(0, 86400)][int]$Delai = 600,
  [ValidateRange(1, 60)][int]$Pas = 3
)

if (-not (Test-Path -LiteralPath $Chemin -PathType Container)) { Write-Error 'chemin absent'; exit 2 }

# On photographie l existant : on ne veut etre reveille que par du NOUVEAU.
$connus = @{}
Get-ChildItem -LiteralPath $Chemin -Filter $Motif -File -ErrorAction SilentlyContinue |
  ForEach-Object { $connus[$_.FullName] = $_.LastWriteTimeUtc }

$chrono = [Diagnostics.Stopwatch]::StartNew()
while ($chrono.Elapsed.TotalSeconds -lt $Delai) {
  $nouveaux = Get-ChildItem -LiteralPath $Chemin -Filter $Motif -File -ErrorAction SilentlyContinue |
    Where-Object { -not $connus.ContainsKey($_.FullName) -or $connus[$_.FullName] -ne $_.LastWriteTimeUtc }
  if ($nouveaux) {
    # Un fichier peut etre en cours d ecriture : on laisse la taille se stabiliser
    # avant de rendre la main, sinon on lit la moitie d une reponse.
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
Write-Error "rien de nouveau dans $Chemin apres $Delai s"
exit 1
