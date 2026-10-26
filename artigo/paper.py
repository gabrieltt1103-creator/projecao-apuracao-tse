# Gera o artigo cientifico sobre o modelo de projecao (HTML para imprimir em A4 com o Edge).
# Uso: python -I paper.py <pasta_sim> <noite_ao_vivo.json> <base_secoes_1t.csv> <r2_zonas.csv> <historico2.csv> <saida.html>
import sys, re, json, csv, math
from collections import defaultdict, Counter

PSIM, PNOITE, PBASE, PZONAS, PHIST, SAIDA = sys.argv[1:7]
INK, MUTED, GRID = '#1A1A1A', '#666666', '#E2E2E2'
C_PROJ, C_RAP, C_PLAC, C_SIMP, C_SEM = '#17607D', '#7DB2C9', '#3A3A3A', '#B07A12', '#8A5A9E'
FRACS = [2, 5, 10, 15, 20, 30, 40, 50, 60, 70, 80, 90, 95, 98]
LINKEDIN = 'https://www.linkedin.com/in/gabrieltteixeira'


def n(v, d=1):
    s = f'{v:,.{d}f}'
    return s.replace(',', 'X').replace('.', ',').replace('X', '.').replace('-', '−')


def esc(s):
    return str(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def txt(x, y, s, size=11, fill=INK, anchor='start', weight=400, halo=False, italic=False):
    h = ' paint-order="stroke" stroke="#FFFFFF" stroke-width="3.5" stroke-linejoin="round"' if halo else ''
    it = ' font-style="italic"' if italic else ''
    return f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}"{h}{it}>{esc(s)}</text>'


def svg(w, h, c):
    return f'<svg viewBox="0 0 {w} {h}" width="100%" xmlns="http://www.w3.org/2000/svg" font-family="Inter, Segoe UI, sans-serif">{c}</svg>'


# ------------------------------------------------------------------ dados das simulacoes
def ler(arq):
    b = open(arq, 'rb').read()
    t = b.decode('utf-16') if b[:2] in (b'\xff\xfe', b'\xfe\xff') else b.decode('utf-8', 'replace')
    return t.replace('\r', '')


def num(s):
    return float(s.replace('+', '').replace(',', '.'))


def tabela_sim(t):
    ls = t.split('\n'); i = next(k for k, l in enumerate(ls) if l.startswith('variante'))
    out = {}
    for l in ls[i + 1:]:
        if l.startswith('horario') or not l.strip():
            break
        tok = l[42:].split()
        out[l[:42].strip()] = dict(erros=[num(x) for x in tok[:14]], eam=num(tok[14]), cob=tok[15] if len(tok) > 15 else '')
    return out


def detalhe(t):
    rx = re.compile(r'^\s+(\d+)%\s+proj ([\d,]+)%\s+erro\s+([+-][\d,]+)\s+IC \+-([\d,]+) \[([\d,]+) ; ([\d,]+)\].*?sigmaUnid ([\d,]+)\s+kappa\s+([\d,]+)')
    return [dict(frac=int(m.group(1)), proj=num(m.group(2)), erro=num(m.group(3)), meia=num(m.group(4)), lo=num(m.group(5)), hi=num(m.group(6)),
                 sigu=num(m.group(7)), kappa=num(m.group(8))) for m in map(rx.match, t.split('\n')) if m]


def real_de(t):
    return num(re.search(r'% de A entre os dois: ([\d,]+)%', t).group(1))


T22, T26, TROB = ler(PSIM + r'\det_2022t2.txt'), ler(PSIM + r'\det_2026t1.txt'), ler(PSIM + r'\sim_2022t2_robustez.txt')
S22, S26, ROB = tabela_sim(T22), tabela_sim(T26), tabela_sim(TROB)
D22, D26 = detalhe(T22), detalhe(T26)
R22, R26 = real_de(T22), real_de(T26)
PAD = 'SECOES casadas, por zona (PADRAO)'

# ------------------------------------------------------------------ noite ao vivo
NOITE = json.load(open(PNOITE, encoding='utf-8'))
REAL = NOITE['real']; PTS = NOITE['pts']; FX = NOITE['faixas']
POS = [p for p in PTS if p['dados'] >= '19:00']
hist = [r for r in csv.DictReader(open(PHIST, encoding='utf-8-sig'), delimiter=';') if r['rodada'].startswith('2026-10-25')]
N_RODADAS = len(hist); R_INI, R_FIM = hist[0]['rodada'][11:16], hist[-1]['rodada'][11:16]
fz = lambda s: float(s.replace(',', '.'))
CONG = []
for r in hist:
    if '17:07' not in r['dados_ate']:
        continue
    v = [fz(r[c]) for c in ('proj_a', 'proj_a_lo', 'proj_a_hi', 'prob_a', 'secoes_identificadas')]
    k = (round(v[0], 1), round(v[1], 1), round(v[2], 1), round(v[3]), v[4])
    if not CONG or CONG[-1]['k'] != k:
        CONG.append(dict(k=k, ini=r['rodada'][11:16], fim=r['rodada'][11:16], n=1, proj=v[0], lo=v[1], hi=v[2], prob=v[3], q=v[4]))
    else:
        CONG[-1]['fim'] = r['rodada'][11:16]; CONG[-1]['n'] += 1
c_prim = next(c for c in CONG if c['q'] == 0); c_long = max(CONG, key=lambda c: c['n']); c_19 = next(c for c in CONG if c['ini'] >= '19:00')

def marco(f):
    k = next((i for i in range(len(POS)) if all(f(q) for q in POS[i:])), None)
    return POS[k]
M_IC50 = marco(lambda q: q['lo'] > 50); M_025 = marco(lambda q: abs(q['e_proj']) <= 0.25); M_010 = marco(lambda q: abs(q['e_proj']) <= 0.10)
M_PLAC = marco(lambda q: q['parcial'] > 50)
EN = [p['erro_novo'] for p in POS if p['erro_novo'] is not None]
EN_RMS = (sum(e * e for e in EN) / len(EN)) ** 0.5; EN_EAM = sum(abs(e) for e in EN) / len(EN)
COB = sum(p['cobre'] for p in POS)
Q_DEP = [p['q'] for p in POS if p['dados'] >= M_IC50['dados']]

# ------------------------------------------------------------------ homogeneidade do swing (municipio x zona)
base = defaultdict(lambda: [0, 0])
for ln in open(PBASE, encoding='utf-8'):
    p = ln.rstrip('\n').split(';')
    if len(p) < 10:
        continue
    v = dict(x.split(':') for x in p[9].split('|') if x)
    u = base[(p[0], p[1], p[2])]; u[0] += int(v.get('13', 0)); u[1] += int(v.get('22', 0))
UN = []
for r in csv.DictReader(open(PZONAS, encoding='utf-8-sig'), delimiter=';'):
    k = tuple(r['id'].split(';')); a2, b2 = int(r['vA']), int(r['vB'])
    if k in base and a2 + b2 > 0 and sum(base[k]) > 0:
        x = base[k][0] / sum(base[k]); UN.append((x, a2 / (a2 + b2) - x, a2 + b2, a2 / (a2 + b2)))
W = sum(u[2] for u in UN)
mw = lambda i: sum(u[i] * u[2] for u in UN) / W
sdw = lambda i, m: math.sqrt(sum(u[2] * (u[i] - m) ** 2 for u in UN) / W)
MX, MS, MY = mw(0), mw(1), mw(3); SX, SS, SY = sdw(0, MX), sdw(1, MS), sdw(3, MY)
BETA = sum(u[2] * (u[1] - MS) * (u[0] - MX) for u in UN) / W / SX ** 2
CORR = BETA * SX / SS
N_UN_TSE = sum(1 for _ in open(PZONAS, encoding='utf-8-sig')) - 1

# ------------------------------------------------------------------ MathML
mi = lambda s: '<mi>' + s + '</mi>'
mn = lambda s: '<mn>' + s + '</mn>'
mo = lambda s: '<mo>' + s + '</mo>'
mt = lambda s: '<mtext>' + s + '</mtext>'
r_ = lambda *a: '<mrow>' + ''.join(a) + '</mrow>'
sub = lambda b, s: '<msub>' + b + s + '</msub>'
sup = lambda b, s: '<msup>' + b + s + '</msup>'
ss = lambda b, s, p: '<msubsup>' + b + s + p + '</msubsup>'
fr = lambda a, b: '<mfrac>' + r_(a) + r_(b) + '</mfrac>'
bar = lambda b: '<mover accent="true">' + b + '<mo>&#xAF;</mo></mover>'
hat = lambda b: '<mover accent="true">' + b + '<mo>^</mo></mover>'
til = lambda b: '<mover accent="true">' + b + '<mo>~</mo></mover>'
soma = lambda s: '<munder><mo>&#x2211;</mo>' + r_(s) + '</munder>'
par = lambda *a: r_(mo('('), *a, mo(')'))
esp = '<mspace width="1.6em"/>'
U, E_ = mi('u'), mi('e')
EU = r_(mi('e'), mo('('), mi('u'), mo(')'))
RR = r_(mo('('), mi('r'), mo(')'))
yC, xC, xM, yM = ss(mi('y'), U, mi('C')), ss(mi('x'), U, mi('C')), ss(mi('x'), U, mi('M')), ss(hat(mi('y')), U, mi('M'))
VM = ss(hat(mi('V')), U, mi('M'))
NEQ = [0]


def eq(corpo):
    NEQ[0] += 1
    return f'<div class="eq"><math display="block">{corpo}</math><span class="eqn">({NEQ[0]})</span></div>', NEQ[0]


EQ_SHARE, e_share = eq(r_(sub(mi('y'), U), mo('='), fr(sub(mi('A'), U), r_(sub(mi('A'), U), mo('+'), sub(mi('B'), U))), mo(','), esp,
                          sub(mi('x'), U), mo('='), fr(sub(mi('a'), U), r_(sub(mi('a'), U), mo('+'), sub(mi('b'), U)))))
EQ_CASA, e_casa = eq(r_(ss(mi('s'), U, mi('C')), mo('='), mo('{'), '<mtable columnalign="left">'
                        '<mtr><mtd>' + r_(fr(ss(mi('E'), U, mi('C')), ss(mi('E'), U, mi('R'))), ss(mi('s'), U, mi('R'))) + '</mtd><mtd>' + r_(mt('se'), '<mspace width="0.4em"/>', ss(mi('E'), U, mi('R')), mo('&#x2265;'), ss(mi('E'), U, mi('C'))) + '</mtd></mtr>'
                        '<mtr><mtd>' + r_(ss(mi('s'), U, mi('R')), mo('+'), mi('min'), par(mn('1'), mo(','), fr(r_(ss(mi('E'), U, mi('C')), mo('&#x2212;'), ss(mi('E'), U, mi('R'))), ss(mi('E'), U, mi('N')))), ss(mi('s'), U, mi('N'))) + '</mtd><mtd>' + mt('caso contrário') + '</mtd></mtr></mtable>'))
