-- Frontend-neutral SNES console. include(path) must return a Lua module.
return function(include)
  local Console={};Console.__index=Console
  local Runtime=include('core/runtime.lua')
  local function environment()
    local env={};for k,v in pairs(Runtime) do env[k]=v end
    env.typed=Runtime.fastTyped
    if Runtime.nativeBit then
      for _,name in ipairs({'band','bor','bxor','bnot','lshift','rshift','arshift'}) do env[name]=Runtime.nativeBit[name] end
    end
    for _,name in ipairs({'cpu','pipu','spc','dsp','apu','cart','snes'}) do include('core/'..name..'.lua')(env) end
    return env
  end
  local function header(bytes,base,hi)
    if #bytes<base+32 then return end
    local function b(n) return bytes:byte(base+n+1) end
    local map=b(0x15)
    if map~=(hi and 0x21 or 0x20) and map~=(hi and 0x31 or 0x30) then return end
    local reset=bytes:byte(base+0x3c+1) or 0
    reset=reset+256*(bytes:byte(base+0x3d+1) or 0)
    if reset<0x8000 then return end
    local inverse=b(0x1c)+b(0x1d)*256
    local checksum=b(0x1e)+b(0x1f)*256
    return {name=bytes:sub(base+1,base+21):gsub('[%z\1-\31\127-\255]',' '):gsub('%s+$',''),
      type=map%16,speed=math.floor(map/16),chips=b(0x16),romExponent=b(0x17),ramExponent=b(0x18),
      region=b(0x19),score=(inverse+checksum==65535 and 4 or 0)+(b(0x1a)==0x33 and 1 or 0),isHirom=hi}
  end
  function Console.inspect(bytes)
    if type(bytes)~='string' then return nil,'Cartridge must contain binary .sfc or .smc data.' end
    if #bytes%32768==512 then bytes=bytes:sub(513) end
    if #bytes<32768 or #bytes>4*1024*1024 or #bytes%32768~=0 then
      return nil,'Use an uncompressed 32 KiB to 4 MiB .sfc/.smc cartridge.'
    end
    local lo,hi=header(bytes,0x7fc0,false),header(bytes,0xffc0,true)
    local h=(hi and (not lo or hi.score>lo.score)) and hi or lo
    if not h then return nil,'Unsupported cartridge layout. This preview accepts standard LoROM and HiROM.' end
    if h.chips>2 then return nil,'This cartridge requires an unsupported enhancement chip (type '..h.chips..').' end
    if h.romExponent<5 or h.romExponent>12 or h.ramExponent>8 then return nil,'Invalid or unsupported cartridge memory sizes.' end
    if h.region>=2 and h.region<=12 then return nil,'PAL timing is not supported in this NTSC preview.' end
    local size=32768;while size<#bytes do size=size*2 end
    if size~=#bytes then return nil,'Non power-of-two cartridge sizes are not supported in this preview.' end
    h.romSize=#bytes;h.ramSize=h.ramExponent==0 and 0 or 1024*2^h.ramExponent
    if h.chips~=0 and h.ramSize==0 then return nil,'Cartridge declares RAM but its RAM size is zero.' end
    return h,bytes
  end
  function Console.new(bytes)
    local h,body=Console.inspect(bytes);if not h then return nil,body end
    local env=environment();local machine=env.new(env.Snes)
    include('core/fast_ppu.lua')(machine.ppu,env)
    include('core/fast_sprites.lua')(machine.ppu,env)
    include('core/fast_system.lua')(machine)
    include('core/fast_address.lua')(machine.cpu)
    include('core/fast_spc_address.lua')(machine.apu.spc)
    -- CPU instruction fetches are hot: keep decoded cartridge bytes in an
    -- indexed array rather than calling a string-proxy metamethod per read.
    local data={length=#body}
    for i=0,#body-1 do data[i]=body:byte(i+1) end
    machine.cart=env.new(env.Cart,data,h,h.isHirom)
    machine:reset(true)
    return setmetatable({machine=machine,header=h,env=env,frames=0},Console)
  end
  function Console:reset() self.machine:reset(false);self.frames=0 end
  function Console:setButtons(mask) self.machine.joypad1State=mask%4096 end
  function Console:advance(cycles)
    local m=self.machine;local previous=m.frames
    local used=0
    while used<cycles do
      local skip=0
      -- Skip only intervals with no CPU/DMA work and stop before each event.
      -- Timer countdowns do not need one Lua call per two master clocks.
      local x=m.xPos
      if x>0 and x<1362 then
        local target=x<512 and 512 or x<536 and 536 or x<576 and 576 or x<1024 and 1024 or 1362
        local irq=m.hTimer*4
        if m.hIrqEnabled and irq>x and irq<target then target=irq end
        if x~=512 and x~=536 and x~=576 and x~=1024 and x~=irq then
          local limit=math.min(target-x,(cycles-used)*2)
          local kind=0
          if m.hdmaTimer>0 then skip=math.min(limit,m.hdmaTimer);kind=1
          elseif m.dmaBusy then skip=math.min(limit,m.dmaTimer);kind=2
          elseif x>=536 and x<576 then skip=limit;kind=3
          elseif m.cpu.waiting and not m.cpu.irqWanted and not m.cpu.nmiWanted
            and not m.cpu.aboWanted and not m.cpu.abortWanted then skip=limit;kind=4
          else skip=math.min(limit,m.cpuCyclesLeft);kind=5 end
          if skip>2 then
            m.apuCatchCycles=m.apuCatchCycles+m.apuCyclesPerMaster*skip
            if m.joypadStrobe then m.joypad1Val=m.joypad1State;m.joypad2Val=m.joypad2State end
            if kind==1 then m.hdmaTimer=m.hdmaTimer-skip
            elseif kind==2 then m.dmaTimer=m.dmaTimer-skip
            elseif kind==4 then
              if skip>m.cpuCyclesLeft then m.cpuMemOps=0;m.cpu.cyclesLeft=0 end
              m.cpuCyclesLeft=m.cpuCyclesLeft>=skip and m.cpuCyclesLeft-skip or (m.cpuCyclesLeft-skip)%6
            elseif kind==5 then m.cpuCyclesLeft=m.cpuCyclesLeft-skip end
            m.autoJoyTimer=math.max(0,m.autoJoyTimer-skip)
            m.xPos=x+skip;used=used+skip/2
          else skip=0 end
        end
      end
      if skip==0 then m:cycle(false);used=used+1 end
      if m.frames~=previous then self.frames=self.frames+1;return true end
    end
    return false
  end
  function Console:frame() repeat until self:advance(4096);return self.frames end
  function Console:saveRam()
    local ram=self.machine.cart.sram;local parts={}
    for start=0,ram.length-1,4096 do
      local chars={};for i=start,math.min(start+4095,ram.length-1) do chars[#chars+1]=string.char(ram[i]) end
      parts[#parts+1]=table.concat(chars)
    end
    return table.concat(parts)
  end
  function Console:loadRam(bytes)
    local ram=self.machine.cart.sram
    if type(bytes)~='string' or #bytes~=ram.length then return false end
    for i=0,ram.length-1 do ram[i]=bytes:byte(i+1) end
    return true
  end
  return Console
end
