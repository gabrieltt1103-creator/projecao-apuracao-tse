# Metricas da projecao ao vivo na noite de 25/10/2026 (historico2_presidente.csv).
# Uso: python -I noite_ao_vivo.py <historico2_presidente.csv> <saida.json>
import sys, csv, json

L2, F2 = 64256232, 59826041
REAL = 100 * L2 / (L2 + F2)
f = lambda s: float(s.replace(',', '.')) if s else None
rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8-sig'), delimiter=';'))
vist, pts = set(), []
for r in rows:
    if not r['rodada'].startswith('2026-10-25') or r['dados_ate'] in vist:
        continue
    vist.add(r['dados_ate'])
    pts.append(dict(rodada=r['rodada'][11:16], dados=r['dados_ate'][6:11], pct=f(r['pct_eleitorado']), parcial=f(r['parcial_a']), proj=f(r['proj_a']),
                    lo=f(r['proj_a_lo']), hi=f(r['proj_a_hi']), rapida=f(r['proj_rapida_a']), prob=f(r['prob_a']), q=f(r['secoes_identificadas']),
                    erro_novo=f(r['erro_no_que_chegou'])))
for p in pts:
    p['e_proj'] = p['proj'] - REAL; p['e_parc'] = p['parcial'] - REAL; p['e_rap'] = p['rapida'] - REAL
    p['cobre'] = p['lo'] <= REAL <= p['hi']; p['meia'] = (p['hi'] - p['lo']) / 2
print('resultado real (Lula entre os dois): %.4f' % REAL)
print('estados de dados distintos:', len(pts))
print('%-6s %-6s %7s %8s %8s %8s %7s %6s %6s %5s' % ('rodada', 'dados', '%apur', 'e_parc', 'e_proj', 'e_rap', 'meia', 'cobre', 'prob', 'Q'))
for p in pts:
    print('%-6s %-6s %7.2f %+8.3f %+8.3f %+8.3f %7.3f %6s %6.1f %5.1f' % (p['rodada'], p['dados'], p['pct'], p['e_parc'], p['e_proj'], p['e_rap'], p['meia'], p['cobre'], p['prob'], p['q']))

pos = [p for p in pts if p['dados'] >= '19:00']   # depois que a divulgacao voltou
faixas = [(0, 5), (5, 20), (20, 50), (50, 90), (90, 101)]
tab = []
for a, b in faixas:
    s = [p for p in pos if a <= p['pct'] < b]
    if not s:
        continue
    m = lambda k: sum(abs(p[k]) for p in s) / len(s)
    tab.append(dict(faixa='%d-%d' % (a, b), n=len(s), eam_parcial=m('e_parc'), eam_proj=m('e_proj'), eam_rapida=m('e_rap'),
                    meia=sum(p['meia'] for p in s) / len(s), cobertura=sum(p['cobre'] for p in s) / len(s)))
print('\nfaixa    n   EAM parcial  EAM proj  EAM rapida  meia-largura  cobertura')
for t in tab:
    print('%-7s %2d   %8.3f   %8.3f   %8.3f   %8.3f   %5.0f%%' % (t['faixa'], t['n'], t['eam_parcial'], t['eam_proj'], t['eam_rapida'], t['meia'], 100 * t['cobertura']))
print('\ncobertura total depois das 19h: %d de %d' % (sum(p['cobre'] for p in pos), len(pos)))
congel = [p for p in pts if p['dados'] < '19:00']
print('primeiro estado dos dados durante a pausa (17h07; as demais rodadas da pausa estao no historico):', len(congel), ';', 'proj', sorted(set(round(p['proj'], 3) for p in congel)), 'cobre', sorted(set(p['cobre'] for p in congel)), 'prob', sorted(set(p['prob'] for p in congel)))
for lim in (0.5, 0.25, 0.1):
    k = next((i for i in range(len(pos)) if all(abs(q['e_proj']) <= lim for q in pos[i:])), None)
    print('a partir de quando |erro| <= %.2f para sempre: %s (%.2f%% apurado)' % (lim, pos[k]['dados'], pos[k]['pct']) if k is not None else 'nunca')
k = next((i for i in range(len(pos)) if all(q['lo'] > 50 for q in pos[i:])), None)
print('intervalo inteiro acima de 50%% a partir de: %s (%.2f%% apurado)' % (pos[k]['dados'], pos[k]['pct']))
k = next((i for i in range(len(pos)) if all(q['parcial'] > 50 for q in pos[i:])), None)
print('placar com Lula a frente em definitivo a partir de: %s (%.2f%% apurado)' % (pos[k]['dados'], pos[k]['pct']))
en = [p['erro_novo'] for p in pos if p['erro_novo'] is not None]
print('erro no que chegou (fora da amostra): n=%d, EAM %.3f, raiz do quadrado medio %.3f' % (len(en), sum(abs(e) for e in en) / len(en), (sum(e * e for e in en) / len(en)) ** 0.5))
json.dump(dict(real=REAL, pts=pts, faixas=tab), open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