EQ_Q, e_q = eq(r_(mi('Q'), mo('='), fr(r_(soma(U), mi('min'), par(ss(mi('E'), U, mi('C')), mo(','), ss(mi('E'), U, mi('R')))), r_(soma(U), ss(mi('E'), U, mi('C'))))))
EQ_REG, e_reg = eq(r_(yC, mo('&#x2212;'), xC, mo('='), sub(mi('&#x3B1;'), EU), mo('+'), mi('&#x3B2;'), par(xC, mo('&#x2212;'), bar(mi('x'))), mo('+'),
                      sub(mi('&#x3B3;'), EU), par(xC, mo('&#x2212;'), sub(bar(mi('x')), EU)), mo('+'), sub(mi('&#x3B5;'), U)))
EQ_ALFA, e_alfa = eq(r_(sub(mi('&#x3B1;'), E_), mo('='), fr(r_(soma(r_(U, mo('&#x2208;'), E_)), sub(mi('w'), U), sub(mi('r'), U), mo('+'), sub(mi('n'), mn('0')), sub(mi('&#x3B1;'), mn('0'))),
                                                              r_(soma(r_(U, mo('&#x2208;'), E_)), sub(mi('w'), U), mo('+'), sub(mi('n'), mn('0')))), mo(','), esp,
                        sub(mi('&#x3B3;'), E_), mo('='), fr(r_(soma(r_(U, mo('&#x2208;'), E_)), sub(mi('w'), U), par(sub(mi('x'), U), mo('&#x2212;'), sub(bar(mi('x')), E_)), par(sub(mi('r'), U), mo('&#x2212;'), sub(mi('&#x3B1;'), E_))),
                                                           r_(soma(r_(U, mo('&#x2208;'), E_)), sub(mi('w'), U), sup(par(sub(mi('x'), U), mo('&#x2212;'), sub(bar(mi('x')), E_)), mn('2')), mo('+'), sub(mi('&#x3BB;'), mi('&#x3B3;'))))))
EQ_M, e_m = eq(r_(sub(mi('m'), U), par(mi('x')), mo('='), mi('x'), mo('+'), sub(mi('&#x3B1;'), E_), mo('+'), mi('&#x3B2;'), par(mi('x'), mo('&#x2212;'), bar(mi('x'))), mo('+'),
                  sub(mi('&#x3B3;'), E_), par(mi('x'), mo('&#x2212;'), sub(bar(mi('x')), E_))))
EQ_CRED, e_cred = eq(r_(yM, mo('='), sub(mi('m'), U), par(xM), mo('+'), sub(mi('W'), U), mo('['), yC, mo('&#x2212;'), sub(mi('m'), U), par(xC), mo(']'), mo(','), esp,
                        sub(mi('W'), U), mo('='), fr(sub(mi('k'), U), r_(sub(mi('k'), U), mo('+'), mi('&#x3BA;'))), mo(','), esp,
                        mi('&#x3BA;'), mo('='), fr(ss(mi('&#x3C3;'), mi('s'), mn('2')), ss(mi('&#x3C3;'), mi('u'), mn('2')))))
EQ_VOL, e_vol = eq(r_(VM, mo('='), ss(mi('v'), U, mi('M')), fr(r_(ss(mi('n'), U, mi('C')), mo('+'), mi('K'), sub(bar(mi('&#x3C1;')), E_)), r_(ss(mi('v'), U, mi('C')), mo('+'), mi('K')))))
EQ_AGR, e_agr = eq(r_(hat(mi('S')), mo('='), fr(r_(sup(mi('A'), mi('C')), mo('+'), soma(U), VM, yM), r_(sup(mi('A'), mi('C')), mo('+'), sup(mi('B'), mi('C')), mo('+'), soma(U), VM))))
EQ_MC, e_mc = eq(r_(sup(hat(mi('S')), RR), mo('='), fr(r_(sup(mi('A'), mi('C')), mo('+'), soma(E_), ss(mi('f'), E_, RR), ss(til(mi('A')), E_, RR)),
                                                      r_(sup(mi('A'), mi('C')), mo('+'), sup(mi('B'), mi('C')), mo('+'), soma(E_), ss(mi('f'), E_, RR), ss(mi('V'), E_, mi('M'))))))
EQ_AT, e_at = eq(r_(ss(til(mi('A')), E_, RR), mo('='), soma(r_(U, mo('&#x2208;'), E_)), VM, yM, mo('+'), ss(mi('V'), E_, mi('M')), par(sup(mi('z'), RR), mo('+'), ss(mi('z'), E_, RR)), mo('+'),
                    sub(mi('&#x3C3;'), mi('u')), sup(par(soma(r_(U, mo('&#x2208;'), E_)), sup(par(VM), mn('2')), par(mn('1'), mo('&#x2212;'), sub(mi('W'), U))), r_(mn('1'), mo('/'), mn('2'))), ss(mi('&#x3BE;'), E_, RR)))
EQ_SIG, e_sig = eq(r_(ss(mi('&#x3C3;'), mi('nac'), mn('2')), mo('='), sup(r_(mo('['), par(mn('1'), mo('&#x2212;'), mi('Q')), mi('b'), mo(']')), mn('2')), mo('+'), ss(mi('&#x3C3;'), mi('d'), mn('2')), mo('+'),
                      fr(sup(mi('&#x3C6;'), mn('2')), r_(mi('max'), par(sub(mi('f'), mi('rest')), mo(','), mn('0,0004'))))))


im = lambda s: '<math>' + s + '</math>'   # matematica no meio do texto
I_ER, I_EN, I_EC = (im(ss(mi('E'), U, mi(k))) for k in 'RNC')
I_SR, I_SN = im(ss(mi('s'), U, mi('R'))), im(ss(mi('s'), U, mi('N')))
I_SM = im(r_(ss(mi('s'), U, mi('M')), mo('='), ss(mi('s'), U, mi('R')), mo('+'), ss(mi('s'), U, mi('N')), mo('&#x2212;'), ss(mi('s'), U, mi('C'))))
I_SU2, I_SS2, I_SE2 = im(ss(mi('&#x3C3;'), mi('u'), mn('2'))), im(ss(mi('&#x3C3;'), mi('s'), mn('2'))), im(ss(mi('&#x3C3;'), mi('e'), mn('2')))
I_AT, I_VEM = im(sub(til(mi('A')), E_)), im(ss(mi('V'), E_, mi('M')))
I_ZN = im(r_(mi('z'), mo('~'), mi('N'), par(mn('0'), mo(','), ss(mi('&#x3C3;'), mi('nac'), mn('2')))))
I_ZE = im(r_(sub(mi('z'), E_), mo('~'), mi('N'), par(mn('0'), mo(','), ss(mi('&#x3C3;'), mi('e'), mn('2')))))
I_SD = im(r_(ss(mi('&#x3C3;'), r_(mi('d'), mo(','), mi('t')), mn('2')), mo('='), fr(mn('1'), mn('2')), ss(mi('&#x3C3;'), r_(mi('d'), mo(','), mi('t'), mo('&#x2212;'), mn('1')), mn('2')),
                mo('+'), fr(mn('1'), mn('2')), ss(mi('e'), mi('t'), mn('2'))))


# ------------------------------------------------------------------ figuras
def caixa(x, y, w, h, linhas, cor=INK, fundo='#FFFFFF', borda=INK, peso=500):
    c = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="{fundo}" stroke="{borda}" stroke-width="1.1"/>'
    y0 = y + h / 2 - (len(linhas) - 1) * 7.2 + 4
    for i, l in enumerate(linhas):
        c += txt(x + w / 2, y0 + i * 14.4, l, 11, cor, 'middle', peso if i == 0 else 400)
    return c


