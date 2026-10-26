<#
  Projecao do 2o turno de 2026 com a apuracao em andamento (presidente ou governador), dados oficiais do TSE.

  Ideia central (testada em simular.ps1 nas noites do 2o turno de 2022 e do 1o turno de 2026):
  o TSE publica, por UF, um arquivo que diz quais secoes ja chegaram. Sabendo quais secoes entraram em cada zona,
  compara-se o voto delas agora com o voto DELAS MESMAS no 1o turno, e aplica-se essa variacao as secoes que faltam.

  Uso na noite:
      powershell -ExecutionPolicy Bypass -File projecao2.ps1                       # presidente, uma rodada
      powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Loop 5               # repete a cada 5 minutos
      powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Rapido               # so a projecao rapida (56 arquivos)
      powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Cargo governador -UF rj
  Antes da noite:
      powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Checar               # o TSE ja publicou o 2o turno?
      powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Ensaio               # roda tudo contra o 1o turno

  ASCII de proposito (PowerShell 5.1). Atencao: nomes de variavel nao diferenciam maiusculas.
#>
param(
  [ValidateSet('presidente', 'governador')][string]$Cargo = 'presidente',
  [string]$UF = '',
  [switch]$Ensaio,
  [switch]$Checar,
  [switch]$Preparar,
  [switch]$Rapido,
  [int]$Loop = 0,
  [int]$Concorrencia = 8,
  [int]$PausaMs = 120,
  [int]$PrazoDownload = 300,
  [string]$Eleicao = '',
  [string]$Pleito = '',
  [int]$PaiPid = 0          # usado pelo painel.ps1: encerra a coleta se a janela do painel for fechada
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Concorrencia = [Math]::Max(1, [Math]::Min($Concorrencia, 8))
[Net.ServicePointManager]::DefaultConnectionLimit = $Concorrencia + 2
Add-Type -Path (Join-Path $PSScriptRoot 'motor.cs') -ReferencedAssemblies System.IO.Compression, System.IO.Compression.FileSystem

$Raiz = $PSScriptRoot
$Cache = Join-Path $Raiz 'cache'; $Hist = Join-Path $Raiz 'historico'
foreach ($pasta in $Cache, $Hist) { if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta | Out-Null } }
$UA = 'Mozilla/5.0 (projecao-apuracao; uso pessoal)'
$HostTse = 'https://resultados.tse.jus.br/oficial'
$inv = [Globalization.CultureInfo]::InvariantCulture
$UF = $UF.ToLower()
if ($Cargo -eq 'governador' -and -not $UF) { throw "Para governador informe a UF, por exemplo: -Cargo governador -UF rj" }
$cargoCod = @{ presidente = '1'; governador = '3' }[$Cargo]
$cargo4 = $cargoCod.PadLeft(4, '0')
$cargoNome = @{ presidente = 'Presidente'; governador = 'Governador' }[$Cargo]
$tag = $Cargo; if ($Cargo -eq 'governador') { $tag = "governador_$UF" }
$tagRodada = $tag; if ($Ensaio) { $tagRodada = "${tag}_ensaio" }
$Regiao = @{ ac = 'Norte'; am = 'Norte'; ap = 'Norte'; pa = 'Norte'; ro = 'Norte'; rr = 'Norte'; to = 'Norte'; al = 'Nordeste'; ba = 'Nordeste'; ce = 'Nordeste'; ma = 'Nordeste'; pb = 'Nordeste'; pe = 'Nordeste'; pi = 'Nordeste'; rn = 'Nordeste'; se = 'Nordeste'; es = 'Sudeste'; mg = 'Sudeste'; rj = 'Sudeste'; sp = 'Sudeste'; pr = 'Sul'; rs = 'Sul'; sc = 'Sul'; df = 'Centro-Oeste'; go = 'Centro-Oeste'; ms = 'Centro-Oeste'; mt = 'Centro-Oeste'; zz = 'Exterior' }

function Pc($x) { return ('{0:N2}%' -f (100 * $x)) }
function Pp($x) { return ('{0:+0.00;-0.00;0.00}' -f (100 * $x)) }
function Curto([string]$s, [int]$n) { if ($s.Length -gt $n) { return $s.Substring(0, $n) }; return $s }

function Baixar-Texto([string]$url, [int]$maxTent = 4) {
  for ($tent = 1; $tent -le $maxTent; $tent++) {
    $resp = $null
    try {
      $rq = [Net.HttpWebRequest]::Create($url)
      $rq.UserAgent = $UA; $rq.Timeout = 20000; $rq.ReadWriteTimeout = 20000
      $rq.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
      $resp = $rq.GetResponse()
      $leitor = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
      $txt = $leitor.ReadToEnd(); $leitor.Close(); $resp.Close()
      return $txt
    } catch {
      $ex = $_.Exception; while ($ex.InnerException) { $ex = $ex.InnerException }
      $cod = 0; if ($ex -is [Net.WebException] -and $ex.Response) { $cod = [int]$ex.Response.StatusCode; $ex.Response.Close() }
      if ($resp) { try { $resp.Close() } catch {} }
      if ($cod -eq 404) { throw "404 em $url" }
      if ($tent -eq $maxTent) { throw "Falha ao baixar $url : $cod $($ex.Message)" }
      Start-Sleep -Seconds ([Math]::Min(40, 5 * [Math]::Pow(2, $tent - 1)))
    }
  }
}

# ---------------------------------------------------------------------------
# Qual eleicao? (codigos do TSE)
# ---------------------------------------------------------------------------
function Achar-Eleicao {
  $cfg = (Baixar-Texto "$HostTse/comum/config/ele-c.json") | ConvertFrom-Json
  $achado = @{ ele1 = $null; ele2 = $null; pleito1 = $null; pleito2 = $null; data1 = $null; data2 = $null }
  foreach ($pl in $cfg.pl) {
    if ($pl.c -ne 'ele2026') { continue }
    foreach ($el in $pl.e) {
      $temCargo = @($el.abr | ForEach-Object { $_.cp } | Where-Object { $_.cd -eq $cargoCod }).Count -gt 0
      if ($temCargo -and $el.t -eq '1' -and ($el.tp -eq '8' -or $el.tp -eq '1')) { $achado.ele1 = $el.cd; $achado.ele2 = $el.cdt2; $achado.pleito1 = $pl.cd; $achado.data1 = $pl.dt }
    }
  }
  if ($achado.ele2) { foreach ($pl in $cfg.pl) { foreach ($el in $pl.e) { if ($el.cd -eq $achado.ele2) { $achado.pleito2 = $pl.cd; $achado.data2 = $pl.dt } } } }
  return $achado
}

