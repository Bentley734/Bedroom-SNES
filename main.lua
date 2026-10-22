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
local active
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
  active=Screen.new(game,function() active=nil;restoreTouch() end)
  -- The cartridge has its own presentation; skip Pokemon's unused world/UI
  -- pipeline and other game-draw wrappers for this one opaque state only.
  if type(game.draw)=='function' then
    drawGame=game;previousOwnDraw=rawget(game,'draw')
    local previousDraw=game.draw
    fastDraw=function(self,...)
      if active and self.stack:top()==active and active.image
        and active.mode~='library' and active.mode~='instructions' then
        return active:drawDirect()
      end
      return previousDraw(self,...)
    end
    game.draw=fastDraw
  end
  game.stack:push(active)
  return active
end
mod.content.map_scripts:register('REDS_HOUSE_2F',{
  priority=100,
  onInteract=function(game,ow,x,y)
    if x~=3 or y~=5 then return false end
    if active then return true end
    open(game)
    return true
  end,
})
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
  end
  return next(game,dt)
end)
mod.hooks:wrap('core.quit_to_launcher',function(next)
  if active then active:saveRam() end
  return next()
end)
mod.exports.openBedroomSNES=function(game)
  return open(game)
end
end
