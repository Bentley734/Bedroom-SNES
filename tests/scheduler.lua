local a=assert(Console.new(demo))
local function referenceClock(c)
  local original=c.env.new(c.env.Snes)
  c.machine.cycle=original.cycle;c.machine.cpuCycle=original.cpuCycle
  c.machine.cpu.cycle=original.cpu.cycle;c.machine.apu.spc.cycle=original.apu.spc.cycle
end
local b=assert(Console.new(demo));referenceClock(b)
for frame=1,60 do
  local mask=frame%13==0 and 8 or frame%7<3 and 128 or 0
  a:setButtons(mask);b:setButtons(mask)
  -- Exercise horizontal IRQ boundaries, including refresh and render dots.
  local timer=({1,128,134,144,256,340})[(frame-1)%6+1]
  a.machine.hIrqEnabled=true;b.machine.hIrqEnabled=true
  a.machine.hTimer=timer;b.machine.hTimer=timer
  a:frame();b.machine:runFrame(false)
  local am,bm=a.machine,b.machine
  for _,key in ipairs({'xPos','yPos','frames','cpuCyclesLeft','cpuMemOps','autoJoyTimer','openBus','inIrq','inVblank','inHblank'}) do
    assert(am[key]==bm[key],'idle scheduler mismatch: '..key)
  end
  assert(am.apu.cycles==bm.apu.cycles,'idle scheduler changed SPC timing')
  for i=0,5 do assert(am.cpu.br[i]==bm.cpu.br[i],'idle scheduler changed CPU register') end
  assert(am.ram[0]==bm.ram[0] and am.ram[1]==bm.ram[1],'idle scheduler changed cartridge input')
  am.apu.dsp.sampleOffset=0;bm.apu.dsp.sampleOffset=0
end
print('PASS: idle scheduler matches the reference for 60 frames with six IRQ/render/refresh boundaries')

-- Partial advances are important: the frontend usually gives the scheduler
-- only a small slice, so compare every boundary and countdown against raw
-- two-master-clock cycles, including the point where a frame ends early.
local sliceA=assert(Console.new(demo))
local sliceB=assert(Console.new(demo));referenceClock(sliceB)
local seed=913187
local function random(n)
  seed=(seed*1664525+1013904223)%4294967296
  return math.floor(seed/65536)%n
end
local function compareState(actual,expected,path,seen)
  if seen[actual] then assert(seen[actual]==expected,'scheduler object graph mismatch at '..path);return end
  seen[actual]=expected
  -- Dense typed memory is compared byte/sample-for-byte/sample, not sampled.
  if actual._kind then
    assert(actual._kind==expected._kind and actual.length==expected.length,'scheduler memory layout mismatch at '..path)
    for i=0,actual.length-1 do
      assert(actual[i]==expected[i],'scheduler memory mismatch at '..path..'['..i..']')
    end
    return
  end
  for key,value in pairs(actual) do
    local other=expected[key]
    local kind=type(value)
    if kind=='table' then
      assert(type(other)=='table','scheduler missing state at '..path..'.'..tostring(key))
      compareState(value,other,path..'.'..tostring(key),seen)
    elseif kind~='function' then
      if key=='apuCatchCycles' then
        -- Regrouped additions differ only in the fractional clock remainder.
        assert(math.abs(value-other)<1e-6,'scheduler APU remainder drift at '..path)
      else
        assert(value==other,'scheduler state mismatch at '..path..'.'..tostring(key)..': '..tostring(value)..' ~= '..tostring(other))
      end
    end
  end
  for key,value in pairs(expected) do
    if type(value)~='function' then assert(actual[key]~=nil,'scheduler lost state at '..path..'.'..tostring(key)) end
  end
