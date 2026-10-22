-- Private-ROM native graphics/audio diagnostic; launched only by a local test.
local records={}
local function report()
  local Json=require('src.link.Json')
  love.filesystem.write('cartridge-result.json',Json.encode(records))
end
local function shot(screen,name)
  local canvas=love.graphics.newCanvas(320,288)
  love.graphics.setCanvas(canvas);screen:draw();love.graphics.setCanvas()
  local data=canvas:newImageData();data:encode('png',name..'.png');data:release();canvas:release()
end
function love.load()
  local ok,err=xpcall(function()
    require('src.core.GameVersion').set('red')
    local T=require('tests.modkit')
    local r=T.sdk.loadMods({'mods/bedroom_snes'},{root=love.filesystem.getSource(),generation=1,dev=false})
    assert(#r.errors==0,'Mod failed to load')
    local stack=setmetatable({}, {__index=require('src.core.StateStack')});stack:init()
    local input=require('src.core.Input');input:init()
    local game={stack=stack,input=input,data=r.data,save={version='red',meta={playthroughId='bedroom_snes_private_test'}}}
    stack:push({screenId='BedroomFixture'})
    local screen=r.loader.exports.bedroom_snes.openBedroomSNES(game)
    for i,row in ipairs(screen.rows) do if row.name=='private-test.sfc' then screen.index=i end end
    screen:requestLaunch();shot(screen,'cartridge-instructions');screen:keyReleased('return');screen:key('return');screen:update(1/60)
    assert(screen.console and screen.console.header.name=='ZOMBIES ATE MY NEIGHB','Private test cartridge was not selected')
    local plan={{420,0},{600,0},{600,0},{2,8},{120,0},{2,8},{180,0},{30,128},{30,256},{2,8},{180,0},{2,8},{120,0},{30,128},{30,256},{599,0}}
    for _,stage in ipairs(plan) do
      screen.console:setButtons(stage[2])
      for i=1,stage[1] do screen.console.machine:runFrame(true);screen.console.machine.apu.dsp.sampleOffset=0 end
    end
    local console=screen.console;console:setButtons(0);console:frame();screen:video()
    assert(console.machine.frames==2948,'Wrong gameplay checkpoint')
    shot(screen,'cartridge-gameplay')
    records[#records+1]={checkpoint='first_level',frame=console.machine.frames,pc=console.machine.cpu.br[4]}
    for _,stage in ipairs({{name='walk',mask=128},{name='shoot',mask=256}}) do
      console:setButtons(stage.mask)
      local started=love.timer.getTime()
      for i=1,30 do
        console:frame();screen:video()
        local canvas=love.graphics.newCanvas(320,288);love.graphics.setCanvas(canvas);screen:draw();love.graphics.setCanvas();canvas:release()
      end
      local seconds=love.timer.getTime()-started
      screen.fps=30/seconds
      records[#records+1]={stage=stage.name,frames=30,seconds=seconds,fps=30/seconds,pc=console.machine.cpu.br[4]}
      shot(screen,'cartridge-'..stage.name);report()
    end
    screen:key('backspace');assert(#stack.states==1,'Immediate exit failed')
    records[#records+1]={exit=true}
  end,debug.traceback)
  if not ok then records[#records+1]={error=tostring(err)} end
  report();love.event.quit(ok and 0 or 1)
end
