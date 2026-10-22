"""Reproducible, deliberately narrow SnesJs -> Lua 5.1 source port.

This is not a general JavaScript compiler. Unsupported syntax fails the build.
Install esprima==4.0.1; pass the checked-out upstream directory as argv[1].
"""
import sys,json,re
from pathlib import Path
try: import esprima
except ImportError:
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'.work/snes-research/python'))
    import esprima

ROOT=Path(__file__).resolve().parents[1]
KEYWORDS=set('and break do else elseif end false for function if in local nil not or repeat return then true until while'.split())
def ident(n): return '_js_'+n if n in KEYWORDS else n
def field(n):return '['+json.dumps(n)+']'

class Port:
    TYPES={}
    BOOL_FIELDS=set()
    BOOL_LOCALS=set()
    def __init__(self):self.seq=0;self.multi_return=False
    def wrap(self,target,value):
        if target['type']=='MemberExpression' and target['computed']:
            obj=target['object']
            if obj['type']=='MemberExpression' and not obj['computed']:
                kind=self.TYPES.get(obj['property']['name'])
                wrapper={'Uint8Array':'_u8','Uint16Array':'_u16','Int16Array':'_i16','Int32Array':'_i32'}.get(kind)
                if wrapper:return wrapper+'('+value+')'
        return value
    def unique(self):self.seq+=1;return '_switch'+str(self.seq)
    def bool(self,n):
        if n['type']=='Literal' and isinstance(n.get('value'),bool):return self.expr(n)
        if n['type']=='BinaryExpression' and n['operator'] in ['==','===','!=','!==','<','>','<=','>=']:return self.expr(n)
        if n['type']=='UnaryExpression' and n['operator']=='!':return self.expr(n)
        if n['type']=='LogicalExpression':
            return '('+self.bool(n['left'])+(' and ' if n['operator']=='&&' else ' or ')+self.bool(n['right'])+')'
        return '_truth('+self.expr(n)+')'
    def bitarg(self,n):
        value=self.expr(n)
        def fractional(x):
            if not isinstance(x,dict):return False
            if x.get('type')=='Identifier' and x['name'] in ['bMult','total','apuCatchCycles']:return True
            if x.get('type')=='MemberExpression' and not x.get('computed') and x['property'].get('name')=='apuCatchCycles':return True
            if x.get('type')=='BinaryExpression' and x['operator']=='/':return True
            if x.get('type')=='Literal' and isinstance(x.get('value'),float) and not x['value'].is_integer():return True
            return any(fractional(v) for v in x.values())
        if fractional(n):return '_bitnum('+value+')'
        # Only these source expressions mix booleans into bitwise operands.
        isbool=(n['type']=='Literal' and isinstance(n.get('value'),bool)) or (n['type']=='BinaryExpression' and n['operator'] in ['==','===','!=','!==','<','>','<=','>='])
        if n['type']=='Identifier' and n['name'] in self.BOOL_LOCALS:isbool=True
        if n['type']=='MemberExpression':
            obj=n['object'] if n['computed'] else n
            if obj['type']=='MemberExpression' and not obj['computed'] and obj['property'].get('name') in self.BOOL_FIELDS:isbool=True
        if isbool:return '_num('+value+')'
        return value
    def binary(self,op,a,b):
        bitops={'&':'band','|':'bor','^':'bxor','<<':'lshift','>>':'arshift','>>>':'rshift'}
        if op in bitops:return bitops[op]+'('+a+', '+b+')'
        if op in ['<','>','<=','>=']:return '(_num('+a+') '+op+' _num('+b+'))'
        if op in ['===','==']:op='=='
        elif op in ['!==','!=']:op='~='
        elif op=='%':return '_rem('+a+', '+b+')'
        return '('+a+' '+op+' '+b+')'
    def expr(self,n):
        t=n['type']
        if t=='Literal':
            v=n.get('value')
            if v is None:return 'nil'
            if isinstance(v,bool):return str(v).lower()
            if isinstance(v,str):return json.dumps(v,ensure_ascii=True)
            return str(v)
        if t=='Identifier':return 'nil' if n['name']=='undefined' else ident(n['name'])
        if t=='ThisExpression':return 'self'
        if t=='MemberExpression':
            if n['computed'] and n['object']['type']=='Identifier' and n['object']['name'] in ['colLay','secondLay']:
                assert n['property']['type']=='Literal' and n['property']['value'] in [0,1,2]
                return n['object']['name']+str(n['property']['value'])
            return self.expr(n['object'])+('['+self.expr(n['property'])+']' if n['computed'] else field(n['property']['name']))
        if t=='ArrayExpression':return '{length = '+str(len(n['elements']))+', '+', '.join('['+str(i)+'] = '+self.expr(v) for i,v in enumerate(n['elements']) if v)+'}'
        if t=='ObjectExpression':return '{'+', '.join('['+json.dumps(p['key'].get('name',p['key'].get('value')))+'] = '+self.expr(p['value']) for p in n['properties'])+'}'
        if t=='BinaryExpression':
            if n['operator'] in ['&','|','^','<<','>>','>>>']:
                return self.binary(n['operator'],self.bitarg(n['left']),self.bitarg(n['right']))
            if n['operator']=='+':
                # String concatenation only occurs in diagnostics and header names.
                def stringy(x):return (x['type']=='Literal' and isinstance(x.get('value'),str)) or (x['type']=='BinaryExpression' and (stringy(x['left']) or stringy(x['right'])))
                if stringy(n):return '_add('+self.expr(n['left'])+', '+self.expr(n['right'])+')'
            return self.binary(n['operator'],self.expr(n['left']),self.expr(n['right']))
        if t=='LogicalExpression':
            # Operand-valued logical expressions are rare in this core.
            a,b=self.expr(n['left']),self.expr(n['right'])
            return '(function() local _v = '+a+'; if _truth(_v) then return '+(b if n['operator']=='&&' else '_v')+' else return '+('_v' if n['operator']=='&&' else b)+' end end)()'
        if t=='UnaryExpression':
            op=n['operator']
            if op=='!':return '(not '+self.bool(n['argument'])+')'
            if op=='~':return 'bnot('+self.expr(n['argument'])+')'
            return '('+op+self.expr(n['argument'])+')'
        if t=='ConditionalExpression':
            a,b=self.expr(n['consequent']),self.expr(n['alternate'])
            def call(x):return isinstance(x,dict) and (x.get('type') in ['CallExpression','UpdateExpression','AssignmentExpression'] or any(call(v) for v in x.values()))
            if call(n['consequent']) or call(n['alternate']):
                return '(function() if '+self.bool(n['test'])+' then return '+a+' else return '+b+' end end)()'
            return '_sel('+self.bool(n['test'])+', '+a+', '+b+')'
        if t=='FunctionExpression':
            params=['self'];defaults=[]
            for p in n['params']:
                if p['type']=='AssignmentPattern':
                    name=self.expr(p['left']);params.append(name);defaults.append('if '+name+' == nil then '+name+' = '+self.expr(p['right'])+' end')
                else:params.append(self.expr(p))
            return 'function('+', '.join(params)+')\n'+self.indent('\n'.join(defaults+[self.stmt(n['body'])]))+'\nend'
        if t=='CallExpression':
            c=n['callee'];args=[self.expr(a) for a in n['arguments']]
            if c['type']=='MemberExpression':
                prop=c['property'].get('name') if not c['computed'] else None
                obj=c['object']
                if prop=='call':
                    if self.expr(obj)=='Array["prototype"]["slice"]':return '_slice('+', '.join(args)+')'
                    return self.expr(obj)+'('+', '.join(args)+')'
                if prop=='toString':return '_hex('+self.expr(obj)+')'
                if obj['type']=='Identifier' and obj['name'] in ['Math','String','console']:
                    key=obj['name']+'.'+prop
                    fn={'Math.pow':'_pow','Math.ceil':'math.ceil','Math.log2':'_log2','String.fromCharCode':'string.char','console.log':'log'}[key]
                    return fn+'('+', '.join(args)+')'
                return self.expr(c)+'('+', '.join([self.expr(obj)]+args)+')'
            return '('+self.expr(c)+')(nil'+(', '+', '.join(args) if args else '')+')' if c['type']=='FunctionExpression' else self.expr(c)+'('+', '.join(args)+')'
        if t=='NewExpression':
            name=n['callee']['name'];args=', '.join(self.expr(a) for a in n['arguments'])
            if name.endswith('Array'):return '_typed('+json.dumps(name)+', '+args+')'
            return '_new('+name+(', '+args if args else '')+')'
        if t=='UpdateExpression':
            a=self.expr(n['argument']);step=' + 1' if n['operator']=='++' else ' - 1'
            return '(function() local _old = '+a+'; '+a+' = '+self.wrap(n['argument'],'_old'+step)+'; return '+(a if n['prefix'] else '_old')+' end)()'
        raise ValueError('Unsupported expression '+t)
    def indent(self,s):return '\n'.join('  '+x for x in s.splitlines())
    def assignment(self,n):
        if n['left']['type']=='MemberExpression' and not n['left']['computed'] and n['left']['property']['name']=='getColor':
            previous=self.multi_return;self.multi_return=True
            value=self.expr(n['right']);self.multi_return=previous
            return self.expr(n['left'])+' = '+value
        if n['left']['type']=='Identifier' and n['left']['name'] in ['colLay','secondLay']:
            name=n['left']['name'];assert n['operator']=='='
            return ', '.join(name+str(i) for i in range(3))+' = '+self.expr(n['right'])
        a,b=self.expr(n['left']),self.expr(n['right']);op=n['operator']
        if op=='=':return a+' = '+self.wrap(n['left'],b)
        if op=='+=' and (n['left'].get('name')=='str' or n['right']['type']=='Literal' and isinstance(n['right'].get('value'),str)):return a+' = _add('+a+', '+b+')'
        if op[:-1] in ['&','|','^','<<','>>','>>>']:return a+' = '+self.wrap(n['left'],self.binary(op[:-1],self.bitarg(n['left']),self.bitarg(n['right'])))
        return a+' = '+self.wrap(n['left'],self.binary(op[:-1],a,b))
    def stmt(self,n):
        t=n['type']
        if t=='AssignmentExpression':return self.assignment(n)
        if t in ['Program','BlockStatement']:return '\n'.join(self.stmt(s) for s in n['body'])
        if t=='ExpressionStatement':
            e=n['expression']
            if e['type']=='AssignmentExpression':return self.assignment(e)
            if e['type']=='UpdateExpression':
                a=self.expr(e['argument']);return a+' = '+self.wrap(e['argument'],a+(' + 1' if e['operator']=='++' else ' - 1'))
            return self.expr(e)
        if t=='VariableDeclaration':
            rows=[]
            for d in n['declarations']:
                name=d['id']['name'];init=d.get('init')
                if name in ['colLay','secondLay']:
                    value=', '.join(self.expr(v) for v in init['elements']) if init['type']=='ArrayExpression' else self.expr(init)
                    rows.append('local '+', '.join(name+str(i) for i in range(3))+' = '+value)
                else:rows.append('local '+ident(name)+' = '+(self.expr(init) if init else 'nil'))
            return '\n'.join(rows)
        if t=='FunctionDeclaration':
            e=dict(n,type='FunctionExpression');return ident(n['id']['name'])+' = '+self.expr(e)
        if t=='ReturnStatement':
            if self.multi_return and n.get('argument') and n['argument']['type']=='ArrayExpression':
                return 'do return '+', '.join(self.expr(v) for v in n['argument']['elements'])+' end'
            return 'do return'+(' '+self.expr(n['argument']) if n.get('argument') else '')+' end'
        if t=='IfStatement':return 'if '+self.bool(n['test'])+' then\n'+self.indent(self.stmt(n['consequent']))+('\nelse\n'+self.indent(self.stmt(n['alternate'])) if n.get('alternate') else '')+'\nend'
        if t=='ForStatement':
            init=self.stmt(n['init']);test=self.bool(n['test']);step=self.stmt({'type':'ExpressionStatement','expression':n['update']})
            return 'do\n'+self.indent(init+'\nwhile '+test+' do\n'+self.indent(self.stmt(n['body'])+'\n'+step)+'\nend')+'\nend'
        if t=='WhileStatement':return 'while '+self.bool(n['test'])+' do\n'+self.indent(self.stmt(n['body']))+'\nend'
        if t=='DoWhileStatement':return 'repeat\n'+self.indent(self.stmt(n['body']))+'\nuntil not ('+self.bool(n['test'])+')'
        if t=='BreakStatement':return 'do break end'
        if t=='SwitchStatement':
            key=self.unique();rows=['do','  local '+key+' = '+self.expr(n['discriminant']),'  local _fall = false','  repeat']
            for c in n['cases']:
                cond='_fall or '+key+' == '+self.expr(c['test']) if c['test'] else 'true'
                rows+=['    if '+cond+' then','      _fall = true']
                rows += [self.indent(self.indent(self.indent(self.stmt(s)))) for s in c['consequent']]
                rows+=['    end']
            return '\n'.join(rows+['  until true','end'])
        if t=='TryStatement':
            # Upstream swallowed SPC instruction errors, making corruption silent.
            # The port deliberately propagates errors to the frontend's error screen.
            return self.stmt(n['block'])
        raise ValueError('Unsupported statement '+t)

