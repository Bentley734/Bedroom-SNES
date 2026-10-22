return function(mod)
local modules={}
local function include(path)
  if modules[path]==nil then
    local source,err=mod:read(path)
    assert(source,err or ('Missing mod file: '..path))
    local chunk,compileErr=load(source,'@bedroom_snes/'..path)
    assert(chunk,compileErr)
    modules[path]=chunk()
  end
  return modules[path]
end
local Screen=include('screen.lua')(mod,include)
local Version=require('src.core.GameVersion')
local generation=Version.generation()
local active
local previousStack
local TouchControls=require('src.core.TouchControls')
local previousVisible,touchVisible,previousPressed,touchPressed
local drawGame,previousOwnDraw,fastDraw
local function restoreTouch()
  if drawGame and drawGame.draw==fastDraw then drawGame.draw=previousOwnDraw end
  drawGame,previousOwnDraw,fastDraw=nil,nil,nil
  if TouchControls.visible==touchVisible then TouchControls.visible=previousVisible end
  if TouchControls.touchpressed==touchPressed then TouchControls.touchpressed=previousPressed end
end
local function open(game)
  if active then return active end
  if generation==3 then
    -- Game3 has a modal layer system rather than a StateStack. Keep a private
    -- stack while its update is suspended; restore the host property on exit.
    previousStack=rawget(game,'stack')
    game.stack=setmetatable({}, {__index=require('src.core.StateStack')})
    game.stack:init();game.stack:push({screenId='BedroomSNESHost'})
  end
  previousVisible=TouchControls.visible
  previousPressed=TouchControls.touchpressed
  touchVisible=function(self,...)
    if active and active.game.stack:top()==active then return false end
    return previousVisible(self,...)
  end
  TouchControls.visible=touchVisible
  touchPressed=function(self,...)
    if active and active.game.stack:top()==active then return false end
    return previousPressed(self,...)
  end
  TouchControls.touchpressed=touchPressed
  TouchControls:reset()
  active=Screen.new(game,function()
    active=nil;restoreTouch()
    if generation==3 then game.stack=previousStack;previousStack=nil end
  end)
  active.generation=generation
  -- The cartridge has its own presentation; skip Pokemon's unused world/UI
  -- pipeline and other game-draw wrappers for this one opaque state only.
  if type(game.draw)=='function' then
    drawGame=game;previousOwnDraw=rawget(game,'draw')
    local previousDraw=game.draw
    fastDraw=function(self,...)
      if active and self.stack:top()==active and (generation~=1 or (active.image
        and active.mode~='library' and active.mode~='instructions')) then
        return active:drawDirect()
      end
      return previousDraw(self,...)
    end
    game.draw=fastDraw
  end
  game.stack:push(active)
  return active
end
if generation==1 then mod.content.map_scripts:register('REDS_HOUSE_2F',{
  priority=100,
  onInteract=function(game,ow,x,y)
    if x~=3 or y~=5 then return false end
    if active then return true end
    open(game)
    return true
  end,
}) else
  local Overworld=require('src.world.OverworldController')
  local previousInteract=Overworld.interact
  local delta={up={0,-1},down={0,1},left={-1,0},right={1,0}}
  Overworld.interact=function(ow,...)
    local game=mod.game
    local p=ow and ow.player
    local map=ow and ow.map
    local id=map and (map.gen3Id or map.id)
    local d=p and delta[p.facing]
    local target=generation==2 and 'PLAYERS_HOUSE_2F' or 'FR_PLAYERS_HOUSE_2F'
    local tx,ty=generation==2 and 4 or 6,generation==2 and 2 or 5
    local ready=game and game.input and p and not p.moving and d
    if ready and generation==2 then
      local console=ow:npcAt(tx,ty)
      ready=not ow:busy() and console and console.def and console.def.eventFlag==1857
    end
    if ready and generation==3 then
      local Field=require('src.core.game3.field')
      local Space=require('src.core.game3.scripting.space')
      local Runtime=require('src.core.game3.runtime')
      ready=game.phase=='field' and not Field.locked and not p.boulderPush
        and not require('src.ui.game3.stack').busy()
        and not (Runtime.uiBusy and Runtime.uiBusy())
        and not (Space.vm and Space.vm.isRunning and Space.vm:isRunning())
    end
    if ready and id==target and p.cellX+d[1]==tx and p.cellY+d[2]==ty then
      if not active then open(game) end
      return true
    end
    return previousInteract(ow,...)
  end
end
local function owned(game)
  return active and game and game.stack and game.stack:top()==active
end
-- Own the final composition while the SNES is topmost. The Pokemon palette
-- pass and shader chain must not quantize full-color cartridge pixels or menus.
mod.hooks:wrap('render.compose',function(next,renderer,ctx)
  if active and owned(active.game) then return active:present(ctx) end
  return next(renderer,ctx)
end,1000)
mod.hooks:wrap('input.key',function(next,game,ev)
  if not owned(game) then return next(game,ev) end
  if ev.phase=='pressed' then active:key(ev.key) end
  if ev.phase=='released' then active:keyReleased(ev.key) end
  return true
end)
mod.hooks:wrap('input.gamepad',function(next,game,ev)
  if not owned(game) then return next(game,ev) end
  if ev.phase=='pressed' then active:pad(ev.button) end
  if ev.phase=='released' then active:keyReleased(ev.button) end
  return true
end)
mod.hooks:wrap('input.pointer',function(next,game,ev)
  if not owned(game) then return next(game,ev) end
  return active:pointer(ev) or next(game,ev)
end)
mod.hooks:wrap('core.update',function(next,game,dt)
  if owned(game) then
    -- Start the shared emulation allowance at the first SNES slice, not
    -- before unrelated host/mod work. Catch-up callbacks reuse that deadline.
    active:beginHostFrame(love.timer.getTime())
    if love.window and not love.window.hasFocus() then active:pause() end
    if generation==3 then active:update(dt);return end
  end
  return next(game,dt)
end)
mod.hooks:wrap('core.quit_to_launcher',function(next)
  if active and not active:close() then return false end
  return next()
end)
mod.exports.openBedroomSNES=function(game)
  return open(game)
end
end
