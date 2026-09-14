#!/usr/bin/env python3
"""Deterministic Lua 5.3 static-table bytecode recovery for JSONCapture captures.

Parses official-layout Lua 5.3 chunks (including observed format byte 1), executes only
an allow-listed data-construction opcode subset, and reconstructs TAB_* tables without
executing untrusted native/Lua code.
"""
import argparse, json, math, struct, hashlib
from pathlib import Path

OPNAMES=['MOVE','LOADK','LOADKX','LOADBOOL','LOADNIL','GETUPVAL','GETTABUP','GETTABLE','SETTABUP','SETUPVAL','SETTABLE','NEWTABLE','SELF','ADD','SUB','MUL','MOD','POW','DIV','IDIV','BAND','BOR','BXOR','SHL','SHR','UNM','BNOT','NOT','LEN','CONCAT','JMP','EQ','LT','LE','TEST','TESTSET','CALL','TAILCALL','RETURN','FORLOOP','FORPREP','TFORCALL','TFORLOOP','SETLIST','CLOSURE','VARARG','EXTRAARG']
LFIELDS_PER_FLUSH=50

class LuaTable:
    __slots__=('d','order')
    def __init__(self): self.d={}; self.order=[]
    def set(self,k,v):
        if k not in self.d: self.order.append(k)
        if v is None: self.d.pop(k,None)
        else: self.d[k]=v
    def get(self,k): return self.d.get(k)

class Parser:
    def __init__(self,b): self.b=b; self.p=0; self.endian='<'; self.intsz=self.sizetsz=self.inssz=4; self.isz=self.nsz=8
    def take(self,n):
        if self.p+n>len(self.b): raise EOFError(f'truncated @0x{self.p:x}, need {n}')
        x=self.b[self.p:self.p+n]; self.p+=n; return x
    def u8(self): return self.take(1)[0]
    def uint(self,n): return int.from_bytes(self.take(n),'little' if self.endian=='<' else 'big')
    def sint(self,n): return int.from_bytes(self.take(n),'little' if self.endian=='<' else 'big',signed=True)
    def count(self):
        n=self.sint(self.intsz)
        if n<0 or n>100_000_000: raise ValueError(f'invalid count {n} @0x{self.p:x}')
        return n
    def string(self):
        n=self.u8()
        if n==0: return None
        if n==0xff: n=self.uint(self.sizetsz)
        if n<1: raise ValueError('invalid string size')
        return self.take(n-1).decode('utf-8','surrogateescape')

def fields(i):
    op=i&0x3f; A=(i>>6)&0xff; C=(i>>14)&0x1ff; B=(i>>23)&0x1ff; Bx=(i>>14)&0x3ffff; Ax=(i>>6)&0x3ffffff; sBx=Bx-131071
    return op,A,B,C,Bx,Ax,sBx

def parse_chunk(path):
    b=Path(path).read_bytes(); p=Parser(b)
    if p.take(4)!=b'\x1bLua': raise ValueError('missing Lua signature')
    ver,fmt=p.u8(),p.u8(); data=p.take(6)
    if ver!=0x53: raise ValueError(f'unsupported Lua version {ver:#x}')
    if data!=b'\x19\x93\r\n\x1a\n': raise ValueError('LUAC_DATA mismatch')
    p.intsz,p.sizetsz,p.inssz,p.isz,p.nsz=[p.u8() for _ in range(5)]
    raw=p.take(p.isz)
    if int.from_bytes(raw,'little')==0x5678: p.endian='<'
    elif int.from_bytes(raw,'big')==0x5678: p.endian='>'
    else: raise ValueError('LUAC_INT mismatch')
    num=struct.unpack(p.endian+'d',p.take(p.nsz))[0]
    if abs(num-370.5)>1e-12: raise ValueError('LUAC_NUM mismatch')
    root_up=p.u8(); header_end=p.p
    def fn(depth=0):
        source=p.string(); linedefined=p.sint(p.intsz); lastlinedefined=p.sint(p.intsz); numparams=p.u8(); isvararg=p.u8(); maxstack=p.u8()
        code=[p.uint(p.inssz) for _ in range(p.count())]
        K=[]
        for _ in range(p.count()):
            t=p.u8()
            if t==0: v=None
            elif t==1: v=bool(p.u8())
            elif t==3: v=struct.unpack(p.endian+'d',p.take(p.nsz))[0]
            elif t==19: v=p.sint(p.isz)
            elif t in (4,20): v=p.string()
            else: raise ValueError(f'unknown constant tag {t} @0x{p.p-1:x}')
            K.append(v)
        up=[(p.u8(),p.u8()) for _ in range(p.count())]
        protos=[fn(depth+1) for _ in range(p.count())]
        lines=[p.sint(p.intsz) for _ in range(p.count())]
        loc=[(p.string(),p.sint(p.intsz),p.sint(p.intsz)) for _ in range(p.count())]
        upnames=[p.string() for _ in range(p.count())]
        return {'source':source,'linedefined':linedefined,'lastlinedefined':lastlinedefined,'numparams':numparams,'isvararg':isvararg,'maxstack':maxstack,'code':code,'K':K,'up':up,'protos':protos,'lines':lines,'loc':loc,'upnames':upnames}
    root=fn()
    meta={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b),'version_byte':ver,'format':fmt,'sizeof_int':p.intsz,'sizeof_size_t':p.sizetsz,'sizeof_instruction':p.inssz,'sizeof_lua_integer':p.isz,'sizeof_lua_number':p.nsz,'endianness':'little' if p.endian=='<' else 'big','luac_num':num,'root_upvalues':root_up,'header_bytes_without_root_upvalue_count':header_end-1,'header_and_root_upvalue_bytes':header_end,'parsed_bytes':p.p,'trailing_bytes':len(b)-p.p}
    return b,meta,root

