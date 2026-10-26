<#
  Reproduz os numeros, tabelas e figuras do artigo a partir das simulacoes e do registro da noite de 25/10/2026.
  Requer: preparar_simulacoes.ps1 ja rodado, Python 3 e a base do 1o turno de 2026 (projecao2.ps1 -Preparar).
  Saida: pasta saida\ com as tabelas das simulacoes, as metricas da noite e artigo.html (e artigo.pdf com -Pdf).

  Uso:  powershell -ExecutionPolicy Bypass -File reproduzir_artigo.ps1 [-Pdf] [-Base caminho\base_secoes_presidente_1t.csv]
  ASCII de proposito (PowerShell 5.1).
#>
param([switch]$Pdf, [string]$Base = (Join-Path $PSScriptRoot 'cache\base_secoes_presidente_1t.csv'))
$ErrorActionPreference = 'Stop'
$R = $PSScriptRoot; $Saida = Join-Path $R 'saida'
New-Item -ItemType Directory -Force $Saida | Out-Null
if (-not (Test-Path $Base)) { throw "Falta a base do 1o turno ($Base). Rode antes: projecao2.ps1 -Preparar" }
$sim = Join-Path $R 'simular.ps1'
$pol = Get-ExecutionPolicy   # cada simulacao roda em um processo proprio (o motor e compilado uma vez por processo), com a mesma politica desta chamada

Write-Host '1/4 reconstituicao do 2o turno de 2022'
& powershell -NoProfile -ExecutionPolicy $pol -File $sim -Noite 2022t2 -Conjunto principal -Detalhe PADRAO *> (Join-Path $Saida 'det_2022t2.txt')
Write-Host '2/4 reconstituicao do 1o turno de 2026'
& powershell -NoProfile -ExecutionPolicy $pol -File $sim -Noite 2026t1 -Conjunto principal -Detalhe PADRAO *> (Join-Path $Saida 'det_2026t1.txt')
Write-Host '3/4 sensibilidade ao atraso da relacao de secoes'
& powershell -NoProfile -ExecutionPolicy $pol -File $sim -Noite 2022t2 -Conjunto robustez *> (Join-Path $Saida 'sim_2022t2_robustez.txt')
Write-Host '4/4 metricas da noite ao vivo e artigo'
& python -I (Join-Path $R 'artigo\noite_ao_vivo.py') (Join-Path $R 'dados\historico2_presidente.csv') (Join-Path $Saida 'noite_ao_vivo.json')
if ($LASTEXITCODE -ne 0) { throw 'noite_ao_vivo.py falhou' }
& python -I (Join-Path $R 'artigo\paper.py') $Saida (Join-Path $Saida 'noite_ao_vivo.json') $Base (Join-Path $R 'dados\r2_presidente_zonas.csv') (Join-Path $R 'dados\historico2_presidente.csv') (Join-Path $Saida 'artigo.html')
if ($LASTEXITCODE -ne 0) { throw 'paper.py falhou' }

if ($Pdf) {
  $edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
  if (-not (Test-Path $edge)) { Write-Host 'Edge nao encontrado: abra saida\artigo.html no navegador e imprima em PDF (A4).'; return }
  $url = 'file:///' + ((Join-Path $Saida 'artigo.html') -replace '\\', '/')
  & $edge --headless --disable-gpu --no-pdf-header-footer --virtual-time-budget=10000 ("--user-data-dir=" + (Join-Path $Saida 'edge_perfil')) ("--print-to-pdf=" + (Join-Path $Saida 'artigo.pdf')) $url 2>$null | Out-Null
}
Write-Host "Pronto: $Saida"
