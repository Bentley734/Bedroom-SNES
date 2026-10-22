-- Private-ROM benchmark using the actual mod loader, state and native LÖVE APIs.
-- Copy this file to an isolated probe's main.lua; never package the ROM or output.
-- private-plan.json:
-- {"expectedTitle":"...", "preload":[[120,0],[2,8]], "warmupFrames":1,
--  "benchmark":[{"name":"gameplay","frames":600,"mask":128}],
--  "paced":{"seconds":15,"mask":128,"resetToCheckpoint":true}}
-- paced.inputs can replace paced.mask: [{"seconds":2,"mask":0}, ...].
local records={}
local Json
local screen,canvas
local function report()
  love.filesystem.write('native-gameplay-result.json',Json.encode(records))
end
local function draw()
  love.graphics.setCanvas(canvas);screen:draw();love.graphics.setCanvas()
  love.graphics.flushBatch()
end
local function shot(name)
  draw()
  local data=canvas:newImageData()
  data:encode('png','native-gameplay-'..name..'.png');data:release()
end
local function percentile(values,fraction)
  local copy={};for i,v in ipairs(values) do copy[i]=v end;table.sort(copy)
  return copy[math.max(1,math.ceil(#copy*fraction))] or 0
end
local function snapshot()
  local m=screen.console.machine
  local pixels=m.ppu.pixelOutput
  local rows={}
  for y=1,224 do
    local row={}
    for x=0,1535 do row[x+1]=string.char(pixels[y*1536+x]) end
    rows[y]=table.concat(row)
  end
  local rgb=table.concat(rows)
  return {frame=m.frames,pc=m.cpu.br[4],spcPc=m.apu.spc.br[0],ppuMode=m.ppu.mode,
    pixelSha256=love.data.encode('string','hex',love.data.hash('sha256',rgb))}
end
local function peak()
  local dsp=screen.console.machine.apu.dsp
  local value=0
  for i=0,dsp.sampleOffset-1 do value=math.max(value,math.abs(dsp.samplesL[i]),math.abs(dsp.samplesR[i])) end
  return value
end
function love.load()
  Json=require('src.link.Json')
  local originalFocus=love.window.hasFocus
  local ok,err=xpcall(function()
    local plan=assert(Json.decode(assert(love.filesystem.read('private-plan.json'))),'Invalid private plan')
    require('src.core.GameVersion').set('red')
    local T=require('tests.modkit')
    local loaded=T.sdk.loadMods({'mods/bedroom_snes'},{root=love.filesystem.getSource(),generation=1,dev=false})
    assert(#loaded.errors==0,'Mod failed to load')
    local stack=setmetatable({}, {__index=require('src.core.StateStack')});stack:init()
    local input=require('src.core.Input');input:init()
    local game={stack=stack,input=input,data=loaded.data,save={version='red',meta={playthroughId='bedroom_snes_private_gameplay_test'}}}
    stack:push({screenId='BedroomFixture'})
    screen=loaded.loader.exports.bedroom_snes.openBedroomSNES(game)
    local found=false
    for i,row in ipairs(screen.rows) do if row.name=='private-test.sfc' then screen.index=i;found=true end end
    assert(found,'Private cartridge was not present in the isolated probe')
    canvas=love.graphics.newCanvas(320,288)
    screen:requestLaunch();shot('instructions');screen:keyReleased('return');screen:key('return');screen:update(1/60)
    assert(screen.console,screen.error or 'Private cartridge did not load')
    if plan.expectedTitle then assert(screen.console.header.name==plan.expectedTitle,'Wrong cartridge selected') end
    records.cartridge=screen.console.header.name
    records.preloadSkippedVideo=true
    records.benchmark={}
    local initialRam=string.rep('\0',#screen.console:saveRam())
    local function preload()
      screen.console:loadRam(initialRam)
      screen.console:reset()
      screen:stopAudio()
      local ppu=screen.console.machine.ppu;local render=ppu.renderLine
      ppu.renderLine=function() end
      for _,stage in ipairs(plan.preload or {}) do
        screen.console:setButtons(stage.mask or stage[2] or 0)
        for i=1,(stage.frames or stage[1]) do
          screen.console:frame()
          screen.console.machine.apu.dsp.sampleOffset=0
        end
      end
      ppu.renderLine=render
      screen.console:setButtons(0)
      for i=1,(plan.warmupFrames or 1) do screen.console:frame();screen:video() end
      records.warmupFrames=plan.warmupFrames or 1
      screen:stopAudio()
    end
    preload()
    records.checkpoint=snapshot();shot('checkpoint');report()
    for index,stage in ipairs(plan.benchmark or {{name='gameplay',frames=600,mask=0}}) do
      local frames=stage.frames or 600
      local times,audioPeak={},0
      screen.console:setButtons(stage.mask or 0)
      local started=love.timer.getTime()
      for frame=1,frames do
        local t=love.timer.getTime()
        screen.console:frame();audioPeak=math.max(audioPeak,peak())
        screen:video();draw()
        times[frame]=love.timer.getTime()-t
      end
      local seconds=love.timer.getTime()-started
      local result=snapshot()
      result.name=stage.name or tostring(index);result.frames=frames;result.seconds=seconds
      result.fps=frames/seconds;result.processingP95Ms=percentile(times,.95)*1000
      result.processingMaxMs=percentile(times,1)*1000;result.audioPeak=audioPeak
      result.includes='Console frame, audio sampling/queue, texture upload and draw; uncapped, no display synchronization'
      records.benchmark[#records.benchmark+1]=result
      screen.fps=result.fps;shot('benchmark-'..index);report()
    end
    local paced=plan.paced or {}
    if paced.resetToCheckpoint~=false then preload() end
    local inputMask=paced.mask or 0
    -- Test-only deterministic controller input and focus; cartridge input still
    -- reaches the normal Screen:update / Console:setButtons path.
    screen.buttons=function() return inputMask end
    love.window.hasFocus=function() return true end
    screen.mode='playing';screen.waitRelease=false;screen.playTime=0
    screen.frameCount=0;screen.clock=0;screen.lastSave=0;screen.fps=0
    local FixedStep=require('src.core.FixedStep')
    FixedStep.setHz(60);FixedStep:init(function(dt) screen:update(dt) end)
    FixedStep.refreshPeriod=1/60
    local times={}
    local started=love.timer.getTime()
    screen.performance={windowAt=started,windowFrames=0,slowWindows=0,warmup=2}
    local previous=started-1/60
    local firstFrame=screen.console.machine.frames
    local ticks=0
    local duration=paced.seconds or 15
    repeat
      local now=love.timer.getTime()
      local elapsed=now-started
      if paced.inputs then
        local edge=0
        for _,stage in ipairs(paced.inputs) do
          inputMask=stage.mask or 0;edge=edge+stage.seconds
          if elapsed<edge then break end
        end
      end
      local dt=now-previous;previous=now
      local t=love.timer.getTime()
      loaded.loader.hooks:call('core.update',function(_,hostDt) FixedStep:update(hostDt,1) end,game,dt)
      assert(screen.mode=='playing',screen.error or 'Unexpected pause during paced test')
      draw()
      ticks=ticks+1;times[ticks]=love.timer.getTime()-t
      local wait=started+ticks/60-love.timer.getTime()
      if wait>0 then love.timer.sleep(wait) end
    until love.timer.getTime()-started>=duration
    local seconds=love.timer.getTime()-started
    local result=snapshot()
    result.seconds=seconds;result.frames=screen.console.machine.frames-firstFrame
    result.fps=result.frames/seconds;result.hostTicks=ticks
    result.processingP95Ms=percentile(times,.95)*1000;result.processingMaxMs=percentile(times,1)*1000
    result.includes='Wall-paced 60 Hz core.update hook, native FixedStep, Screen:update, audio/video/draw and sleeps'
    records.paced=result
    screen.fps=result.fps;shot('paced');report()
    screen:key('backspace')
    assert(stack.states[1].screenId=='BedroomFixture' and stack:top()~=screen,'Exit did not preserve the bedroom')
    assert(#stack.states==1 or (#stack.states==2 and stack:top().pages),'Exit left an unexpected state')
    records.exit=true
  end,debug.traceback)
  love.window.hasFocus=originalFocus
  if not ok then records.error=tostring(err) end
  if canvas then canvas:release() end
  report();love.event.quit(ok and 0 or 1)
end