def seta(x1, y1, x2, y2, cor=MUTED, trac=False):
    d = ' stroke-dasharray="4 3"' if trac else ''
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{cor}" stroke-width="1.3" marker-end="url(#ponta)"{d}/>'


def fig_fluxo():
    c = f'<defs><marker id="ponta" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{MUTED}"/></marker></defs>'
    c += txt(90, 12, 'ENTRADAS (TSE)', 9.5, MUTED, 'middle', 700) + txt(295, 12, 'PAREAMENTO', 9.5, MUTED, 'middle', 700) + txt(490, 12, 'MODELO', 9.5, MUTED, 'middle', 700) + txt(650, 12, 'INCERTEZA', 9.5, MUTED, 'middle', 700)
    c += caixa(0, 22, 180, 62, ['Boletins de urna do turno', 'de referência, por seção'], fundo='#F4F4F2')
    c += caixa(0, 104, 180, 62, ['Relação de seções', 'recebidas (arquivo cs)'], fundo='#F4F4F2')
    c += caixa(0, 186, 180, 62, ['Totais oficiais por', 'município × zona'], fundo='#F4F4F2')
    c += caixa(215, 104, 160, 62, ['Base das seções', 'contadas (C) e', 'faltantes (M), eq. %d–%d' % (e_casa, e_q)])
    c += caixa(410, 22, 160, 62, ['Regressão do swing', 'efeitos por UF e', 'encolhimento, eq. %d–%d' % (e_reg, e_m)])
    c += caixa(410, 104, 160, 62, ['Combinação com o', 'desvio observado', '(credibilidade), eq. %d' % e_cred])
    c += caixa(410, 186, 160, 62, ['Volume restante e', 'agregação nacional', 'eq. %d–%d' % (e_vol, e_agr)])
    c += caixa(600, 104, 120, 62, ['Erro fora da amostra', 'entre rodadas', '(σd)'], fundo='#FFFFFF', borda=MUTED, cor=INK)
    c += caixa(600, 186, 120, 62, ['Monte Carlo', 'IC 95% e P(A > 50%)', 'eq. %d–%d' % (e_mc, e_sig)], fundo='#E8F1F5', borda=C_PROJ, cor=C_PROJ, peso=700)
    c += seta(180, 53, 213, 125) + seta(180, 135, 213, 135) + seta(180, 217, 213, 147)
    c += seta(375, 125, 408, 60) + seta(490, 84, 490, 102) + seta(490, 166, 490, 184) + seta(570, 217, 598, 217) + seta(660, 166, 660, 184, trac=True)
    c += f'<path d="M90,248 L90,262 L490,262 L490,250" fill="none" stroke="{MUTED}" stroke-width="1.3" marker-end="url(#ponta)"/>'
    c += txt(290, 275, 'votos já apurados entram diretamente na agregação', 9.5, MUTED, 'middle', 400, italic=True)
    return svg(720, 282, c)


def eixo_y(X0, X1, Y, vals, fmt, size=10):
    c = ''
    for v in vals:
        c += f'<line x1="{X0}" x2="{X1}" y1="{Y(v):.1f}" y2="{Y(v):.1f}" stroke="{INK if v == 0 else GRID}" stroke-width="{1.1 if v == 0 else 0.8}"/>' + txt(X0 - 6, Y(v) + 3.5, fmt(v), size, MUTED, 'end')
    return c


def painel_backtest(ox, w, tit, S, D, real, ymin, ymax):
    left, right, top, base = ox + 38, ox + w - 18, 34, 228
    X = lambda f: left + f / 100 * (right - left)
    Y = lambda v: base - (v - ymin) / (ymax - ymin) * (base - top)
    c = txt(ox + 4, 16, tit, 11.5, INK, 'start', 700)
    c += eixo_y(left, right, Y, [v for v in range(math.ceil(ymin), math.floor(ymax) + 1)], lambda v: ('+' if v > 0 else '') + str(v).replace('-', '−'))
    for f in (0, 25, 50, 75, 100):
        c += txt(X(f), base + 15, f'{f}%', 10, MUTED, 'middle')
    banda = [f'{X(d["frac"]):.1f},{Y(d["hi"] - real):.1f}' for d in D] + [f'{X(d["frac"]):.1f},{Y(d["lo"] - real):.1f}' for d in reversed(D)]
    c += f'<polygon points="{" ".join(banda)}" fill="{C_PROJ}" fill-opacity="0.16"/>'
    for nome, cor, larg, trac in (('parcial (o que o placar mostra)', C_PLAC, 1.6, '4 3'), ('extrapolacao simples por UF', C_SIMP, 1.6, ''),
                                  ('zona, sem saber as secoes', C_SEM, 1.6, ''), (PAD, C_PROJ, 2.2, '')):
        e = S[nome]['erros']
        pts = ' '.join(f'{X(f):.1f},{Y(max(min(v, ymax), ymin)):.1f}' for f, v in zip(FRACS, e))
        c += f'<polyline points="{pts}" fill="none" stroke="{cor}" stroke-width="{larg}" stroke-dasharray="{trac or 0}" stroke-linejoin="round"/>'
        for f, v in zip(FRACS, e):
            c += f'<circle cx="{X(f):.1f}" cy="{Y(max(min(v, ymax), ymin)):.1f}" r="{2.4 if nome == PAD else 1.8}" fill="{cor}"/>'
    return c


def fig_backtest():
    c = painel_backtest(0, 355, '(a) 2º turno de 2022 — base: 1º turno de 2022', S22, D22, R22, -7.5, 1.5)
    c += painel_backtest(365, 355, '(b) 1º turno de 2026 — base: 1º turno de 2022', S26, D26, R26, -5, 1)
    leg = [(C_PLAC, '4 3', 'Placar parcial'), (C_SIMP, '', 'Extrapolação por UF'), (C_SEM, '', 'Sem pareamento'), (C_PROJ, '', 'Seções pareadas (padrão) e IC 95%')]
    x = 38
    for cor, trac, nome in leg:
        c += f'<line x1="{x}" x2="{x + 22}" y1="280" y2="280" stroke="{cor}" stroke-width="2.2" stroke-dasharray="{trac or 0}"/>' + txt(x + 28, 283.5, nome, 10, INK)
        x += 28 + len(nome) * 5.3 + 26
    for ox in (0, 365):
        c += txt(ox + (38 + 355 - 18) / 2, 258, '% do eleitorado apurado', 10, MUTED, 'middle')
    return svg(720, 290, c)


def hm(s):
    hh, mm = s.split(':'); return int(hh) * 60 + int(mm)


def fig_noite():
    pts = [p for p in POS]
    left, right, top, base = 44, 700, 28, 222
    t0, t1 = 19 * 60, 21 * 60 + 42
    X = lambda t: left + (t - t0) / (t1 - t0) * (right - left)
    Y = lambda v: base - (v - 48) / (56 - 48) * (base - top)
    c = txt(4, 14, '(a) Placar oficial e projeção, por horário dos dados do TSE', 11.5, INK, 'start', 700)
    ab = [p for p in pts if p['parcial'] < 50]; xa, xb = X(hm(ab[0]['dados'])) - 3, X(hm(ab[-1]['dados'])) + 3
    c += f'<rect x="{xa:.1f}" y="{top}" width="{xb - xa:.1f}" height="{base - top}" fill="#000" fill-opacity="0.045"/>' + txt((xa + xb) / 2, top + 14, 'placar com B à frente', 10, MUTED, 'middle', 600)
    c += eixo_y(left, right, Y, [48, 50, 52, 54, 56], lambda v: f'{v}%')
    for t in range(19 * 60, 21 * 60 + 31, 30):
        c += txt(X(t), base + 15, f'{t // 60}h{t % 60:02d}', 10, MUTED, 'middle')
    banda = [f'{X(hm(p["dados"])):.1f},{Y(min(p["hi"], 56)):.1f}' for p in pts] + [f'{X(hm(p["dados"])):.1f},{Y(max(p["lo"], 48)):.1f}' for p in reversed(pts)]
    c += f'<polygon points="{" ".join(banda)}" fill="{C_PROJ}" fill-opacity="0.16"/>'
    c += f'<line x1="{left}" x2="{right}" y1="{Y(REAL):.1f}" y2="{Y(REAL):.1f}" stroke="{MUTED}" stroke-dasharray="5 4" stroke-width="1"/>' + txt(right, Y(REAL) - 6, f'resultado final {n(REAL, 2)}%', 10, INK, 'end', 600, halo=True)
    for k, cor, lw in (('rapida', C_RAP, 1.5), ('proj', C_PROJ, 2.2), ('parcial', C_PLAC, 2.0)):
        d = ' '.join(f'{X(hm(p["dados"])):.1f},{Y(min(max(p[k], 48), 56)):.1f}' for p in pts)
        c += f'<polyline points="{d}" fill="none" stroke="{cor}" stroke-width="{lw}" stroke-linejoin="round"/>'
    for p in pts:
        c += f'<circle cx="{X(hm(p["dados"])):.1f}" cy="{Y(p["parcial"]):.1f}" r="1.9" fill="{C_PLAC}"/>'
    c += txt(X(hm(pts[0]['dados'])) + 8, Y(pts[0]['parcial']) + 4, f'placar {n(pts[0]["parcial"])}% com {n(pts[0]["pct"], 2)}% apurado', 10, INK, 'start', 600, halo=True)
    xm = X(hm(M_IC50['dados']))
    c += f'<line x1="{xm:.1f}" x2="{xm:.1f}" y1="{Y(53.15):.1f}" y2="{Y(M_IC50["lo"]):.1f}" stroke="{C_PROJ}" stroke-width="1" stroke-dasharray="2 2"/>'
    c += txt(xm + 4, Y(53.3), f'{M_IC50["dados"].replace(":", "h")}: todo o IC acima de 50%', 10, C_PROJ, 'start', 700, halo=True)
    lo = min(pts, key=lambda p: p['parcial'])
    c += txt(X(hm(lo['dados'])), Y(lo['parcial']) + 16, f'placar {n(lo["parcial"])}% com {n(lo["pct"], 0)}% apurado', 10, INK, 'middle', 600, halo=True)
    # (b) erro absoluto em escala log
    oy = 250; l2, r2, t2, b2 = 44, 700, oy + 46, oy + 206
    XL = lambda v: l2 + (math.log10(v) - math.log10(0.4)) / (math.log10(100) - math.log10(0.4)) * (r2 - l2)
    YL = lambda v: b2 - (math.log10(max(v, 0.001)) - (-3)) / (1.3 - (-3)) * (b2 - t2)
    c += txt(4, oy + 12, '(b) Erro absoluto em relação ao resultado final (pontos percentuais, escalas logarítmicas)', 11.5, INK, 'start', 700)
    for v, rot in ((0.001, '0,001'), (0.01, '0,01'), (0.1, '0,1'), (1, '1'), (10, '10')):
        c += f'<line x1="{l2}" x2="{r2}" y1="{YL(v):.1f}" y2="{YL(v):.1f}" stroke="{GRID}" stroke-width="0.8"/>' + txt(l2 - 6, YL(v) + 3.5, rot, 10, MUTED, 'end')
    for v in (0.5, 1, 2, 5, 10, 20, 50, 100):
        c += txt(XL(v), b2 + 15, (n(v, 1) if v < 1 else str(v)) + '%', 10, MUTED, 'middle')
    c += txt((l2 + r2) / 2, b2 + 29, '% do eleitorado apurado', 10, MUTED, 'middle')
    for k, cor, nome in (('e_parc', C_PLAC, 'placar'), ('e_rap', C_RAP, 'projeção rápida (UF)'), ('e_proj', C_PROJ, 'projeção refinada (zona)')):
        d = ' '.join(f'{XL(p["pct"]):.1f},{YL(abs(p[k])):.1f}' for p in pts)
        c += f'<polyline points="{d}" fill="none" stroke="{cor}" stroke-width="1.3" stroke-opacity="0.8"/>'
        for p in pts:
            c += f'<circle cx="{XL(p["pct"]):.1f}" cy="{YL(abs(p[k])):.1f}" r="2.3" fill="{cor}"/>'
    x = l2
    for cor, nome in ((C_PLAC, 'Placar parcial'), (C_RAP, 'Projeção rápida (UF)'), (C_PROJ, 'Projeção refinada (município × zona)')):
        c += f'<circle cx="{x + 5}" cy="{oy + 28}" r="3.5" fill="{cor}"/>' + txt(x + 13, oy + 31.5, nome, 10, INK)
        x += 13 + len(nome) * 5.4 + 26
    return svg(720, oy + 244, c)


def fig_swing():
    left, right, top, base = 44, 700, 10, 168
    ymin, ymax = -4, 10
    X = lambda v: left + v * (right - left)
    Y = lambda v: base - (v - ymin) / (ymax - ymin) * (base - top)
    c = eixo_y(left, right, Y, list(range(-4, 11, 2)), lambda v: ('+' if v > 0 else '') + str(v).replace('-', '−'))
    for v in range(0, 101, 10):
        c += txt(X(v / 100), base + 15, f'{v}%', 10, MUTED, 'middle')
    fora = 0
    for x, s, w, y in UN:
        sv = 100 * s
        if not ymin <= sv <= ymax:
            fora += 1; continue
        rad = 0.9 + 3.2 * math.sqrt(w / 400000)
        c += f'<circle cx="{X(x):.1f}" cy="{Y(sv):.1f}" r="{rad:.2f}" fill="{C_PROJ}" fill-opacity="0.28"/>'
    xa, xb = 0.05, 0.95
    ya, yb = 100 * (MS + BETA * (xa - MX)), 100 * (MS + BETA * (xb - MX))
    c += f'<line x1="{X(xa):.1f}" x2="{X(xb):.1f}" y1="{Y(ya):.1f}" y2="{Y(yb):.1f}" stroke="{INK}" stroke-width="1.6"/>'
    c += txt(X(0.05), Y(7.4), f'reta ponderada: inclinação de {n(BETA, 3)} ponto de swing por ponto de partida', 10, INK, 'start', 600, halo=True)
    c += txt((left + right) / 2, base + 30, '% de A entre os dois no 1º turno de 2026 (turno de referência)', 10, MUTED, 'middle')
    c += f'<text transform="translate(12,{(top + base) / 2}) rotate(-90)" font-size="10" fill="{MUTED}" text-anchor="middle">swing de A (pontos)</text>'
    return svg(720, base + 36, c), fora


def fig(conteudo, rot, legenda, largura='100%'):
    return f'<figure style="width:{largura}"><div>{conteudo}</div><figcaption><b>{rot}.</b> {legenda}</figcaption></figure>'


# ------------------------------------------------------------------ tabelas
def tab(rot, legenda, cab, linhas, nota='', cls=''):
    h = f'<table class="tab {cls}"><caption><b>{rot}.</b> {legenda}</caption><thead><tr>' + ''.join(f'<th>{x}</th>' for x in cab) + '</tr></thead><tbody>'
    for l in linhas:
        if isinstance(l, str):
            h += f'<tr class="grp"><td colspan="{len(cab)}">{l}</td></tr>'
        else:
            h += '<tr>' + ''.join(f'<td>{x}</td>' for x in l) + '</tr>'
    h += '</tbody></table>'
    if nota:
        h += f'<p class="tnota">{nota}</p>'
    return f'<div class="tbloco">{h}</div>'


cob = lambda s: s.replace('/', ' de ') if s else '—'
NOMES = [('parcial (o que o placar mostra)', 'Placar parcial (sem modelo)'), ('extrapolacao simples por UF', 'Extrapolação simples por UF'),
         'Mesmo modelo, sem saber quais seções chegaram',
         ('municipio, sem saber as secoes (1o turno)', 'por município'), ('zona, sem saber as secoes', 'por município × zona'),
         ('zona + covariaveis', 'por município × zona, com covariáveis'), ('zona + covariaveis + correcoes', 'por município × zona, com covariáveis e correções'),
         'Seções pareadas',
         ('SECOES casadas, por UF (rapida)', 'por UF (projeção rápida)'), ('SECOES casadas, por municipio', 'por município'),
         (PAD, '<b>por município × zona (padrão)</b>'), ('SECOES casadas, zona + covariaveis', 'por município × zona, com covariáveis'),
         ('SECOES casadas, zona + correcoes', 'por município × zona, com correções')]
lin3 = []
for it in NOMES:
    if isinstance(it, str):
        lin3.append(it); continue
    k, rot = it; a, b = S22[k], S26[k]
    f = (lambda v: f'<b>{n(v, 2)}</b>') if k == PAD else (lambda v: n(v, 2))
    lin3.append([rot, f(a['eam']), cob(a['cob']), f(b['eam']), cob(b['cob'])])
TAB3 = tab('Tabela 3', 'Erro absoluto médio (EAM, em pontos percentuais) entre 5% e 98% do eleitorado apurado e cobertura do intervalo de 95% nos 14 cortes, por variante, nas duas noites reconstituídas (2022: 2º turno; 2026: 1º turno).',
           ['Variante', 'EAM 2022', 'Cobertura 2022', 'EAM 2026', 'Cobertura 2026'], lin3,
           'Covariáveis: percentual dos demais candidatos no turno de referência e logaritmo do eleitorado da unidade. Correções: viés temporal aplicado à estimativa pontual (λ<sub>B</sub> = 1) e correção de deriva (λ<sub>D</sub> = 1). Sem pareamento, usa-se σ<sub>s</sub> = 0,08.', 'larga')
ROBN = [('secao/zona, marcacao exata', 'exata'), ('secao/zona, marcacao 2 min atrasada', '2 min atrasada'), ('secao/zona, marcacao 5 min atrasada', '5 min atrasada'),
        ('secao/zona, marcacao 15 min atrasada', '15 min atrasada'), ('secao/zona, marcacao 30 min atrasada', '30 min atrasada'),
        ('secao/zona, marcacao 5 min adiantada', '5 min adiantada'), ('secao/zona, marcacao 15 min adiantada', '15 min adiantada'),
        ('secao/UF, 5 min atrasada', '5 min atrasada, por UF'), ('sem marcacao nenhuma (zona)', 'sem relação de seções')]
TAB4 = tab('Tabela 4', 'Sensibilidade ao atraso da relação de seções recebidas: 2º turno de 2022, modelo por município × zona.',
           ['Relação de seções', 'EAM (pontos)', 'Cobertura', 'Erro com 10% apurado', 'Erro com 30% apurado'],
           [[rot, n(ROB[k]['eam'], 2), cob(ROB[k]['cob']), n(ROB[k]['erros'][2], 2).replace('-', '−'), n(ROB[k]['erros'][5], 2).replace('-', '−')] for k, rot in ROBN])
FXN = {'0-5': 'até 5%', '5-20': '5% a 20%', '20-50': '20% a 50%', '50-90': '50% a 90%', '90-101': 'acima de 90%'}
TAB5 = tab('Tabela 5', 'Desempenho ao vivo no 2º turno de 2026, por faixa do eleitorado apurado, nas %d atualizações posteriores à retomada da divulgação (19h01).' % len(POS),
           ['Eleitorado apurado', 'Atualizações', 'EAM placar', 'EAM rápida (UF)', 'EAM refinada', 'Meia-largura do IC', 'Cobertura'],
           [[FXN[t['faixa']], t['n'], n(t['eam_parcial'], 2), n(t['eam_rapida'], 2), '<b>' + n(t['eam_proj'], 3) + '</b>', n(t['meia'], 2), '%d de %d' % (round(t['cobertura'] * t['n']), t['n'])] for t in FX],
           'EAM e meia-largura em pontos percentuais. A projeção refinada é a do modelo por município × zona; a rápida usa só os totais por UF.')
TAB1 = tab('Tabela 1', 'Noites usadas no estudo.',
           ['Noite', 'Seções', 'Turno de referência', 'Eleitorado com seção pareada', 'Resultado (A entre os dois)', 'Uso'],
           [['2º turno de 2022 (Lula × Jair Bolsonaro)', '472.028', '1º turno de 2022', '100,0%', n(R22, 2) + '%', 'reconstituição'],
            ['1º turno de 2026 (Lula × Flávio Bolsonaro)', '499.206', '1º turno de 2022', '93,2%', n(R26, 2) + '%', 'reconstituição'],
            ['2º turno de 2026 (Lula × Flávio Bolsonaro)', '499.206', '1º turno de 2026', '—', n(REAL, 2) + '%', 'ao vivo']],
           'No 1º turno de 2026 consideram-se só os votos dos dois candidatos que foram ao 2º turno. Para o 2º turno de 2026, o número de seções é o do turno de referência. Nas reconstituições, o turno de referência de 2026 é o de 2022, o que torna o teste mais difícil: a numeração das seções mudou em parte e a distância entre as eleições é maior.')
TAB2 = tab('Tabela 2', 'Parâmetros do modelo (fixados antes da eleição).',
           ['Símbolo', 'Valor', 'Papel'],
           [['σ<sub>s</sub>', '0,03', 'desvio-padrão entre seções de uma mesma unidade; entra em κ'],
            ['σ<sub>u</sub>', 'validação cruzada (5 dobras); 0,02 se houver menos de 30 unidades completas', 'erro de previsão por unidade'],
            ['λ<sub>β</sub>', '0,05', 'penalização ridge da inclinação β'],
            ['n<sub>0</sub>', '3', 'pseudocontagem do encolhimento de α<sub>e</sub> (em unidades de peso médio)'],
            ['λ<sub>γ</sub>', '0,10', 'penalização da inclinação por UF γ<sub>e</sub>'],
            ['K', '300 votos', 'encolhimento da razão de volume ρ'],
            ['σ<sub>d</sub>', 'média móvel do erro fora da amostra; 0,004 sem histórico; piso 0,0005', 'deriva entre rodadas'],
            ['φ', '0,001', 'piso da incerteza nacional no fim da apuração'],
            ['R', '4.000', 'sorteios de Monte Carlo'],
            ['—', '[0,003; 0,997]', 'limites da previsão por unidade']], cls='t2')

# ------------------------------------------------------------------ texto
FIG1 = fig(fig_fluxo(), 'Figura 1', 'Esquema do método. O pareamento usa a relação de seções recebidas para dividir o turno de referência de cada unidade entre a parte já contada e a que falta.')
FIG2 = fig(fig_backtest(), 'Figura 2', 'Erro da projeção (projetado − real, em pontos percentuais) ao longo de duas noites reconstituídas com o horário de chegada de cada seção. A faixa é o intervalo de 95% do modelo padrão, centrado no erro.')
FIG3 = fig(fig_noite(), 'Figura 3', f'Noite de 25 de outubro de 2026, a partir da retomada da divulgação. Em (a), a faixa é o intervalo de 95% da projeção refinada; a área sombreada marca o período em que o placar oficial mostrou o candidato B à frente. Em (b), cada ponto é um estado distinto dos dados do TSE; erros abaixo de 0,001 ponto aparecem sobre a linha de 0,001.')
FIG4_SVG, FORA = fig_swing()
FIG4 = fig(FIG4_SVG, 'Figura 4', f'Swing de A entre os turnos de 2026 nas {n(len(UN), 0)} unidades município × zona, contra o percentual de A no 1º turno. Área dos pontos proporcional aos votos; {FORA} unidades fora do eixo vertical não aparecem; a reta é a regressão ponderada.')

# referencias conferidas no Crossref em 26/10/2026 (autores, ano, titulo, revista, volume, numero, paginas e DOI)
def doi(d):
    return f' <a href="https://doi.org/{d}">https://doi.org/{d}</a>'
REFS = '\n'.join('<li>' + r + '</li>' for r in [
    'Bernardo, J. M. (1984). Monitoring the 1982 Spanish Socialist victory: A Bayesian analysis. <i>Journal of the American Statistical Association</i>, <i>79</i>(387), 510–515.' + doi('10.1080/01621459.1984.10478077'),
    'Brown, P. J., Firth, D., &amp; Payne, C. D. (1999). Forecasting on British election night 1997. <i>Journal of the Royal Statistical Society: Series A (Statistics in Society)</i>, <i>162</i>(2), 211–226.' + doi('10.1111/1467-985X.00131'),
    'Bühlmann, H. (1967). Experience rating and credibility. <i>ASTIN Bulletin</i>, <i>4</i>(3), 199–207.' + doi('10.1017/S0515036100008989'),
    'Butler, D., &amp; Stokes, D. (1969). <i>Political change in Britain: Forces shaping electoral choice</i>. Macmillan.',
    'Curtice, J., &amp; Firth, D. (2008). Exit polling in a cold climate: The BBC–ITV experience in Britain in 2005. <i>Journal of the Royal Statistical Society: Series A (Statistics in Society)</i>, <i>171</i>(3), 509–539.' + doi('10.1111/j.1467-985X.2007.00536.x'),
    'Efron, B., &amp; Morris, C. (1975). Data analysis using Stein’s estimator and its generalizations. <i>Journal of the American Statistical Association</i>, <i>70</i>(350), 311–319.' + doi('10.1080/01621459.1975.10479864'),
    'Efron, B., &amp; Tibshirani, R. J. (1993). <i>An introduction to the bootstrap</i>. Chapman &amp; Hall.',
    'Goodman, L. A. (1953). Ecological regressions and behavior of individuals. <i>American Sociological Review</i>, <i>18</i>(6), 663–664.' + doi('10.2307/2088121'),
    'Hoerl, A. E., &amp; Kennard, R. W. (1970). Ridge regression: Biased estimation for nonorthogonal problems. <i>Technometrics</i>, <i>12</i>(1), 55–67.' + doi('10.1080/00401706.1970.10488634'),
    'King, G. (1997). <i>A solution to the ecological inference problem: Reconstructing individual behavior from aggregate data</i>. Princeton University Press.',
    'Mendoza, M., &amp; Nieto-Barajas, L. E. (2016). Quick counts in the Mexican presidential elections: A Bayesian approach. <i>Electoral Studies</i>, <i>43</i>, 124–132.' + doi('10.1016/j.electstud.2016.06.007'),
    'Pavía, J. M., Larraz, B., &amp; Montero, J. M. (2008). Election forecasts using spatiotemporal models. <i>Journal of the American Statistical Association</i>, <i>103</i>(483), 1050–1059.' + doi('10.1198/016214507000001427'),
    'Pavía-Miralles, J. M. (2005). Forecasts from nonrandom samples: The election night case. <i>Journal of the American Statistical Association</i>, <i>100</i>(472), 1113–1122.' + doi('10.1198/016214504000001835'),
    'Stone, M. (1974). Cross-validatory choice and assessment of statistical predictions. <i>Journal of the Royal Statistical Society: Series B (Methodological)</i>, <i>36</i>(2), 111–133.' + doi('10.1111/j.2517-6161.1974.tb00994.x'),
    'Tribunal Superior Eleitoral. (2026a). <i>Portal de Dados Abertos do TSE: Boletins de urna, Eleições 2022 e 2026</i> [Conjunto de dados]. <a href="https://dadosabertos.tse.jus.br">https://dadosabertos.tse.jus.br</a>. Acesso em 26 out. 2026.',
    'Tribunal Superior Eleitoral. (2026b). <i>Divulgação de resultados das Eleições 2026: Totais por unidade e relação de seções recebidas</i> [Conjunto de dados]. <a href="https://resultados.tse.jus.br/oficial/ele2026">https://resultados.tse.jus.br/oficial/ele2026</a>. Acesso em 26 out. 2026.'])
d22 = {d['frac']: d for d in D22}; d26 = {d['frac']: d for d in D26}
q_min, q_max = min(Q_DEP), max(Q_DEP)
corpo = f'''
<div class="topo"><span>Artigo original</span><span>Preprint · versão de 26 de outubro de 2026</span></div>
<h1>Projeção em tempo real de resultados eleitorais com seções pareadas: método e avaliação no 2º turno presidencial brasileiro de 2026</h1>
<p class="autor"><a href="{LINKEDIN}">Gabriel Telles Teixeira</a></p>
<p class="afil">Pesquisador independente, Brasil</p>

<div class="resumo">
<p><b>Resumo.</b> Durante a apuração, o placar parcial é um estimador viesado do resultado final, porque as seções não chegam em ordem aleatória. Este artigo propõe e avalia um método de projeção em tempo real que usa dois conjuntos de dados públicos do Tribunal Superior Eleitoral: os boletins de urna de cada seção no turno de referência e a relação das seções já recebidas, atualizada durante a apuração. Em cada unidade (município × zona eleitoral), o voto das seções apuradas é comparado com o voto delas mesmas no turno de referência. A variação é modelada por uma regressão ponderada com efeitos por unidade da federação e encolhimento, combinada com o desvio observado da unidade por um fator de credibilidade e aplicada às seções que faltam; a incerteza vem de uma simulação de Monte Carlo. Em reconstituições de duas noites reais com o horário de chegada de cada seção, o erro absoluto médio foi de {n(S22[PAD]['eam'], 2)} e {n(S26[PAD]['eam'], 2)} ponto percentual, contra {n(S22['parcial (o que o placar mostra)']['eam'], 2)} e {n(S26['parcial (o que o placar mostra)']['eam'], 2)} do placar, e o intervalo de 95% conteve o resultado nos 28 cortes avaliados. Ao vivo, no 2º turno presidencial de 2026, com o código congelado 17 dias antes, a projeção indicou o vencedor com {n(M_IC50['pct'], 1)}% do eleitorado apurado e ficou a menos de 0,1 ponto do resultado a partir de {n(M_010['pct'], 0)}%. Com apenas 62 seções apuradas, porém, o intervalo subestimou a incerteza, por ignorar o erro de estimação dos parâmetros; discutem-se a causa e as correções.</p>
<p class="pc"><b>Palavras-chave:</b> projeção eleitoral; apuração em tempo real; swing; credibilidade; eleições brasileiras; urna eletrônica.</p>
</div>
<div class="resumo en">
<p><b>Abstract.</b> During an election count, the running tally is a biased estimator of the final result because polling stations do not report in random order. This paper proposes and evaluates a real-time projection method based on two public datasets from Brazil’s Superior Electoral Court: the station-level returns of a reference round and the list of stations already received, updated during the count. Within each unit (municipality × electoral zone), the vote of the reported stations is compared with the vote of the same stations in the reference round. This change is modelled by a weighted regression with state effects and shrinkage, blended with the unit’s observed deviation through a credibility factor, and applied to the stations still missing; uncertainty comes from a Monte Carlo simulation. In replays of two real election nights using each station’s arrival time, the mean absolute error was {n(S22[PAD]['eam'], 2).replace(',', '.')} and {n(S26[PAD]['eam'], 2).replace(',', '.')} percentage points, against {n(S22['parcial (o que o placar mostra)']['eam'], 2).replace(',', '.')} and {n(S26['parcial (o que o placar mostra)']['eam'], 2).replace(',', '.')} for the running tally, and the 95% interval covered the result at all 28 checkpoints. Live, in the 2026 presidential runoff, with the code frozen 17 days earlier, the projection identified the winner with {n(M_IC50['pct'], 1).replace(',', '.')}% of the electorate counted and stayed within 0.1 point of the result from {n(M_010['pct'], 0)}% onwards. With only 62 stations counted, however, the interval understated uncertainty because it ignores parameter estimation error; the cause and possible corrections are discussed.</p>
<p class="pc"><b>Keywords:</b> election-night forecasting; real-time vote counting; swing; credibility; Brazilian elections.</p>
</div>

<h2>1 Introdução</h2>
<p>No Brasil, a totalização dos votos é eletrônica e rápida. No 2º turno presidencial de 25 de outubro de 2026, 99,7% do eleitorado estava apurado às 21h12, pouco mais de duas horas depois da retomada da divulgação, que ficou suspensa entre 17h07 e 19h01. A rapidez não elimina, porém, um problema estatístico conhecido: as seções não chegam em ordem aleatória. A ordem depende de fuso horário, da logística de transmissão e do porte das zonas eleitorais, fatores correlacionados com a geografia do voto. Por isso o placar parcial é um estimador viesado do resultado durante boa parte da noite. Em 2026, o placar oficial mostrou o candidato que viria a perder à frente entre 19h47 e 20h23. Na reconstituição do 2º turno de 2022 feita neste trabalho, o placar subestimava o vencedor em {n(-S22['parcial (o que o placar mostra)']['erros'][0], 1)} pontos com 2% do eleitorado apurado e em {n(-S22['parcial (o que o placar mostra)']['erros'][7], 1)} ponto com 50%.</p>
<p>Projeções durante a apuração têm longa tradição. Bernardo (1984) usou uma pequena amostra de seções e um modelo bayesiano hierárquico para antecipar o resultado das eleições espanholas de 1982 duas horas depois do fechamento das urnas. Brown, Firth e Payne (1999) descrevem as projeções feitas para a BBC a partir dos primeiros resultados declarados na eleição britânica de 1997. Pavía-Miralles (2005) trata do fato de que, na noite da eleição, as primeiras seções apuradas formam uma amostra não aleatória, e Pavía, Larraz e Montero (2008) incorporam a estrutura espacial do voto a essas previsões. No México, a autoridade eleitoral divulga contagens rápidas baseadas em amostras probabilísticas de seções (Mendoza e Nieto-Barajas, 2016). A ideia de medir a mudança nos mesmos locais de votação entre duas eleições está no centro do modelo de pesquisa de boca de urna usado pela BBC e pela ITV no Reino Unido (Curtice e Firth, 2008), herdeiro da tradição do swing uniforme (Butler e Stokes, 1969).</p>
<p>O caso brasileiro tem duas particularidades que favorecem essa abordagem. Primeiro, o TSE publica o boletim de urna de cada uma das cerca de 500 mil seções, com os votos por candidato, o que permite conhecer o turno de referência no nível mais fino possível. Segundo, durante a apuração, o TSE publica para cada unidade da federação (UF) um arquivo que relaciona todas as seções e registra a data e a hora em que cada uma foi recebida. Juntos, os dois arquivos permitem saber quais seções compõem o placar a cada instante e comparar o voto delas com o voto delas mesmas no turno anterior, sem amostragem.</p>
<p>Este artigo (i) descreve um método que explora esse pareamento por seção, com uma regressão do swing com efeitos por UF e encolhimento, uma combinação com o desvio observado de cada unidade inspirada na teoria da credibilidade e um intervalo obtido por simulação; (ii) avalia o método em reconstituições de duas noites reais; (iii) relata o desempenho ao vivo no 2º turno de 2026, com o código congelado em 8 de outubro, 17 dias antes da eleição; e (iv) documenta uma falha do intervalo no início da apuração e propõe correções.</p>

<h2>2 Dados</h2>
<h3>2.1 Turno de referência</h3>
<p>Para o 2º turno de 2026, o turno de referência é o 1º turno de 4 de outubro de 2026. Os boletins de urna, obtidos no Portal de Dados Abertos do TSE (Tribunal Superior Eleitoral, 2026a), trazem para cada seção a UF, o município, a zona, o número da seção, o eleitorado apto, o comparecimento e os votos por candidato. São 499.206 seções, das quais 497.897 no país e 1.309 no exterior. Entre os dois candidatos que disputariam o 2º turno, A (Lula, PT, 13) e B (Flávio Bolsonaro, PL, 22), A teve 48,99% no 1º turno.</p>
<h3>2.2 Divulgação oficial</h3>
<p>O TSE divulga os totais em arquivos JSON por UF e por combinação de município e zona eleitoral (Tribunal Superior Eleitoral, 2026b), com votos por candidato, eleitorado apurado, seções totalizadas e hora de geração. Esta última combinação é a menor agregação publicada e foi adotada como unidade do modelo: são {n(N_UN_TSE, 0)} unidades, incluindo as do exterior. Os arquivos são atualizados a cada poucos minutos.</p>
<h3>2.3 Relação de seções recebidas</h3>
<p>Para cada UF, um arquivo de configuração lista todas as seções e, para as já recebidas, a data e a hora do recebimento. Seções agregadas a outras são ignoradas. A chave UF, município, zona e seção liga cada registro ao boletim do turno de referência. A utilidade do método depende da atualidade desse arquivo. Em 2026 ele marcou as primeiras seções logo após o início da divulgação e, a partir da retomada às 19h01, acompanhou a chegada praticamente em tempo real (seção 5).</p>
<h3>2.4 Noites para validação</h3>
<p>Para as reconstituições, usam-se os boletins de urna de duas noites com o horário em que cada boletim foi recebido pelo TSE (Tabela 1). A ordem real de chegada permite reproduzir, seção a seção, o que a ferramenta teria visto em cada instante.</p>
{TAB1}

<h2>3 Método</h2>
<p>A Figura 1 resume as etapas, detalhadas a seguir.</p>
{FIG1}
<h3>3.1 Notação</h3>
<p>Seja <i>u</i> uma unidade (município × zona) e <i>e</i>(<i>u</i>) a sua UF. Em cada instante, <i>A<sub>u</sub></i> e <i>B<sub>u</sub></i> são os votos já contados dos dois candidatos e <i>a<sub>u</sub></i>, <i>b<sub>u</sub></i> e <i>v<sub>u</sub></i> são os votos de A, de B e os votos válidos totais no turno de referência, somados sobre um conjunto de seções. Os índices C e M indicam a parte contada e a parte que falta da unidade. As proporções de interesse são as dos dois candidatos:</p>
{EQ_SHARE}
<p>A projeção é a proporção nacional de A entre os dois, <i>S</i>, ao fim da apuração.</p>
<h3>3.2 Pareamento</h3>
<p>Para cada unidade, a relação de seções divide o eleitorado entre seções marcadas como recebidas ({I_ER}) e não marcadas ({I_EN}), e o TSE informa o eleitorado efetivamente apurado ({I_EC}). Os dois nem sempre coincidem, porque os arquivos são gerados em momentos diferentes. Sendo {I_SR} e {I_SN} os vetores de votos do turno de referência somados sobre as seções marcadas e não marcadas, a base da parte contada é</p>
{EQ_CASA}
<p>e a da parte que falta é o complemento, {I_SM}. Se a marcação está adiantada, a base marcada é reduzida na proporção do eleitorado; se está atrasada, completa-se com uma fração proporcional das seções não marcadas. Sem marcação nenhuma, a regra vira o rateio da base pelo eleitorado apurado. A qualidade do pareamento é medida pela fração do eleitorado apurado com seções identificadas:</p>
{EQ_Q}
<p>Seções que não existem no turno de referência recebem a média por eleitor das demais seções da unidade.</p>
<h3>3.3 Modelo do swing</h3>
<p>O swing de cada unidade na parte contada é modelado por uma regressão ponderada:</p>
{EQ_REG}
<p>com pesos proporcionais aos votos contados nos dois candidatos, normalizados para média 1. A inclinação β é estimada por mínimos quadrados ponderados depois de centrar as variáveis dentro de cada UF, com uma penalização ridge leve (Hoerl e Kennard, 1970). Com os resíduos <i>r<sub>u</sub></i> dessa etapa, o intercepto nacional α<sub>0</sub> é a média ponderada dos resíduos, e os efeitos por UF e as inclinações próprias de cada UF são encolhidos (Efron e Morris, 1975):</p>
{EQ_ALFA}
<p>em que <i>x̄<sub>e</sub></i> é a média ponderada de <i>x</i> na UF. Entram no ajuste todas as unidades com votos contados, completas ou não, cada uma pela sua parte contada. A previsão para um conjunto de seções com proporção de referência <i>x</i> é</p>
{EQ_M}
<p>limitada ao intervalo [0,003; 0,997]. O termo β capta a tendência de o swing depender do nível de partida, que em 2026 foi expressiva (seção 6.1). Variantes com covariáveis adicionais, como o percentual dos demais candidatos no turno de referência e o tamanho da unidade, foram testadas e não melhoraram as projeções (Tabela 3).</p>
<h3>3.4 Combinação com o observado</h3>
<p>Em uma unidade parcialmente apurada, o desvio entre o que se viu e o que o modelo previa para a parte contada é informativo sobre a parte que falta. A previsão para a parte que falta combina as duas fontes:</p>
{EQ_CRED}
<p>em que <i>k<sub>u</sub></i> é o número de seções já contadas na unidade. O peso <i>W<sub>u</sub></i> tem a forma do fator de credibilidade de Bühlmann (1967): cresce com o número de seções observadas e com a razão entre a variabilidade da unidade em torno do modelo, {I_SU2}, e a variabilidade entre seções de uma mesma unidade, {I_SS2}. O valor de σ<sub>u</sub> é estimado a cada rodada por validação cruzada em 5 dobras (Stone, 1974) sobre as unidades já completas, com o erro ponderado pelos votos. Unidades completas têm <i>W<sub>u</sub></i> = 1 e não entram na previsão.</p>
<h3>3.5 Volume restante e agregação</h3>
<p>Os votos que ainda faltam em cada unidade são estimados a partir dos votos válidos do turno de referência nas seções que faltam, corrigidos pela razão entre votos atuais e votos de referência observada na própria unidade e encolhida para a razão da UF, <i>ρ̄<sub>e</sub></i>:</p>
{EQ_VOL}
<p>com <i>K</i> = 300 votos. A projeção nacional soma o que já foi contado e o que se espera do que falta:</p>
{EQ_AGR}
<h3>3.6 Incerteza</h3>
<p>O intervalo e a probabilidade de vitória vêm de <i>R</i> = 4.000 sorteios de Monte Carlo. Em cada sorteio <i>r</i>,</p>
{EQ_MC}
{EQ_AT}
<p>com {I_AT} truncado em [0, {I_VEM}], {I_ZN} um choque nacional, {I_ZE} um choque por UF, ξ<sub>e</sub> ~ N(0, 1) o ruído agregado das unidades e <i>f<sub>e</sub></i> = exp(σ<sub>v</sub>η<sub>e</sub>), com η<sub>e</sub> ~ N(0, 1), um choque de volume. O intervalo de 95% é formado pelos percentis 2,5 e 97,5 dos sorteios, e a probabilidade de vitória de A é a fração de sorteios acima de 50%.</p>
<p>Os parâmetros σ<sub>e</sub> e σ<sub>v</sub>, e um viés temporal <i>b</i>, vêm de um teste feito a cada rodada. Dentro de cada UF com pelo menos seis unidades completas, as unidades são ordenadas pelo horário em que fecharam. O modelo é ajustado na primeira metade e usado para prever a segunda. <i>b</i> é o erro médio ponderado dessas previsões, {I_SE2} é a variância entre UFs do erro médio descontado o ruído esperado, e σ<sub>v</sub> é a dispersão da razão de volume. Quando há menos de 30 unidades em cada metade, usam-se valores padrão. O choque nacional reúne três termos:</p>
{EQ_SIG}
<p>O primeiro termo faz o viés temporal entrar na incerteza só na medida em que o pareamento é imperfeito. Com seções identificadas, a ordem de chegada deixa de ser fonte de viés. O segundo é a deriva fora da amostra: a cada rodada, os votos que chegaram desde a anterior são comparados com o que a rodada anterior previa para aquelas mesmas seções, e o erro <i>e<sub>t</sub></i> alimenta uma média móvel, {I_SD}, desde que tenham chegado mais de 50 mil votos. O terceiro, com φ = 0,001 e <i>f</i><sub>rest</sub> a fração de votos que falta, impede que o intervalo encolha demais no fim, quando as últimas seções costumam ser as mais atípicas. Nem o viés temporal nem a deriva corrigem a estimativa pontual: nas reconstituições, essas correções pioraram as projeções (Tabela 3).</p>
<h3>3.7 Versões e implementação</h3>
<p>A ferramenta produz duas projeções a cada rodada. A projeção rápida aplica o mesmo modelo com a UF como unidade e precisa só dos 28 arquivos de totais por UF, incluindo o exterior, e da relação de seções. A projeção refinada usa a unidade município × zona. Para ela, a cada rodada são baixadas apenas as unidades ainda não encerradas, em ordem decrescente de eleitorado faltante, com no máximo oito conexões simultâneas, pausa entre pedidos e prazo de 300 segundos. UFs cujas zonas não chegam no prazo entram como uma unidade só. O motor foi escrito em C# e compilado pelo PowerShell, e o mesmo código roda nas reconstituições e ao vivo. As rodadas se repetiram a cada três a quatro minutos. Os parâmetros fixos estão na Tabela 2.</p>
{TAB2}

<h2>4 Validação retrospectiva</h2>
<h3>4.1 Desenho</h3>
<p>Cada noite da Tabela 1 é reproduzida com as seções na ordem real de chegada. Em 14 cortes, de 2% a 98% do eleitorado apurado, monta-se o que o TSE estaria mostrando: totais por unidade das seções já recebidas e relação de seções com as marcadas até aquele instante. A projeção é comparada com o resultado final pelo erro (projetado − real) e pela cobertura do intervalo de 95%. O erro absoluto médio (EAM) é calculado entre 5% e 98% do eleitorado apurado. As comparações incluem dois procedimentos sem modelo: o próprio placar e uma extrapolação simples, que aplica a parcial de cada UF ao eleitorado que nela falta. Incluem também o mesmo modelo sem saber quais seções chegaram, com a base rateada pelo eleitorado apurado.</p>
<h3>4.2 Resultados</h3>
<p>O pareamento é o que faz a diferença (Tabela 3 e Figura 2). Sem saber quais seções chegaram, o mesmo modelo erra em média {n(S22['zona, sem saber as secoes']['eam'], 2)} ponto em 2022 e {n(S26['zona, sem saber as secoes']['eam'], 2)} em 2026, e o erro tem sinal persistente durante boa parte da noite. Com as seções pareadas, o EAM cai para {n(S22[PAD]['eam'], 2)} e {n(S26[PAD]['eam'], 2)}. Já com 2% do eleitorado apurado, o erro foi de {n(S22[PAD]['erros'][0], 2)} ponto em 2022 e {n(S26[PAD]['erros'][0], 2)} em 2026. A unidade município × zona foi a melhor nas duas noites, mas a projeção rápida por UF ficou próxima ({n(S22['SECOES casadas, por UF (rapida)']['eam'], 2)} e {n(S26['SECOES casadas, por UF (rapida)']['eam'], 2)}), o que a torna útil como primeira leitura. As covariáveis não ajudaram, e as correções de viés temporal e de deriva pioraram as projeções, sobretudo no início da noite de 2026 ({n(S26['SECOES casadas, zona + correcoes']['erros'][0], 2).replace('-', '−')} ponto com 2% apurado), por isso ficaram fora do modelo padrão.</p>
<p>O teste de 2026 é mais exigente que o de 2022, porque usa como referência uma eleição de quatro anos antes, com parte das seções renumerada. Isso aparece na dispersão das unidades em torno do modelo: σ<sub>u</sub> ficou entre {n(min(d['sigu'] for d in D26), 1)} e {n(max(d['sigu'] for d in D26), 1)} pontos em 2026, contra {n(min(d['sigu'] for d in D22), 1)} a {n(max(d['sigu'] for d in D22), 1)} em 2022. Em consequência, κ caiu de {n(min(d['kappa'] for d in D22), 0)}–{n(max(d['kappa'] for d in D22), 0)} para {n(min(d['kappa'] for d in D26), 1)}–{n(max(d['kappa'] for d in D26), 1)}, e o desvio observado de cada unidade passou a pesar mais. Ainda assim, o EAM ficou em {n(S26[PAD]['eam'], 2)} ponto.</p>
{FIG2}
{TAB3}
<h3>4.3 Atraso da relação de seções</h3>
<p>Como a relação de seções e os totais são arquivos distintos, a marcação pode estar adiantada ou atrasada em relação aos totais. A Tabela 4 repete a noite de 2022 deslocando a marcação no tempo. Atrasos de até 2 minutos são inofensivos. Com 5 minutos, o EAM quase triplica, e com 15 a 30 minutos o método perde boa parte da vantagem e se aproxima do modelo sem pareamento. Marcação adiantada prejudica bem menos. Por isso, ao vivo, a relação de seções de cada UF é lida depois dos totais das zonas daquela UF.</p>
{TAB4}
<h3>4.4 Calibração do intervalo</h3>
<p>O intervalo de 95% do modelo padrão conteve o resultado nos 14 cortes de cada noite. Em 2022 ele foi conservador: com 20% apurado a meia-largura era de {n(d22[20]['meia'], 2)} ponto para um erro de {n(d22[20]['erro'], 2)}, e com 50%, de {n(d22[50]['meia'], 2)} para {n(d22[50]['erro'], 2)}. Em 2026, com a referência mais distante, as meias-larguras foram maiores ({n(d26[2]['meia'], 2)} ponto com 2% apurado e {n(d26[50]['meia'], 2)} com 50%), e os erros continuaram dentro delas. Duas noites não bastam para afirmar que a cobertura nominal é atingida, mas nenhuma das 28 verificações falhou.</p>

<h2>5 Aplicação ao vivo: 25 de outubro de 2026</h2>
<h3>5.1 Contexto</h3>
<p>A divulgação dos resultados começou às 17h05 e foi congelada às 17h07, depois que o ministro Cristiano Zanin, do Supremo Tribunal Federal, prorrogou a votação até as 19h. Ela foi retomada às 19h01. O placar oficial mostrou B à frente entre 19h47 e 20h23. A voltou à frente às 20h26, com 49% do eleitorado apurado, e venceu com 64.256.232 votos contra 59.826.041 ({n(REAL, 2)}% entre os dois). A ferramenta rodou de {R_INI.replace(':', 'h')} a {R_FIM.replace(':', 'h')}, em {N_RODADAS} rodadas, com o código inalterado desde 8 de outubro. Como várias rodadas podem ver o mesmo estado dos dados, a análise usa os {len(PTS)} estados distintos, identificados pela hora de geração dos totais. Destes, {len(POS)} são posteriores à retomada.</p>
<h3>5.2 Desempenho</h3>
<p>A Tabela 5 e a Figura 3 resumem a noite. Depois da retomada, a projeção refinada teve EAM de {n(FX[0]['eam_proj'], 2)} ponto até 5% apurado e de {n(FX[1]['eam_proj'], 2)} entre 5% e 20%. O placar errava, nas mesmas faixas, {n(FX[0]['eam_parcial'], 2)} e {n(FX[1]['eam_parcial'], 2)} pontos. Às {M_IC50['dados'].replace(':', 'h')}, com {n(M_IC50['pct'], 2)}% do eleitorado apurado, todo o intervalo passou para cima de 50% e não voltou, com probabilidade de vitória de A de {n(M_IC50['prob'], 1)}%. O placar só fixou A à frente às {M_PLAC['dados'].replace(':', 'h')}, com {n(M_PLAC['pct'], 0)}%. A partir de {n(M_025['pct'], 1)}% apurado, o erro não passou de 0,25 ponto; a partir de {n(M_010['pct'], 1)}%, não passou de 0,1. O intervalo conteve o resultado em todas as {COB} atualizações posteriores à retomada. A projeção rápida, por UF, seguiu a mesma trajetória com erros maiores: EAM de {n(FX[0]['eam_rapida'], 2)} e {n(FX[1]['eam_rapida'], 2)} ponto nas duas primeiras faixas.</p>
<p>Duas medidas de diagnóstico ajudam a ler a noite. A fração do eleitorado apurado com seções identificadas, <i>Q</i>, ficou entre {n(q_min, 0)}% e {n(q_max, 0)}% a partir de {M_IC50['dados'].replace(':', 'h')}. Antes disso, nas primeiras atualizações, chegou a 41%. O erro fora da amostra, medido sobre os votos que chegaram entre rodadas consecutivas, teve raiz do erro quadrático médio de {n(EN_RMS, 2)} ponto em {len(EN)} medições; é ele que alimenta o termo σ<sub>d</sub> da equação {e_sig}.</p>
{TAB5}
{FIG3}
<h3>5.3 Falha durante a suspensão da divulgação</h3>
<p>Entre 17h07 e 19h01, os totais oficiais ficaram parados em 62 seções, 0,04% do eleitorado. A ferramenta continuou rodando, e o resultado expõe uma fragilidade do intervalo. Na primeira rodada ({c_prim['ini'].replace(':', 'h')}), a relação de seções ainda não marcava nada (<i>Q</i> = 0), e o modelo, no modo de rateio, deu {n(c_prim['proj'], 2)}% [{n(c_prim['lo'], 2)}; {n(c_prim['hi'], 2)}], com probabilidade de vitória de A de {n(c_prim['prob'], 1)}%. Três minutos depois, com as mesmas 62 seções já identificadas (<i>Q</i> = 100%), passou a {n(c_long['proj'], 2)}% [{n(c_long['lo'], 2)}; {n(c_long['hi'], 2)}], com probabilidade de {n(c_long['prob'], 1)}%, e assim ficou em {c_long['n']} rodadas, até {c_long['fim'].replace(':', 'h')}. Esse intervalo não contém o resultado final. Os mesmos votos produziram probabilidades de {n(c_prim['prob'], 1)}% e {n(c_long['prob'], 1)}% com poucos minutos de diferença, sinal de que o intervalo não refletia a escassez de informação.</p>
<p>A causa está no desenho da simulação. Ela propaga os choques nacional, por UF, de unidade e de volume, mas trata os coeficientes ajustados (α<sub>0</sub>, α<sub>e</sub>, β) como conhecidos. Com dezenas de milhares de seções, o erro de estimação desses coeficientes é desprezível perto dos demais. Com 62 seções, justamente as primeiras a transmitir, ele domina. Além disso, abaixo de 30 unidades completas, σ<sub>u</sub> e σ<sub>e</sub> assumem valores padrão, e o piso da incerteza nacional foi pensado para o fim da apuração, não para o começo. Nessas condições, o choque nacional fica perto de 0,4 ponto, o valor padrão de σ<sub>d</sub>, qualquer que seja o número de unidades observadas, o que é compatível com a meia-largura de cerca de 0,9 ponto registrada. Na rodada das {c_19['ini'].replace(':', 'h')}, com a relação de seções já marcando as que começavam a chegar e os totais ainda parados nas 17h07, o intervalo se abriu para [{n(c_19['lo'], 2)}; {n(c_19['hi'], 2)}]. Depois da retomada, a falha não se repetiu.</p>
<p>Três correções são naturais. A primeira é incluir a incerteza dos parâmetros, por exemplo reamostrando unidades com bootstrap (Efron e Tibshirani, 1993) dentro de cada sorteio, ou somando ao choque nacional a variância de α<sub>0</sub> calculada com o tamanho efetivo da amostra de unidades. A segunda é um termo simétrico ao piso atual, que cresça quando a fração apurada é pequena. A terceira é uma regra mínima de publicação: não exibir probabilidade de vitória enquanto houver menos de, por exemplo, 30 unidades completas ou 0,5% do eleitorado apurado. Pelas reconstituições, com 2% do eleitorado apurado o modelo já é informativo.</p>

<h2>6 Discussão</h2>
<h3>6.1 Por que o pareamento funciona</h3>
<p>A explicação está na diferença entre níveis e variações. Nas {n(len(UN), 0)} unidades município × zona do 2º turno de 2026, o percentual de A tem desvio-padrão ponderado de {n(100 * SY, 1)} pontos. O swing em relação ao 1º turno tem desvio-padrão de {n(100 * SS, 2)} ponto (Figura 4). A razão entre as variâncias é de {n((SS / SY) ** 2, 3)}. Como o viés do placar vem da composição geográfica do que já chegou, e a composição pesa sobre os níveis, comparar cada seção com ela mesma elimina quase todo o problema. O que sobra é a heterogeneidade do swing, que é pequena e em parte previsível. Em 2026, o swing caiu com o nível de partida, com inclinação de {n(BETA, 3)} e correlação de {n(CORR, 2)}: A cresceu mais onde era mais fraco. Isso justifica o termo β da equação {e_reg}, que um swing uniforme puro ignoraria.</p>
{FIG4}
<p>O método se aproxima do modelo da BBC e da ITV (Curtice e Firth, 2008) ao modelar a mudança nos mesmos locais entre duas eleições, com duas diferenças. Aqui a fonte são os próprios votos apurados, não uma pesquisa de boca de urna, e o pareamento cobre todas as seções que chegam, não uma amostra. Não se tenta inferir transições individuais de voto, que exigiriam técnicas de inferência ecológica (Goodman, 1953; King, 1997). O modelo trata apenas da variação agregada de cada unidade.</p>
<h3>6.2 Limitações</h3>
<p>Primeiro, o método depende da atualidade da relação de seções. A Tabela 4 mostra que atrasos acima de alguns minutos corroem a vantagem, e ao vivo a qualidade do pareamento só é conhecida na hora; por isso <i>Q</i> é exibido a cada rodada e entra no intervalo. Segundo, o turno de referência precisa existir no nível da seção. Entre ciclos eleitorais parte das seções é renumerada (93,2% do eleitorado pareado entre 2022 e 2026), e a imputação pela média da unidade é uma aproximação. Terceiro, o intervalo omite a incerteza dos parâmetros, o que importa no início da apuração (seção 5.3). Quarto, o modelo trata a proporção entre dois candidatos. No 1º turno, a ferramenta foi usada com o mesmo modelo para essa proporção, e generalizar para vários candidatos exigiria um modelo multinomial do swing. Quinto, os hiperparâmetros (σ<sub>s</sub>, <i>K</i>, <i>n</i><sub>0</sub>) foram escolhidos com as mesmas duas noites usadas na validação, o que pode tornar as reconstituições otimistas. A noite de 2026, com o código congelado antes, é o teste verdadeiramente fora da amostra, mas é uma só.</p>

<h2>7 Conclusão</h2>
<p>Os dados públicos do TSE permitem, durante a apuração, comparar cada seção que chega com ela mesma no turno anterior. Um modelo simples sobre essa comparação, com uma regressão do swing com efeitos por UF, um peso de credibilidade para o desvio observado e uma simulação para a incerteza, reduziu o erro do placar parcial em mais de trinta vezes nas reconstituições. Ao vivo, apontou o vencedor do 2º turno de 2026 com menos de 2% do eleitorado apurado e ficou a menos de 0,1 ponto do resultado a partir de 30%. A principal lição da noite é sobre o começo da apuração: com poucas dezenas de seções, o intervalo precisa refletir também a incerteza dos parâmetros. A correção é simples, e os próximos passos são incorporá-la, testar o método em mais eleições, incluindo disputas estaduais, e estendê-lo a vários candidatos.</p>

<div class="decl">
<h2 class="decl-t">Declarações</h2>
<p><b>Contribuição do autor.</b> Gabriel Telles Teixeira concebeu o estudo, propôs o método e definiu suas características e nuances, supervisionou a construção do código, os testes e a operação ao vivo, e interpretou os resultados.</p>
<p><b>Uso de inteligência artificial.</b> O assistente de inteligência artificial Claude (Anthropic) auxiliou, sob supervisão do autor, na construção do código da ferramenta e nos testes do modelo, incluindo as reconstituições das noites de 2022 e de 2026, e na preparação do texto deste artigo a partir dos resultados e das orientações do autor. As decisões sobre o método e as conclusões foram tomadas ou aprovadas pelo autor, que revisou o código, os resultados e o texto e assume integral responsabilidade pelo conteúdo. A ferramenta não é autora do trabalho.</p>
<p><b>Financiamento.</b> Esta pesquisa não recebeu financiamento.</p>
<p><b>Conflito de interesses.</b> O autor é filiado ao Partido Socialismo e Liberdade (PSOL) desde 2006. A filiação reflete apenas posicionamento político: o autor nunca foi candidato, nunca exerceu cargo político ou partidário, remunerado ou não, e não participa das atividades do partido. O partido não teve nenhum papel no estudo. O código do modelo foi congelado 17 dias antes da eleição, e todos os resultados podem ser reproduzidos a partir de dados públicos. Não há outros conflitos de interesses a declarar.</p>
<p><b>Aspectos éticos.</b> O estudo usa apenas dados públicos, agregados por seção eleitoral, e não envolve dados pessoais.</p>
<p><b>Disponibilidade de dados e código.</b> Todos os dados são públicos e foram obtidos no Portal de Dados Abertos e no sistema de divulgação de resultados do TSE (Tribunal Superior Eleitoral, 2026a, 2026b). O código da ferramenta e das reconstituições está disponível mediante solicitação ao autor.</p>
</div>

<h2 class="ref">Referências</h2>
<ol class="refs">
{REFS}
</ol>
'''

CSS = '''
@page { size: A4; margin: 22mm 21mm 20mm;
  @top-left { content: "G. T. Teixeira"; font: italic 8.5pt 'STIX Two Text', serif; color: #777; }
  @top-right { content: "Projeção em tempo real com seções pareadas"; font: italic 8.5pt 'STIX Two Text', serif; color: #777; }
  @bottom-center { content: counter(page); font: 9pt 'STIX Two Text', serif; color: #555; } }
@page :first { @top-left { content: none; } @top-right { content: none; } }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body { font-family: 'STIX Two Text', 'Cambria', serif; font-size: 10.6pt; line-height: 1.5; color: #1A1A1A; text-align: justify; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
math { font-family: 'Cambria Math', 'STIX Two Math', math; font-size: 1.04em; }
a { color: inherit; text-decoration: none; }
.topo { display: flex; justify-content: space-between; font: 600 8pt Inter, sans-serif; letter-spacing: .08em; text-transform: uppercase; color: #6A6A6A; border-bottom: 0.6pt solid #1A1A1A; padding-bottom: 2mm; margin-bottom: 6mm; }
h1 { font-family: 'STIX Two Text', serif; font-size: 19pt; line-height: 1.22; font-weight: 700; margin: 0 0 4mm; text-align: left; }
.autor { font-size: 11.5pt; margin: 0; text-align: left; }
.autor a { text-decoration: underline; text-decoration-thickness: 0.5pt; text-underline-offset: 0.6mm; }
.afil { font-size: 9.5pt; font-style: italic; color: #555; margin: 0.5mm 0 6mm; text-align: left; }
.resumo { background: #F3F3F1; border-left: 1.2mm solid ACCENT; padding: 3.5mm 5mm; margin: 0 0 3.5mm; font-size: 9.6pt; line-height: 1.45; }
.resumo p { margin: 0 0 1.6mm; }
.resumo .pc { margin: 0; font-size: 9.2pt; }
.resumo.en { margin-bottom: 7mm; }
h2 { font: 700 12.5pt Inter, sans-serif; margin: 7mm 0 2.5mm; break-after: avoid; text-align: left; }
h3 { font: 600 10.5pt Inter, sans-serif; margin: 4.5mm 0 1.5mm; break-after: avoid; text-align: left; color: #222; }
p { margin: 0 0 2.6mm; orphans: 3; widows: 3; }
.eq { display: flex; align-items: center; justify-content: center; position: relative; margin: 2.5mm 0 3mm; break-inside: avoid; }
.eq math { display: block; }
.eqn { position: absolute; right: 0; font-size: 10pt; }
.eq mtd { text-align: left; padding: 0.2em 0.5em; }
figure { margin: 4mm auto 5mm; break-inside: avoid; }
figcaption { font: 8.6pt/1.4 Inter, sans-serif; color: #333; margin-top: 2mm; text-align: left; }
.tbloco { margin: 4mm 0 5mm; break-inside: avoid; }
table.tab { width: 100%; border-collapse: collapse; font: 8.6pt/1.35 Inter, sans-serif; border-top: 1.1pt solid #1A1A1A; border-bottom: 1.1pt solid #1A1A1A; }
table.tab caption { caption-side: top; text-align: left; font: 8.6pt/1.4 Inter, sans-serif; color: #333; margin-bottom: 1.8mm; }
table.tab th { text-align: left; font-weight: 600; padding: 1.3mm 1.6mm; border-bottom: 0.6pt solid #1A1A1A; vertical-align: bottom; }
table.tab td { padding: 1mm 1.6mm; vertical-align: top; text-align: left; }
table.tab td + td, table.tab th + th { text-align: right; }
table.tab tr.grp td { text-align: left; font-weight: 600; font-style: italic; padding-top: 2mm; color: #444; }
table.tab tbody tr:not(.grp) td:first-child { padding-left: 4mm; }
table.tab.larga td:first-child { width: 46%; }
.tnota { font: 7.8pt/1.4 Inter, sans-serif; color: #555; margin: 1.5mm 0 0; text-align: left; }
.decl { margin-top: 0; font-size: 9.2pt; line-height: 1.45; }
.decl p { margin-bottom: 1.5mm; }
h2.ref { margin-top: 5mm; }
ol.refs { padding-left: 6mm; margin: 0; font-size: 9pt; line-height: 1.36; text-align: left; }
ol.refs li { margin-bottom: 0.9mm; padding-left: 1mm; }
ol.refs a { overflow-wrap: anywhere; }
'''.replace('ACCENT', C_PROJ)

# a tabela 2 tem colunas de texto: alinhamento a esquerda
CSS += 'table.t2 td + td, table.t2 th + th { text-align: left; } table.t2 tbody tr td:first-child { padding-left: 1.6mm; width: 12%; } table.t2 td:nth-child(2) { width: 36%; }'
html = f'''<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Projeção em tempo real com seções pareadas</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=STIX+Two+Text:ital,wght@0,400;0,600;0,700;1,400&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body>{corpo}</body></html>'''
open(SAIDA, 'w', encoding='utf-8').write(html)
print('ok |', 'equacoes', NEQ[0], '| unidades', len(UN), '| fora do eixo', FORA, '| rodadas', N_RODADAS, '| estados', len(PTS), len(POS))
