-- Deterministic host scheduling test: a frame that fits 60 Hz must not be
-- split merely because the emulator's work slice is shorter than that frame.
local originalLove,originalRequire=love,require
local now=0
love={timer={getTime=function() return now end}}
require=function(name)
  if name=='src.core.Music' or name=='src.render.TextBox' then return {} end
  return originalRequire(name)
end
local ok,problem=xpcall(function()
  local Screen=include('screen.lua')({},function() return function() return {} end end)
  assert(Screen.isFixedSpeed==true,'SNES must ignore Pokemon speed multipliers')
  local function fixture(cost,budget)
    local s=Screen.new({})
    s.mode='playing';s.playTime=0;s.lastSave=0;s.clock=0
    s.budget=budget or s.budget
    local progress=0
    s.console={setButtons=function() end,advance=function()
      progress=progress+1;now=now+cost/12
      if progress==12 then progress=0;return true end
      return false
    end}
    s.buttons=function() return 0 end
    s.video=function() now=now+0.0005 end
    s.saveRam=function() return true end
    return s
  end
  local function run(budget)
    now=0;local s=fixture(.012,budget)
    for tick=1,60 do
      now=tick/60;s.hostDeadline=now+s.budget
      s:update(1/60)
    end
    return s.frameCount
  end
  assert(run(.010)<60,'10 ms work allowance cannot sustain 12 ms frames')
  assert(run()==60,'a 12 ms frame must complete at 60 Hz with the 16 ms slice')
  now=0;local s=fixture(.050)
  for tick=1,10 do
    now=tick/60
    local start=now;s.hostDeadline=start+s.budget
    for i=1,8 do s:update(1/60) end
    assert(now-start<s.budget+.050/12+.0005+1e-9,'catch-up steps multiplied the host allowance')
  end
  local queued
  love.sound={newSoundData=function(count,rate,bits,channels)
    assert(count==534 and rate==32040 and bits==16 and channels==2)
    return {setSample=function(self,i,ch,value) self[i*2+ch]=value end,release=function() end}
  end}
  local audioScreen=Screen.new({});local dsp={sampleOffset=533,samplesL={},samplesR={}}
  for i=0,533 do dsp.samplesL[i]=i/1024;dsp.samplesR[i]=-i/1024 end
  audioScreen.console={machine={ppu={pixelOutput={}},apu={dsp=dsp}}}
  audioScreen.quad={setViewport=function() end};audioScreen.imageData={mapPixel=function() end}
  audioScreen.image={replacePixels=function() end}
  local freeBuffers,playCalls=8,0
  audioScreen.audio={getFreeBufferCount=function() return freeBuffers end,queue=function(_,data) queued=data;freeBuffers=freeBuffers-1 end,isPlaying=function() return false end,play=function() playCalls=playCalls+1 end}
  audioScreen:video()
  assert(queued[1067]==533/1024*.55 and queued[1068]==-533/1024*.55,'last stereo sample lost')
  assert(dsp.sampleOffset==0 and playCalls==0,'audio started without jitter buffer')
  audioScreen:video();assert(playCalls==1,'two complete audio frames must start playback')
  print('PASS: audio queues all 534 stereo samples including the capped last cursor; clock is fixed-speed')
  print('PASS: frontend scheduling completes 12 ms frames at 60 Hz; shared deadline bounds catch-up work')
end,debug.traceback)
love,require=originalLove,originalRequire
assert(ok,problem)