def main():
    upstream=Path(sys.argv[1])
    def collect(n):
        if isinstance(n,list):
            for x in n:collect(x)
        elif isinstance(n,dict):
            def boolean(x):
                return bool(x) and ((x['type']=='Literal' and isinstance(x.get('value'),bool)) or x['type']=='UnaryExpression' and x['operator']=='!' or x['type']=='BinaryExpression' and x['operator'] in ['===','!==','==','!=','<','>','<=','>='] or x['type']=='ArrayExpression' and any(boolean(v) for v in x['elements']))
            if n.get('type')=='AssignmentExpression' and boolean(n['right']):
                if n['left']['type']=='MemberExpression' and not n['left']['computed']:Port.BOOL_FIELDS.add(n['left']['property']['name'])
                elif n['left']['type']=='Identifier':Port.BOOL_LOCALS.add(n['left']['name'])
            if n.get('type')=='VariableDeclarator' and boolean(n.get('init')):Port.BOOL_LOCALS.add(n['id']['name'])
            if n.get('type')=='AssignmentExpression' and n['left']['type']=='MemberExpression' and not n['left']['computed'] and n['right']['type']=='NewExpression' and n['right']['callee']['name'].endswith('Array'):
                key=n['left']['property']['name'];kind=n['right']['callee']['name']
                assert key not in Port.TYPES or Port.TYPES[key]==kind,(key,kind,Port.TYPES.get(key))
                Port.TYPES[key]=kind
            for x in n.values():collect(x)
    for p in (upstream/'snes').glob('*.js'):collect(esprima.parseScript(p.read_text()).toDict())
    for p in sorted((upstream/'snes').glob('*.js')):
        code=Port().stmt(esprima.parseScript(p.read_text()).toDict())
        (ROOT/'core'/p.with_suffix('.lua').name).write_text('-- Ported from SnesJs (MIT); see THIRD_PARTY.txt. Generated by tools/port_core.py.\nreturn function(env)\n  local band, bor, bxor, bnot = env.band, env.bor, env.bxor, env.bnot\n  local lshift, rshift, arshift = env.lshift, env.rshift, env.arshift\n  local _truth, _sel, _rem, _add, _num = env.truth, env.sel, env.rem, env.add, env.num\n  local _typed, _new, _slice = env.typed, env.new, env.slice\n  local _u8, _u16, _i16, _i32 = env.u8, env.u16, env.i16, env.i32\n  local _bitnum = env.int\n  local _hex, _pow, _log2 = env.hex, env.pow, env.log2\n  local clearArray, log = env.clearArray, env.log\n  local getByteRep, getWordRep, getLongRep = env.hex, env.hex, env.hex\n  local Cpu, Ppu, Apu, Spc, Dsp, Cart, Snes = env.Cpu, env.Ppu, env.Apu, env.Spc, env.Dsp, env.Cart, env.Snes\n  local header\n'+Port().indent(code)+'\n  env.'+{'cpu':'Cpu','pipu':'Ppu','apu':'Apu','spc':'Spc','dsp':'Dsp','cart':'Cart','snes':'Snes'}[p.stem]+' = '+{'cpu':'Cpu','pipu':'Ppu','apu':'Apu','spc':'Spc','dsp':'Dsp','cart':'Cart','snes':'Snes'}[p.stem]+'\nend\n',encoding='utf-8')
    print('Ported 7 core modules.')
if __name__=='__main__':main()

