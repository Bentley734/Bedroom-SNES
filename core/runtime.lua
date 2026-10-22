-- JavaScript numeric/array semantics needed by the source port, in Lua 5.1.
-- No FFI, native libraries, or dynamically generated machine code.
local R = {}
local floor, ceil = math.floor, math.ceil
local function int(v)
  if v == true then return 1 elseif v == false then return 0 end
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return 0 end
  return v < 0 and ceil(v) or floor(v)
end
R.int=int
function R.truth(v) return v ~= nil and v ~= false and v ~= 0 and v ~= "" and v == v end
function R.num(v) if v==true then return 1 elseif v==false then return 0 else return v end end
function R.sel(c,a,b) if c then return a else return b end end
function R.rem(a,b) return a - int(a / b) * b end
function R.add(a,b)
  if type(a)=='string' or type(b)=='string' then return tostring(a)..tostring(b) end
  return a+b
end
function R.pow(a,b) return a^b end
function R.log2(v) return math.log(v)/math.log(2) end
function R.hex(v) return string.format('%X',v or 0) end
function R.log(_) end
function R.new(ctor,...)
  local self={}; ctor(self,...); return self
end
function R.clearArray(a) for i=0,a.length-1 do a[i]=0 end end
function R.slice(a,start)
  local result={length=a.length-start}
  for i=0,result.length-1 do result[i]=a[start+i] end
  return result
end
function R.typed(kind,init)
  local size=type(init)=='table' and init.length or init
  assert(type(size)=='number' and size>=0 and size<=8*1024*1024,'Invalid emulated array size')
  local data={};local modulus,signed
  if kind=='Uint8Array' then modulus=256
  elseif kind=='Uint16Array' then modulus=65536
  elseif kind=='Int16Array' then modulus=65536;signed=32768
  elseif kind=='Int32Array' then modulus=4294967296;signed=2147483648 end
  local a={length=size,_data=data,_kind=kind}
  setmetatable(a,{
    __index=function(_,k) if type(k)=='number' and k>=0 and k<size then return data[k] or 0 end end,
    __newindex=function(_,k,v)
      if type(k)=='number' and k>=0 and k<size then
        if modulus then v=int(v)%modulus;if signed and v>=signed then v=v-modulus end end
        data[k]=v
      end
    end,
  })
  if type(init)=='table' then for i=0,size-1 do a[i]=init[i] end end
  return a
end
function R.u8(v) return int(v)%256 end
function R.u16(v) return int(v)%65536 end
function R.i16(v) v=int(v)%65536;return v>=32768 and v-65536 or v end
function R.i32(v) v=int(v)%4294967296;return v>=2147483648 and v-4294967296 or v end
-- Generated core writes explicitly enforce typed-array widths. Plain tables
-- avoid a metamethod on every emulated memory/pixel access, without FFI.
function R.fastTyped(kind,init)
  local size=type(init)=='table' and init.length or init
  assert(type(size)=='number' and size>=0 and size<=8*1024*1024,'Invalid emulated array size')
  local a={length=size,_kind=kind}
  local cast=kind=='Uint8Array' and R.u8 or kind=='Uint16Array' and R.u16 or kind=='Int16Array' and R.i16 or kind=='Int32Array' and R.i32 or function(v) return v end
  for i=0,size-1 do a[i]=type(init)=='table' and cast(init[i]) or 0 end
  return setmetatable(a,{__newindex=function(t,k,v)
    if type(k)~='number' then rawset(t,k,v) end
  end})
end
-- LÖVE supplies LuaJIT's bit library, also on builds with JIT disabled.
-- The arithmetic fallback keeps the core runnable on plain Lua 5.1/5.4.
local ok,bitlib=pcall(require,'bit')
if ok then
  R.nativeBit=bitlib
  R.band=function(a,b) return bitlib.band(int(a),int(b)) end
  R.bor=function(a,b) return bitlib.bor(int(a),int(b)) end
  R.bxor=function(a,b) return bitlib.bxor(int(a),int(b)) end
  R.bnot=function(a) return bitlib.bnot(int(a)) end
  R.lshift=function(a,b) return bitlib.lshift(int(a),int(b)) end
  R.rshift=function(a,b) return bitlib.rshift(int(a),int(b)) end
  R.arshift=function(a,b) return bitlib.arshift(int(a),int(b)) end
else
  local function u(v) return int(v)%4294967296 end
  local function s(v) v=u(v);return v>=2147483648 and v-4294967296 or v end
  local function combine(a,b,mode)
    a,b=u(a),u(b);local out,p=0,1
    for _=1,32 do
      local x,y=a%2,b%2
      if (mode==1 and x==1 and y==1) or (mode==2 and (x==1 or y==1)) or (mode==3 and x~=y) then out=out+p end
      a,b,p=floor(a/2),floor(b/2),p*2
    end
    return s(out)
  end
  R.band=function(a,b) return combine(a,b,1) end
  R.bor=function(a,b) return combine(a,b,2) end
  R.bxor=function(a,b) return combine(a,b,3) end
  R.bnot=function(a) return s(4294967295-u(a)) end
  R.lshift=function(a,b) return s(u(a)*2^(u(b)%32)) end
  R.rshift=function(a,b) return floor(u(a)/2^(u(b)%32)) end
  R.arshift=function(a,b) return floor(s(a)/2^(u(b)%32)) end
end
return R
