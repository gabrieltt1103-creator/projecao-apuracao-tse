# Projeção em tempo real da apuração com seções pareadas

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23672276.svg)](https://doi.org/10.5281/zenodo.23672276)

Código da ferramenta de projeção usada ao vivo na noite do 2º turno presidencial brasileiro de 25 de outubro de 2026 e das análises do artigo:

> Teixeira, G. T. (2026). *Projeção em tempo real de resultados eleitorais com seções pareadas: método e avaliação no 2º turno presidencial brasileiro de 2026* [Preprint].

## A ideia

Durante a apuração, o placar parcial engana porque as seções não chegam em ordem aleatória. O TSE publica, por UF, a relação das seções já recebidas, e o Portal de Dados Abertos traz o boletim de urna de cada seção no turno anterior. A ferramenta junta os dois: em cada unidade (município × zona eleitoral), compara o voto das seções que já chegaram com o voto delas mesmas no turno de referência e aplica essa variação, com um modelo estatístico, às seções que faltam. O intervalo de 95% e a probabilidade de vitória vêm de uma simulação de Monte Carlo. O método e a avaliação estão descritos no artigo.

## Conteúdo

| Arquivo | O que faz |
|---|---|
| `motor.cs` | O modelo: pareamento por seção, regressão do swing, peso de credibilidade, agregação e intervalo por Monte Carlo. É compilado pelo PowerShell na hora e é o mesmo código nas simulações e ao vivo. |
| `projecao2.ps1` | Ferramenta ao vivo: baixa do TSE os totais por UF e por município × zona e a relação de seções recebidas, e roda o modelo a cada rodada. |
| `painel.ps1`, `painel.html` | Painel no navegador (`http://localhost:8765`) com a apuração e a projeção. |
| `simular.ps1` | Reconstitui noites reais seção a seção, na ordem em que os boletins chegaram (2º turno de 2022 e 1º turno de 2026). |
| `preparar_simulacoes.ps1` | Baixa e extrai os boletins de urna usados nas reconstituições. |
| `reproduzir_artigo.ps1` | Refaz todas as tabelas e figuras do artigo. |
| `artigo/` | Scripts em Python que calculam as métricas da noite e montam o artigo. |
| `dados/historico2_presidente.csv` | Registro de cada rodada da ferramenta na noite de 25/10/2026: placar, projeção, intervalo, probabilidade e fração de seções identificadas. |
| `dados/r2_presidente_zonas.csv` | Resultado final do 2º turno de 2026 por município × zona, como publicado pelo TSE. |

## Requisitos

- Windows com PowerShell 5.1, que já vem no sistema. A ferramenta não precisa de nenhuma instalação.
- Python 3, só para reproduzir o artigo. Não usa bibliotecas externas.
- Microsoft Edge, opcional, para gerar o PDF do artigo.
- Acesso aos servidores do TSE.

O Windows costuma bloquear scripts baixados da internet. Depois de baixar o repositório, rode uma vez dentro da pasta:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

## Uso na noite da eleição

```powershell
powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Checar     # o TSE já publicou a eleição?
powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Preparar   # monta a base do turno de referência (só na primeira vez)
powershell -ExecutionPolicy Bypass -File painel.ps1 -Loop 3        # coleta a cada 3 minutos e abre o painel
```

Os códigos da eleição são descobertos nos arquivos do próprio TSE. Para forçar outra eleição, use `-Eleicao` e `-Pleito`. Com `-Ensaio`, a ferramenta roda contra o 1º turno, para teste.

## Demonstração

Depois de rodar `preparar_simulacoes.ps1`, o painel reproduz uma noite real passo a passo:

```powershell
powershell -ExecutionPolicy Bypass -File painel.ps1 -Demo 2022t2
```

A demonstração regrava `painel_dados.js`, o mesmo arquivo do painel ao vivo. Não a rode na mesma pasta enquanto o painel ao vivo estiver aberto.

## Reproduzir o artigo

```powershell
powershell -ExecutionPolicy Bypass -File projecao2.ps1 -Preparar
powershell -ExecutionPolicy Bypass -File preparar_simulacoes.ps1
powershell -ExecutionPolicy Bypass -File reproduzir_artigo.ps1 -Pdf
```

Na primeira vez, `preparar_simulacoes.ps1` baixa alguns GB de boletins de urna; `-SoListar` mostra antes o que será baixado. Os resultados ficam em `saida/`. As simulações usam semente fixa, e o artigo gerado é idêntico ao publicado. A versão v1.0, arquivada no Zenodo, gera os mesmos números, tabelas e figuras; a versão atual do repositório gera também o texto final do artigo, que passou a citar o DOI do código.

## Versão usada na noite

`motor.cs` (7/10/2026), `projecao2.ps1` (8/10/2026) e `simular.ps1` (8/10/2026) estão exatamente como rodaram em 25/10/2026. O painel (`painel.ps1`, `painel.html`) recebeu apenas ajustes de exibição até a tarde do dia da eleição. Os scripts `preparar_simulacoes.ps1`, `reproduzir_artigo.ps1` e os da pasta `artigo/` foram escritos depois, para a reprodução.

## Dados

Todos os dados são públicos: o Portal de Dados Abertos do TSE (boletins de urna) e o sistema de divulgação de resultados (`resultados.tse.jus.br`). Os scripts limitam o número de conexões e fazem pausas entre os pedidos; mantenha essa cortesia com os servidores do TSE.

## Como citar

O código:

> Teixeira, G. T. (2026). *projecao-apuracao-tse: Projeção em tempo real da apuração eleitoral com seções pareadas* (Versão 1.0) [Software]. Zenodo. https://doi.org/10.5281/zenodo.23672276

O artigo:

> Teixeira, G. T. (2026). *Projeção em tempo real de resultados eleitorais com seções pareadas: método e avaliação no 2º turno presidencial brasileiro de 2026* [Preprint].

## Uso de inteligência artificial

O código foi construído com o auxílio do assistente Claude (Anthropic), sob supervisão do autor, que propôs o método e definiu suas características.

## Licença

Código sob a licença MIT (ver `LICENSE`). Os dados são do Tribunal Superior Eleitoral.
