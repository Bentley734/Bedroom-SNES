-- Decode edge addresses through the optimized and unmodified CPU paths.
local env=console.env
local install=include('core/fast_address.lua')
local seed=18347
local function rand(n) seed=(seed*1664525+1013904223)%4294967296;return math.floor(seed/65536)%n end
local checked=0
for trial=1,96 do
  for mode=0,28 do
    local readsA,readsB={},{}
    local salt=rand(256)
    local function memory(reads)
      return {read=function(_,address) reads[#reads+1]=address;return (address*13+salt)%256 end,write=function() error('decoder unexpectedly wrote the bus') end}
    end
    local a=env.new(env.Cpu,memory(readsA));local b=env.new(env.Cpu,memory(readsB));install(a)
    local flags=rand(256);a:setP(flags);b:setP(flags)
    for i=0,5 do local v=rand(65536);a.br[i]=v;b.br[i]=v end
    for i=0,1 do local v=rand(256);a.r[i]=v;b.r[i]=v end
    local pc=({0,1,255,256,65534,65535})[trial%6+1];a.br[4]=pc;b.br[4]=pc
    a.cyclesLeft=7;b.cyclesLeft=7
    for i=#readsA,1,-1 do readsA[i]=nil end;for i=#readsB,1,-1 do readsB[i]=nil end
    local x,y=a:getAdr(0x69,mode);local u,v=b:getAdr(0x69,mode)
    assert(x==u and y==v,'address mode '..mode..' returned different operands')
    assert(a.cyclesLeft==b.cyclesLeft and a.br[4]==b.br[4],'address mode changed cycle/PC timing')
    assert(#readsA==#readsB,'address mode changed bus read count')
    for i=1,#readsA do assert(readsA[i]==readsB[i],'address mode changed bus read ordering') end
    checked=checked+1
  end
end
local data=console.machine.cart.data
for i=0,#demo-1 do assert(data[i]==demo:byte(i+1),'decoded ROM byte changed') end
assert(data.length==#demo and data[#demo]==nil and data[-1]==nil)
print('PASS: '..checked..' decoder cases match addresses, cycle penalties, PC wrapping and bus order; ROM bytes match')
local installSpc=include('core/fast_spc_address.lua')
for trial=1,64 do for mode=0,19 do
  local readsA,readsB={},{}
  local salt=rand(256)
  local function memory(reads) return {read=function(_,adr) reads[#reads+1]=adr;return (adr*17+salt)%256 end,write=function() error('decoder wrote memory') end} end
  local a=env.new(env.Spc,memory(readsA));local b=env.new(env.Spc,memory(readsB));installSpc(a)
  local flags=rand(256);a:setP(flags);b:setP(flags)
  for i=0,3 do local value=rand(256);a.r[i]=value;b.r[i]=value end
  local pc=({0,255,65534,65535})[trial%4+1];a.br[0]=pc;b.br[0]=pc
  for i=#readsA,1,-1 do readsA[i]=nil end;for i=#readsB,1,-1 do readsB[i]=nil end
  local x,y=a:getAdr(mode);local u,v=b:getAdr(mode)
  assert(x==u and y==v and a.br[0]==b.br[0],'SPC address decoder mismatch mode '..mode)
  for i=0,3 do assert(a.r[i]==b.r[i],'SPC address decoder changed register') end
  assert(#readsA==#readsB);for i=1,#readsA do assert(readsA[i]==readsB[i],'SPC bus order changed') end
end end
print('PASS: 1280 SPC decoder cases match operands, page/PC/index wrapping and bus order')
