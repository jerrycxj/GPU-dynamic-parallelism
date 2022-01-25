import numpy as np
import matplotlib.pyplot as plt
import sys
import tools as Q

# functional mapping for [work, wrf, time, speedup, speedup-sbr, speedup-mbr]
funcs = [lambda n,g,B,r,P,lam,A,q,c: Q.subdivWork(n, g, B, r, P, lam, A),
         lambda n,g,B,r,P,lam,A,q,c: Q.exhaustiveWork(n,A)/Q.subdivWork(n, g, B, r, P, lam, A),
         lambda n,g,B,r,P,lam,A,q,c: Q.subdivSBR(n, g, B, r, P, lam, A, q, c),
         lambda n,g,B,r,P,lam,A,q,c: [Q.exhaustive(n,A,q,c)/Q.subdivSBR(n, g, B, r, P, lam, A, q, c),
                                        Q.exhaustive(n,A,q,c)/Q.subdivMBR(n, g, B, r, P, lam, A, q, c)],
         lambda n,g,B,r,P,lam,A,q,c: Q.exhaustive(n,A,q,c)/Q.subdivSBR(n, g, B, r, P, lam, A, q, c),
         lambda n,g,B,r,P,lam,A,q,c: Q.exhaustive(n,A,q,c)/Q.subdivMBR(n, g, B, r, P, lam, A, q, c)]

# functional mapping for [work, wrf, time, speedup-sbr, speedup-mbr]
refFuncs = [lambda n,g,B,r,P,lam,A,q,c: Q.exhaustiveWork(n,A),
            lambda n,g,B,r,P,lam,A,q,c: Q.exhaustiveWork(n,A)/Q.exhaustiveWork(n,A),
            lambda n,g,B,r,P,lam,A,q,c: Q.exhaustive(n,A,q,c),
            lambda n,g,B,r,P,lam,A,q,c: Q.exhaustive(n,A,q,c)/Q.exhaustive(n,A,q,c),
            lambda n,g,B,r,P,lam,A,q,c: Q.exhaustive(n,A,q,c)/Q.exhaustive(n,A,q,c)]

# functional mapping for [work, wrf, time, speedup-sbr, speedup-mbr]
setYscale = [lambda ax: ax.set_yscale('log', base=2),
             lambda ax: ax.set_yscale('linear'),
             lambda ax: ax.set_yscale('log', base=2),
             lambda ax: ax.set_yscale('linear'),
             lambda ax: ax.set_yscale('linear')]

# functional mapping for [work, wrf, time, speedup-sbr, speedup-mbr]
setYlim = [lambda ax,ymin,ymax,dmin,dmax: ax.set_ylim(dmin, 1.2*dmax),
           lambda ax,ymin,ymax,dmin,dmax: ax.set_ylim(ymin, ymax),
           lambda ax,ymin,ymax,dmin,dmax: ax.set_ylim(dmin, 1.2*dmax),
           lambda ax,ymin,ymax,dmin,dmax: ax.set_ylim(ymin, ymax),
           lambda ax,ymin,ymax,dmin,dmax: ax.set_ylim(ymin, ymax)]

# functional mapping of variables
mvarMap = [lambda mvar,n,g,B,r,P,lam,A,q,c: [mvar,    g,    B,    r,    P,   lam,    A,    q,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   , mvar,    B,    r,    P,   lam,    A,    q,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   ,    g, mvar,    r,    P,   lam,    A,    q,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   ,    g,    B, mvar,    P,   lam,    A,    q,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   ,    g,    B,    r, mvar,   lam,    A,    q,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   ,    g,    B,    r,    P,  mvar,    A,    q,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   ,    g,    B,    r,    P,   lam, mvar,    q,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   ,    g,    B,    r,    P,   lam,    A, mvar,    c],
           lambda mvar,n,g,B,r,P,lam,A,q,c: [n   ,    g,    B,    r,    P,   lam,    A,    q, mvar]]

# ------------
# main code
# ------------
if len(sys.argv) !=22:
    print("\nEjecutar como python <prog> <measure> <n> <g> <B> <r> <P> <lam> <A> <q> <c> <mvar1> <mvar2> <mvar3> <mvar4> <MVAR> <VAR> <xmin> <xmax> <ymin> <ymax> <res>")
    print("measure = {work, wrf, time, speedup, speedup-sbr, speedup-mbr}")
    print("MVAR = {n, g, B, r, P, lam, A, q, c}")
    print("VAR = {n, g, B, r, P, lam, A, q, c}")
    print("res = number of points in [xmin, xmax]")
    exit(2)

