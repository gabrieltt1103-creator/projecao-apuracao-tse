<#
  Painel visual da apuracao: inicia a coleta em segundo plano, sobe um servidor local e abre o navegador.

  Uso na noite do 2o turno:
      powershell -ExecutionPolicy Bypass -File painel.ps1                      # presidente, rodada a cada 5 minutos
      powershell -ExecutionPolicy Bypass -File painel.ps1 -Loop 3
  Para ver como fica antes do dia (reproduz uma noite real, um passo a cada 6 segundos):
      powershell -ExecutionPolicy Bypass -File painel.ps1 -Demo 2022t2
      powershell -ExecutionPolicy Bypass -File painel.ps1 -Demo 2026t1
  Na demonstracao, o botao "Reiniciar" do painel volta a noite para o primeiro passo.
  Para testar com o 1o turno ja encerrado:
      powershell -ExecutionPolicy Bypass -File painel.ps1 -Ensaio

  O servidor so escuta em localhost (nada sai da maquina) e so entrega o painel e o arquivo de dados.
  Ctrl+C nesta janela encerra o painel e a coleta. ASCII de proposito (PowerShell 5.1).
#>
param(
  [int]$Loop = 5,
  [switch]$Ensaio,
  [ValidateSet('', '2022t2', '2026t1')][string]$Demo = '',
  [int]$PassoSeg = 6,
  [int]$Porta = 8765,
  [switch]$SemNavegador,
  [switch]$SoServidor
)
$ErrorActionPreference = 'Stop'
$Raiz = $PSScriptRoot
$arqHtml = Join-Path $Raiz 'painel.html'
$arqDados = Join-Path $Raiz 'painel_dados.js'
$pastaCache = Join-Path $Raiz 'cache'
if (-not (Test-Path $pastaCache)) { New-Item -ItemType Directory -Path $pastaCache | Out-Null }
$gatilho = Join-Path $pastaCache 'atualizar.agora'

# 1. a coleta roda em outra janela (minimizada), para o registro ficar visivel se voce quiser olhar
$filho = $null
if (-not $SoServidor) {
  if (Test-Path $arqDados) { Remove-Item -LiteralPath $arqDados -Confirm:$false }   # nao mostrar dado de outra sessao
  if ($Demo) { $argsFilho = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $Raiz 'simular.ps1') + '"'), '-Noite', $Demo, '-Painel', '-PassoSeg', $PassoSeg, '-PaiPid', $PID) }
  else {
    $argsFilho = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $Raiz 'projecao2.ps1') + '"'), '-Loop', $Loop, '-PaiPid', $PID)
    if ($Ensaio) { $argsFilho += '-Ensaio' }
  }
  $filho = Start-Process -FilePath 'powershell.exe' -ArgumentList $argsFilho -WindowStyle Minimized -PassThru
  Write-Host "Coleta iniciada em outra janela (minimizada na barra de tarefas)."
}

# 2. servidor local
$escuta = New-Object Net.HttpListener
$escuta.Prefixes.Add("http://localhost:$Porta/")
try { $escuta.Start() }
catch {
  Write-Host "Nao consegui abrir o servidor local na porta $Porta ($($_.Exception.Message))." -ForegroundColor Yellow
  Write-Host "Abrindo o painel direto do arquivo: funciona igual, so sem o botao 'Atualizar agora'."
  if (-not $SemNavegador) { Start-Process $arqHtml }
  if ($filho) { $filho.WaitForExit() }
  return
}
Write-Host "Painel em http://localhost:$Porta/   (Ctrl+C aqui encerra o painel e a coleta)"
if (-not $SemNavegador) { Start-Process "http://localhost:$Porta/" }

function Responder($ctx, [int]$cod, [string]$tipo, [byte[]]$corpo) {
  $resp = $ctx.Response; $resp.StatusCode = $cod; $resp.ContentType = $tipo; $resp.Headers['Cache-Control'] = 'no-store'
  $resp.ContentLength64 = $corpo.Length; $resp.OutputStream.Write($corpo, 0, $corpo.Length); $resp.OutputStream.Close()
}
$utf8 = [Text.Encoding]::UTF8
try {
  while ($true) {
    $tarefa = $escuta.GetContextAsync()
    while (-not $tarefa.Wait(400)) { }
    $ctx = $tarefa.Result
    try {
      $caminho = $ctx.Request.Url.AbsolutePath; $metodo = $ctx.Request.HttpMethod
      if ($caminho -eq '/' -or $caminho -eq '/painel.html') { Responder $ctx 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($arqHtml)) }
      elseif ($caminho -eq '/painel_dados.js') {
        if (Test-Path $arqDados) { Responder $ctx 200 'application/javascript; charset=utf-8' ([IO.File]::ReadAllBytes($arqDados)) }
        else { Responder $ctx 200 'application/javascript; charset=utf-8' ($utf8.GetBytes('window.receberPainel(null);')) }
      }
      elseif ($caminho -eq '/atualizar' -and $metodo -eq 'POST') { [IO.File]::WriteAllText($gatilho, (Get-Date).ToString('s')); Responder $ctx 200 'application/json' ($utf8.GetBytes('{"ok":true}')) }
      elseif ($caminho -eq '/reiniciar' -and $metodo -eq 'POST' -and $Demo -and $argsFilho) {
        # so na demonstracao: encerra a reproducao, apaga os dados e comeca a noite de novo do primeiro passo
        if ($filho -and -not $filho.HasExited) { try { Stop-Process -Id $filho.Id -Force } catch {}; Start-Sleep -Milliseconds 300 }
        if (Test-Path $arqDados) { try { Remove-Item -LiteralPath $arqDados -Confirm:$false } catch {} }
        $filho = Start-Process -FilePath 'powershell.exe' -ArgumentList $argsFilho -WindowStyle Minimized -PassThru
        Responder $ctx 200 'application/json' ($utf8.GetBytes('{"ok":true}'))
      }
      elseif ($caminho -eq '/estado') { $vivo = 'false'; if ($filho -and -not $filho.HasExited) { $vivo = 'true' }; Responder $ctx 200 'application/json' ($utf8.GetBytes('{"coleta":' + $vivo + '}')) }
      else { Responder $ctx 404 'text/plain; charset=utf-8' ($utf8.GetBytes('nao encontrado')) }
    } catch { try { $ctx.Response.Abort() } catch {} }
  }
}
finally {
  try { $escuta.Stop(); $escuta.Close() } catch {}
  if ($filho -and -not $filho.HasExited) { try { Stop-Process -Id $filho.Id -Force } catch {} }
}
