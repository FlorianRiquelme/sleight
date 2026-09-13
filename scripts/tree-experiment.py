#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["scikit-learn", "numpy"]
# ///
"""Would a learned classifier beat the hand-written rules on the current fixtures?

Fits shallow decision trees on every still, fully-visible frame in recordings/*.jsonl, once on
the 16 hand-designed features the rules use and once on the 42 raw wrist-normalized landmarks,
and prints per-frame confusion next to the shipped thresholds. Cross-validation holds out a
contiguous fifth of every recording. The trees are printed so their splits can be read against
GestureClassifier.swift.

Run:  uv run scripts/tree-experiment.py        (from the repo root)

Result on 2026-09-13 (see docs/decisions.md): on the hand features the tree rediscovers the same
splits and needs depth 6 to match the rules; on raw landmarks it does slightly better per frame
but splits on knuckle positions that encode one user's left hand at one distance. Re-run once the
fixtures include the right hand and a second distance; if the raw-landmark tree still holds
there, a personal model is a fair option. `rules()` below must be kept in step with the Swift
classifier or the comparison is meaningless.
"""
import json, math, glob, os, numpy as np
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.metrics import confusion_matrix
J=['VNHLKWRI','VNHLKTCMC','VNHLKTMP','VNHLKTIP','VNHLKTTIP','VNHLKIMCP','VNHLKIPIP','VNHLKIDIP','VNHLKITIP','VNHLKMMCP','VNHLKMPIP','VNHLKMDIP','VNHLKMTIP','VNHLKRMCP','VNHLKRPIP','VNHLKRDIP','VNHLKRTIP','VNHLKPMCP','VNHLKPPIP','VNHLKPDIP','VNHLKPTIP']
F=[('VNHLKITIP','VNHLKIPIP'),('VNHLKMTIP','VNHLKMPIP'),('VNHLKRTIP','VNHLKRPIP'),('VNHLKPTIP','VNHLKPPIP')]
def d(a,b): return math.hypot(a[0]-b[0],a[1]-b[1])
def hand_features(p):
    w=p['VNHLKWRI']; m=p['VNHLKMMCP']; size=d(w,m)
    reach=[d(p[t],w)/d(p[pp],w) for t,pp in F]
    tips=[d(p[t],w)/size for t,_ in F]
    xs=[v[0] for v in p.values()]; ys=[v[1] for v in p.values()]
    return dict(reach_i=reach[0],reach_m=reach[1],reach_r=reach[2],reach_l=reach[3],
        tip_max=max(tips),tip_mean=sum(tips)/4,ext=math.hypot(max(xs)-min(xs),max(ys)-min(ys)),size=size,
        span=d(p['VNHLKIMCP'],p['VNHLKPMCP'])/size,ang=math.degrees(math.atan2(m[1]-w[1],m[0]-w[0])),
        thumb_straight=d(p['VNHLKTTIP'],w)/d(p['VNHLKTIP'],w),thumb_clear=d(p['VNHLKTTIP'],p['VNHLKIMCP'])/size,
        thumb_up=(p['VNHLKTTIP'][1]-p['VNHLKIMCP'][1])/size,wrist_y=w[1],
        n_ext=sum(r>1.15 for r in reach),n_curl=sum(r<0.85 for r in reach))
def raw_features(p):
    w=p['VNHLKWRI']; size=d(w,p['VNHLKMMCP']); out={}
    for j in J: out['x_'+j[5:]]=(p[j][0]-w[0])/size; out['y_'+j[5:]]=(p[j][1]-w[1])/size
    return out
def rules(f, min_open=0.19, min_closed=0.11, max_span=0.6):
    e=[f['reach_i']>1.15,f['reach_m']>1.15,f['reach_r']>1.15,f['reach_l']>1.15]
    c=[f['reach_i']<0.85,f['reach_m']<0.85,f['reach_r']<0.85,f['reach_l']<0.85]
    th=f['thumb_straight']>1.1 and f['thumb_clear']>0.6; g=None
    if sum(e)==4: g='openPalm'
    elif all(c) and not th and f['tip_max']<0.9: g='fist'
    elif e[0] and e[1] and c[2] and c[3]: g='twoFingers'
    elif all(c) and th and f['thumb_up']>0.3: g='thumbsUp'
    if g in ('openPalm','twoFingers') and f['ext']<min_open: g=None
    if g in ('fist','thumbsUp') and f['ext']<min_closed: g=None
    if g in ('openPalm','twoFingers','fist') and f['span']>max_span: g=None
    return g or 'none'
rows=[]
for path in sorted(glob.glob('recordings/*.jsonl')):
    lines=[json.loads(l) for l in open(path)]; label=lines[0]['label']; frames=lines[1:]
    if label.startswith('swipe'): continue
    kept=[]
    for i,r in enumerate(frames):
        h=r.get('hand')
        if not h or len(h['p'])<21: continue
        if label!='none' and r['d']['speed']>0.4: continue   # static classifier only sees still frames
        kept.append((i,r))
    n=len(kept)
    for k,(i,r) in enumerate(kept):
        p=r['hand']['p']
        rows.append(dict(label=label,fixture=os.path.basename(path),chunk=min(4,5*k//max(1,n)),A=hand_features(p),B=raw_features(p)))
labels=sorted({r['label'] for r in rows}); print('classes',labels)
from collections import Counter; print('frames per fixture', Counter(r['fixture'] for r in rows))
y=np.array([r['label'] for r in rows]); chunk=np.array([r['chunk'] for r in rows])
def matrix(name, Xkeys, X):
    print('\n'+'='*70+'\n'+name)
    for cw in (None,'balanced'):
      for depth in (3,4,6):
        # blocked 5-fold CV: hold out one contiguous fifth of every fixture
        pred=np.empty_like(y)
        for k in range(5):
            tr=chunk!=k; te=chunk==k
            clf=DecisionTreeClassifier(max_depth=depth,class_weight=cw,random_state=0).fit(X[tr],y[tr]); pred[te]=clf.predict(X[te])
        report(f'depth {depth} {cw or "unweighted"}, CV',pred)
    for depth in (3,4):
        clf=DecisionTreeClassifier(max_depth=depth,random_state=0).fit(X,y)
        print(f'\n-- depth-{depth} unweighted tree fit on everything:'); print(export_text(clf,feature_names=Xkeys,decimals=2))
def report(title,pred):
    cm=confusion_matrix(y,pred,labels=labels)
    none_i=labels.index('none'); fp=cm[none_i].sum()-cm[none_i,none_i]
    rec={l:cm[i,i]/cm[i].sum() for i,l in enumerate(labels) if l!='none'}
    wrong_pos=sum(cm[i].sum()-cm[i,i]-cm[i,none_i] for i,l in enumerate(labels) if l!='none')
    print('%-28s none frames misread as a gesture: %5d / %d   positives recalled: %s   positives read as another gesture: %d'%(
        title,fp,cm[none_i].sum(),' '.join('%s %.0f%%'%(l[:5],100*v) for l,v in rec.items()),wrong_pos))
Akeys=list(rows[0]['A'].keys()); Bkeys=list(rows[0]['B'].keys())
XA=np.array([[r['A'][k] for k in Akeys] for r in rows]); XB=np.array([[r['B'][k] for k in Bkeys] for r in rows])
print('\n'+'='*70+'\nCURRENT RULES (per frame, same frames)')
report('shipped thresholds',np.array([rules(r['A']) for r in rows]))
matrix('TREE ON HAND-DESIGNED FEATURES (16)',Akeys,XA)
matrix('TREE ON RAW NORMALIZED LANDMARKS (42)',Bkeys,XB)
