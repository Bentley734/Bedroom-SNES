local a=assert(Console.new(demo))
local b=assert(Console.new(demo))
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