# parameters
res = int(sys.argv[21])
measure = sys.argv[1]
n = np.full(res, int(sys.argv[2]))
g = np.full(res, int(sys.argv[3]))
B = np.full(res, int(sys.argv[4]))
r = np.full(res, int(sys.argv[5]))
P = np.full(res, float(sys.argv[6]))
lam = np.full(res, float(sys.argv[7]))
A = np.full(res, float(sys.argv[8]))
q = np.full(res, int(sys.argv[9]))
c = np.full(res, int(sys.argv[10]))

# multi parameters
mvar1 = np.full(res, float(sys.argv[11]))
mvar2 = np.full(res, float(sys.argv[12]))
mvar3 = np.full(res, float(sys.argv[13]))
mvar4 = np.full(res, float(sys.argv[14]))

MVAR = sys.argv[15]
VAR = sys.argv[16]

# maps
dFunc = {"work":0, "wrf":1, "time":2, "speedup":3, "speedup-sbr":4, "speedup-mbr":5}
dmvar = {"n":0, "g":1, "B":2, "r":3, "P":4, "lam":5, "A":6, "q":7, "c":8}
dmvarStr = {"n":"n", "g":"g", "B":"B", "r":"r", "P":"P", "lam":"\lambda", "A":"C_A", "q":"q", "c":"c"}
dLabel = {"work":r"${W}$",
          "wrf":r"$\Omega$",
          "time":"T",
          "speedup":r"S",
          "speedup-sbr":r"$S_{\textit{SBR}}$",
          "speedup-mbr":r"$S_{\textit{MBR}}$"}
dTitle = {"work":f"Theoretical Work vs ${dmvarStr[VAR]}$",
          "wrf":f"Theoretical $\Omega({VAR})$, multi-${dmvarStr[MVAR]}$",
          "time":f"Theoretical Execution Time [s] vs ${dmvarStr[VAR]}$",
          "speedup":f"Theoretical $S({VAR})$, multi-${dmvarStr[MVAR]}$",
          "speedup-sbr":r"Theoretical $S_{\textit{SBR}}$"+f"$({VAR})$, multi-${dmvarStr[MVAR]}$",
          "speedup-mbr":r"Theoretical $S_{\textit{MBR}}$"+f"$({VAR})$, multi-${dmvarStr[MVAR]}$"}
# x range
xmin = float(sys.argv[17])
xmax = float(sys.argv[18])

# y range
ymin = float(sys.argv[19])
ymax = float(sys.argv[20])

# creating xrange
print(f"[CMODEL]> MVAR={MVAR} VAR={VAR}")
print(f"[CMODEL]> n={n[0]} g={g[0]} B={B[0]} r={r[0]} P={P[0]} lam={lam[0]} A={A[0]} q={q[0]} c={c[0]}")
print(f"[CMODEL]> xmin={xmin} xmax={xmax} ymin={ymin} ymax={ymax} res={res}")
print(f"[CMODEL]> dFunc[{measure}] = {dFunc[measure]}")
xrange = np.linspace(xmin, xmax, res)
# creating plot
fig = plt.figure(figsize=(4,3))
ax = fig.add_subplot()
#fig, ax = plt.subplots()
plt.suptitle(dTitle[measure], y=0.93, fontsize=10)

if measure == "speedup" or measure == "speedup-sbr" or measure == "speedup-mbr":
    plt.title(Q.genSubtitle(measure,MVAR,VAR,n,g,B,r,P,lam,A,q,c), fontsize=8)
else:
    plt.title(Q.genSubtitle(measure,MVAR,VAR,n,g,B,r,P,lam,A,q,c), fontsize=9)

ax.set_xlabel(fr'${dmvarStr[VAR]}$')
ax.set_ylabel(dLabel[measure], rotation=0, labelpad=15)

if VAR == "n":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=2)
    n = xrange
    ax.set_xscale('log', base=2)
if VAR == "g":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=2)
    r = xrange
    ax.set_xscale('log', base=2)
if VAR == "B":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=2)
    B = xrange
    ax.set_xscale('log', base=2)
if VAR == "P":
    P = xrange
if VAR == "r":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=2)
    r = xrange
    ax.set_xscale('log', base=2)
if VAR == "lam":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=10)
    lam = xrange
    ax.set_xscale('log', base=10)
if VAR == "A":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=2)
    lam = xrange
    ax.set_xscale('log', base=2)
if VAR == "q":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=2)
    q = xrange
    ax.set_xscale('log', base=2)
if VAR == "c":
    xrange = np.logspace(np.log2(xmin), np.log2(xmax), res, base=2)
    c = xrange
    ax.set_xscale('log', base=2)


