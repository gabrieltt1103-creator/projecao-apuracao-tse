<#
  Simulacao de noites de apuracao reais, secao a secao, para testar o motor da projecao.
  Usa os boletins de urna do TSE (com o horario em que cada secao chegou) ja extraidos em %TEMP%\tse_bu.

  Uso:  powershell -ExecutionPolicy Bypass -File simular.ps1 -Noite 2022t2
        powershell -ExecutionPolicy Bypass -File simular.ps1 -Noite 2026t1
  ASCII de proposito. Atencao: no PowerShell nomes de variavel nao diferenciam maiusculas.
#>
param(
  [ValidateSet('2022t2', '2026t1')][string]$Noite = '2022t2',
  [string]$Conjunto = 'principal',
  [string]$Detalhe = '',
  [switch]$Painel,          # em vez da tabela, reproduz a noite no painel.html (demonstracao)
  [int]$PassoSeg = 6,
  [int]$PaiPid = 0,
  [string]$Pasta = (Join-Path $env:TEMP 'tse_bu')
)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'motor.cs') -ReferencedAssemblies System.IO.Compression, System.IO.Compression.FileSystem

$fracs = [double[]]@(0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 0.95, 0.98)
$sw = [Diagnostics.Stopwatch]::StartNew()

function Nova-Noite($atual, $numA, $numB, $baseSec, $baseA, $baseB, $outros) {
  $n = New-Object Apuracao.Noite
  $n.Atual = $atual; $n.NumA = $numA; $n.NumB = $numB
  if ($baseSec) { $n.BaseSec = $baseSec; $n.BaseA = $baseA; $n.BaseB = $baseB; $n.BaseOutros = [int[]]$outros }
  return $n
}

if ($Noite -eq '2022t2') {
  $atual = [Apuracao.Dados]::Ler((Join-Path $Pasta 'sec_2022_2t.csv'))
  $baseL = [Apuracao.Dados]::Ler((Join-Path $Pasta 'sec_2022_1t.csv'))
  $titulo = '2o turno de 2022 (Lula x Bolsonaro), base = 1o turno de 2022'
  $outros = @(15, 12)       # Tebet, Ciro
} else {
  $atual = New-Object 'System.Collections.Generic.List[Apuracao.Sec]'
  foreach ($p in 'a', 'b', 'c', 'd') { $atual.AddRange([Apuracao.Dados]::Ler((Join-Path $Pasta "sec_2026_1t_$p.csv"))) }
  $baseL = [Apuracao.Dados]::Ler((Join-Path $Pasta 'sec_2022_1t.csv'))
  $titulo = '1o turno de 2026 (Lula x Flavio, so os dois), base = 1o turno de 2022'
  $outros = @(15, 12)
}
$baseIdx = [Apuracao.Dados]::Indexar($baseL)
$noiteSec = Nova-Noite $atual 13 22 $baseIdx 13 22 $outros
$res = $noiteSec.Resumo()
Write-Host ""
Write-Host "=== $titulo ==="
Write-Host ("secoes: {0:N0} | A (13): {1:N0} | B (22): {2:N0} | % de A entre os dois: {3:N3}% | eleitorado com secao na base: {4:N1}% | sem horario: {5}" -f $res[0], $res[1], $res[2], (100 * $noiteSec.Verdade), (100 * $res[4]), $res[5])
if ($res[5] -lt $res[0]) { Write-Host ("chegada das secoes: de {0} a {1} | carga em {2:N0} s" -f [Apuracao.Dados]::Hora([long]$res[6]), [Apuracao.Dados]::Hora([long]$res[7]), $sw.Elapsed.TotalSeconds) }