# ---------------------------------------------------------------------------
# Base do 1o turno por secao (a partir dos boletins de urna do Portal de Dados Abertos)
# ---------------------------------------------------------------------------
function Preparar-Base {
  $dest = Join-Path $Cache "base_secoes_${tag}_1t.csv"
  if (Test-Path $dest) { return $dest }
  Write-Host "Montando a base do 1o turno por secao ($tag). So na primeira vez; pode levar alguns minutos."
  $pastaBu = Join-Path $env:TEMP 'tse_bu\2026_1t'
  if (-not (Test-Path $pastaBu)) { New-Item -ItemType Directory -Force -Path $pastaBu | Out-Null }
  $pacote = (Baixar-Texto 'https://dadosabertos.tse.jus.br/api/3/action/package_show?id=resultados-2026-boletim-de-urna') | ConvertFrom-Json
  $links = @($pacote.result.resources | ForEach-Object { $_.url } | Where-Object { $_ -match 'bweb_1t_\w\w_\d+\.zip$' } | Sort-Object -Unique)
  if ($UF) { $links = @($links | Where-Object { $_ -match "bweb_1t_$($UF.ToUpper())_" }) }
  if ($links.Count -eq 0) { throw "Nao achei os boletins de urna do 1o turno no Portal de Dados Abertos." }
  $tmp = "$dest.tmp"; if (Test-Path $tmp) { Remove-Item $tmp -Confirm:$false }
  foreach ($link in $links) {
    $arq = Join-Path $pastaBu (Split-Path $link -Leaf)
    $tam = -1; try { $rq = [Net.HttpWebRequest]::Create($link); $rq.Method = 'HEAD'; $rq.UserAgent = $UA; $resp = $rq.GetResponse(); $tam = $resp.ContentLength; $resp.Close() } catch {}
    if (-not ((Test-Path $arq) -and $tam -gt 0 -and (Get-Item $arq).Length -eq $tam)) {
      Write-Host ("  baixando {0} ({1:N0} MB)" -f (Split-Path $link -Leaf), ($tam / 1MB))
      & curl.exe -sS -L --retry 6 --retry-delay 5 -C - -A $UA -o $arq $link
      if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 33) { throw "curl falhou ($LASTEXITCODE) em $link" }
    }
    Write-Host ("  " + [Apuracao.Extrator]::Extrair($arq, $tmp, $cargoNome, $true))
  }
  Move-Item $tmp $dest
  return $dest
}

function Ler-Abr($base, $ele6, [string]$abr) {
  $j = (Baixar-Texto "$base/dados/$abr/$abr-c$cargo4-e$ele6-u.json") | ConvertFrom-Json
  $cands = @($j.carg[0].agr | ForEach-Object { $_.par } | ForEach-Object { $_.cand })
  return [pscustomobject]@{ abr = $abr; hg = "$($j.dg) $($j.hg)"; fim = "$($j.dt) $($j.ht)"; te = [double]$j.e.te; est = [double]$j.e.est; ts = [double]$j.s.ts; st = [double]$j.s.st; vv = [double]$j.v.vv; cands = $cands }
}
function Seg-De([string]$dataHora) {
  # "dd/MM/yyyy HH:mm:ss" -> segundos (mesma escala do motor)
  $dh = [datetime]::MinValue
  if ([datetime]::TryParseExact($dataHora.Trim(), 'dd/MM/yyyy HH:mm:ss', $inv, [Globalization.DateTimeStyles]::None, [ref]$dh)) { return [double][Apuracao.Dados]::Seg($dh.ToString('yyyyMMddHHmmss')) }
  return 0.0
}
function Novo-Dic { return , (New-Object 'System.Collections.Generic.Dictionary[string,double[]]') }
function Tot-De($reg) {
  # registro baixado -> {A, B, eleitorado apurado, eleitorado, secoes totalizadas, secoes, instante em que fechou}
  $fimSeg = 0.0; if ([double]$reg.ts -gt 0 -and [double]$reg.st -ge [double]$reg.ts) { $fimSeg = Seg-De ([string]$reg.fim) }
  return [double[]]@([double]$reg.vA, [double]$reg.vB, [double]$reg.est, [double]$reg.te, [double]$reg.st, [double]$reg.ts, $fimSeg)
}
function Gravar-Tot($dic, $horas, [string]$arq) {
  $linhas = foreach ($par in $dic.GetEnumerator()) { $tv = $par.Value; [pscustomobject]@{ id = $par.Key; vA = $tv[0].ToString('R', $inv); vB = $tv[1].ToString('R', $inv); est = $tv[2].ToString('R', $inv); te = $tv[3].ToString('R', $inv); st = $tv[4].ToString('R', $inv); ts = $tv[5].ToString('R', $inv); fim = $tv[6].ToString('R', $inv); hg = [string]$horas[$par.Key] } }
  @($linhas) | Export-Csv -Path $arq -Delimiter ';' -Encoding UTF8 -NoTypeInformation
}
function Ler-Tot([string]$arq, $horas) {
  $dic = Novo-Dic
  if (Test-Path $arq) { foreach ($ln in (Import-Csv -Path $arq -Delimiter ';')) { $dic[$ln.id] = [double[]]@([double]::Parse($ln.vA, $inv), [double]::Parse($ln.vB, $inv), [double]::Parse($ln.est, $inv), [double]::Parse($ln.te, $inv), [double]::Parse($ln.st, $inv), [double]::Parse($ln.ts, $inv), [double]::Parse($ln.fim, $inv)); if ($null -ne $horas) { $horas[$ln.id] = $ln.hg } } }
  return , $dic
}

# ---------------------------------------------------------------------------
# Preparacao (uma vez por execucao)
# ---------------------------------------------------------------------------
$codigos = Achar-Eleicao
if (-not $codigos.ele1) { throw "Nao achei a eleicao de $Cargo no ciclo ele2026." }
if ($Checar) {
  Write-Host ("1o turno: eleicao {0}, pleito {1} ({2})" -f $codigos.ele1, $codigos.pleito1, $codigos.data1)
  if ($codigos.pleito2) { Write-Host ("2o turno: eleicao {0}, pleito {1} ({2}) - JA PUBLICADO pelo TSE" -f $codigos.ele2, $codigos.pleito2, $codigos.data2) }
  else { Write-Host ("2o turno: eleicao prevista {0} - o TSE ainda NAO publicou os arquivos. Tente de novo mais perto do dia." -f $codigos.ele2) }
  $arqChec = Join-Path $Cache "base_secoes_${tag}_1t.csv"
  if (Test-Path $arqChec) { Write-Host ("Base do 1o turno por secao: pronta ({0:N1} MB)" -f ((Get-Item $arqChec).Length / 1MB)) } else { Write-Host "Base do 1o turno por secao: FALTA. Rode com -Preparar." }
  return
}
$arqBase = Preparar-Base
if ($Preparar) { Write-Host "Base pronta: $arqBase"; return }

if ($Ensaio) { $ele = $codigos.ele1; $pleito = $codigos.pleito1; $dataEle = $codigos.data1 }
else {
  if (-not $codigos.pleito2 -and -not ($Eleicao -and $Pleito)) { throw "O TSE ainda nao publicou o 2o turno (eleicao $($codigos.ele2)). Use -Checar para acompanhar ou -Ensaio para testar com o 1o turno." }
  $ele = $codigos.ele2; $pleito = $codigos.pleito2; $dataEle = $codigos.data2
}
if ($Eleicao) { $ele = $Eleicao }; if ($Pleito) { $pleito = $Pleito }
$ele6 = $ele.PadLeft(6, '0'); $pleito6 = $pleito.PadLeft(6, '0')
$base = "$HostTse/ele2026/$ele"
$abrEscopo = 'br'; if ($Cargo -eq 'governador') { $abrEscopo = $UF }