end
local xEdges={0,2,510,512,514,534,536,538,574,576,578,1022,1024,1026,1360,1362}
local yEdges={0,1,223,224,225,239,240,260,261}
local lengths={1,2,3,4,7,8,9,17,31,64,129,257,683,1371}
local slices,frameEnds=0,0
local coverage={cpu=false,dma=false,hdma=false,refresh=false,hirq=false,virq=false,strobe=false,autojoy=false}
for scenario=1,144 do
  sliceA:reset();sliceB:reset()
  local am,bm=sliceA.machine,sliceB.machine
  local function both(key,value) am[key]=value;bm[key]=value end
  local function cpu(key,value) am.cpu[key]=value;bm.cpu[key]=value end
  local function array(key,i,value) am[key][i]=value;bm[key][i]=value end
  local x=xEdges[(scenario-1)%#xEdges+1]
  local y=yEdges[math.floor((scenario-1)/#xEdges)%#yEdges+1]
  both('xPos',x);both('yPos',y)
  both('cpuCyclesLeft',random(33)*2);both('cpuMemOps',random(6));cpu('cyclesLeft',random(12))
  cpu('waiting',scenario%5==0);cpu('irqWanted',scenario%17==0);cpu('nmiWanted',scenario%19==0)
  both('hdmaTimer',scenario%3==0 and random(25)*2 or 0)
  both('dmaBusy',scenario%3==1);both('dmaTimer',random(17)*2)
  both('inHblank',x>=1024);both('inVblank',y>=225)
  both('hIrqEnabled',scenario%4<2);both('vIrqEnabled',scenario%4~=0)
  both('hTimer',scenario%2==0 and math.floor(x/4) or math.floor(x/4)+1)
  both('vTimer',scenario%3==0 and (y+1)%262 or y)
  both('nmiEnabled',scenario%2==0)
  both('autoJoyRead',true);both('autoJoyTimer',random(34)*2)
  both('joypadStrobe',scenario%2==0)
  both('joypad1State',random(4096));both('joypad2State',random(4096))
  both('joypad1Val',random(65536));both('joypad2Val',random(65536))
  -- Real DMA transfers and HDMA table reads target CGRAM using private RAM.
  array('dmaActive',0,am.dmaBusy);array('hdmaActive',0,scenario%7==0)
  array('dmaAadrBank',0,0x7e);array('dmaAadr',0,0x200);array('dmaBadr',0,0x22)
  array('dmaSize',0,random(8)+1);array('dmaMode',0,0)
  array('hdmaTableAdr',0,0x200);array('hdmaRepCount',0,0x82);array('hdmaDoTransfer',0,true)
  for i=0x200,0x23f do array('ram',i,random(128)) end
  coverage.cpu=coverage.cpu or am.cpuCyclesLeft>2
  coverage.dma=coverage.dma or am.dmaBusy
  coverage.hdma=coverage.hdma or am.hdmaTimer>2
  coverage.refresh=coverage.refresh or (x>=536 and x<576)
  coverage.hirq=coverage.hirq or am.hIrqEnabled
  coverage.virq=coverage.virq or am.vIrqEnabled
  coverage.strobe=coverage.strobe or am.joypadStrobe
  coverage.autojoy=coverage.autojoy or (y==225 and x==0)
  for step=1,12 do
    local count=lengths[(step+scenario-2)%#lengths+1]+random(5)
    local previous=bm.frames
    local fastDone=sliceA:advance(count)
    local referenceDone=false
    for i=1,count do
      bm:cycle(false)
      if bm.frames~=previous then referenceDone=true;break end
    end
    assert(fastDone==referenceDone,'scheduler frame return mismatch')
    if referenceDone then frameEnds=frameEnds+1 end
    compareState(am,bm,'scenario '..scenario..' slice '..step,{})
    slices=slices+1
  end
end
for key,value in pairs(coverage) do assert(value,'scheduler coverage missing '..key) end
assert(frameEnds>0,'scheduler early frame return was not exercised')
print('PASS: '..slices..' randomized partial scheduler slices match full reference state (CPU/DMA/HDMA countdowns, refresh, IRQ, joypad and frame boundaries)')