if ($Painel) {
  # Demonstracao: reproduz a noite passo a passo, gravando painel_dados.js como a ferramenta ao vivo faria
  $nomes = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  try {
    $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers['User-Agent'] = 'Mozilla/5.0'
    $cfg = $wc.DownloadString('https://resultados.tse.jus.br/oficial/ele2026/6257/config/mun-e006257-cm.json') | ConvertFrom-Json
    foreach ($ab in $cfg.abr) { foreach ($mu in $ab.mu) { $nomes["$($ab.cd);$($mu.cd)"] = $mu.nm } }
  } catch { Write-Host "Nao consegui baixar os nomes dos municipios; o painel vai mostrar os codigos." }
  $passos = [double[]]@(0.01, 0.02, 0.03, 0.05, 0.07, 0.10, 0.13, 0.16, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.94, 0.97, 0.99, 0.999)
  Write-Host "Calculando a noite em $($passos.Count) passos (por zona e por UF)..."
  $ptsZ = $noiteSec.Rodar('zona', $true, (New-Object Apuracao.Opcoes), 0.0, 300000.0, $passos)
  $ptsU = $noiteSec.Rodar('uf', $true, (New-Object Apuracao.Opcoes), 0.0, 300000.0, $passos)
  # quadro de validos, brancos/nulos e abstencao do painel: acumulado das secoes na ordem em que chegaram, em cada passo
  $nSec = $atual.Count; $chegada = New-Object 'long[]' $nSec; $ordemSec = New-Object 'int[]' $nSec
  for ($k = 0; $k -lt $nSec; $k++) { $chegada[$k] = $atual[$k].T; $ordemSec[$k] = $k }
  [Array]::Sort($chegada, $ordemSec)
  $acumExtras = New-Object 'System.Collections.Generic.List[double[]]'; $ponteiro = 0; $somaAptos = 0.0; $somaComp = 0.0; $somaBrancos = 0.0; $somaNulos = 0.0; $somaValidos = 0.0
  foreach ($pz in $ptsZ) {
    while ($ponteiro -lt $nSec -and $chegada[$ponteiro] -le $pz.T) { $sec = $atual[$ordemSec[$ponteiro]]; $somaAptos += $sec.Aptos; $somaComp += $sec.Comp; $somaBrancos += $sec.Brancos; $somaNulos += $sec.Nulos; $somaValidos += $sec.Validos(); $ponteiro++ }
    $acumExtras.Add([double[]]@($somaComp, ($somaAptos - $somaComp), $somaBrancos, $somaNulos, $somaValidos))
  }
  $nomeA = 'LULA'; $nomeB = 'FLAVIO BOLSONARO'; if ($Noite -eq '2022t2') { $nomeB = 'JAIR BOLSONARO' }
  $arqDados = Join-Path $PSScriptRoot 'painel_dados.js'; $inv = [Globalization.CultureInfo]::InvariantCulture
  $hist = New-Object 'System.Collections.Generic.List[string[]]'
  Write-Host "Demonstracao rodando: um passo a cada $PassoSeg s, em ciclo. Feche esta janela para parar."
  while ($true) {
    $hist.Clear()
    for ($i = 0; $i -lt $ptsZ.Count; $i++) {
      $pz = $ptsZ[$i]; $pu = $ptsU[$i]; $hora = [Apuracao.Dados]::Hora($pz.T)
      $hist.Add([string[]]@($hora.Substring(6, 5), (100 * $pz.R.PctEle).ToString('R', $inv), (100 * $pz.R.Parcial).ToString('R', $inv), (100 * $pz.R.Share).ToString('R', $inv), (100 * $pz.R.Lo).ToString('R', $inv), (100 * $pz.R.Hi).ToString('R', $inv), (100 * $pu.R.Share).ToString('R', $inv), (100 * $pz.R.PA50).ToString('R', $inv), (100 * $pz.Q).ToString('R', $inv)))
      $meta = New-Object 'System.Collections.Generic.Dictionary[string,string]'
      $meta['cargo'] = 'presidente'; $meta['uf'] = ''; $meta['modo'] = 'demo'; $meta['noite'] = $Noite; $meta['estado'] = 'ok'; $meta['nivel'] = 'zona'
      $meta['gerado'] = (Get-Date).ToString('s'); $meta['dadosAte'] = $hora; $meta['loopMin'] = '0'; $meta['proxima'] = (Get-Date).AddSeconds($PassoSeg).ToString('s'); $meta['passo'] = "$($i + 1)/$($ptsZ.Count)"
      $ext = $acumExtras[$i]; $meta['comp'] = $ext[0].ToString('R', $inv); $meta['abst'] = $ext[1].ToString('R', $inv); $meta['brancos'] = $ext[2].ToString('R', $inv); $meta['nulos'] = $ext[3].ToString('R', $inv); $meta['validos'] = $ext[4].ToString('R', $inv)
      $erro = [double]::NaN; if ($i -gt 0) { $erro = $pz.ErroDeriva }
      $qual = [double[]]@($pz.Q, ($pz.R.PctSec * $res[0]), $res[0], 0.0, $erro, 0.0, 0.0, 0.0, 0.0)
      $json = [Apuracao.Painel]::Json($pz.Us, $pz.R, $pu.R, $nomes, $meta, 13, $nomeA, 22, $nomeB, $qual, [string[]]@(), $hist)
      [IO.File]::WriteAllText($arqDados, 'window.receberPainel(' + $json + ');', (New-Object Text.UTF8Encoding($false)))
      Write-Host ("  passo {0,2}/{1}: {2,5:N1}% apurado, projecao de {3} {4:N2}%" -f ($i + 1), $ptsZ.Count, (100 * $pz.R.PctEle), $nomeA, (100 * $pz.R.Share))
      if ($PaiPid -gt 0 -and -not (Get-Process -Id $PaiPid -ErrorAction SilentlyContinue)) { return }
      Start-Sleep -Seconds $PassoSeg
    }
    Start-Sleep -Seconds 15
  }
}