# lista de municipios e zonas. Municipio de zona unica: usa o arquivo do municipio (mesmo conteudo, mais leve para o TSE)
$munCfg = (Baixar-Texto "$base/config/mun-e$ele6-cm.json") | ConvertFrom-Json
$nomeMun = @{}; $zonasDaUf = @{}; $tipoArq = @{}; $listaUf = New-Object System.Collections.ArrayList; $nZonas = 0
foreach ($ab in $munCfg.abr) {
  if ($UF -and $ab.cd -ne $UF) { continue }
  [void]$listaUf.Add($ab.cd); $zonasDaUf[$ab.cd] = New-Object System.Collections.ArrayList
  foreach ($mu in $ab.mu) {
    $nomeMun["$($ab.cd);$($mu.cd)"] = $mu.nm; $zs = @($mu.z)
    foreach ($zn in $zs) { $idz = "$($ab.cd);$($mu.cd);$zn"; [void]$zonasDaUf[$ab.cd].Add($idz); $tipoArq[$idz] = $(if ($zs.Count -eq 1) { 'm' } else { 'z' }); $nZonas++ }
  }
}
if ($listaUf.Count -eq 0) { throw "A UF '$UF' nao aparece na lista de municipios desta eleicao (nao ha 2o turno para $Cargo nela?)." }

# candidatos: os dois do 2o turno (no ensaio, os dois mais votados do 1o)
$escopo = Ler-Abr $base $ele6 $abrEscopo
$doisCands = @($escopo.cands | Sort-Object { [long]$_.vap } -Descending | Select-Object -First 2 | Sort-Object { [int]$_.n })
if (-not $Ensaio -and @($escopo.cands).Count -ne 2) { Write-Host ("AVISO: o arquivo tem {0} candidatos; usando os dois mais votados." -f @($escopo.cands).Count) -ForegroundColor Yellow }
if ($doisCands.Count -lt 2 -or ([long]$doisCands[0].vap + [long]$doisCands[1].vap) -eq 0) { $doisCands = @($escopo.cands | Sort-Object { [int]$_.n } | Select-Object -First 2) }
$numA = [int]$doisCands[0].n; $numB = [int]$doisCands[1].n
$nomeA = $doisCands[0].nmu; $nomeB = $doisCands[1].nmu
$baseSec = [Apuracao.BaseSecoes]::Carregar($arqBase, $numA, $numB, [int[]]@())
$baseZona = $baseSec.PorUnid('zona')
if (($baseSec.TotA + $baseSec.TotB) -le 0) { throw "A base do 1o turno nao tem votos para os candidatos $numA e $numB." }
$dataMin = 0L
if (-not $Ensaio -and $dataEle) { $dEle = [datetime]::ParseExact($dataEle, 'dd/MM/yyyy', $inv); $dataMin = [long]($dEle.AddDays(-1).ToString('yyyyMMdd') + '120000') }

$arqZonas = Join-Path $Cache "r2_${tagRodada}_zonas.csv"     # ultimo dado conhecido de cada zona
$arqTot = Join-Path $Cache "r2_${tagRodada}_tot.csv"         # unidades usadas na ultima rodada
$arqMarc = Join-Path $Cache "r2_${tagRodada}_marc.bin"       # secoes marcadas na ultima rodada
$arqEstado = Join-Path $Cache "r2_${tagRodada}_estado.csv"

# painel.html le este arquivo a cada poucos segundos; o botao "Atualizar agora" do painel cria o gatilho
$arqPainel = Join-Path $Raiz 'painel_dados.js'
$gatilho = Join-Path $Cache 'atualizar.agora'
$nomesDic = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($chv in $nomeMun.Keys) { $nomesDic[$chv] = [string]$nomeMun[$chv] }
function Meta-Painel([string]$estado, [string]$dadosAte, [string]$nivel) {
  $mt = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  $mt['cargo'] = $Cargo; $mt['uf'] = $UF; $mt['modo'] = $(if ($Ensaio) { 'ensaio' } else { 'vivo' }); $mt['estado'] = $estado
  $mt['gerado'] = (Get-Date).ToString('s'); $mt['dadosAte'] = $dadosAte; $mt['nivel'] = $nivel; $mt['loopMin'] = [string]$Loop
  $mt['proxima'] = $(if ($Loop -gt 0 -and $script:proximaRodada) { $script:proximaRodada.ToString('s') } else { '' })
  if ($script:extrasPainel) { foreach ($chaveExtra in 'comp', 'abst', 'brancos', 'nulos', 'validos') { $mt[$chaveExtra] = ([double]$script:extrasPainel[$chaveExtra]).ToString('R', $inv) } }
  return , $mt
}
function Gravar-Painel([string]$json) { [IO.File]::WriteAllText($arqPainel, 'window.receberPainel(' + $json + ');', (New-Object Text.UTF8Encoding($false))) }
function Num-Inv([string]$v) { return $v.Replace(',', '.') }

function Ler-SecoesUf([string]$sigla, $marcas, $cont) {
  # arquivo de configuracao de secoes da UF: marca as secoes que ja tem data/hora (algo delas ja chegou ao TSE)
  try {
    $txt = Baixar-Texto "$HostTse/ele2026/arquivo-urna/$pleito/config/$sigla/$sigla-p$pleito6-cs.json" 3
    $ret = [Apuracao.Vivo]::LerCs($baseSec, $marcas, $sigla, $txt, $dataMin)
    $cont.principais += $ret[0]; $cont.marcadas += $ret[1]; $cont.semBase += $ret[2]
  } catch { $cont.falhou++ }
}

