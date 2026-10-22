import sys,collections,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'.work/snes-research/python'))
import esprima
root=Path(__file__).resolve().parents[2]/'.work/snes-research/SnesJs/snes'
counts=collections.Counter(); calls=collections.Counter(); news=collections.Counter()
def visit(n):
    if isinstance(n,list):
        for v in n:visit(v)
    elif isinstance(n,dict):
        counts[n.get('type')]+=1
        if n.get('type')=='CallExpression':calls[json.dumps(n['callee'],sort_keys=True)]+=1
        if n.get('type')=='NewExpression':news[n['callee']['name']]+=1
        for v in n.values():visit(v)
for p in root.glob('*.js'): visit(esprima.parseScript(p.read_text()).toDict())
print(counts);print(news)
for k,v in calls.items():
    if 'ThisExpression' not in k:print(v,k[:230])