function Opc([hashtable]$h) { $o = New-Object Apuracao.Opcoes; foreach ($k in $h.Keys) { $o.$k = $h[$k] }; return $o }

# variante: nome, nivel, modoSecao, opcoes, lambdaD
$V = New-Object System.Collections.ArrayList
function Variante($nome, $nivel, $modoSecao, $op, $lamD, $lag = 0.0) { [void]$V.Add(@{ nome = $nome; nivel = $nivel; sec = $modoSecao; op = $op; lamD = $lamD; lag = $lag }) }

$semSecao = @{ SigmaSec = 0.08 }
$cov = @{ UsaOutros = $true; UsaTamanho = $true }
if ($Conjunto -eq 'principal') {
  Variante 'municipio, sem saber as secoes (1o turno)' 'mun'  $false (Opc $semSecao) 0.0
  Variante 'zona, sem saber as secoes'                'zona' $false (Opc $semSecao) 0.0
  Variante 'zona + covariaveis'                       'zona' $false (Opc @{ SigmaSec = 0.08; UsaOutros = $true; UsaTamanho = $true }) 0.0
  Variante 'zona + covariaveis + correcoes'           'zona' $false (Opc @{ SigmaSec = 0.08; UsaOutros = $true; UsaTamanho = $true; LambdaB = 1.0 }) 1.0
  Variante 'SECOES casadas, por UF (rapida)'          'uf'   $true  (Opc @{}) 0.0
  Variante 'SECOES casadas, por municipio'            'mun'  $true  (Opc @{}) 0.0
  Variante 'SECOES casadas, por zona (PADRAO)'        'zona' $true  (Opc @{}) 0.0
  Variante 'SECOES casadas, zona + covariaveis'       'zona' $true  (Opc $cov) 0.0
  Variante 'SECOES casadas, zona + correcoes'         'zona' $true  (Opc @{ LambdaB = 1.0 }) 1.0
} elseif ($Conjunto -eq 'robustez') {
  $s = @{ UsaOutros = $false; UsaTamanho = $false; LambdaB = 0.0; SigmaSec = 0.03 }
  Variante 'secao/zona, marcacao exata'          'zona' $true (Opc $s) 0.0
  Variante 'secao/zona, marcacao 2 min atrasada' 'zona' $true (Opc $s) 0.0 120.0
  Variante 'secao/zona, marcacao 5 min atrasada' 'zona' $true (Opc $s) 0.0 300.0
  Variante 'secao/zona, marcacao 15 min atrasada' 'zona' $true (Opc $s) 0.0 900.0
  Variante 'secao/zona, marcacao 30 min atrasada' 'zona' $true (Opc $s) 0.0 1800.0
  Variante 'secao/zona, marcacao 5 min adiantada' 'zona' $true (Opc $s) 0.0 -300.0
  Variante 'secao/zona, marcacao 15 min adiantada' 'zona' $true (Opc $s) 0.0 -900.0
  Variante 'secao/municipio, exata'              'mun'  $true (Opc $s) 0.0
  Variante 'secao/UF, exata'                     'uf'   $true (Opc $s) 0.0
  Variante 'secao/UF, 5 min atrasada'            'uf'   $true (Opc $s) 0.0 300.0
  Variante 'sem marcacao nenhuma (zona)'         'zona' $false (Opc @{ UsaOutros = $false; UsaTamanho = $false; LambdaB = 0.0 }) 0.0
} elseif ($Conjunto -eq 'kappa') {
  foreach ($s in 0.005, 0.01, 0.02, 0.03, 0.05, 0.08, 0.15) { Variante ("secao/zona sigmaSec={0}" -f $s) 'zona' $true (Opc @{ UsaOutros = $false; UsaTamanho = $false; LambdaB = 0.0; SigmaSec = $s }) 0.0 }
  foreach ($k in 0.5, 2.0, 8.0, 30.0, 100.0) { Variante ("secao/zona kappa fixo={0}" -f $k) 'zona' $true (Opc @{ UsaOutros = $false; UsaTamanho = $false; LambdaB = 0.0; Kappa = $k }) 0.0 }
} elseif ($Conjunto -eq 'ajuste') {
  Variante 'secao/zona padrao'                 'zona' $true (Opc @{ SigmaSec = 0.03 }) 1.0
  Variante 'secao/zona peso raiz'              'zona' $true (Opc @{ SigmaSec = 0.03; PesoExp = 0.5 }) 1.0
  Variante 'secao/zona sem inclinacao por UF'  'zona' $true (Opc @{ SigmaSec = 0.03; InclUf = $false }) 1.0
  Variante 'secao/zona sem tamanho'            'zona' $true (Opc @{ SigmaSec = 0.03; UsaTamanho = $false }) 1.0
  Variante 'secao/zona sem outros'             'zona' $true (Opc @{ SigmaSec = 0.03; UsaOutros = $false }) 1.0
  Variante 'secao/zona vies 0,5'               'zona' $true (Opc @{ SigmaSec = 0.03; LambdaB = 0.5 }) 1.0
  Variante 'secao/zona deriva 0,5'             'zona' $true (Opc @{ SigmaSec = 0.03 }) 0.5
  Variante 'secao/zona ridge 50'               'zona' $true (Opc @{ SigmaSec = 0.03; Ridge = 50.0 }) 1.0
  Variante 'secao/municipio padrao'            'mun'  $true (Opc @{ SigmaSec = 0.03 }) 1.0
}