def truth(v): return not (v is None or v is False)

def execute(root):
    K,code=root['K'],root['code']; R=[None]*max(64,root['maxstack']+16); env=LuaTable(); U=[env]; pc=steps=0; hist={}
    def rk(x): return K[x&0xff] if x&0x100 else R[x]
    while pc<len(code):
        if steps>len(code)*4: raise RuntimeError('execution runaway')
        steps+=1; i=code[pc]; op,A,B,C,Bx,Ax,sBx=fields(i); name=OPNAMES[op]; hist[name]=hist.get(name,0)+1; npc=pc+1
        if name=='MOVE': R[A]=R[B]
        elif name=='LOADK': R[A]=K[Bx]
        elif name=='LOADKX':
            e=fields(code[npc])
            if e[0]!=46: raise RuntimeError(f'LOADKX without EXTRAARG @pc={pc}')
            R[A]=K[e[5]]; npc+=1
        elif name=='LOADBOOL': R[A]=bool(B); npc += 1 if C else 0
        elif name=='LOADNIL':
            for x in range(A,A+B+1): R[x]=None
        elif name=='GETUPVAL': R[A]=U[B]
        elif name=='GETTABUP':
            base,key=U[B],rk(C)
            if not isinstance(base,LuaTable): raise RuntimeError(f'GETTABUP non-table @pc={pc}')
            R[A]=base.get(key)
        elif name=='GETTABLE':
            base,key=R[B],rk(C)
            if not isinstance(base,LuaTable): raise RuntimeError(f'GETTABLE non-table @pc={pc}')
            R[A]=base.get(key)
        elif name=='SETTABUP':
            base,key,val=U[A],rk(B),rk(C)
            if not isinstance(base,LuaTable): raise RuntimeError(f'SETTABUP non-table @pc={pc}')
            base.set(key,val)
        elif name=='SETUPVAL': U[B]=R[A]
        elif name=='SETTABLE':
            base,key,val=R[A],rk(B),rk(C)
            if not isinstance(base,LuaTable): raise RuntimeError(f'SETTABLE non-table @pc={pc}')
            base.set(key,val)
        elif name=='NEWTABLE': R[A]=LuaTable()
        elif name=='JMP': npc=pc+1+sBx
        elif name=='TEST':
            if truth(R[A]) != bool(C): npc+=1
        elif name=='SETLIST':
            base=R[A]
            if not isinstance(base,LuaTable): raise RuntimeError(f'SETLIST non-table @pc={pc}')
            n,c=B,C
            if c==0:
                e=fields(code[npc])
                if e[0]!=46: raise RuntimeError(f'SETLIST C=0 without EXTRAARG @pc={pc}')
                c=e[5]; npc+=1
            if n==0: raise RuntimeError(f'SETLIST B=0 unsupported @pc={pc}')
            start=(c-1)*LFIELDS_PER_FLUSH
            for j in range(1,n+1): base.set(start+j,R[A+j])
        elif name=='RETURN': break
        elif name=='EXTRAARG': pass
        else: raise RuntimeError(f'non-static opcode {name} @pc={pc}')
        pc=npc
    return env,{'steps':steps,'opcode_histogram_executed':hist,'unsupported_opcodes':[]}