function Baixar-Unidades($itens, [string]$nivel, [datetime]$limite) {
  # itens: "uf;mun;zona" (nivel zona) ou "uf" (nivel uf). Devolve hashtable id -> registro
  $fila = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  foreach ($it in $itens) { if ($nivel -eq 'zona') { $fila.Enqueue("$it;$($tipoArq[$it])") } else { $fila.Enqueue($it) } }
  $sacola = New-Object 'System.Collections.Concurrent.ConcurrentBag[object]'
  $ctrl = [hashtable]::Synchronized(@{ ate = [datetime]::MinValue; recusas = 0 })
  $trabalho = {
    param($fila, $sacola, $prefixo, $sufixo, $ua, $limite, $ctrl, $numA, $numB, $pausa, $nivel)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $sorteio = New-Object Random; $it = $null
    while ($fila.TryDequeue([ref]$it)) {
      $partes = $it.Split(';'); $sigla = $partes[0]; $ident = $sigla
      if ($nivel -eq 'zona') {
        $ident = "$sigla;$($partes[1]);$($partes[2])"
        if ($partes[3] -eq 'm') { $url = "$prefixo/$sigla/$sigla$($partes[1])$sufixo" } else { $url = "$prefixo/$sigla/$sigla$($partes[1])-z$($partes[2])$sufixo" }
      } else { $url = "$prefixo/$sigla/$sigla$sufixo" }
      $reg = @{ id = $ident; ok = 0; erro = ''; tent = 0; hg = ''; fim = ''; ts = 0; st = 0; te = 0; est = 0; vA = 0; vB = 0; comp = 0; abst = 0; brancos = 0; nulos = 0; validos = 0 }
      for ($tent = 1; $tent -le 4; $tent++) {
        $reg.tent = $tent; $resp = $null; $rq = $null
        if ((Get-Date) -gt $limite) { $reg.erro = 'prazo esgotado'; break }
        while ((Get-Date) -lt $ctrl.ate -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 500 }
        Start-Sleep -Milliseconds $pausa
        try {
          $rq = [Net.HttpWebRequest]::Create($url); $rq.UserAgent = $ua; $rq.Timeout = 15000; $rq.ReadWriteTimeout = 15000
          $rq.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
          $resp = $rq.GetResponse()
          $leitor = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
          $txt = $leitor.ReadToEnd(); $leitor.Close(); $resp.Close()
          $j = $txt | ConvertFrom-Json
          $reg.hg = "$($j.dg) $($j.hg)"; $reg.fim = "$($j.dt) $($j.ht)"
          $reg.ts = [long]$j.s.ts; $reg.st = [long]$j.s.st; $reg.te = [long]$j.e.te; $reg.est = [long]$j.e.est
          foreach ($ag in $j.carg[0].agr) { foreach ($pa in $ag.par) { foreach ($cn in $pa.cand) {
            if ([int]$cn.n -eq $numA) { $reg.vA = [long]$cn.vap } elseif ([int]$cn.n -eq $numB) { $reg.vB = [long]$cn.vap }
          } } }
          # extras so para o quadro do painel (comparecimento, abstencao, brancos, nulos, validos); se faltarem, a rodada segue igual
          try { $reg.comp = [long]$j.e.c; $reg.abst = [long]$j.e.a; $reg.brancos = [long]$j.v.vb; $reg.nulos = [long]$j.v.tvn; $reg.validos = [long]$j.v.vvc } catch {}
          $reg.ok = 1; $reg.erro = ''
          break
        } catch {
          $ex = $_.Exception; while ($ex.InnerException) { $ex = $ex.InnerException }
          $cod = 0; if ($ex -is [Net.WebException] -and $ex.Response) { $cod = [int]$ex.Response.StatusCode; $ex.Response.Close() }
          if ($resp) { try { $resp.Close() } catch {} }; if ($rq) { try { $rq.Abort() } catch {} }
          $reg.erro = "$cod $($ex.Message)"
          if ($cod -eq 404) { break }
          if ($cod -eq 429 -or $cod -eq 403 -or $cod -eq 503) {
            # o TSE recusou: todos os trabalhadores esperam
            $ctrl.recusas++; $novo = (Get-Date).AddSeconds([Math]::Min(60, 10 * [Math]::Pow(2, $tent - 1))); if ($novo -gt $ctrl.ate) { $ctrl.ate = $novo }
            continue
          }
          Start-Sleep -Milliseconds ([int]([Math]::Min(30, [Math]::Pow(2, $tent)) * 1000) + $sorteio.Next(0, 800))
        }
      }
      $sacola.Add([pscustomobject]$reg)
    }
  }
  $nTrab = [Math]::Min($Concorrencia, [Math]::Max(1, $fila.Count))
  $pool = [RunspaceFactory]::CreateRunspacePool(1, $nTrab); $pool.Open(); $tarefas = @()
  for ($i = 0; $i -lt $nTrab; $i++) {
    $ps = [PowerShell]::Create(); $ps.RunspacePool = $pool
    [void]$ps.AddScript($trabalho).AddArgument($fila).AddArgument($sacola).AddArgument("$base/dados").AddArgument("-c$cargo4-e$ele6-u.json").AddArgument($UA).AddArgument($limite).AddArgument($ctrl).AddArgument($numA).AddArgument($numB).AddArgument($script:pausaAtual).AddArgument($nivel)
    $tarefas += @{ ps = $ps; h = $ps.BeginInvoke() }
  }
  while ($tarefas | Where-Object { -not $_.h.IsCompleted }) { Start-Sleep -Milliseconds 200 }
  foreach ($tf in $tarefas) { $tf.ps.EndInvoke($tf.h) | Out-Null; $tf.ps.Dispose() }
  $pool.Close()
  $saida = @{}; foreach ($reg in $sacola.ToArray()) { $saida[$reg.id] = $reg }
  $script:recusasRodada += $ctrl.recusas
  return $saida
}

function Resumo-Projecao($res, [string]$rotulo, $qual) {
  $vTot = $res.Acont + $res.Bcont + $res.Vrem
  Write-Host ("   {0}" -f $rotulo)
  Write-Host ("     {0,-28} {1}   IC95% [{2} ; {3}]   {4,13:N0} votos" -f "$nomeA ($numA)", (Pc $res.Share), (Pc $res.Lo), (Pc $res.Hi), ($res.Acont + $res.Arem))
  Write-Host ("     {0,-28} {1}   IC95% [{2} ; {3}]   {4,13:N0} votos" -f "$nomeB ($numB)", (Pc (1 - $res.Share)), (Pc (1 - $res.Hi)), (Pc (1 - $res.Lo)), ($vTot - $res.Acont - $res.Arem))
  $prob = 100 * $res.PA50; $quem = $nomeA; if ($prob -lt 50) { $prob = 100 - $prob; $quem = $nomeB }
  Write-Host ("     {0} vence em {1:N1}% das simulacoes | secoes identificadas: {2} do eleitorado apurado" -f $quem, $prob, (Pc $qual[0]))
}

