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
local function restoreTouch()
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
    -- Game speed/catch-up can run several fixed steps in one rendered frame.
    -- Share one small time allowance so emulation cannot multiply that cost.
    active.hostDeadline=love.timer.getTime()+0.010
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
