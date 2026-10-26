<#
  Prepara os arquivos de secoes usados por simular.ps1, em %TEMP%\tse_bu:
    sec_2022_1t.csv e sec_2022_2t.csv   boletins de urna de 2022 (Portal de Dados Abertos do TSE)
    sec_2026_1t_a.csv (b, c, d vazios)  copia de cache\base_secoes_presidente_1t.csv, gerada por projecao2.ps1 -Preparar

  Uso:  powershell -ExecutionPolicy Bypass -File preparar_simulacoes.ps1 -SoListar   # mostra o que seria baixado
        powershell -ExecutionPolicy Bypass -File preparar_simulacoes.ps1             # baixa e extrai (alguns GB na primeira vez)
  ASCII de proposito (PowerShell 5.1).
#>
param([switch]$SoListar)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -Path (Join-Path $PSScriptRoot 'motor.cs') -ReferencedAssemblies System.IO.Compression, System.IO.Compression.FileSystem
$UA = 'Mozilla/5.0 (projecao-apuracao; uso pessoal)'
$Pasta = Join-Path $env:TEMP 'tse_bu'
New-Item -ItemType Directory -Force $Pasta | Out-Null

function Links([string]$pacote, [string]$turno) {
  $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = $UA; $wc.Encoding = [Text.Encoding]::UTF8
  $j = $wc.DownloadString("https://dadosabertos.tse.jus.br/api/3/action/package_show?id=$pacote") | ConvertFrom-Json
  return @($j.result.resources | ForEach-Object { $_.url } | Where-Object { $_ -match "bweb_${turno}_\w\w_\d+\.zip$" } | Sort-Object -Unique)
}

# baixa os boletins de urna de um turno (um arquivo por UF) e extrai uma linha por secao, so do cargo de presidente
function Montar([string]$pacote, [string]$turno, [string]$saida) {
  $dest = Join-Path $Pasta $saida
  $links = Links $pacote $turno
  Write-Host ("{0}: {1} arquivos de boletins de urna ({2})" -f $saida, $links.Count, $turno)
  if ($SoListar) { $links | Select-Object -First 3 | ForEach-Object { Write-Host "   $_" }; return }
  if (Test-Path $dest) { Write-Host "   ja existe, mantido"; return }
  if ($links.Count -eq 0) { throw "Nao achei os boletins de urna ($pacote, $turno)." }
  $sub = Join-Path $Pasta ($saida -replace '\.csv$', '_zip'); New-Item -ItemType Directory -Force $sub | Out-Null
  $tmp = "$dest.tmp"; if (Test-Path $tmp) { Remove-Item $tmp -Confirm:$false }
  foreach ($link in $links) {
    $arq = Join-Path $sub (Split-Path $link -Leaf)
    if (-not (Test-Path $arq)) {
      Write-Host ("   baixando " + (Split-Path $link -Leaf))
      & curl.exe -sS -L --retry 6 --retry-delay 5 -A $UA -o $arq $link
      if ($LASTEXITCODE -ne 0) { throw "curl falhou ($LASTEXITCODE) em $link" }
    }
    Write-Host ("   " + [Apuracao.Extrator]::Extrair($arq, $tmp, 'Presidente', $true))
  }
  Move-Item $tmp $dest
}

Montar 'resultados-2022-boletim-de-urna' '1t' 'sec_2022_1t.csv'
Montar 'resultados-2022-boletim-de-urna' '2t' 'sec_2022_2t.csv'

$base = Join-Path $PSScriptRoot 'cache\base_secoes_presidente_1t.csv'
if ($SoListar) { Write-Host ("sec_2026_1t_a.csv: copia de {0} ({1})" -f $base, $(if (Test-Path $base) { 'existe' } else { 'falta: rode projecao2.ps1 -Preparar' })); return }
if (-not (Test-Path $base)) { throw "Falta $base. Rode antes: powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Preparar" }
Copy-Item $base (Join-Path $Pasta 'sec_2026_1t_a.csv') -Force
foreach ($k in 'b', 'c', 'd') { $v = Join-Path $Pasta "sec_2026_1t_$k.csv"; if (-not (Test-Path $v)) { New-Item -ItemType File $v | Out-Null } }
Write-Host "Pronto: arquivos em $Pasta"
