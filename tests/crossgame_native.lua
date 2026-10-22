-- Production loader/compatibility dispatch, graphics and audio; fixture worlds
-- do not load or alter a user's Pokemon save.
function love.load()
  local checks={}
  local function check(ok,message) assert(ok,message);checks[#checks+1]='PASS: '..message end
  local ok,err=xpcall(function()
    local Version=require('src.core.GameVersion')
    local version=assert(love.filesystem.read('engine-test-version.txt'));Version.set(version)
    local gen=Version.generation()
    local T=require('tests.modkit')
    local r=T.sdk.loadMods({'mods/bedroom_snes'},{root=love.filesystem.getSource(),generation=gen,dev=false,data=gen==3 and T.sdk.gen3Data() or nil})
    check(#r.errors==0,'production mod loads for '..version)
    local Input=require('src.core.Input');Input:init()
    local Stack=require('src.core.StateStack')
    local host={screenId='BedroomFixture'}
    local game={input=Input,data=r.data,save={version=version,generation=gen,meta={playthroughId='bedroom_snes_crossgame_'..version}},phase=gen==3 and 'field' or 'play'}
    r.loader.game=game
    local draws=0;local originalDraw=function() draws=draws+1 end;game.draw=originalDraw
    local dispatch,p,map,setMap
    local busy=false;local consoleVisible=true
    if gen==2 then
      game.stack=setmetatable({},{__index=Stack});game.stack:init();game.stack:push(host)
      p={cellX=4,cellY=3,facing='up',moving=false}
      local World=require('src.world.gen2.World')
      local w=setmetatable({player=p,map={id='PLAYERS_HOUSE_2F'},game=game,
        busy=function() return busy end,npcAt=function() return consoleVisible and {def={eventFlag=1857}} or nil end,
        interactBody=function() return false end},{__index=World})
      game.world=w;game.overworld=w
      dispatch=function() return w:interact() end
      setMap=function(id) w.map.id=id end
    else
      game.session={map='FR_PLAYERS_HOUSE_2F'}
      local R=require('src.core.game3.runtime');R.active=true;R._game=game;R.session=game.session
      local M=require('src.core.game3.map');M.current='FR_PLAYERS_HOUSE_2F'
      p=require('src.core.game3.player');p.cellX=6;p.cellY=6;p.facing='up';p.moving=false
      local F=require('src.core.game3.field');F.running=true;F.locked=false
      local S=require('src.core.game3.scripting.space');S.vm=nil;S.active=false
      dispatch=function() F.locked=busy;return F.interact(game) end
      setMap=function(id) M.current=id;game.session.map=id end
    end
    local beforeStack=game.stack
    p.facing='left';check(not dispatch(),'nearby non-console interaction passes through');p.facing='up'
    setMap('OTHER_ROOM');check(not dispatch(),'same coordinates in another map pass through')
    setMap(gen==2 and 'PLAYERS_HOUSE_2F' or 'FR_PLAYERS_HOUSE_2F')
    busy=true;check(not dispatch(),'busy script/dialogue cannot launch console');busy=false
    p.moving=true;check(not dispatch(),'moving player cannot launch console');p.moving=false
    if gen==2 then consoleVisible=false;check(not dispatch(),'put-away console leaves an empty tile');consoleVisible=true end
    check(dispatch()==true,'native bedroom console interaction opens emulator')
    local screen=game.stack:top();check(screen.screenId=='BedroomSNES','SNES owns its state')
    check(dispatch()==true and game.stack:top()==screen,'repeat interaction does not duplicate emulator')
    game:draw();check(screen.presentation~=nil and screen.uiCanvas~=nil,'library draws through native host')
    local delegated=0
    r.loader.hooks:call('input.key',function() delegated=delegated+1 end,game,{phase='pressed',key='return'})
    check(screen.mode=='instructions' and not screen.console and delegated==0,'launch instructions consume host input')
    if gen==3 then game:draw();check(screen.uiCanvas~=nil,'Game3 menus render to scaled full-color canvas') end
    screen:keyReleased('return');screen:key('return')
    r.loader.hooks:call('core.update',function(_,dt) game.stack:update(dt) end,game,1/60)
    check(screen.console~=nil and screen.mode=='playing','demo launches with native audio/video')
    for i=1,4 do screen.console:frame() end;screen:video();game:draw()
    check(screen.cartridgePresentation and screen.cartridgePresentation.scale>=1,'cartridge uses native integer-scale presentation')
    local hostUpdates=0
    r.loader.hooks:call('core.update',function() hostUpdates=hostUpdates+1 end,game,1/60)
    check(gen~=3 or hostUpdates==0,'Game3 field stays suspended while SNES owns input')
    if gen==3 then check(require('src.core.game3.audio')._bgmPaused,'Game3 music pauses during cartridge') end
    local ram=screen.console.env.typed('Uint8Array',8192);ram[35]=0xa5
    screen.console.machine.cart.sram=ram;screen.console.header.chips=2
    check(screen:saveRam(),'cartridge SRAM writes in '..version..' playthrough scope')
    screen:pause();screen:resume();check(screen.mode=='playing','pause/resume retains cartridge')
    local saveRam=screen.saveRam;screen.saveRam=function() return false end
    screen:key('backspace');check(game.stack:top()==screen,'failed save keeps native emulator open')
    screen.saveRam=saveRam
    screen:key('backspace')
    check(game.stack==beforeStack and (gen==3 or game.stack:top()==host),'exit restores bedroom stack')
    check(game.draw==originalDraw,'exit restores host draw')
    if gen==3 then check(not require('src.core.game3.audio')._bgmPaused,'Game3 music resumes after exit') end
    r.loader.hooks:call('input.key',function() delegated=delegated+1 end,game,{phase='pressed',key='z'})
    check(delegated==1,'normal host input resumes on exit')
    -- A second entry covers Game3's temporary stack and slow-session dialogue.
    check(dispatch()==true,'console can be entered again')
    screen=game.stack:top();screen.slowSession=true;screen:key('backspace')
    check(gen==3 and require('src.ui.game3.message').open or gen==2 and game.stack:top().pages~=nil,'slow-session dialogue uses native game UI')
    if gen==3 then require('src.ui.game3.message').close() else game.stack:pop() end
    check(dispatch()==true,'console reopens after native dialogue')
    local quit=false;r.loader.hooks:call('core.quit_to_launcher',function() quit=true end)
    check(quit and game.stack==beforeStack and game.draw==originalDraw,'launcher exit restores host stack and draw')
  end,debug.traceback)
  if not ok then checks[#checks+1]='FAIL: '..tostring(err) end
  love.filesystem.write('crossgame-result.txt',table.concat(checks,'\n'))
  love.event.quit(ok and 0 or 1)
end