def as_array(t):
    if not isinstance(t,LuaTable): return None
    keys=list(t.d)
    if not keys: return []
    if not all(isinstance(k,int) and k>=1 for k in keys): return None
    m=max(keys)
    if set(keys)!=set(range(1,m+1)): return None
    return [t.d[i] for i in range(1,m+1)]

def to_json_value(v):
    if isinstance(v,LuaTable):
        a=as_array(v)
        if a is not None: return [to_json_value(x) for x in a]
        return {str(k):to_json_value(v.d[k]) for k in v.order if k in v.d}
    return v

def lua_quote(v):
    if isinstance(v,LuaTable):
        a=as_array(v)
        if a is not None: return '{' + ', '.join(lua_quote(x) for x in a) + '}'
        return '{' + ', '.join('['+lua_quote(k)+']='+lua_quote(v.d[k]) for k in v.order if k in v.d) + '}'
    if v is None: return 'nil'
    if v is True: return 'true'
    if v is False: return 'false'
    if isinstance(v,str): return json.dumps(v,ensure_ascii=False)
    if isinstance(v,float):
        if math.isnan(v): return '(0/0)'
        if math.isinf(v): return '(1/0)' if v>0 else '(-1/0)'
        if v.is_integer(): return str(int(v))
        return repr(v)
    return str(v)

def norm_field(name):
    return name[2:] if isinstance(name,str) and len(name)>2 and name[:2] in ('s_','u_') else name

def reconstruct(env):
    globals_=[k for k in env.order if isinstance(k,str) and k.startswith('TAB_') and isinstance(env.get(k),LuaTable)]
    if len(globals_)!=1: raise RuntimeError(f'expected exactly one TAB_* global, got {globals_}')
    global_name=globals_[0]; main=env.get(global_name); header=as_array(main.get(-1))
    if header is None or not all(isinstance(x,str) for x in header): raise RuntimeError('missing/invalid -1 header row')
    rows=[]
    for key in main.order:
        if key==-1: continue
        arr=as_array(main.get(key))
        if arr is None: raise RuntimeError(f'main row {key!r} is not an array')
        if len(arr)!=len(header): raise RuntimeError(f'row {key!r} width={len(arr)} header={len(header)}')
        rec={'id':key}
        for h,v in zip(header,arr): rec[norm_field(h)]=to_json_value(v)
        rows.append(rec)
    return global_name,main,header,rows

def recover(input_path,outdir):
    b,meta,root=parse_chunk(input_path); env,execution=execute(root); global_name,main,header,rows=reconstruct(env)
    stem=global_name.removeprefix('TAB_'); out=Path(outdir); out.mkdir(parents=True,exist_ok=True)
    norm=bytearray(b); norm[5]=0
    norm_path=out/f'{stem}.normalized-format0.luac'; norm_path.write_bytes(norm)
    lua_path=out/f'{stem}.recovered.lua'; json_path=out/f'{stem}.recovered.json'; meta_path=out/f'{stem}.recovered.meta.json'
    lines=['-- Deterministically reconstructed from Lua 5.3 bytecode. Original capture is unchanged.',f'{global_name} = {global_name} or {{}}']
    for key in main.order:
        if key not in main.d: continue
        lines.append(f'{global_name}[{lua_quote(key)}] = {lua_quote(main.d[key])}')
    lua_path.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    json_path.write_text(json.dumps({'ListConfigModel':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    normdiff=[i for i,(x,y) in enumerate(zip(b,norm)) if x!=y]
    report={'global':global_name,'chunk':meta,'function':{'instructions':len(root['code']),'constants':len(root['K']),'protos':len(root['protos']),'maxstack':root['maxstack']},'execution':execution,'recovery':{'header_original':header,'header_json':[norm_field(x) for x in header],'records':len(rows),'first_id':rows[0]['id'] if rows else None,'last_id':rows[-1]['id'] if rows else None},'format_normalization':{'changed_zero_based_offsets':normdiff,'original_format':b[5],'normalized_format':norm[5],'sha256':hashlib.sha256(norm).hexdigest()}}
    meta_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return report, {'lua':str(lua_path),'json':str(json_path),'meta':str(meta_path),'normalized':str(norm_path)}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('input'); ap.add_argument('-o','--outdir',required=True); a=ap.parse_args()
    report,paths=recover(a.input,a.outdir); print(json.dumps({'report':report,'paths':paths},ensure_ascii=False,indent=2))
if __name__=='__main__': main()