# ---------------------------------------------------------------------------
# Uma rodada
# ---------------------------------------------------------------------------
$script:pausaAtual = $PausaMs; $script:extrasPainel = $null
function Rodada {
  $relogio = [Diagnostics.Stopwatch]::StartNew(); $script:recusasRodada = 0
  Write-Host ""
  Write-Host "=========================================================================="
  Write-Host (" {0} 2026 - {1} - {2} x {3}   [{4:HH:mm:ss}]" -f $cargoNome.ToUpper(), $(if ($Ensaio) { 'ENSAIO com o 1o turno' } else { '2o turno' }), $nomeA, $nomeB, (Get-Date))
  Write-Host "=========================================================================="

  # 1. totais por UF (poucos arquivos, sempre frescos)
  $regUf = Baixar-Unidades $listaUf 'uf' ((Get-Date).AddSeconds(90))
  $totUf = Novo-Dic; $hgUf = New-Object System.Collections.ArrayList; $ufFalhas = 0
  foreach ($sigla in $listaUf) { $reg = $regUf[$sigla]; if ($reg -and $reg.ok -eq 1) { $totUf[$sigla] = Tot-De $reg; if ([double]$reg.est -gt 0) { [void]$hgUf.Add((Seg-De $reg.hg)) } } else { $ufFalhas++ } }
  if ($totUf.Count -eq 0) { Write-Host " Nao consegui baixar os totais por UF nesta rodada." -ForegroundColor Yellow; return }
  # quadro de validos, brancos/nulos e abstencao do painel: soma das UFs, so quando todas responderam (senao fica o da rodada anterior)
  if ($ufFalhas -eq 0) {
    $somaExtras = @{ comp = 0.0; abst = 0.0; brancos = 0.0; nulos = 0.0; validos = 0.0 }
    foreach ($sigla in $listaUf) { foreach ($chaveExtra in 'comp', 'abst', 'brancos', 'nulos', 'validos') { $somaExtras[$chaveExtra] += [double]$regUf[$sigla].$chaveExtra } }
    if ($somaExtras.comp -gt 0) { $script:extrasPainel = $somaExtras }
  }
  $sAc = 0.0; $sBc = 0.0; $sEst = 0.0; $sTe = 0.0; $sSt = 0.0; $sTs = 0.0
  foreach ($tt in $totUf.Values) { $sAc += $tt[0]; $sBc += $tt[1]; $sEst += $tt[2]; $sTe += $tt[3]; $sSt += $tt[4]; $sTs += $tt[5] }
  $horaDados = ''; if ($hgUf.Count -gt 0) { $horaDados = [Apuracao.Dados]::Hora([long](($hgUf | Measure-Object -Maximum).Maximum)) }
  Write-Host (" Dados ate {0} | apurado: {1} do eleitorado ({2:N0} de {3:N0}) | {4} das secoes" -f $horaDados, (Pc ($sEst / [Math]::Max(1, $sTe))), $sEst, $sTe, (Pc ($sSt / [Math]::Max(1, $sTs))))
  if ($ufFalhas -gt 0) { Write-Host (" ATENCAO: {0} UFs sem resposta nesta rodada." -f $ufFalhas) -ForegroundColor Yellow }
  $x0 = $baseSec.TotA / ($baseSec.TotA + $baseSec.TotB)
  if (($sAc + $sBc) -le 0) {
    Write-Host (" Ainda nao ha votos apurados. Referencia do 1o turno, so entre os dois: {0} {1} x {2} {3}" -f $nomeA, (Pc $x0), $nomeB, (Pc (1 - $x0)))
    Gravar-Painel ([Apuracao.Painel]::JsonVazio((Meta-Painel 'sem_votos' $horaDados 'uf'), $numA, $nomeA, $numB, $nomeB, $x0))
    return
  }
  Write-Host (" PARCIAL: {0} {1} ({2:N0})   {3} {4} ({5:N0})" -f $nomeA, (Pc ($sAc / ($sAc + $sBc))), $sAc, $nomeB, (Pc ($sBc / ($sAc + $sBc))), $sBc)

  # 2. projecao rapida: UF + secoes
  $marcas = New-Object 'bool[]' $baseSec.N; $cont = @{ principais = 0; marcadas = 0; semBase = 0; falhou = 0 }
  foreach ($sigla in $listaUf) { Ler-SecoesUf $sigla $marcas $cont; Start-Sleep -Milliseconds 100 }
  $qualUf = New-Object 'double[]' 3
  $unUf = [Apuracao.Vivo]::Montar($baseSec, $marcas, 'uf', $totUf, $qualUf)
  $opUf = New-Object Apuracao.Opcoes; $opUf.PesoVies = 1 - $qualUf[0]; $opUf.SigmaDeriva = 0.004
  $resUf = [Apuracao.Modelo]::Projetar($unUf, $opUf)
  Write-Host ""
  Write-Host (" PROJECAO FINAL (% dos votos validos)")
  Resumo-Projecao $resUf ("rapida, por UF ({0:N0} s)" -f $relogio.Elapsed.TotalSeconds) $qualUf
  if ($cont.falhou -gt 0) { Write-Host ("     ATENCAO: {0} arquivos de secoes nao baixaram." -f $cont.falhou) -ForegroundColor Yellow }
  if (-not $script:painelEscrito -and -not $Rapido) {
    # primeira rodada desta execucao: o painel ja recebe a projecao rapida, sem esperar as zonas
    $h1 = New-Object 'System.Collections.Generic.List[string[]]'
    $h1.Add([string[]]@((Get-Date).ToString('HH:mm'), (100 * $resUf.PctEle).ToString('R', $inv), (100 * $resUf.Parcial).ToString('R', $inv), (100 * $resUf.Share).ToString('R', $inv), (100 * $resUf.Lo).ToString('R', $inv), (100 * $resUf.Hi).ToString('R', $inv), (100 * $resUf.Share).ToString('R', $inv), (100 * $resUf.PA50).ToString('R', $inv), (100 * $qualUf[0]).ToString('R', $inv)))
    $q1 = [double[]]@([double]$qualUf[0], [double]$cont.marcadas, [double]$cont.principais, 0.0, [double]::NaN, 0.0, 0.0, 0.0, 0.0)
    Gravar-Painel ([Apuracao.Painel]::Json($unUf, $resUf, $resUf, $nomesDic, (Meta-Painel 'ok' $horaDados 'uf'), $numA, $nomeA, $numB, $nomeB, $q1, [string[]]@(), $h1))
  }
  $resFinal = $resUf; $qualFinal = $qualUf; $unFinal = $unUf; $nivelFinal = 'uf'; $erroNovo = $null; $votosNovos = 0.0; $nBaixadas = 0; $nFechadas = 0; $ufInteira = $null

  # 3. projecao refinada: zonas + secoes, UF por UF (da que tem mais eleitorado faltando para a que tem menos)
  if (-not $Rapido) {
    $horaZona = @{}; $cacheZona = Ler-Tot $arqZonas $horaZona
    $totAntes = Ler-Tot $arqTot $null; $marcAntes = $null
    if ((Test-Path $arqMarc) -and $totAntes.Count -gt 0) { $bytes = [IO.File]::ReadAllBytes($arqMarc); if ($bytes.Length -eq $baseSec.N) { $marcAntes = New-Object 'bool[]' $baseSec.N; for ($i = 0; $i -lt $bytes.Length; $i++) { $marcAntes[$i] = ($bytes[$i] -ne 0) } } }
    $limite = (Get-Date).AddSeconds($PrazoDownload)
    $marcas = New-Object 'bool[]' $baseSec.N; $cont = @{ principais = 0; marcadas = 0; semBase = 0; falhou = 0 }
    $totMisto = Novo-Dic; $horaMisto = @{}; $ufPorZona = New-Object System.Collections.ArrayList; $ufInteira = New-Object System.Collections.ArrayList; $nBaixadas = 0; $nFechadas = 0
    $ordemUf = $listaUf | Sort-Object { $tu = $null; if ($totUf.TryGetValue($_, [ref]$tu)) { $tu[3] - $tu[2] } else { 1e12 } } -Descending
    foreach ($sigla in $ordemUf) {
      $pendUf = foreach ($idz in $zonasDaUf[$sigla]) {
        $ant = $null; $falta = 0.0
        if ($cacheZona.TryGetValue($idz, [ref]$ant)) { if ($ant[5] -gt 0 -and $ant[4] -ge $ant[5]) { $nFechadas++; continue }; $falta = $ant[3] - $ant[2] }
        else { $bz = $null; if ($baseZona.TryGetValue($idz, [ref]$bz)) { $falta = $bz[3] } }
        [pscustomobject]@{ id = $idz; falta = $falta }
      }
      $pendUf = @($pendUf | Sort-Object falta -Descending | ForEach-Object { $_.id })
      $inteiro = $true
      if ($pendUf.Count -gt 0) {
        if ((Get-Date) -ge $limite) { $inteiro = $false }
        else {
          $regs = Baixar-Unidades $pendUf 'zona' $limite
          foreach ($idz in $pendUf) { $reg = $regs[$idz]; if ($reg -and $reg.ok -eq 1) { $cacheZona[$idz] = Tot-De $reg; $horaZona[$idz] = $reg.hg; $nBaixadas++ } else { $inteiro = $false } }
        }
      }
      if ($inteiro) { foreach ($idz in $zonasDaUf[$sigla]) { $tz = $null; if ($cacheZona.TryGetValue($idz, [ref]$tz)) { $totMisto[$idz] = $tz; $horaMisto[$idz] = $horaZona[$idz] } } }
      if ($inteiro) {
        # as secoes sao lidas DEPOIS das zonas da UF: melhor a marcacao um pouco adiantada do que atrasada
        [void]$ufPorZona.Add($sigla); Ler-SecoesUf $sigla $marcas $cont
      } else { [void]$ufInteira.Add($sigla) }
    }
    if ($ufInteira.Count -gt 0) {
      # UFs cujas zonas nao deu tempo de baixar inteiras: entram como uma unidade so, com o total fresco da UF
      $regs2 = Baixar-Unidades $ufInteira 'uf' ((Get-Date).AddSeconds(60))
      foreach ($sigla in $ufInteira) {
        $reg = $regs2[$sigla]; if (-not ($reg -and $reg.ok -eq 1)) { $reg = $regUf[$sigla] }
        if ($reg -and $reg.ok -eq 1) { $totMisto[$sigla] = Tot-De $reg; $horaMisto[$sigla] = $reg.hg }
        Ler-SecoesUf $sigla $marcas $cont
      }
    }
    $msg = "   zonas: {0} baixadas, {1} ja fechadas | {2} UFs por zona" -f $nBaixadas, $nFechadas, $ufPorZona.Count
    if ($ufInteira.Count -gt 0) { $msg += ", {0} por UF inteira ({1})" -f $ufInteira.Count, (($ufInteira | ForEach-Object { $_.ToUpper() }) -join ' ') }
    Write-Host $msg
    if ($script:recusasRodada -gt 0) {
      $script:pausaAtual = [Math]::Min(800, $script:pausaAtual * 2)
      Write-Host ("   o TSE recusou {0} requisicoes; reduzindo o ritmo (pausa de {1} ms entre pedidos)" -f $script:recusasRodada, $script:pausaAtual) -ForegroundColor Yellow
    }

    $qualZ = New-Object 'double[]' 3
    $unZ = [Apuracao.Vivo]::Montar($baseSec, $marcas, 'misto', $totMisto, $qualZ)
    $opZ = New-Object Apuracao.Opcoes; $opZ.PesoVies = 1 - $qualZ[0]

    # erro fora da amostra: o que chegou desde a rodada anterior veio como a rodada anterior previa?
    $s2 = -1.0
    if (Test-Path $arqEstado) { $est0 = Import-Csv -Path $arqEstado -Delimiter ';' | Select-Object -Last 1; if ($est0) { $s2 = [double]::Parse($est0.s2, $inv) } }
    if ($totAntes.Count -gt 0 -and $marcAntes) {
      $qA = New-Object 'double[]' 3
      $unAntes = [Apuracao.Vivo]::Montar($baseSec, $marcAntes, 'misto', $totAntes, $qA)
      $opA = New-Object Apuracao.Opcoes; $opA.PesoVies = 1 - $qA[0]
      $resAntes = [Apuracao.Modelo]::Projetar($unAntes, $opA)
      [Apuracao.Vivo]::Novos($baseSec, $marcAntes, $marcas, 'misto', $unAntes, $totMisto)
      $dv = [Apuracao.Modelo]::Deriva($unAntes, $resAntes.Fit, $opA, $resAntes.VB)
      if ($dv[1] -gt 50000) { $erroNovo = $dv[0]; $votosNovos = $dv[1]; if ($s2 -lt 0) { $s2 = $erroNovo * $erroNovo } else { $s2 = 0.5 * $s2 + 0.5 * $erroNovo * $erroNovo } }
    }
    $opZ.SigmaDeriva = 0.004; if ($s2 -ge 0) { $opZ.SigmaDeriva = [Math]::Max(0.0005, [Math]::Sqrt($s2)) }
    $resZ = [Apuracao.Modelo]::Projetar($unZ, $opZ)
    Resumo-Projecao $resZ ("refinada, por zona ({0:N0} s)" -f $relogio.Elapsed.TotalSeconds) $qualZ
    $resFinal = $resZ; $qualFinal = $qualZ; $unFinal = $unZ; $nivelFinal = 'zona'

    # guarda a rodada (para a proxima comparar) e uma copia no historico (para poder reproduzir a noite depois)
    Gravar-Tot $cacheZona $horaZona $arqZonas
    Gravar-Tot $totMisto $horaMisto $arqTot
    $bytes = New-Object 'byte[]' $baseSec.N; for ($i = 0; $i -lt $bytes.Length; $i++) { if ($marcas[$i]) { $bytes[$i] = 1 } }
    [IO.File]::WriteAllBytes($arqMarc, $bytes)
    [pscustomobject]@{ rodada = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); s2 = $s2.ToString('R', $inv) } | Export-Csv -Path $arqEstado -Delimiter ';' -Encoding UTF8 -NoTypeInformation -Append
    $carimbo = (Get-Date).ToString('yyyyMMdd_HHmmss')
    Copy-Item $arqTot (Join-Path $Hist "${tagRodada}_${carimbo}_tot.csv"); Copy-Item $arqMarc (Join-Path $Hist "${tagRodada}_${carimbo}_marc.bin")
  }

  # 4. leitura do resultado
  $res = $resFinal; $vCont = $res.Acont + $res.Bcont; $vTot = $vCont + $res.Vrem
  Write-Host ""
  Write-Host (" Votos validos projetados: {0:N0} (apurados {1:N0} + a apurar {2:N0})" -f $vTot, $vCont, $res.Vrem)
  if ($res.Vrem -gt 0) {
    Write-Host (" No que falta o modelo espera: {0} {1} x {2} {3}" -f $nomeA, (Pc $res.ShareRem), $nomeB, (Pc (1 - $res.ShareRem)))
    $empate = (0.5 * $vTot - $res.Acont) / $res.Vrem
    $atras = $nomeB; $precisa = 1 - $empate; $previsto = 1 - $res.ShareRem
    if ($res.Share -lt 0.5) { $atras = $nomeA; $precisa = $empate; $previsto = $res.ShareRem }
    if ($precisa -gt 1) { Write-Host (" Virada: {0} precisaria de mais de 100% do que falta. Matematicamente definido." -f $atras) }
    else { Write-Host (" Virada: {0} precisaria de {1} do que falta; o modelo preve {2} (faltam {3} pontos)." -f $atras, (Pc $precisa), (Pc $previsto), (Pp ($precisa - $previsto))) }
  }
  Write-Host (" Em relacao ao 1o turno (so entre os dois): {0} {1} -> {2} ({3} pontos)" -f $nomeA, (Pc $x0), (Pc $res.Share), (Pp ($res.Share - $x0)))
  if ($null -ne $erroNovo) { Write-Host (" Conferencia: desde a rodada anterior entraram {0:N0} votos; o erro da previsao para eles foi de {1} ponto ({2})." -f $votosNovos, (Pp $erroNovo), $nomeA) }

  # qualidade do casamento por secao
  $dif = 0.0; if ($qualFinal[2] -gt 0) { $dif = ($qualFinal[1] - $qualFinal[2]) / $qualFinal[2] }
  $situ = 'em dia'; if ($dif -gt 0.01) { $situ = 'adiantado em relacao aos totais, o que nao atrapalha' } elseif ($dif -lt -0.01) { $situ = 'ATRASADO em relacao aos totais' }
  Write-Host (" Arquivo de secoes do TSE: {0:N0} secoes marcadas de {1:N0}; eleitorado marcado = {2} do apurado ({3})." -f $cont.marcadas, $cont.principais, (Pc (1 + $dif)), $situ)
  if ($qualFinal[0] -lt 0.80 -and $res.PctEle -lt 0.98) {
    Write-Host " ATENCAO: o arquivo de secoes nao esta acompanhando a apuracao. A projecao caiu no modo antigo (rateio pelo eleitorado)," -ForegroundColor Yellow
    Write-Host "          que nas simulacoes errou cerca de 0,4 ponto no meio da noite. O intervalo ja esta mais largo por isso." -ForegroundColor Yellow
  }

  # tabela
  Write-Host ""
  $grupos = @{}
  foreach ($un in $unFinal) {
    $pp = $un.Id.Split(';'); $chave = $un.Uf
    if ($Cargo -ne 'presidente') { if ($pp.Length -ge 2) { $chave = [string]$nomeMun["$($pp[0]);$($pp[1])"] } else { $chave = "(UF $($un.Uf.ToUpper()) inteira)" } }
    $g = $grupos[$chave]; if (-not $g) { $g = @{ te = 0.0; est = 0.0; ac = 0.0; vc = 0.0; ar = 0.0; vr = 0.0; ba = 0.0; bv = 0.0 }; $grupos[$chave] = $g }
    $g.te += $un.EleTot; $g.est += $un.EleC; $g.ac += $un.A; $g.vc += $un.A + $un.B; $g.ar += $un.VolM * $un.PredM; $g.vr += $un.VolM
    $g.ba += $un.bA_C + $un.bA_M; $g.bv += $un.bA_C + $un.bA_M + $un.bB_C + $un.bB_M
  }
  $cabA = Curto $nomeA 8; $cabB = Curto $nomeB 8
  if ($Cargo -eq 'presidente') {
    $reg5 = @{}
    foreach ($chave in $grupos.Keys) { $g = $grupos[$chave]; $nr = $Regiao[$chave]; $h = $reg5[$nr]; if (-not $h) { $h = @{ te = 0.0; est = 0.0; ac = 0.0; vc = 0.0; ar = 0.0; vr = 0.0; ba = 0.0; bv = 0.0 }; $reg5[$nr] = $h }; foreach ($campo in 'te', 'est', 'ac', 'vc', 'ar', 'vr', 'ba', 'bv') { $h[$campo] += $g[$campo] } }
    Write-Host (" POR REGIAO          %apur | parcial {0,-8} | projecao {0,-8} {1,-8} | vs 1o turno | a apurar" -f $cabA, $cabB)
    foreach ($nr in 'Sudeste', 'Nordeste', 'Sul', 'Norte', 'Centro-Oeste', 'Exterior') { $h = $reg5[$nr]; if (-not $h) { continue }
      $pj = ($h.ac + $h.ar) / [Math]::Max(1, $h.vc + $h.vr); $pa = '    -   '; if ($h.vc -gt 0) { $pa = Pc ($h.ac / $h.vc) }
      Write-Host ("   {0,-16} {1,6:N1} | {2,16} | {3,17} {4,8} | {5,11} | {6,10:N0}" -f $nr, (100 * $h.est / [Math]::Max(1, $h.te)), $pa, (Pc $pj), (Pc (1 - $pj)), (Pp ($pj - $h.ba / [Math]::Max(1, $h.bv))), $h.vr) }
    Write-Host ""
  }
  $titulo = ' POR UF'; if ($Cargo -ne 'presidente') { $titulo = ' MAIS VOTOS A APURAR' }
  Write-Host ("{0,-20} %apur | parcial {1,-8} | projecao {1,-8} {2,-8} | vs 1o turno | a apurar" -f $titulo, $cabA, $cabB)
  $ordem = $grupos.Keys | Sort-Object { $grupos[$_].vc + $grupos[$_].vr } -Descending
  if ($Cargo -ne 'presidente') { $ordem = $grupos.Keys | Sort-Object { $grupos[$_].vr } -Descending | Select-Object -First 12 }
  foreach ($chave in $ordem) { $g = $grupos[$chave]
    $pj = ($g.ac + $g.ar) / [Math]::Max(1, $g.vc + $g.vr); $pa = '    -   '; if ($g.vc -gt 0) { $pa = Pc ($g.ac / $g.vc) }
    Write-Host ("   {0,-16} {1,6:N1} | {2,16} | {3,17} {4,8} | {5,11} | {6,10:N0}" -f (Curto $chave.ToUpper() 16), (100 * $g.est / [Math]::Max(1, $g.te)), $pa, (Pc $pj), (Pc (1 - $pj)), (Pp ($pj - $g.ba / [Math]::Max(1, $g.bv))), $g.vr) }

  # checagens
  Write-Host ""
  if ($nivelFinal -eq 'zona') {
    $difA = $res.Acont - $sAc; $difB = $res.Bcont - $sBc
    Write-Host (" CHECAGENS: unidades usadas - soma das UFs no inicio da rodada: {0} {1:N0} ({2:+0.00;-0.00}%) | {3} {4:N0} ({5:+0.00;-0.00}%)" -f $nomeA, $difA, (100 * $difA / [Math]::Max(1, $sAc)), $nomeB, $difB, (100 * $difB / [Math]::Max(1, $sBc)))
    $ruins = @($unFinal | Where-Object { $_.EleC -gt $_.EleTot + 0.5 -or ($_.A + $_.B) -gt $_.EleC + 0.5 }).Count
    if ($ruins -eq 0) { Write-Host "            votos <= eleitorado apurado <= eleitorado: OK em todas as unidades" } else { Write-Host ("            ATENCAO: {0} unidades com votos acima do eleitorado" -f $ruins) -ForegroundColor Yellow }
  }
  try { $nacional = Ler-Abr $base $ele6 $abrEscopo; Write-Host ("            arquivo '{0}' do TSE: gerado {1}, {2} do eleitorado apurado (soma das UFs: {3})" -f $abrEscopo, $nacional.hg, (Pc ($nacional.est / [Math]::Max(1, $nacional.te))), (Pc ($sEst / [Math]::Max(1, $sTe)))) } catch {}

  # arquivos
  $arquivos = "historico2_$tagRodada.csv"
  if ($nivelFinal -eq 'zona') {
    $unFinal | Sort-Object Id | ForEach-Object {
      $pp = $_.Id.Split(';'); $vz = $_.A + $_.B + $_.VolM; $nm = '(UF inteira)'; $cdm = ''; $zn = ''
      if ($pp.Length -ge 3) { $nm = $nomeMun["$($pp[0]);$($pp[1])"]; $cdm = $pp[1]; $zn = $pp[2] }
      [pscustomobject]@{ uf = $pp[0].ToUpper(); cd_tse = $cdm; municipio = $nm; zona = $zn
        eleitorado = $_.EleTot; eleitorado_apurado = $_.EleC; pct_apurado = [Math]::Round(100 * $_.EleC / [Math]::Max(1.0, $_.EleTot), 2); secoes = $_.SecTot; secoes_totalizadas = $_.SecC
        votos_a = $_.A; votos_b = $_.B; pct_a_parcial = $(if (($_.A + $_.B) -gt 0) { [Math]::Round(100 * $_.YC, 2) })
        pct_a_1o_turno = $(if (($_.bA_C + $_.bA_M + $_.bB_C + $_.bB_M) -gt 0) { [Math]::Round(100 * ($_.bA_C + $_.bA_M) / ($_.bA_C + $_.bA_M + $_.bB_C + $_.bB_M), 2) })
        pct_a_restante = $(if ($_.VolM -gt 0) { [Math]::Round(100 * $_.PredM, 2) }); votos_a_apurar = [Math]::Round($_.VolM)
        votos_a_proj = [Math]::Round($_.A + $_.VolM * $_.PredM); votos_b_proj = [Math]::Round($_.B + $_.VolM * (1 - $_.PredM)); pct_a_proj = $(if ($vz -gt 0) { [Math]::Round(100 * ($_.A + $_.VolM * $_.PredM) / $vz, 2) }) }
    } | Export-Csv -Path (Join-Path $Raiz "projecao2_${tagRodada}_zonas.csv") -Delimiter ';' -Encoding UTF8 -NoTypeInformation
    $arquivos = "projecao2_${tagRodada}_zonas.csv | " + $arquivos
  }
  [pscustomobject]@{ rodada = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); dados_ate = $horaDados; nivel = $nivelFinal; pct_eleitorado = [Math]::Round(100 * $sEst / [Math]::Max(1, $sTe), 2)
    candidato_a = $nomeA; parcial_a = [Math]::Round(100 * $sAc / ($sAc + $sBc), 3); proj_a = [Math]::Round(100 * $res.Share, 3); proj_a_lo = [Math]::Round(100 * $res.Lo, 3); proj_a_hi = [Math]::Round(100 * $res.Hi, 3)
    proj_rapida_a = [Math]::Round(100 * $resUf.Share, 3); prob_a = [Math]::Round(100 * $res.PA50, 1); secoes_identificadas = [Math]::Round(100 * $qualFinal[0], 1); erro_no_que_chegou = $(if ($null -ne $erroNovo) { [Math]::Round(100 * $erroNovo, 3) })
  } | Export-Csv -Path (Join-Path $Raiz "historico2_$tagRodada.csv") -Delimiter ';' -Encoding UTF8 -NoTypeInformation -Append
  # dados para o painel (painel.html)
  $histL = New-Object 'System.Collections.Generic.List[string[]]'; $limiteHist = (Get-Date).AddHours(-18)
  foreach ($hl in (Import-Csv -Path (Join-Path $Raiz "historico2_$tagRodada.csv") -Delimiter ';')) {
    $dtH = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($hl.rodada, 'yyyy-MM-dd HH:mm:ss', $inv, [Globalization.DateTimeStyles]::None, [ref]$dtH)) { continue }
    if ($dtH -lt $limiteHist) { continue }
    $histL.Add([string[]]@($dtH.ToString('HH:mm'), (Num-Inv $hl.pct_eleitorado), (Num-Inv $hl.parcial_a), (Num-Inv $hl.proj_a), (Num-Inv $hl.proj_a_lo), (Num-Inv $hl.proj_a_hi), (Num-Inv $hl.proj_rapida_a), (Num-Inv $hl.prob_a), (Num-Inv $hl.secoes_identificadas)))
  }
  $erroP = [double]::NaN; if ($null -ne $erroNovo) { $erroP = [double]$erroNovo }
  $qualArr = [double[]]@([double]$qualFinal[0], [double]$cont.marcadas, [double]$cont.principais, [double]$dif, $erroP, [double]$votosNovos, [double]$nBaixadas, [double]$nFechadas, [double]$script:recusasRodada)
  $ufsArr = [string[]]@(); if ($ufInteira) { $ufsArr = [string[]]@($ufInteira | ForEach-Object { $_.ToUpper() }) }
  Gravar-Painel ([Apuracao.Painel]::Json($unFinal, $res, $resUf, $nomesDic, (Meta-Painel 'ok' $horaDados $nivelFinal), $numA, $nomeA, $numB, $nomeB, $qualArr, $ufsArr, $histL))
  $script:painelEscrito = $true
  Write-Host (" Arquivos: {0} | painel_dados.js | rodada em {1:N0} s" -f $arquivos, $relogio.Elapsed.TotalSeconds)
}
$script:painelEscrito = $false

