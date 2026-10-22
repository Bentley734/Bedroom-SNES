-- Native Lua dispatch for the hot clock loop. Instruction implementations,
-- bus accesses, DMA and PPU events retain their reference ordering.
return function(m)
  m.cpu.cycle=function(c)
    if c.cyclesLeft==0 then
      if c.stopped then c.cyclesLeft=1
      elseif c.waiting then
        if c.abortWanted or c.irqWanted or c.nmiWanted then c.waiting=false end
        c.cyclesLeft=1
      else
        local pc=c.br[4];c.br[4]=(pc+1)%65536
        local instr=c.mem:read(c.r[1]*65536+pc)
        c.cyclesLeft=c.cycles[instr]
        local mode=c.modes[instr]
        if (c.irqWanted and not c.i) or c.nmiWanted or c.aboWanted then
          c.br[4]=(c.br[4]-1)%65536
          if c.aboWanted then c.aboWanted=false;instr=256
          elseif c.nmiWanted then c.nmiWanted=false;instr=257
          else instr=258 end
          c.cyclesLeft=c.cycles[instr];mode=c.modes[instr]
        end
        local a,b=c:getAdr(instr,mode)
        local instruction=c.functions[instr]
        if instruction then instruction(c,a,b) else c:uni(a,b,instr) end
      end
    end
    c.cyclesLeft=c.cyclesLeft-1
  end
  m.apu.spc.cycle=function(c)
    if c.cyclesLeft==0 then
      local pc=c.br[0];c.br[0]=(pc+1)%65536
      local instr=c.mem:read(pc)
      c.cyclesLeft=c.cycles[instr]
      local a,b=c:getAdr(c.modes[instr])
      c.functions[instr](c,a,b,instr)
    end
    c.cyclesLeft=c.cyclesLeft-1
  end
  m.cpuCycle=function(s)
    if s.cpuCyclesLeft==0 then
      s.cpu.cyclesLeft=0;s.cpuMemOps=0
      s.cpu:cycle()
      s.cpuCyclesLeft=s.cpuCyclesLeft+(s.cpu.cyclesLeft+1-s.cpuMemOps)*6
    end
    s.cpuCyclesLeft=s.cpuCyclesLeft-2
  end
  m.cycle=function(s,noPpu)
    s.apuCatchCycles=s.apuCatchCycles+s.apuCyclesPerMaster*2
    if s.joypadStrobe then s.joypad1Val=s.joypad1State;s.joypad2Val=s.joypad2State end
    if s.hdmaTimer>0 then s.hdmaTimer=s.hdmaTimer-2
    elseif s.dmaBusy then s:handleDma()
    elseif s.xPos<536 or s.xPos>=576 then s:cpuCycle() end
    local x,y=s.xPos,s.yPos
    if y==s.vTimer and s.vIrqEnabled then
      if (not s.hIrqEnabled and x==0) or (s.hIrqEnabled and x==s.hTimer*4) then s.inIrq=true;s.cpu.irqWanted=true end
    elseif s.hIrqEnabled and not s.vIrqEnabled and x==s.hTimer*4 then s.inIrq=true;s.cpu.irqWanted=true end
    if x==1024 then
      s.inHblank=true
      if not s.inVblank then s:handleHdma() end
    elseif x==0 then s.inHblank=false;s.ppu:checkOverscan(y)
    elseif x==512 and not noPpu then s.ppu:renderLine(y) end
    if y==(s.ppu.frameOverscan and 240 or 225) and x==0 then
      s.inNmi=true;s.inVblank=true
      if s.autoJoyRead then s.autoJoyTimer=4224;s:doAutoJoyRead() end
      if s.nmiEnabled then s.cpu.nmiWanted=true end
    elseif y==0 and x==0 then s.inNmi=false;s.inVblank=false;s:initHdma() end
    if s.autoJoyTimer>0 then s.autoJoyTimer=s.autoJoyTimer-2 end
    s.xPos=x+2
    if s.xPos==1364 then
      s.xPos=0;s.yPos=y+1
      if s.yPos==262 then s:catchUpApu();s.yPos=0;s.frames=s.frames+1 end
    end
  end
end