Write-Host ""
Write-Host ("erro da projecao em pontos percentuais (projetado - real), por % do eleitorado ja apurado")
$cab = "{0,-42}" -f 'variante'; foreach ($f in $fracs) { $cab += "{0,7}" -f ("{0:N0}%" -f (100 * $f)) }; $cab += "   EAM  cob"
Write-Host $cab
$linhas = @(); $primeiro = $null
foreach ($v in $V) {
  $noiteSec.LagCs = $v.lag; $pts = $noiteSec.Rodar($v.nivel, $v.sec, $v.op, $v.lamD, 300000.0, $fracs)
  if (-not $primeiro) { $primeiro = $pts }
  $ln = "{0,-42}" -f $v.nome; $soma = 0.0; $n = 0; $cob = 0
  foreach ($p in $pts) {
    $e = 100 * ($p.R.Share - $p.Verdade); $ln += "{0,7:+0.00;-0.00}" -f $e
    if ($p.Frac -ge 0.05) { $soma += [Math]::Abs($e); $n++ }
    if ($p.Verdade -ge $p.R.Lo -and $p.Verdade -le $p.R.Hi) { $cob++ }
  }
  $ln += "  {0,5:N2} {1,2}/{2}" -f ($soma / $n), $cob, $pts.Count
  Write-Host $ln
  $linhas += @{ v = $v; pts = $pts }
}
# referencias sem modelo
$ln = "{0,-42}" -f 'parcial (o que o placar mostra)'; $s = 0.0; $n = 0; foreach ($p in $primeiro) { $e = 100 * ($p.R.Parcial - $p.Verdade); $ln += "{0,7:+0.00;-0.00}" -f $e; if ($p.Frac -ge 0.05) { $s += [Math]::Abs($e); $n++ } }; Write-Host ($ln + ("  {0,5:N2}" -f ($s / $n)))
$ln = "{0,-42}" -f 'extrapolacao simples por UF'; $s = 0.0; $n = 0; foreach ($p in $primeiro) { $e = 100 * ($p.Simples - $p.Verdade); $ln += "{0,7:+0.00;-0.00}" -f $e; if ($p.Frac -ge 0.05) { $s += [Math]::Abs($e); $n++ } }; Write-Host ($ln + ("  {0,5:N2}" -f ($s / $n)))
$ln = "{0,-42}" -f 'horario'; foreach ($p in $primeiro) { $ln += "{0,7}" -f ([Apuracao.Dados]::Hora($p.T).Substring(6, 5)) }; Write-Host $ln

Write-Host ""
Write-Host "detalhe da ultima variante (meia-largura do intervalo de 95%, vies temporal medido, deriva acumulada, erro por unidade)"
$esc = $linhas[-1]; if ($Detalhe) { $achou = @($linhas | Where-Object { $_.v.nome -like "*$Detalhe*" }); if ($achou.Count -gt 0) { $esc = $achou[0] } }; Write-Host ("  -> " + $esc.v.nome); $ult = $esc.pts
foreach ($p in $ult) { Write-Host ("  {0,4:N0}%  proj {1:N3}%  erro {12,6:+0.00;-0.00}  IC +-{4:N2} [{2:N2} ; {3:N2}]  casamento {13,5:N1}%  vies {5,6:+0.00;-0.00}  erro no que chegou {6,6:+0.00;-0.00}  sigmaUnid {7:N2}  kappa {8,5:N1}  completas {10,5}  P(A>50%) {11:N1}%" -f (100 * $p.Frac), (100 * $p.R.Share), (100 * $p.R.Lo), (100 * $p.R.Hi), (50 * ($p.R.Hi - $p.R.Lo)), (100 * $p.R.VB), (100 * $p.ErroDeriva), (100 * $p.R.SigmaUnid), $p.R.Kappa, $p.R.NTreino, $p.R.NCompletas, (100 * $p.R.PA50), (100 * ($p.R.Share - $p.Verdade)), (100 * $p.Q)) }
Write-Host ("tempo total: {0:N0} s" -f $sw.Elapsed.TotalSeconds)
