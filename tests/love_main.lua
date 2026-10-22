-- Real LÖVE graphics/audio plus Gen1Recomp's actual sandbox and mod loader.
local result={};local failed
local function check(ok,message) assert(ok,message);result[#result+1]='PASS: '..message end
local function screenshot(screen,name)
  local canvas=love.graphics.newCanvas(320,288)
  love.graphics.setCanvas(canvas);screen:draw();love.graphics.setCanvas()
  local data=canvas:newImageData();data:encode('png',name..'.png');data:release();canvas:release()
end
function love.load()
  local ok,err=xpcall(function()
    local version=love.filesystem.read('engine-test-version.txt') or 'red'
    require('src.core.GameVersion').set(version)
    local T=require('tests.modkit')
    local r=T.sdk.loadMods({'mods/bedroom_snes'},{generation=1,dev=false,root=love.filesystem.getSource()})
    for _,error in ipairs(r.errors) do print(error.message or tostring(error)) end
    check(#r.errors==0,'api-2 mod loads in the production sandbox without errors')
    check(r.loader.exports.bedroom_snes~=nil,'bedroom mod exports are registered')
    local Data=require('src.core.Data');Data.map_scripts=r.data.map_scripts
    local handler=require('src.script.MapScripts').get('REDS_HOUSE_2F').onInteract
    check(type(handler)=='function','native bedroom interaction composes through MapScripts')
    local stack=setmetatable({}, {__index=require('src.core.StateStack')});stack:init()
    local input=require('src.core.Input');input:init()
    local Touch=require('src.core.TouchControls');local visibleBefore=Touch.visible
    local game={stack=stack,input=input,data=r.data,save={version=version,meta={playthroughId='bedroom_snes_test'}}}
    local delegatedDraws=0;local originalDraw=function() delegatedDraws=delegatedDraws+1 end;game.draw=originalDraw
    local bedroom={screenId='BedroomFixture'};stack:push(bedroom)
    check(not handler(game,bedroom,2,5),'interacting with another bedroom tile is preserved')
    check(handler(game,bedroom,3,5)==true,'interacting with the SNES opens the emulator')
    local screen=stack:top();check(screen.screenId=='BedroomSNES','emulator owns the top state')
    check(not Touch:visible(),'the vanilla touch overlay is hidden while the emulator owns the screen')
    check(not Touch:touchpressed('overlay-probe',20,250),'native touch capture yields to the emulator controls')
    check(handler(game,bedroom,3,5) and #stack.states==2,'repeated interaction does not open duplicate screens')
    game:draw();check(delegatedDraws==1,'cartridge library delegates the normal host draw')
    screenshot(screen,'library')
    local delegated=0
    r.loader.hooks:call('input.key',function() delegated=delegated+1 end,game,{phase='pressed',key='return'})
    check(delegated==0 and screen.mode=='instructions' and not screen.console,'exit instructions appear before launching a cartridge')
    screenshot(screen,'instructions')
    screen:key('return');check(not screen.pendingLoad,'a held launch button cannot skip the exit instructions')
    r.loader.hooks:call('input.key',function() end,game,{phase='released',key='return'})
    r.loader.hooks:call('input.key',function() end,game,{phase='pressed',key='return'})
    check(screen.pendingLoad,'release then confirm launches the cartridge')
    screen:update(1/60)
    check(screen.console~=nil and screen.mode=='playing','built-in original SNES cartridge loads')
    check(require('src.core.Game').isFixedSpeedInStack(stack),'SNES clock ignores Pokemon speed multipliers')
    screen.waitRelease=false
    for i=1,4 do screen.console:frame() end
    screen:video();screenshot(screen,'playing')
    assert(loadstring(love.filesystem.read('mods/bedroom_snes/tests/presentation.lua')))()(screen,r,check)
    check(screen.console.machine.ppu.forcedBlank==false,'SNES graphics render to a real LÖVE texture')
    screen:pause();check(screen.mode=='paused','pause stops emulator updates')
    screenshot(screen,'paused')
    screen:pointer({phase='pressed',id='finger',gameX=100,gameY=155})
    check(screen.mode=='playing','touch pause menu resumes the cartridge')
    screen:pointer({phase='pressed',id='finger',gameX=90,gameY=245})
    check(screen.mode=='paused' and screen.touch.finger==nil,'tapping the picture pauses without visible gameplay controls')
    screen:resume()
    screen:pointer({phase='cancelled',id='finger'})
    check(screen.touch.finger==nil,'focus cancellation releases touch holds')
    screen:pause();screen:key('q')
    check(screen.mode=='library' and screen.console==nil,'cartridge menu releases emulator resources')
    screen:key('return');screen:keyReleased('return');screen:key('return');screen:update(1/60);check(screen.console~=nil,'cartridge can be opened again')
    screen:pause();screen:key('backspace')
    check(stack:top()==bedroom and #stack.states==1,'exit returns to the existing bedroom state')
    check(Touch.visible==visibleBefore,'exit restores the vanilla touch overlay')
    check(game.draw==originalDraw,'exit restores the previous host draw method')
    r.loader.hooks:call('input.key',function() delegated=delegated+1 end,game,{phase='pressed',key='z'})
    check(delegated==1,'normal input resumes after leaving the emulator')
    -- Real per-mod opaque storage, isolated in the SDK filesystem overlay.
    local exported=r.loader.exports.bedroom_snes
    screen=exported.openBedroomSNES(game);screen:loadSelected()
    local saved=screen.console
    local ram=saved.env.typed('Uint8Array',8192);saved.machine.cart.sram=ram
    saved.header.chips=2;ram[35]=0xa5
    local key=screen.saveKey
    check(screen:saveRam(),'battery RAM writes through Gen1Recomp mod.storage')
    local api=r.loader:_api(r.loader.mods.bedroom_snes)
    local persisted=api.storage:readBytes(game,key)
    check(type(persisted)=='string' and #persisted==8192 and persisted:byte(36)==0xa5,'battery save bytes survive the storage round-trip')
    local originalStorage=screen.saveRam
    screen.saveRam=function() return false end
    check(not screen:close() and stack:top()==screen,'a failed save keeps the emulator open')
    screen.saveRam=originalStorage;screen:close()
    screen=exported.openBedroomSNES(game);screen:loadSelected()
    screen.performance={windowAt=0,windowFrames=0,slowWindows=0,warmup=2}
    for i=1,5 do screen.performance.windowFrames=120;screen:measurePerformance(i*2,false) end
    check(not screen.slowSession,'normal frame rates do not trigger the broken-SNES dialogue')
    screen.performance={windowAt=0,windowFrames=0,slowWindows=0,warmup=2}
    for i=1,4 do screen:measurePerformance(i*2,false) end
    check(not screen.slowSession,'warm-up and brief slowdowns do not trigger the dialogue')
    screen:measurePerformance(10,false)
    check(screen.slowSession,'sustained unplayable frame rates flag the session')
    screen:key('backspace')
    check(stack:top()~=bedroom and #stack.states==2,'Backspace exits immediately and shows the player dialogue after a slow session')
    local lines={};for _,page in ipairs(stack:top().pages or {}) do for _,line in ipairs(page) do lines[#lines+1]=line end end
    check(table.concat(lines,' '):find("I think there's something wrong with my SNES",1,true)~=nil,'the slow-session dialogue contains the requested player line')
    stack:pop();check(stack:top()==bedroom,'slow-session dialogue leaves the original bedroom underneath')
    r.release()
  end,debug.traceback)
  if not ok then failed=err;result[#result+1]='FAIL: '..tostring(err) end
  love.filesystem.write('result.txt',table.concat(result,'\n'))
  love.event.quit(ok and 0 or 1)
end