v = mvarMap[dmvar[MVAR]](mvar1,n,g,B,r,P,lam,A,q,c)
d1 = funcs[dFunc[measure]](v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8])
v = mvarMap[dmvar[MVAR]](mvar2,n,g,B,r,P,lam,A,q,c)
d2 = funcs[dFunc[measure]](v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8])
v = mvarMap[dmvar[MVAR]](mvar3,n,g,B,r,P,lam,A,q,c)
d3 = funcs[dFunc[measure]](v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8])
v = mvarMap[dmvar[MVAR]](mvar4,n,g,B,r,P,lam,A,q,c)
d4 = funcs[dFunc[measure]](v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8])

d5 = refFuncs[dFunc[measure]](v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8])

# refplot
if measure == "time" or measure == "work":
    refPlot,     = plt.plot(xrange, d5, label="Ex, "+Q.genLabel(MVAR, dmvarStr[MVAR], mvar4[0]), lw=2, ls=':', color=Q.cGrayscale[2])
else:
    refPlot,     = plt.plot(xrange, d5, lw=0.5, ls='--', color=Q.cGrayscale[2])

# mainplot
if measure=="speedup":
    # SBR part
    subdivPlot1, = plt.plot(xrange, d1[0], label="SBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar1[0]), lw=1, ls=":", color=Q.cTemporal[3])
    subdivPlot2, = plt.plot(xrange, d2[0], label="SBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar2[0]), lw=1, ls="-.", color=Q.cTemporal[2])
    subdivPlot3, = plt.plot(xrange, d3[0], label="SBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar3[0]), lw=1, ls="--", color=Q.cTemporal[1])
    subdivPlot4, = plt.plot(xrange, d4[0], label="SBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar4[0]), lw=1, ls="-", color=Q.cTemporal[0])

    # MBR part
    subdivPlot1b, = plt.plot(xrange, d1[1], label="MBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar1[0]), lw=1, ls=":", color=Q.cOrange[3])
    subdivPlot2b, = plt.plot(xrange, d2[1], label="MBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar2[0]), lw=1, ls="-.", color=Q.cOrange[2])
    subdivPlot3b, = plt.plot(xrange, d3[1], label="MBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar3[0]), lw=1, ls="--", color=Q.cOrange[1])
    subdivPlot4b, = plt.plot(xrange, d4[1], label="MBR, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar4[0]), lw=1, ls="-", color=Q.cOrange[0])
else:
    subdivPlot1, = plt.plot(xrange, d1, label="Sub, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar1[0]), lw=1, ls=":", color=Q.cTemporal[3])
    subdivPlot2, = plt.plot(xrange, d2, label="Sub, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar2[0]), lw=1, ls="-.", color=Q.cTemporal[2])
    subdivPlot3, = plt.plot(xrange, d3, label="Sub, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar3[0]), lw=1, ls="--", color=Q.cTemporal[1])
    subdivPlot4, = plt.plot(xrange, d4, label="Sub, " + Q.genLabel(MVAR, dmvarStr[MVAR], mvar4[0]), lw=1, ls="-", color=Q.cTemporal[0])


#plt.legend(loc="lower left", ncol=2, prop={"size":5.5}, bbox_to_anchor=(-0.2, -0.3))
if measure == "speedup" or measure == "speedup-sbr" or measure == "speedup-mbr":
    plt.legend(prop={"size":6.5}, ncol=2)
else:
    plt.legend(prop={"size":7})


#ax.margins(0.1)
setYscale[dFunc[measure]](ax)
ax.set_xlim([xmin, xmax])
if measure == "speedup":
    setYlim[dFunc[measure]](ax,ymin,ymax, min(Q.minmaxFromLists(min, d1[0], d2[0], d3[0], d4[0], d5[0]), Q.minmaxFromLists(min, d1[1], d2[1], d3[1], d4[1], d5[1])), max(Q.minmaxFromLists(max, d1[0],d2[0],d3[0],d4[0],d5[0]), Q.minmaxFromLists(max, d1[1],d2[1],d3[1],d4[1],d5[1])))
else:
    setYlim[dFunc[measure]](ax,ymin,ymax, Q.minmaxFromLists(min, d1,d2,d3,d4,d5), Q.minmaxFromLists(max, d1,d2,d3,d4,d5))
plt.tight_layout()
plt.savefig(f'../plots/theo-{measure}-multi{MVAR}-{VAR}.eps', format='eps')
#plt.show()
print("END\n\n")
