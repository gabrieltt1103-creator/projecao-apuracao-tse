// Motor da projecao de apuracao (2o turno em diante).
// Compilado pelo PowerShell 5.1 com Add-Type, portanto so C# 5: nada de $"...", ?., out var, tuplas.
// Usado tanto pela ferramenta ao vivo (projecao2.ps1) quanto pelas simulacoes (simular.ps1),
// para que o que foi testado seja exatamente o que roda na noite.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;

namespace Apuracao
{
    // =====================================================================================
    // Extracao dos boletins de urna (Portal de Dados Abertos do TSE): uma linha por secao
    // =====================================================================================
    public static class Extrator
    {
        class Acc { public int Aptos, Comp, Brancos, Nulos; public string Rec = ""; public Dictionary<int, int> V = new Dictionary<int, int>(); }

        // cargoNome: "Presidente", "Governador"... Devolve um resumo em texto.
        public static string Extrair(string zipPath, string outPath, string cargoNome, bool append)
        {
            Encoding enc = Encoding.GetEncoding(1252);
            Dictionary<string, Acc> acc = new Dictionary<string, Acc>(200000);
            long linhas = 0, usadas = 0;
            string marca = ";\"" + cargoNome + "\";";
            using (ZipArchive zip = ZipFile.OpenRead(zipPath))
            {
                ZipArchiveEntry ent = null;
                foreach (ZipArchiveEntry e in zip.Entries) if (e.Name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase)) { ent = e; break; }
                if (ent == null) throw new Exception("csv nao encontrado em " + zipPath);
                using (StreamReader sr = new StreamReader(ent.Open(), enc, false, 1 << 20))
                {
                    string[] cols = sr.ReadLine().Split(';');
                    Dictionary<string, int> ix = new Dictionary<string, int>();
                    for (int i = 0; i < cols.Length; i++) ix[cols[i].Trim('"')] = i;
                    int iUf = ix["SG_UF"], iMun = ix["CD_MUNICIPIO"], iZ = ix["NR_ZONA"], iS = ix["NR_SECAO"], iCg = ix["DS_CARGO_PERGUNTA"];
                    int iRec = ix["DT_BU_RECEBIDO"], iAp = ix["QT_APTOS"], iCo = ix["QT_COMPARECIMENTO"], iTp = ix["CD_TIPO_VOTAVEL"], iNr = ix["NR_VOTAVEL"], iQt = ix["QT_VOTOS"];
                    string line;
                    while ((line = sr.ReadLine()) != null)
                    {
                        linhas++;
                        if (line.IndexOf(marca, StringComparison.Ordinal) < 0) continue;
                        string[] f = line.Split(';');
                        if (f.Length < cols.Length) continue;
                        if (f[iCg].Trim('"') != cargoNome) continue;
                        usadas++;
                        string key = f[iUf].Trim('"').ToLowerInvariant() + ";" + f[iMun].Trim('"').PadLeft(5, '0') + ";" + f[iZ].Trim('"').PadLeft(4, '0') + ";" + f[iS].Trim('"').PadLeft(4, '0');
                        Acc a;
                        if (!acc.TryGetValue(key, out a))
                        {
                            a = new Acc(); acc[key] = a;
                            a.Aptos = int.Parse(f[iAp].Trim('"')); a.Comp = int.Parse(f[iCo].Trim('"'));
                            string r = f[iRec].Trim('"');   // 2022: dd/MM/yyyy HH:mm:ss   2026: yyyy-MM-dd HH:mm:ss
                            if (r.Length >= 19 && r[4] == '-') a.Rec = r.Substring(0, 4) + r.Substring(5, 2) + r.Substring(8, 2) + r.Substring(11, 2) + r.Substring(14, 2) + r.Substring(17, 2);
                            else if (r.Length >= 19) a.Rec = r.Substring(6, 4) + r.Substring(3, 2) + r.Substring(0, 2) + r.Substring(11, 2) + r.Substring(14, 2) + r.Substring(17, 2);
                        }
                        int qt = int.Parse(f[iQt].Trim('"'));
                        string tp = f[iTp].Trim('"');
                        if (tp == "2") a.Brancos += qt;
                        else if (tp == "3") a.Nulos += qt;
                        else
                        {
                            int nr; if (!int.TryParse(f[iNr].Trim('"'), out nr)) nr = -1;
                            int cur; a.V.TryGetValue(nr, out cur); a.V[nr] = cur + qt;
                        }
                    }
                }
            }
            using (StreamWriter sw = new StreamWriter(outPath, append, new UTF8Encoding(false)))
            {
                foreach (KeyValuePair<string, Acc> kv in acc)
                {
                    StringBuilder sb = new StringBuilder(kv.Key);
                    Acc a = kv.Value;
                    sb.Append(';').Append(a.Aptos).Append(';').Append(a.Comp).Append(';').Append(a.Rec).Append(';').Append(a.Brancos).Append(';').Append(a.Nulos).Append(';');
                    bool first = true;
                    foreach (KeyValuePair<int, int> v in a.V) { if (!first) sb.Append('|'); first = false; sb.Append(v.Key).Append(':').Append(v.Value); }
                    sw.WriteLine(sb.ToString());
                }
            }
            return Path.GetFileName(zipPath) + ": " + linhas + " linhas, " + usadas + " do cargo, " + acc.Count + " secoes";
        }
    }

    // =====================================================================================
    // Dados por secao
    // =====================================================================================
    public class Sec
    {
        public string Uf, Mun, Zona, Num;
        public int Aptos, Comp, Brancos, Nulos;
        public long T;                 // segundos desde 2000-01-01 (horario de Brasilia) em que o boletim chegou; 0 = desconhecido
        public int[] Nums, Votos;
        public string Chave { get { return Uf + ";" + Mun + ";" + Zona + ";" + Num; } }
        public int Voto(int n) { for (int i = 0; i < Nums.Length; i++) if (Nums[i] == n) return Votos[i]; return 0; }
        public int Validos() { int s = 0; for (int i = 0; i < Votos.Length; i++) s += Votos[i]; return s; }
    }

    public static class Dados
    {
        static readonly DateTime Epoca = new DateTime(2000, 1, 1);
        public static long Seg(string yyyymmddhhmmss)
        {
            if (yyyymmddhhmmss == null || yyyymmddhhmmss.Length < 14) return 0;
            DateTime d;
            if (!DateTime.TryParseExact(yyyymmddhhmmss.Substring(0, 14), "yyyyMMddHHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out d)) return 0;
            return (long)(d - Epoca).TotalSeconds;
        }
        public static string Hora(long seg) { return seg <= 0 ? "" : Epoca.AddSeconds(seg).ToString("dd/MM HH:mm:ss"); }

        public static List<Sec> Ler(string path)
        {
            List<Sec> l = new List<Sec>(500000);
            using (StreamReader sr = new StreamReader(path, Encoding.UTF8, false, 1 << 20))
            {
                string line;
                while ((line = sr.ReadLine()) != null)
                {
                    string[] f = line.Split(';');
                    if (f.Length < 10) continue;
                    Sec s = new Sec();
                    s.Uf = f[0]; s.Mun = f[1]; s.Zona = f[2]; s.Num = f[3];
                    s.Aptos = int.Parse(f[4]); s.Comp = int.Parse(f[5]); s.T = Seg(f[6]); s.Brancos = int.Parse(f[7]); s.Nulos = int.Parse(f[8]);
                    if (f[9].Length == 0) { s.Nums = new int[0]; s.Votos = new int[0]; }
                    else
                    {
                        string[] ps = f[9].Split('|');
                        s.Nums = new int[ps.Length]; s.Votos = new int[ps.Length];
                        for (int i = 0; i < ps.Length; i++) { int c = ps[i].IndexOf(':'); s.Nums[i] = int.Parse(ps[i].Substring(0, c)); s.Votos[i] = int.Parse(ps[i].Substring(c + 1)); }
                    }
                    l.Add(s);
                }
            }
            return l;
        }
        public static Dictionary<string, Sec> Indexar(List<Sec> l)
        {
            Dictionary<string, Sec> d = new Dictionary<string, Sec>(l.Count);
            foreach (Sec s in l) d[s.Chave] = s;
            return d;
        }
    }

    // =====================================================================================
    // Modelo
    // =====================================================================================
    // Uma unidade e um pedaco do pais (zona, municipio ou UF). Tem uma parte ja contada (C) e uma parte que falta (M).
    // "Base" e a eleicao de referencia (1o turno do mesmo ano, ou a eleicao anterior), medida nas MESMAS secoes
    // quando se sabe quais secoes chegaram (modo secao), ou rateada pelo eleitorado quando nao se sabe.
    public class Unid
    {
        public string Id, Uf;
        public double EleTot, EleC, SecTot, SecC;
        public double A, B;                                   // votos ja contados nos dois candidatos
        public bool BaseOk;
        public double bA_C, bB_C, bV_C, bA_M, bB_M, bV_M;      // base nas partes contada e faltante (V = validos totais da base)
        public double[] bO_C, bO_M;                           // outros candidatos da base
        public double Fim;                                    // instante em que a unidade fechou (0 = nao fechou)
        public double LogTam;
        // conjunto N: o que chegou entre a rodada anterior e esta (so para medir a deriva)
        public double nA, nB, bA_N, bB_N, bV_N; public double[] bO_N;
        // saidas
        public double YC, ModC, ModM, Res, W, PredM, VolM;
        public bool Completa { get { return SecTot > 0 && SecC >= SecTot; } }
    }

    public class Opcoes
    {
        public bool UsaOutros = false;     // % dos outros candidatos da base como variavel (transferencia de votos)
        public bool UsaTamanho = false;    // log do eleitorado da unidade como variavel
        public bool InclUf = true;         // inclinacao propria por UF (encolhida)
        public double PesoExp = 1.0;       // peso da unidade na regressao = votos ^ PesoExp
        public double SigmaSec = 0.03;     // desvio-padrao entre secoes da mesma unidade (para o peso do observado)
        public double Kappa = -1;          // se > 0, fixa o kappa em vez de calcular
        public double LambdaB = 0.0;       // quanto do vies temporal (cedo -> tarde) e aplicado na previsao (as simulacoes mostraram que atrapalha)
        public double PesoVies = 1.0;      // quanto do vies temporal entra no INTERVALO: 1 sem casamento por secao, 0 com casamento perfeito
        public double D = 0;               // correcao de deriva ja multiplicada pelo seu lambda
        public double SigmaDeriva = 0.003; // erro recente fora da amostra (o que chegou x o que se previa), entra no intervalo
        public double Ridge = 5.0, N0Uf = 3.0, N0Incl = 10.0, KRho = 300.0, PisoNat = 0.001;
        public int Folds = 5, Sims = 4000, Seed = 20261025;
    }

    public class Ajuste
    {
        public int P; public double[] B, Med; public double A0;
        public Dictionary<string, double> AUf = new Dictionary<string, double>();
        public Dictionary<string, double> SUf = new Dictionary<string, double>();
        public Dictionary<string, double> XUf = new Dictionary<string, double>();
        public int N;
    }

    public class Resultado
    {
        public double Acont, Bcont, Arem, Vrem, Share, Lo, Hi, PA50, Parcial, PctEle, PctSec;
        public double SigmaUnid, SigmaUf, SigmaNat, SigmaVol, VB, Kappa, ShareRem;
        public int NTreino, NCompletas;
        public Ajuste Fit;
        public Dictionary<string, double[]> PorUf = new Dictionary<string, double[]>();   // uf -> Acont, Vcont, Arem, Vrem, EleTot, EleC
    }

    public static class Modelo
    {
        static double Clip(double v) { return v < 0.003 ? 0.003 : (v > 0.997 ? 0.997 : v); }

        // variaveis de um conjunto de secoes da base: [0] = % de A entre A e B; depois outros candidatos; depois tamanho
        static double[] Vars(Opcoes op, double bA, double bB, double bV, double[] bO, double logTam)
        {
            int k = (op.UsaOutros && bO != null) ? bO.Length : 0;
            double[] z = new double[1 + k + (op.UsaTamanho ? 1 : 0)];
            z[0] = bA / (bA + bB);
            for (int i = 0; i < k; i++) z[1 + i] = bV > 0 ? bO[i] / bV : 0;
            if (op.UsaTamanho) z[z.Length - 1] = logTam;
            return z;
        }
        static double RefVar(Opcoes op, int j, int p) { if (j == 0) return 0.01; if (op.UsaTamanho && j == p - 1) return 0.25; return 0.0004; }

        static double[] Resolver(double[,] m, double[] v)
        {
            int n = v.Length; double[,] a = (double[,])m.Clone(); double[] b = (double[])v.Clone();
            for (int c = 0; c < n; c++)
            {
                int piv = c; for (int r = c + 1; r < n; r++) if (Math.Abs(a[r, c]) > Math.Abs(a[piv, c])) piv = r;
                if (Math.Abs(a[piv, c]) < 1e-14) continue;
                if (piv != c) { for (int k = 0; k < n; k++) { double t = a[c, k]; a[c, k] = a[piv, k]; a[piv, k] = t; } double tb = b[c]; b[c] = b[piv]; b[piv] = tb; }
                for (int r = 0; r < n; r++) { if (r == c) continue; double fct = a[r, c] / a[c, c]; if (fct == 0) continue; for (int k = c; k < n; k++) a[r, k] -= fct * a[c, k]; b[r] -= fct * b[c]; }
            }
            double[] x = new double[n];
            for (int i = 0; i < n; i++) x[i] = Math.Abs(a[i, i]) < 1e-14 ? 0 : b[i] / a[i, i];
            return x;
        }

        // Regressao do swing (y - x) com efeito fixo por UF, ponderada, com ridge. rows: uf, z, y, n (votos)
        public static Ajuste Ajustar(Opcoes op, List<string> ufs, List<double[]> zs, List<double> ys, List<double> ns)
        {
            Ajuste f = new Ajuste(); int n = ys.Count; f.N = n;
            int p = n > 0 ? zs[0].Length : 1; f.P = p; f.B = new double[p]; f.Med = new double[p];
            if (n == 0) return f;
            double[] w = new double[n]; double sw = 0;
            for (int i = 0; i < n; i++) { w[i] = Math.Pow(Math.Max(ns[i], 1.0), op.PesoExp); sw += w[i]; }
            for (int i = 0; i < n; i++) w[i] *= n / sw;      // peso medio 1
            Dictionary<string, double[]> mu = new Dictionary<string, double[]>();   // por UF: somas de w, w*d, w*z...
            for (int i = 0; i < n; i++)
            {
                double[] a; if (!mu.TryGetValue(ufs[i], out a)) { a = new double[2 + p]; mu[ufs[i]] = a; }
                double d = ys[i] - zs[i][0];
                a[0] += w[i]; a[1] += w[i] * d; for (int j = 0; j < p; j++) { a[2 + j] += w[i] * zs[i][j]; f.Med[j] += w[i] * zs[i][j] / n; }
            }
            double[,] m = new double[p, p]; double[] v = new double[p];
            for (int i = 0; i < n; i++)
            {
                double[] a = mu[ufs[i]]; double dd = (ys[i] - zs[i][0]) - a[1] / a[0];
                for (int j = 0; j < p; j++)
                {
                    double zj = zs[i][j] - a[2 + j] / a[0]; v[j] += w[i] * zj * dd;
                    for (int k = j; k < p; k++) m[j, k] += w[i] * zj * (zs[i][k] - a[2 + k] / a[0]);
                }
            }
            for (int j = 0; j < p; j++) { for (int k = 0; k < j; k++) m[j, k] = m[k, j]; m[j, j] += op.Ridge * RefVar(op, j, p); }
            f.B = Resolver(m, v);
            double[] e = new double[n]; double se = 0;
            Dictionary<string, double[]> eu = new Dictionary<string, double[]>();
            for (int i = 0; i < n; i++)
            {
                double pr = 0; for (int j = 0; j < p; j++) pr += f.B[j] * (zs[i][j] - f.Med[j]);
                e[i] = (ys[i] - zs[i][0]) - pr; se += w[i] * e[i];
                double[] a; if (!eu.TryGetValue(ufs[i], out a)) { a = new double[5]; eu[ufs[i]] = a; }
                a[0] += w[i]; a[1] += w[i] * e[i]; a[2] += w[i] * zs[i][0];
            }
            f.A0 = se / n;
            foreach (KeyValuePair<string, double[]> kv in eu) { double[] a = kv.Value; f.AUf[kv.Key] = (a[1] + op.N0Uf * f.A0) / (a[0] + op.N0Uf); f.XUf[kv.Key] = a[2] / a[0]; }
            if (op.InclUf)
            {
                for (int i = 0; i < n; i++) { double[] a = eu[ufs[i]]; double dx = zs[i][0] - f.XUf[ufs[i]]; a[3] += w[i] * dx * dx; a[4] += w[i] * dx * (e[i] - f.AUf[ufs[i]]); }
                foreach (KeyValuePair<string, double[]> kv in eu) f.SUf[kv.Key] = kv.Value[4] / (kv.Value[3] + op.N0Incl * 0.01);
            }
            return f;
        }

        public static double Prever(Ajuste f, string uf, double[] z)
        {
            double d = f.A0; double a;
            if (f.AUf.TryGetValue(uf, out a)) d = a;
            for (int j = 0; j < f.P && j < z.Length; j++) d += f.B[j] * (z[j] - f.Med[j]);
            double s; if (f.SUf.TryGetValue(uf, out s)) d += s * (z[0] - f.XUf[uf]);
            return Clip(z[0] + d);
        }

        static int Dobra(string id, int k) { unchecked { int h = 17; foreach (char c in id) h = h * 31 + c; return (int)((uint)h % (uint)k); } }
        static bool Treina(Unid u) { return u.BaseOk && (u.A + u.B) > 0 && (u.bA_C + u.bB_C) > 0 && u.bV_C > 0; }

        static Ajuste AjustarEm(Opcoes op, List<Unid> us, Predicate<Unid> filtro)
        {
            List<string> ufs = new List<string>(); List<double[]> zs = new List<double[]>(); List<double> ys = new List<double>(), ns = new List<double>();
            foreach (Unid u in us) { if (!Treina(u) || !filtro(u)) continue; ufs.Add(u.Uf); zs.Add(Vars(op, u.bA_C, u.bB_C, u.bV_C, u.bO_C, u.LogTam)); ys.Add(u.A / (u.A + u.B)); ns.Add(u.A + u.B); }
            return Ajustar(op, ufs, zs, ys, ns);
        }

        static double Normal(Random r) { double u1 = 1.0 - r.NextDouble(), u2 = r.NextDouble(); return Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Cos(2.0 * Math.PI * u2); }

        public static Resultado Projetar(List<Unid> us, Opcoes op)
        {
            Resultado R = new Resultado();
            List<Unid> treino = new List<Unid>(), completas = new List<Unid>();
            foreach (Unid u in us) { u.YC = (u.A + u.B) > 0 ? u.A / (u.A + u.B) : 0; if (Treina(u)) { treino.Add(u); if (u.Completa) completas.Add(u); } }
            R.NTreino = treino.Count; R.NCompletas = completas.Count;
            Ajuste fit = AjustarEm(op, us, delegate(Unid u) { return true; });
            R.Fit = fit;

            // (a) validacao cruzada nas unidades completas -> erro por unidade
            double sigU2 = 0.0004;   // padrao: 2 pontos
            if (completas.Count >= 30)
            {
                double sw = 0, sq = 0;
                for (int d = 0; d < op.Folds; d++)
                {
                    int dd = d;
                    Ajuste fk = AjustarEm(op, us, delegate(Unid u) { return !(u.Completa && Dobra(u.Id, op.Folds) == dd); });
                    foreach (Unid u in completas) { if (Dobra(u.Id, op.Folds) != d) continue; double e = u.YC - Prever(fk, u.Uf, Vars(op, u.bA_C, u.bB_C, u.bV_C, u.bO_C, u.LogTam)); double w = u.A + u.B; sw += w; sq += w * e * e; }
                }
                if (sw > 0) sigU2 = sq / sw;
            }
            R.SigmaUnid = Math.Sqrt(sigU2);

            // (b) teste temporal: ajusta nas que fecharam cedo, preve as que fecharam depois -> vies e dispersao entre UFs
            double VB = 0, sigUf2 = 0.000016, sigVol = 0.02; bool temTemporal = false;
            Dictionary<string, List<Unid>> porUf = new Dictionary<string, List<Unid>>();
            foreach (Unid u in completas) { if (u.Fim <= 0) continue; List<Unid> l; if (!porUf.TryGetValue(u.Uf, out l)) { l = new List<Unid>(); porUf[u.Uf] = l; } l.Add(u); }
            HashSet<string> cedo = new HashSet<string>(); List<Unid> tarde = new List<Unid>();
            foreach (KeyValuePair<string, List<Unid>> kv in porUf)
            {
                List<Unid> l = kv.Value; if (l.Count < 6) continue;
                l.Sort(delegate(Unid x, Unid y) { int c = x.Fim.CompareTo(y.Fim); return c != 0 ? c : string.CompareOrdinal(x.Id, y.Id); });
                int h = l.Count / 2; for (int i = 0; i < l.Count; i++) { if (i < h) cedo.Add(l[i].Id); else tarde.Add(l[i]); }
            }
            if (cedo.Count >= 30 && tarde.Count >= 30)
            {
                Ajuste fc = AjustarEm(op, us, delegate(Unid u) { return cedo.Contains(u.Id); });
                Dictionary<string, double[]> rho = new Dictionary<string, double[]>();
                foreach (Unid u in completas) { if (!cedo.Contains(u.Id)) continue; double[] a; if (!rho.TryGetValue(u.Uf, out a)) { a = new double[2]; rho[u.Uf] = a; } a[0] += u.A + u.B; a[1] += u.bV_C; }
                Dictionary<string, double[]> acc = new Dictionary<string, double[]>();
                foreach (Unid u in tarde)
                {
                    double[] a; if (!acc.TryGetValue(u.Uf, out a)) { a = new double[5]; acc[u.Uf] = a; }
                    double w = u.A + u.B; double e = u.YC - Prever(fc, u.Uf, Vars(op, u.bA_C, u.bB_C, u.bV_C, u.bO_C, u.LogTam));
                    a[0] += w; a[1] += w * e; a[2] += w * w; a[3] += w; double[] rr; if (rho.TryGetValue(u.Uf, out rr) && rr[1] > 0) a[4] += u.bV_C * rr[0] / rr[1]; else a[4] += w;
                }
                double WT = 0, sb = 0; foreach (double[] a in acc.Values) { WT += a[0]; sb += a[1]; }
                VB = sb / WT;
                double varObs = 0, ruido = 0, vt = 0, ct = 0;
                foreach (double[] a in acc.Values) { double bu = a[1] / a[0]; varObs += a[0] * (bu - VB) * (bu - VB) / WT; ruido += a[0] * (a[2] / (a[0] * a[0])) / WT; double rt = a[4] > 0 ? a[3] / a[4] - 1 : 0; vt += a[4] * rt * rt; ct += a[4]; }
                sigUf2 = Math.Max(0, varObs - ruido * sigU2);
                if (ct > 0) sigVol = Math.Sqrt(vt / ct);
                temTemporal = true;
            }
            R.VB = VB; R.SigmaUf = Math.Sqrt(sigUf2); R.SigmaVol = sigVol;

            double kappa = op.Kappa > 0 ? op.Kappa : (op.SigmaSec * op.SigmaSec) / Math.Max(sigU2, 1e-6);
            R.Kappa = kappa;

            // razao de volume (votos atuais por voto valido da base) e taxa por eleitor, por UF
            Dictionary<string, double[]> vol = new Dictionary<string, double[]>(); double[] vn = new double[6];
            foreach (Unid u in us)
            {
                double[] a; if (!vol.TryGetValue(u.Uf, out a)) { a = new double[6]; vol[u.Uf] = a; }
                double n2 = u.A + u.B;
                if (n2 > 0 && u.BaseOk && u.bV_C > 0) { a[0] += n2; a[1] += u.bV_C; vn[0] += n2; vn[1] += u.bV_C; }
                if (n2 > 0 && u.EleC > 0) { a[2] += n2; a[3] += u.EleC; vn[2] += n2; vn[3] += u.EleC; }
                a[4] += u.A; a[5] += n2; vn[4] += u.A; vn[5] += n2;
            }
            double rho0 = vn[1] > 0 ? vn[0] / vn[1] : 1.0, tau0 = vn[3] > 0 ? vn[2] / vn[3] : 0.75, y0 = vn[5] > 0 ? vn[4] / vn[5] : 0.5;

            double totEle = 0, totEleC = 0, totSec = 0, totSecC = 0;
            foreach (Unid u in us)
            {
                double[] a = vol[u.Uf];
                double rhoU = a[1] > 0 ? a[0] / a[1] : rho0, tauU = a[3] > 0 ? a[2] / a[3] : tau0, yU = a[5] > 0 ? a[4] / a[5] : y0;
                double n2 = u.A + u.B;
                totEle += u.EleTot; totEleC += u.EleC; totSec += u.SecTot; totSecC += u.SecC;
                u.W = n2 > 0 ? u.SecC / (u.SecC + kappa) : 0; u.Res = 0; u.ModC = 0; u.ModM = 0; u.PredM = 0; u.VolM = 0;
                if (u.Completa) { u.W = 1; continue; }
                if (u.BaseOk && u.bV_M > 0 && (u.bA_M + u.bB_M) > 0)
                {
                    u.ModM = Prever(fit, u.Uf, Vars(op, u.bA_M, u.bB_M, u.bV_M, u.bO_M, u.LogTam));
                    if (n2 > 0 && u.bV_C > 0 && (u.bA_C + u.bB_C) > 0) { u.ModC = Prever(fit, u.Uf, Vars(op, u.bA_C, u.bB_C, u.bV_C, u.bO_C, u.LogTam)); u.Res = u.YC - u.ModC; } else u.W = 0;
                    u.PredM = Clip(u.ModM + u.W * u.Res + op.LambdaB * VB * (1 - u.W) + op.D);
                    double rho = (n2 + op.KRho * rhoU) / (u.bV_C + op.KRho);
                    u.VolM = u.bV_M * rho;
                }
                else
                {
                    double eleM = Math.Max(0, u.EleTot - u.EleC);
                    u.ModM = yU; u.PredM = Clip(u.W * u.YC + (1 - u.W) * yU + op.D);
                    u.VolM = eleM * (n2 + 300.0 * tauU) / (u.EleC + 300.0);
                }
            }

            Dictionary<string, double[]> ag = R.PorUf;   // Acont, Vcont, Arem, Vrem, EleTot, EleC, S
            foreach (Unid u in us)
            {
                double[] a; if (!ag.TryGetValue(u.Uf, out a)) { a = new double[7]; ag[u.Uf] = a; }
                a[0] += u.A; a[1] += u.A + u.B; a[2] += u.VolM * u.PredM; a[3] += u.VolM; a[4] += u.EleTot; a[5] += u.EleC; a[6] += u.VolM * u.VolM * (1 - u.W);
                R.Acont += u.A; R.Bcont += u.B; R.Arem += u.VolM * u.PredM; R.Vrem += u.VolM;
            }
            double Vc = R.Acont + R.Bcont;
            R.Parcial = Vc > 0 ? R.Acont / Vc : 0.5;
            R.Share = (Vc + R.Vrem) > 0 ? (R.Acont + R.Arem) / (Vc + R.Vrem) : 0.5;
            R.ShareRem = R.Vrem > 0 ? R.Arem / R.Vrem : 0;
            R.PctEle = totEle > 0 ? totEleC / totEle : 0; R.PctSec = totSec > 0 ? totSecC / totSec : 0;

            // intervalo por simulacao: choque nacional + choque por UF + ruido de unidade + volume por UF
            double pv = op.PesoVies * VB;
            // piso: as ultimas secoes a chegar sao as mais atipicas, entao a incerteza por voto restante cresce quando sobra pouco
            double fRem = (Vc + R.Vrem) > 0 ? R.Vrem / (Vc + R.Vrem) : 1.0;
            double piso = op.PisoNat / Math.Sqrt(Math.Max(fRem, 0.0004));
            double sigNat = Math.Sqrt(pv * pv + op.SigmaDeriva * op.SigmaDeriva + piso * piso + (temTemporal ? 0 : op.PesoVies * op.PesoVies * 0.000025));
            R.SigmaNat = sigNat;
            Random rnd = new Random(op.Seed); double[] sims = new double[op.Sims]; int acima = 0;
            double sigU = Math.Sqrt(sigU2), sigUf = Math.Sqrt(sigUf2);
            List<double[]> lst = new List<double[]>(ag.Values);
            for (int i = 0; i < op.Sims; i++)
            {
                double zn = sigNat * Normal(rnd); double A = R.Acont, V = Vc;
                foreach (double[] a in lst)
                {
                    if (a[3] <= 0) continue;
                    double fv = Math.Exp(sigVol * Normal(rnd));
                    double ar = a[2] + a[3] * (zn + sigUf * Normal(rnd)) + Math.Sqrt(a[6]) * sigU * Normal(rnd);
                    if (ar < 0) ar = 0; if (ar > a[3]) ar = a[3];
                    A += fv * ar; V += fv * a[3];
                }
                sims[i] = V > 0 ? A / V : 0.5; if (sims[i] > 0.5) acima++;
            }
            Array.Sort(sims);
            R.Lo = sims[(int)(0.025 * (op.Sims - 1))]; R.Hi = sims[(int)Math.Ceiling(0.975 * (op.Sims - 1))]; R.PA50 = (double)acima / op.Sims;
            return R;
        }

        // Erro fora da amostra: os votos que chegaram desde a rodada anterior (conjunto N de cada unidade) vieram como
        // o modelo da rodada anterior previa? Devolve {erro em share, votos novos}.
        public static double[] Deriva(List<Unid> antes, Ajuste fit, Opcoes op, double VB)
        {
            double an = 0, vn = 0, ap = 0;
            foreach (Unid u in antes)
            {
                double n = u.nA + u.nB; if (n <= 0) continue;
                double pred;
                if (u.BaseOk && u.bV_N > 0 && (u.bA_N + u.bB_N) > 0) pred = Clip(Prever(fit, u.Uf, Vars(op, u.bA_N, u.bB_N, u.bV_N, u.bO_N, u.LogTam)) + u.W * u.Res + op.LambdaB * VB * (1 - u.W) + op.D);
                else pred = u.PredM > 0 ? u.PredM : u.YC;
                an += u.nA; vn += n; ap += n * pred;
            }
            return new double[] { vn > 0 ? (an - ap) / vn : 0, vn };
        }
    }

    // =====================================================================================
    // Simulacao de uma noite de apuracao a partir do horario de chegada de cada secao
    // =====================================================================================
    public class Ponto { public double Frac, Verdade, Simples, ErroDeriva, D, Q; public long T; public Resultado R; public List<Unid> Us; }

    public class Noite
    {
        public List<Sec> Atual; public int NumA, NumB;
        public Dictionary<string, Sec> BaseSec; public int BaseA, BaseB; public int[] BaseOutros;   // base por secao (mesma chave)
        public Dictionary<string, double[]> BaseUnid, BaseMun;                                     // ou base por unidade: {A, B, V, outros...}
        public double Verdade;
        public double LagCs = 0;   // so para simular: arquivo de secoes atrasado (>0) ou adiantado (<0), em segundos

        // Divide a base de uma unidade entre parte contada e parte que falta.
        // sR / sN: somas da base nas secoes marcadas como recebidas / nao marcadas; aptR / aptN: eleitorado delas;
        // eleC: eleitorado que o TSE diz ja ter apurado na unidade (a referencia que vale).
        // Se a marcacao bate com eleC, o casamento e exato. Se estiver adiantada ou atrasada, interpola.
        // Sem marcacao nenhuma (aptR = 0), vira o rateio simples pelo eleitorado.
        public static double[][] Casar(double[] sR, double[] sN, double aptR, double aptN, double eleC, bool completa)
        {
            int m = sR.Length; double fR, extra;
            if (completa) { fR = 1; extra = 1; }
            else if (aptR >= eleC) { fR = aptR > 0 ? eleC / aptR : 0; extra = 0; }
            else { fR = 1; extra = aptN > 0 ? Math.Min(1.0, (eleC - aptR) / aptN) : 0; }
            double[] c = new double[m], f = new double[m];
            for (int k = 0; k < m; k++) { c[k] = fR * sR[k] + extra * sN[k]; f[k] = Math.Max(0, sR[k] + sN[k] - c[k]); }
            return new double[][] { c, f };
        }

        // prepara os campos derivados: resultado final e fracao do eleitorado com secao correspondente na base
        public double[] Resumo()
        {
            double a = 0, b = 0, ele = 0, eleOk = 0, semHora = 0; long tmin = long.MaxValue, tmax = 0;
            foreach (Sec s in Atual)
            {
                a += s.Voto(NumA); b += s.Voto(NumB); ele += s.Aptos;
                if (BaseSec != null && BaseSec.ContainsKey(s.Chave)) eleOk += s.Aptos;
                if (s.T <= 0) semHora++; else { if (s.T < tmin) tmin = s.T; if (s.T > tmax) tmax = s.T; }
            }
            Verdade = a / (a + b);
            return new double[] { Atual.Count, a, b, ele, BaseSec != null ? eleOk / ele : -1, semHora, tmin, tmax };
        }

        // nivel: "zona", "mun" ou "uf". modoSecao: sabe-se quais secoes chegaram (base medida nas mesmas secoes).
        public List<Ponto> Rodar(string nivel, bool modoSecao, Opcoes op, double lambdaD, double derivaN0, double[] fracs)
        {
            int n = Atual.Count; int K = BaseSec != null ? BaseOutros.Length + 1 : -1;
            // unidade de cada secao
            Dictionary<string, int> idx = new Dictionary<string, int>(); List<string> ids = new List<string>(), ufsU = new List<string>(), munU = new List<string>();
            int[] un = new int[n];
            for (int i = 0; i < n; i++)
            {
                Sec s = Atual[i]; string id = nivel == "uf" ? s.Uf : (nivel == "mun" ? s.Uf + ";" + s.Mun : s.Uf + ";" + s.Mun + ";" + s.Zona);
                int j; if (!idx.TryGetValue(id, out j)) { j = ids.Count; idx[id] = j; ids.Add(id); ufsU.Add(s.Uf); munU.Add(s.Uf + ";" + s.Mun); }
                un[i] = j;
            }
            int U = ids.Count;
            double[] ele = new double[n], a = new double[n], b = new double[n];
            double[] eleU = new double[U], secU = new double[U];
            Dictionary<string, double> eleMun = new Dictionary<string, double>();
            for (int i = 0; i < n; i++)
            {
                Sec s = Atual[i]; ele[i] = s.Aptos; a[i] = s.Voto(NumA); b[i] = s.Voto(NumB); eleU[un[i]] += s.Aptos; secU[un[i]] += 1;
                double em; eleMun.TryGetValue(s.Uf + ";" + s.Mun, out em); eleMun[s.Uf + ";" + s.Mun] = em + s.Aptos;
            }
            // base por secao (com imputacao pela media da unidade quando a secao nao existe na base)
            double[][] bs = null; bool[] baseOkU = new bool[U]; double[][] bu = new double[U][];
            if (BaseSec != null)
            {
                bs = new double[n][]; double[][] soma = new double[U][]; double[] eleOk = new double[U];
                for (int j = 0; j < U; j++) soma[j] = new double[3 + K];
                for (int i = 0; i < n; i++)
                {
                    Sec t; if (!BaseSec.TryGetValue(Atual[i].Chave, out t)) continue;
                    double[] v = new double[3 + K]; v[0] = t.Voto(BaseA); v[1] = t.Voto(BaseB); v[2] = t.Validos(); double resto = v[2] - v[0] - v[1];
                    for (int k = 0; k < K - 1; k++) { v[3 + k] = t.Voto(BaseOutros[k]); resto -= v[3 + k]; }
                    v[3 + K - 1] = Math.Max(0, resto);
                    bs[i] = v; for (int k = 0; k < v.Length; k++) soma[un[i]][k] += v[k]; eleOk[un[i]] += ele[i];
                }
                for (int i = 0; i < n; i++) { if (bs[i] != null || eleOk[un[i]] <= 0) continue; double[] v = new double[3 + K]; for (int k = 0; k < v.Length; k++) v[k] = soma[un[i]][k] * ele[i] / eleOk[un[i]]; bs[i] = v; }
                for (int j = 0; j < U; j++) baseOkU[j] = eleOk[j] > 0 && (soma[j][0] + soma[j][1]) > 0;
            }
            else
            {
                for (int j = 0; j < U; j++)
                {
                    double[] v; if (BaseUnid.TryGetValue(ids[j], out v)) { bu[j] = v; baseOkU[j] = (v[0] + v[1]) > 0; continue; }
                    double[] pm; double em;
                    if (BaseMun != null && BaseMun.TryGetValue(munU[j], out pm) && eleMun.TryGetValue(munU[j], out em) && em > 0) { v = new double[pm.Length]; for (int k = 0; k < pm.Length; k++) v[k] = pm[k] * eleU[j] / em; bu[j] = v; baseOkU[j] = (v[0] + v[1]) > 0; }
                }
            }
            int[] ord = new int[n]; for (int i = 0; i < n; i++) ord[i] = i;
            Array.Sort(ord, delegate(int x, int y) { int c = Atual[x].T.CompareTo(Atual[y].T); return c != 0 ? c : x.CompareTo(y); });
            double eleTot = 0; for (int i = 0; i < n; i++) eleTot += ele[i];

            List<Ponto> saida = new List<Ponto>(); List<Unid> antes = null; Resultado rAntes = null; int posAntes = 0; double D = 0, sigDer2 = -1;
            foreach (double frac in fracs)
            {
                // posicao no vetor ordenado em que o eleitorado acumulado atinge a fracao (fechando o segundo inteiro)
                double cum = 0; int pos = 0;
                while (pos < n && cum < frac * eleTot) { cum += ele[ord[pos]]; pos++; }
                long T = pos > 0 ? Atual[ord[pos - 1]].T : 0;
                while (pos < n && Atual[ord[pos]].T <= T) pos++;

                // deriva: o que chegou entre a rodada anterior e esta, comparado com a previsao da rodada anterior
                double erroD = 0;
                if (antes != null && pos > posAntes)
                {
                    int Kb = bs != null ? K : 0;
                    foreach (Unid u in antes) { u.nA = 0; u.nB = 0; u.bA_N = 0; u.bB_N = 0; u.bV_N = 0; if (u.bO_N != null) Array.Clear(u.bO_N, 0, u.bO_N.Length); }
                    for (int q = posAntes; q < pos; q++)
                    {
                        int i = ord[q]; Unid u = antes[un[i]]; u.nA += a[i]; u.nB += b[i];
                        if (modoSecao && bs != null && bs[i] != null) { u.bA_N += bs[i][0]; u.bB_N += bs[i][1]; u.bV_N += bs[i][2]; if (u.bO_N == null) u.bO_N = new double[Kb]; for (int k = 0; k < Kb; k++) u.bO_N[k] += bs[i][3 + k]; }
                    }
                    if (!modoSecao) foreach (Unid u in antes) { u.bA_N = u.bA_M; u.bB_N = u.bB_M; u.bV_N = u.bV_M; u.bO_N = u.bO_M; }
                    op.D = lambdaD * D;
                    double[] dv = Modelo.Deriva(antes, rAntes.Fit, op, rAntes.VB);
                    erroD = dv[0];
                    if (dv[1] > 0) { double eta = dv[1] / (dv[1] + derivaN0); D += eta * erroD; sigDer2 = sigDer2 < 0 ? erroD * erroD : 0.5 * sigDer2 + 0.5 * erroD * erroD; }
                }

                // estado das unidades neste instante
                List<Unid> us = new List<Unid>(U);
                for (int j = 0; j < U; j++) { Unid u = new Unid(); u.Id = ids[j]; u.Uf = ufsU[j]; u.EleTot = eleU[j]; u.SecTot = secU[j]; u.LogTam = Math.Log10(Math.Max(eleU[j], 10)); u.BaseOk = baseOkU[j]; us.Add(u); }
                int Ko = bs != null ? K : (0);
                // R = secoes que o arquivo de secoes marca como recebidas (pode estar atrasado ou adiantado em LagCs segundos)
                double[] aptR = new double[U], aptN = new double[U]; double[][] sR = new double[U][], sN = new double[U][];
                if (bs != null) for (int j = 0; j < U; j++) { sR[j] = new double[3 + Ko]; sN[j] = new double[3 + Ko]; }
                for (int q = 0; q < n; q++)
                {
                    int i = ord[q]; Unid u = us[un[i]]; bool cont = q < pos;
                    if (cont) { u.EleC += ele[i]; u.SecC += 1; u.A += a[i]; u.B += b[i]; if (Atual[i].T > u.Fim) u.Fim = Atual[i].T; }
                    bool marc = modoSecao && Atual[i].T <= T - LagCs;
                    if (marc) aptR[un[i]] += ele[i]; else aptN[un[i]] += ele[i];
                    if (bs != null && bs[i] != null) { double[] dst = marc ? sR[un[i]] : sN[un[i]]; for (int k = 0; k < dst.Length; k++) dst[k] += bs[i][k]; }
                }
                for (int j = 0; j < U; j++)
                {
                    Unid u = us[j]; if (!u.Completa) u.Fim = 0;
                    if (bs != null)
                    {
                        double[][] cm = Casar(sR[j], sN[j], aptR[j], aptN[j], u.EleC, u.Completa);
                        u.bA_C = cm[0][0]; u.bB_C = cm[0][1]; u.bV_C = cm[0][2]; u.bA_M = cm[1][0]; u.bB_M = cm[1][1]; u.bV_M = cm[1][2];
                        u.bO_C = new double[Ko]; u.bO_M = new double[Ko]; for (int k = 0; k < Ko; k++) { u.bO_C[k] = cm[0][3 + k]; u.bO_M[k] = cm[1][3 + k]; }
                    }
                    else if (bu[j] != null)
                    {
                        // base so por unidade: rateada pelo eleitorado apurado
                        double[] v = bu[j]; int ko = v.Length - 3; double fr = u.EleTot > 0 ? u.EleC / u.EleTot : 0; if (u.Completa) fr = 1;
                        u.bO_C = new double[ko]; u.bO_M = new double[ko];
                        u.bA_C = v[0] * fr; u.bB_C = v[1] * fr; u.bV_C = v[2] * fr; u.bA_M = v[0] * (1 - fr); u.bB_M = v[1] * (1 - fr); u.bV_M = v[2] * (1 - fr);
                        for (int k = 0; k < ko; k++) { u.bO_C[k] = v[3 + k] * fr; u.bO_M[k] = v[3 + k] * (1 - fr); }
                    }
                    else { u.bO_C = new double[0]; u.bO_M = new double[0]; }
                }
                // qualidade do casamento: fracao do eleitorado apurado cujas secoes estao identificadas
                double qNum = 0, qDen = 0; for (int j = 0; j < U; j++) { qNum += Math.Min(us[j].EleC, aptR[j]); qDen += us[j].EleC; }
                double Q = (bs != null && qDen > 0) ? qNum / qDen : 0;
                op.D = lambdaD * D; op.SigmaDeriva = sigDer2 < 0 ? 0.003 : Math.Sqrt(sigDer2); op.PesoVies = 1 - Q;
                Resultado R = Modelo.Projetar(us, op);

                // referencia simples: extrapola cada UF pelo eleitorado que falta, com a parcial da propria UF
                double sA = R.Acont, sV = R.Acont + R.Bcont;
                foreach (double[] g in R.PorUf.Values) { if (g[5] > 0 && g[1] > 0) { double v = (g[4] - g[5]) * g[1] / g[5]; sA += v * g[0] / g[1]; sV += v; } else { double v = (g[4] - g[5]) * (R.Acont + R.Bcont) / Math.Max(1, cum); sA += v * R.Parcial; sV += v; } }
                Ponto p = new Ponto(); p.Frac = frac; p.T = T; p.R = R; p.Verdade = Verdade; p.Simples = sV > 0 ? sA / sV : 0.5; p.ErroDeriva = erroD; p.D = D; p.Q = Q; p.Us = us;
                saida.Add(p);
                antes = us; rAntes = R; posAntes = pos;
            }
            return saida;
        }

        // Para testar a montagem ao vivo: devolve o que o TSE mostraria (totais por unidade) e a marcacao de secoes
        // quando a fracao 'frac' do eleitorado ja chegou. tot: id -> {A, B, eleC, eleTot, secC, secTot, fim}
        public bool[] Sintetizar(double frac, string nivel, BaseSecoes b, Dictionary<string, double[]> tot)
        {
            int n = Atual.Count; int[] ord = new int[n]; for (int i = 0; i < n; i++) ord[i] = i;
            Array.Sort(ord, delegate(int x, int y) { int c = Atual[x].T.CompareTo(Atual[y].T); return c != 0 ? c : x.CompareTo(y); });
            double eleTot = 0; foreach (Sec s in Atual) eleTot += s.Aptos;
            double cum = 0; int pos = 0; while (pos < n && cum < frac * eleTot) { cum += Atual[ord[pos]].Aptos; pos++; }
            long T = pos > 0 ? Atual[ord[pos - 1]].T : 0; while (pos < n && Atual[ord[pos]].T <= T) pos++;
            bool[] marc = new bool[b.N];
            for (int q = 0; q < n; q++)
            {
                Sec s = Atual[ord[q]]; string id = nivel == "uf" ? s.Uf : (nivel == "mun" ? s.Uf + ";" + s.Mun : s.Uf + ";" + s.Mun + ";" + s.Zona);
                double[] t; if (!tot.TryGetValue(id, out t)) { t = new double[7]; tot[id] = t; }
                t[3] += s.Aptos; t[5] += 1;
                if (q < pos) { t[0] += s.Voto(NumA); t[1] += s.Voto(NumB); t[2] += s.Aptos; t[4] += 1; if (s.T > t[6]) t[6] = s.T; }
                int ib; if (s.T <= T - LagCs && b.Idx.TryGetValue(s.Chave, out ib)) marc[ib] = true;
            }
            foreach (double[] t in tot.Values) if (t[4] < t[5]) t[6] = 0;
            return marc;
        }
    }

    // =====================================================================================
    // Montagem ao vivo: base por secao + marcacao de secoes recebidas + totais por unidade vindos do TSE
    // =====================================================================================
    public class BaseSecoes
    {
        public int N, K; public string[] Uf, Mun, Zona, Num; public double[] Aptos; public double[][] V;   // V[i] = {A, B, validos, outros..., resto}
        public Dictionary<string, int> Idx = new Dictionary<string, int>();
        public double TotA, TotB, TotV, TotAptos;

        public static BaseSecoes Carregar(string path, int numA, int numB, int[] outros)
        {
            List<Sec> l = Dados.Ler(path); BaseSecoes b = new BaseSecoes(); int n = l.Count; b.N = n; b.K = outros.Length + 1;
            b.Uf = new string[n]; b.Mun = new string[n]; b.Zona = new string[n]; b.Num = new string[n]; b.Aptos = new double[n]; b.V = new double[n][];
            for (int i = 0; i < n; i++)
            {
                Sec s = l[i]; b.Uf[i] = s.Uf; b.Mun[i] = s.Mun; b.Zona[i] = s.Zona; b.Num[i] = s.Num; b.Aptos[i] = s.Aptos; b.Idx[s.Chave] = i;
                double[] v = new double[3 + b.K]; v[0] = s.Voto(numA); v[1] = s.Voto(numB); v[2] = s.Validos(); double resto = v[2] - v[0] - v[1];
                for (int k = 0; k < outros.Length; k++) { v[3 + k] = s.Voto(outros[k]); resto -= v[3 + k]; }
                v[3 + b.K - 1] = Math.Max(0, resto); b.V[i] = v;
                b.TotA += v[0]; b.TotB += v[1]; b.TotV += v[2]; b.TotAptos += s.Aptos;
            }
            return b;
        }
        public string IdUnid(int i, string nivel) { return nivel == "uf" ? Uf[i] : (nivel == "mun" ? Uf[i] + ";" + Mun[i] : Uf[i] + ";" + Mun[i] + ";" + Zona[i]); }

        // votos da base agregados por unidade: id -> {A, B, validos, aptos}
        public Dictionary<string, double[]> PorUnid(string nivel)
        {
            Dictionary<string, double[]> d = new Dictionary<string, double[]>();
            for (int i = 0; i < N; i++) { string id = IdUnid(i, nivel); double[] a; if (!d.TryGetValue(id, out a)) { a = new double[4]; d[id] = a; } a[0] += V[i][0]; a[1] += V[i][1]; a[2] += V[i][2]; a[3] += Aptos[i]; }
            return d;
        }
    }

    // =====================================================================================
    // Dados para o painel (painel.html): um objeto JSON por rodada
    // =====================================================================================
    public static class Painel
    {
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
        static string N(double v) { if (double.IsNaN(v) || double.IsInfinity(v)) return "null"; return v.ToString("0.######", Inv); }
        static string I(double v) { if (double.IsNaN(v) || double.IsInfinity(v)) return "null"; return Math.Round(v).ToString("0", Inv); }
        static string S(string s)
        {
            if (s == null) return "\"\"";
            StringBuilder b = new StringBuilder("\"");
            foreach (char c in s)
            {
                if (c == '"' || c == '\\') b.Append('\\').Append(c);
                else if (c == '<') b.Append("\\u003c");
                else if (c < 32) b.Append(' ');
                else b.Append(c);
            }
            return b.Append('"').ToString();
        }
        static void Meta(StringBuilder sb, Dictionary<string, string> meta, int numA, string nomeA, int numB, string nomeB)
        {
            sb.Append("\"meta\":{"); bool p = true;
            foreach (KeyValuePair<string, string> kv in meta) { if (!p) sb.Append(','); p = false; sb.Append(S(kv.Key)).Append(':').Append(S(kv.Value)); }
            sb.Append("},\"a\":{\"num\":").Append(numA).Append(",\"nome\":").Append(S(nomeA)).Append("},\"b\":{\"num\":").Append(numB).Append(",\"nome\":").Append(S(nomeB)).Append('}');
        }

        // Antes do primeiro voto: so a referencia do 1o turno
        public static string JsonVazio(Dictionary<string, string> meta, int numA, string nomeA, int numB, string nomeB, double baseA)
        {
            StringBuilder sb = new StringBuilder("{"); Meta(sb, meta, numA, nomeA, numB, nomeB);
            sb.Append(",\"nac\":{\"base\":").Append(N(baseA)).Append("}}");
            return sb.ToString();
        }

        // qual: {secoes identificadas (0-1), secoes marcadas, secoes principais, diferenca marcado x apurado, erro no que chegou (NaN se nao ha),
        //        votos novos, zonas baixadas, zonas ja fechadas, recusas do TSE}
        // hist: uma linha por rodada: {hora, % apurado, placar de A, projecao de A, limite inferior, superior, projecao rapida, probabilidade de A, secoes identificadas} (percentuais 0-100)
        public static string Json(List<Unid> us, Resultado res, Resultado rapida, Dictionary<string, string> nomes, Dictionary<string, string> meta,
                                  int numA, string nomeA, int numB, string nomeB, double[] qual, string[] ufsInteiras, List<string[]> hist)
        {
            Dictionary<string, double[]> ufs = new Dictionary<string, double[]>(), muns = new Dictionary<string, double[]>();
            double te = 0, est = 0, st = 0, ts = 0, ba = 0, bv = 0;
            foreach (Unid u in us)
            {
                string[] pp = u.Id.Split(';'); string km = pp.Length >= 2 ? pp[0] + ";" + pp[1] : u.Uf + ";";
                double[] a; if (!ufs.TryGetValue(u.Uf, out a)) { a = new double[8]; ufs[u.Uf] = a; }
                double[] m; if (!muns.TryGetValue(km, out m)) { m = new double[8]; muns[km] = m; }
                double xa = u.bA_C + u.bA_M, xv = xa + u.bB_C + u.bB_M;
                foreach (double[] g in new double[][] { a, m }) { g[0] += u.EleTot; g[1] += u.EleC; g[2] += u.A; g[3] += u.A + u.B; g[4] += u.VolM * u.PredM; g[5] += u.VolM; g[6] += xa; g[7] += xv; }
                te += u.EleTot; est += u.EleC; ts += u.SecTot; st += u.SecC; ba += xa; bv += xv;
            }
            StringBuilder sb = new StringBuilder(600000); sb.Append('{'); Meta(sb, meta, numA, nomeA, numB, nomeB);
            sb.Append(",\"nac\":{\"eleTot\":").Append(I(te)).Append(",\"eleC\":").Append(I(est)).Append(",\"secTot\":").Append(I(ts)).Append(",\"secC\":").Append(I(st));
            sb.Append(",\"ac\":").Append(I(res.Acont)).Append(",\"bc\":").Append(I(res.Bcont)).Append(",\"ar\":").Append(N(res.Arem)).Append(",\"vr\":").Append(N(res.Vrem));
            sb.Append(",\"proj\":").Append(N(res.Share)).Append(",\"lo\":").Append(N(res.Lo)).Append(",\"hi\":").Append(N(res.Hi)).Append(",\"prob\":").Append(N(res.PA50));
            sb.Append(",\"base\":").Append(N(bv > 0 ? ba / bv : double.NaN));
            if (rapida != null) sb.Append(",\"rapida\":").Append(N(rapida.Share)).Append(",\"rapidaLo\":").Append(N(rapida.Lo)).Append(",\"rapidaHi\":").Append(N(rapida.Hi));
            sb.Append("},\"qual\":{\"ident\":").Append(N(qual[0])).Append(",\"marcadas\":").Append(I(qual[1])).Append(",\"principais\":").Append(I(qual[2])).Append(",\"dif\":").Append(N(qual[3]));
            sb.Append(",\"erroNovo\":").Append(N(qual[4])).Append(",\"votosNovos\":").Append(I(qual[5])).Append(",\"zonasBaixadas\":").Append(I(qual[6])).Append(",\"zonasFechadas\":").Append(I(qual[7])).Append(",\"recusas\":").Append(I(qual[8]));
            sb.Append(",\"ufsInteiras\":[");
            if (ufsInteiras != null) for (int i = 0; i < ufsInteiras.Length; i++) { if (i > 0) sb.Append(','); sb.Append(S(ufsInteiras[i])); }
            sb.Append("]},\"ufs\":[");
            bool p = true;
            foreach (KeyValuePair<string, double[]> kv in ufs) { if (!p) sb.Append(','); p = false; sb.Append('[').Append(S(kv.Key)); foreach (double v in kv.Value) sb.Append(',').Append(N(Math.Round(v, 1))); sb.Append(']'); }
            sb.Append("],\"muns\":["); p = true;
            foreach (KeyValuePair<string, double[]> kv in muns)
            {
                string uf = kv.Key.Substring(0, 2); string nm;
                if (kv.Key.Length <= 3) nm = "(UF inteira)"; else if (nomes == null || !nomes.TryGetValue(kv.Key, out nm)) nm = kv.Key.Substring(3);
                if (!p) sb.Append(','); p = false; sb.Append('[').Append(S(uf)).Append(',').Append(S(nm)); foreach (double v in kv.Value) sb.Append(',').Append(N(Math.Round(v, 1))); sb.Append(']');
            }
            sb.Append("],\"hist\":["); p = true;
            if (hist != null) foreach (string[] r in hist)
            {
                if (!p) sb.Append(','); p = false; sb.Append('[').Append(S(r[0]));
                for (int i = 1; i < r.Length; i++) { double v; sb.Append(','); if (double.TryParse(r[i], NumberStyles.Float, Inv, out v)) sb.Append(N(v)); else sb.Append("null"); }
                sb.Append(']');
            }
            sb.Append("]}");
            return sb.ToString();
        }
    }

    public static class Vivo
    {
        static readonly Regex RxCs = new Regex("\\{\\s*\"cd\"\\s*:\\s*\"(?<m>\\d{5})\"\\s*,\\s*\"nm\"|\\{\\s*\"cd\"\\s*:\\s*\"(?<z>\\d{4})\"\\s*,\\s*\"sec\"|\\{\\s*\"ns\"\\s*:\\s*\"(?<s>\\d+)\"(?<r>[^}]*)\\}", RegexOptions.Compiled);
        static readonly Regex RxData = new Regex("\"da\"\\s*:\\s*\"(\\d\\d)/(\\d\\d)/(\\d{4})\"\\s*,\\s*\"ha\"\\s*:\\s*\"(\\d\\d):(\\d\\d):(\\d\\d)\"", RegexOptions.Compiled);

        // Le o arquivo de configuracao de secoes de uma UF e marca, na ordem da base, as secoes que ja tem data/hora
        // (alguma coisa da secao ja chegou ao TSE). minData (yyyyMMddHHmmss): ignora marcacoes anteriores a isso.
        // Devolve {principais no arquivo, marcadas, sem correspondencia na base}.
        public static int[] LerCs(BaseSecoes b, bool[] marc, string uf, string texto, long minData)
        {
            int princ = 0, marcadas = 0, semBase = 0; string mun = "", zona = "";
            foreach (Match m in RxCs.Matches(texto))
            {
                if (m.Groups["m"].Success) { mun = m.Groups["m"].Value; continue; }
                if (m.Groups["z"].Success) { zona = m.Groups["z"].Value; continue; }
                string r = m.Groups["r"].Value;
                if (r.IndexOf("\"nsp\"", StringComparison.Ordinal) >= 0) continue;   // secao agregada a outra
                princ++;
                Match d = RxData.Match(r); bool tem = false;
                if (d.Success) { long v = long.Parse(d.Groups[3].Value + d.Groups[2].Value + d.Groups[1].Value + d.Groups[4].Value + d.Groups[5].Value + d.Groups[6].Value); tem = v >= minData; }
                int i; if (!b.Idx.TryGetValue(uf + ";" + mun + ";" + zona + ";" + m.Groups["s"].Value.PadLeft(4, '0'), out i)) { semBase++; continue; }
                if (tem) { marc[i] = true; marcadas++; }
            }
            return new int[] { princ, marcadas, semBase };
        }

        // tot: id da unidade -> {A, B, eleitorado apurado, eleitorado total, secoes totalizadas, secoes totais, fim (segundos; 0 se nao fechou)}
        // qual (saida): {fracao do eleitorado apurado com secao identificada, eleitorado marcado, eleitorado apurado segundo o TSE}
        public static List<Unid> Montar(BaseSecoes b, bool[] marc, string nivel, Dictionary<string, double[]> tot, double[] qual)
        {
            Dictionary<string, int> ix = new Dictionary<string, int>(); List<Unid> us = new List<Unid>();
            List<double[]> sR = new List<double[]>(), sN = new List<double[]>(); List<double[]> ap = new List<double[]>(); List<bool> doTse = new List<bool>();
            foreach (KeyValuePair<string, double[]> kv in tot)
            {
                Unid u = new Unid(); u.Id = kv.Key; u.Uf = kv.Key.Substring(0, 2); double[] t = kv.Value;
                u.A = t[0]; u.B = t[1]; u.EleC = t[2]; u.EleTot = t[3]; u.SecC = t[4]; u.SecTot = t[5]; u.Fim = t[6];
                ix[kv.Key] = us.Count; us.Add(u); sR.Add(new double[3 + b.K]); sN.Add(new double[3 + b.K]); ap.Add(new double[3]); doTse.Add(true);
            }
            bool misto = nivel == "misto";   // zona onde ha dado por zona; senao a UF inteira, se houver; senao a zona como nao apurada
            for (int i = 0; i < b.N; i++)
            {
                string id = misto ? b.IdUnid(i, "zona") : b.IdUnid(i, nivel); int j;
                if (misto && !ix.ContainsKey(id) && ix.ContainsKey(b.Uf[i])) id = b.Uf[i];
                if (!ix.TryGetValue(id, out j))
                {
                    // unidade sem dado do TSE nesta rodada: entra como ainda nao apurada, com o eleitorado da base
                    Unid u = new Unid(); u.Id = id; u.Uf = b.Uf[i]; j = us.Count; ix[id] = j; us.Add(u);
                    sR.Add(new double[3 + b.K]); sN.Add(new double[3 + b.K]); ap.Add(new double[3]); doTse.Add(false);
                }
                double[] dst = marc[i] ? sR[j] : sN[j]; double[] v = b.V[i]; for (int k = 0; k < dst.Length; k++) dst[k] += v[k];
                if (marc[i]) ap[j][0] += b.Aptos[i]; else ap[j][1] += b.Aptos[i];
                ap[j][2] += 1;
            }
            double qNum = 0, qDen = 0, eleMarc = 0;
            for (int j = 0; j < us.Count; j++)
            {
                Unid u = us[j];
                if (!doTse[j]) { u.EleTot = ap[j][0] + ap[j][1]; u.SecTot = ap[j][2]; }
                u.LogTam = Math.Log10(Math.Max(u.EleTot, 10));
                u.BaseOk = (sR[j][0] + sR[j][1] + sN[j][0] + sN[j][1]) > 0;
                double[][] cm = Noite.Casar(sR[j], sN[j], ap[j][0], ap[j][1], u.EleC, u.Completa);
                u.bA_C = cm[0][0]; u.bB_C = cm[0][1]; u.bV_C = cm[0][2]; u.bA_M = cm[1][0]; u.bB_M = cm[1][1]; u.bV_M = cm[1][2];
                u.bO_C = new double[b.K]; u.bO_M = new double[b.K]; for (int k = 0; k < b.K; k++) { u.bO_C[k] = cm[0][3 + k]; u.bO_M[k] = cm[1][3 + k]; }
                if (!u.Completa) u.Fim = 0;
                qNum += Math.Min(u.EleC, ap[j][0]); qDen += u.EleC; eleMarc += ap[j][0];
            }
            if (qual != null && qual.Length >= 3) { qual[0] = qDen > 0 ? qNum / qDen : 0; qual[1] = eleMarc; qual[2] = qDen; }
            return us;
        }

        // Prepara, nas unidades da rodada anterior, o conjunto N (o que chegou desde entao) para medir o erro fora da amostra.
        public static void Novos(BaseSecoes b, bool[] marcAntes, bool[] marcAgora, string nivel, List<Unid> antes, Dictionary<string, double[]> totAgora)
        {
            Dictionary<string, Unid> ix = new Dictionary<string, Unid>(); bool misto = nivel == "misto";
            Dictionary<string, double[]> porUf = new Dictionary<string, double[]>();   // soma das zonas de agora, por UF (para unidades que antes eram a UF inteira)
            foreach (KeyValuePair<string, double[]> kv in totAgora) { if (kv.Key.Length <= 2) continue; string uf = kv.Key.Substring(0, 2); double[] a; if (!porUf.TryGetValue(uf, out a)) { a = new double[2]; porUf[uf] = a; } a[0] += kv.Value[0]; a[1] += kv.Value[1]; }
            foreach (Unid u in antes)
            {
                ix[u.Id] = u; u.nA = 0; u.nB = 0; u.bA_N = 0; u.bB_N = 0; u.bV_N = 0; u.bO_N = new double[b.K]; double[] t;
                if (totAgora.TryGetValue(u.Id, out t)) { u.nA = Math.Max(0, t[0] - u.A); u.nB = Math.Max(0, t[1] - u.B); }
                else if (u.Id.Length <= 2 && porUf.TryGetValue(u.Id, out t)) { u.nA = Math.Max(0, t[0] - u.A); u.nB = Math.Max(0, t[1] - u.B); }
            }
            for (int i = 0; i < b.N; i++)
            {
                if (!marcAgora[i] || marcAntes[i]) continue;
                string id = misto ? b.IdUnid(i, "zona") : b.IdUnid(i, nivel);
                if (misto && !ix.ContainsKey(id)) id = b.Uf[i];
                Unid u; if (!ix.TryGetValue(id, out u)) continue;
                double[] v = b.V[i]; u.bA_N += v[0]; u.bB_N += v[1]; u.bV_N += v[2]; for (int k = 0; k < b.K; k++) u.bO_N[k] += v[3 + k];
            }
        }
    }
}