if (Test-Path $gatilho) { Remove-Item -LiteralPath $gatilho -Confirm:$false }
do {
  $inicio = Get-Date; $script:proximaRodada = $inicio.AddMinutes($Loop)
  try { Rodada } catch { Write-Host (" ERRO nesta rodada: {0}" -f $_.Exception.Message) -ForegroundColor Red; if ($Loop -le 0) { throw } }
  if ($Loop -gt 0) {
    $espera = [Math]::Max(15, 60 * $Loop - ((Get-Date) - $inicio).TotalSeconds)
    Write-Host (" Proxima rodada em {0:N0} s (Ctrl+C para parar; o botao 'Atualizar agora' do painel adianta)." -f $espera)
    $fimEspera = (Get-Date).AddSeconds($espera)
    while ((Get-Date) -lt $fimEspera) {
      if ($PaiPid -gt 0 -and -not (Get-Process -Id $PaiPid -ErrorAction SilentlyContinue)) { Write-Host " O painel foi fechado; encerrando a coleta."; return }
      if (Test-Path $gatilho) { Remove-Item -LiteralPath $gatilho -Confirm:$false; Write-Host " Atualizacao pedida pelo painel."; break }
      Start-Sleep -Milliseconds 700
    }
  }
} while ($Loop -gt 0)
