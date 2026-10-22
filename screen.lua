return function(mod,include)
  local Console=include('core/console.lua')(include)
  local Music=require('src.core.Music')
  local TextBox=require('src.render.TextBox')
  local Screen={};Screen.__index=Screen;Screen.isOpaque=true;Screen.isFixedSpeed=true;Screen.screenId='BedroomSNES'
  local W,H=320,288
  local COLORS={bg={0.035,0.047,0.09},panel={0.075,0.09,0.15},muted={0.56,0.62,0.74},text={0.90,0.94,1},mint={0.48,0.95,0.77},purple={0.64,0.57,0.96}}
  local keys={z=0,a=1,rshift=2,lshift=2,tab=2,['return']=3,up=4,down=5,left=6,right=7,x=8,s=9,q=10,e=11}
  local padBits={b=0,y=1,back=2,start=3,dpup=4,dpdown=5,dpleft=6,dpright=7,a=8,x=9,leftshoulder=10,rightshoulder=11}
  local padKeys={dpup='up',dpdown='down',a='return',b='escape',start='return',back='escape'}
  local function color(name) love.graphics.setColor(COLORS[name]) end
  local function release(o) if o and o.release then pcall(o.release,o) end end
  function Screen.new(game,onClose)
    return setmetatable({game=game,onClose=onClose,mode='library',index=1,rows={},touch={},
      clock=0,fps=0,frameCount=0,fpsTime=0,mute=false,budget=0.016,dirty=true},Screen)
  end
  function Screen:uiSize() return W,H end
  function Screen:enter()
    self.font=love.graphics.newFont(12);self.small=love.graphics.newFont(9);self.titleFont=love.graphics.newFont(23)
    if self.game.input and self.game.input.reset then self.game.input:reset() end
    self:refresh()
  end
  function Screen:refresh()
    self.rows={}
    for _,name in ipairs(mod:list('roms') or {}) do
      if not name:find('[/\\]') and name:lower():match('%.s[fm]c$') then
        self.rows[#self.rows+1]={name=name,path='roms/'..name}
      end
    end
    table.sort(self.rows,function(a,b) if a.name=='bedroom-demo.sfc' then return true elseif b.name=='bedroom-demo.sfc' then return false else return a.name:lower()<b.name:lower() end end)
    self.index=math.max(1,math.min(self.index,#self.rows))
  end
  function Screen:stopAudio()
    if self.audio then self.audio:stop() end
  end
  function Screen:saveRam()
    if not self.console or not self.saveKey or self.console.header.chips~=2 then return true end
    local ok,code,detail=mod.storage:writeBytes(self.game,self.saveKey,self.console:saveRam())
    if not ok then self.notice='Cartridge save failed: '..tostring(detail or code);return false end
    self.notice='Cartridge saved';return true
  end
  function Screen:loadSelected()
    local row=self.rows[self.index];if not row then return end
    self.mode='library'
    self.error=nil;self.notice=nil
    local info=mod:info(row.path)
    if not info or (type(info.size)=='number' and info.size>4*1024*1024+512) then self.error='Cartridge is missing or larger than 4 MiB.';return end
    local bytes,err=mod:read(row.path)
    if not bytes then self.error=tostring(err or 'Could not read cartridge.');return end
    local ok,console,problem=pcall(Console.new,bytes)
    if not ok or not console then self.error=tostring(ok and problem or console);return end
    self:discard()
    self.console=console
    self.saveKey='sram/'..love.data.encode('string','hex',love.data.hash('sha256',select(2,Console.inspect(bytes))))
    local saved=mod.storage:readBytes(self.game,self.saveKey)
    if saved and not console:loadRam(saved) then self.notice='Saved cartridge RAM has the wrong size; ignored.' end
    self.imageData=love.image.newImageData(512,240)
    self.image=love.graphics.newImage(self.imageData);self.image:setFilter('nearest','nearest')
    self.quad=love.graphics.newQuad(0,0,512,224,512,240)
    local audioOk,source=pcall(love.audio.newQueueableSource,32040,16,2,8)
    if audioOk then self.audio=source else self.notice='Audio output is unavailable on this device.' end
    self.musicSong=Music.current();Music.stop()
    self.mode='playing';self.playTime=0;self.fpsTime=0;self.frameCount=0;self.touch={};self.dirty=true
    self.performance={windowAt=love.timer.getTime(),windowFrames=0,slowWindows=0,warmup=2}
  end
  function Screen:requestLaunch()
    if not self.rows[self.index] then return end
    self.mode='instructions';self.instructionReady=false;self.error=nil
  end
  function Screen:keyReleased(_)
    if self.mode=='instructions' then self.instructionReady=true end
  end
  function Screen:discard()
    self:stopAudio();release(self.audio);self.audio=nil
    release(self.image);release(self.imageData);release(self.quad);self.image=nil;self.imageData=nil;self.quad=nil;self.console=nil
  end
  function Screen:pause()
    if self.mode=='playing' then self.mode='paused';self.touch={};self:stopAudio();self:saveRam() end
  end
  function Screen:resume()
    if self.console then
      self.mode='playing';self.touch={};self.waitRelease=true
      if self.performance then self.performance.windowAt=love.timer.getTime();self.performance.windowFrames=0 end
    end
  end
  function Screen:library()
    if not self:saveRam() then self.mode='paused';return end
    self:discard();self.mode='library';self.touch={};self:restoreMusic();self:refresh()
  end
  function Screen:restoreMusic()
    if self.musicSong then Music.play(self.game.data,self.musicSong);self.musicSong=nil end
  end
  function Screen:close()
    if not self:saveRam() then self.mode='paused';return false end
    self.returnToBedroom=true
    if self.game.stack:top()==self then self.game.stack:pop() end
    return true
  end
  function Screen:exit()
    self:saveRam();self:discard();self:restoreMusic();self.touch={}
    release(self.font);release(self.small);release(self.titleFont)
    if self.game.input and self.game.input.reset then self.game.input:reset() end
    if self.onClose then self.onClose() end
    if self.returnToBedroom and self.slowSession and self.game.stack:top() then
      self.game.stack:push(TextBox.new(self.game,"I think there's\nsomething wrong\nwith my SNES..."))
    end
  end
  function Screen:key(key)
    if self.mode=='library' then
      if key=='up' then self.index=math.max(1,self.index-1)
      elseif key=='down' then self.index=math.min(#self.rows,self.index+1)
      elseif key=='return' or key=='z' or key=='space' then self:requestLaunch()
      elseif key=='escape' or key=='backspace' then self:close()
      elseif key=='r' then self:refresh() end
    elseif self.mode=='instructions' then
      if key=='escape' or key=='backspace' or key=='x' then self.mode='library'
      elseif self.instructionReady and (key=='return' or key=='z' or key=='space') then self.pendingLoad=true end
    elseif self.mode=='playing' then
      if key=='escape' or key=='p' then self:pause() end
      if key=='backspace' then self:close() end
    elseif self.mode=='paused' or self.mode=='error' then
      if key=='escape' or key=='p' or key=='return' then if self.mode~='error' then self:resume() end
      elseif key=='q' then self:library()
      elseif key=='backspace' then self:close()
      elseif key=='r' and self.console then self.console:reset();self:resume()
      elseif key=='m' then self.mute=not self.mute end
    end
  end
  function Screen:pad(button)
    if self.mode=='instructions' then
      if button=='b' or button=='back' then self:key('escape')
      elseif button=='a' or button=='start' then self:key('return') end
    elseif self.mode=='playing' then
      if button=='rightstick' or button=='guide' then self:pause() end
    elseif self.mode=='paused' or self.mode=='error' then
      if button=='a' and self.mode~='error' then self:resume()
      elseif button=='b' then self:library()
      elseif button=='y' then self:close() end
    elseif padKeys[button] then self:key(padKeys[button]) end
  end
  function Screen:pointer(ev)
    local id=ev.id or 'mouse';local x,y=ev.gameX,ev.gameY
    if ev.phase=='released' or ev.phase=='cancelled' then
      self.touch[id]=nil
      if self.mode=='instructions' and ev.phase=='released' then self.instructionReady=true end
      return true
    end
    if type(x)~='number' or type(y)~='number' then return true end
    if self.presentation then
      local r=self.presentation
      x,y=(x-r.x)/r.sx,(y-r.y)/r.sy
    elseif self.game.renderer and self.game.renderer.frameRects then
      local r=self.game.renderer:frameRects()
      x,y=(x-r.uox)/r.Ux,(y-r.uoy)/r.Uy
    end
    if ev.phase~='pressed' and ev.phase~='moved' then return true end
    if self.mode=='playing' then
      if ev.phase=='pressed' then self:pause() end
    elseif ev.phase=='pressed' then
      if self.mode=='library' then
        if y<30 and x>270 then self:close()
        elseif y>=82 and y<218 then
          local first=math.max(1,self.index-3);local row=first+math.floor((y-82)/27)
          if self.rows[row] then self.index=row;self:requestLaunch() end
        end
      elseif self.mode=='instructions' then
        if y>=220 and y<247 and self.instructionReady then self.pendingLoad=true
        elseif y>=250 and y<278 then self.mode='library' end
      else
        if y>=143 and y<170 and self.mode~='error' then self:resume()
        elseif y>=173 and y<200 then self:library()
        elseif y>=203 and y<230 then self:close() end
      end
    end
    return true
  end
  function Screen:buttons()
    local bits={}
    if love.window and not love.window.hasFocus() then self:pause();return 0 end
    for key,bit in pairs(keys) do if love.keyboard.isDown(key) then bits[bit]=true end end
    for _,joy in ipairs(love.joystick.getJoysticks()) do
      if joy:isGamepad() then
        for button,bit in pairs(padBits) do if joy:isGamepadDown(button) then bits[bit]=true end end
        local x,y=joy:getGamepadAxis('leftx'),joy:getGamepadAxis('lefty')
        if x<-.4 then bits[6]=true elseif x>.4 then bits[7]=true end
        if y<-.4 then bits[4]=true elseif y>.4 then bits[5]=true end
        if joy:isGamepadDown('start') and joy:isGamepadDown('back') then self:pause() end
      end
    end
    for _,bit in pairs(self.touch) do bits[bit]=true end
    if self.waitRelease then if next(bits)==nil then self.waitRelease=false end;return 0 end
    local mask=0;for bit in pairs(bits) do mask=mask+2^bit end
    return mask
  end
  function Screen:video()
    local output=self.console.machine.ppu.pixelOutput
    -- SNES lines 1..224 (or 239 with overscan); retain horizontal hires pixels.
    local height=self.console.machine.ppu.frameOverscan and 239 or 224
    self.videoHeight=height
    self.quad:setViewport(0,0,512,height)
    self.imageData:mapPixel(function(x,y)
      if y>=height then return 0,0,0,1 end
      local i=(y+1)*1536+x*3
      return output[i]/255,output[i+1]/255,output[i+2]/255,1
    end)
    self.image:replacePixels(self.imageData)
    if self.audio and self.audio:getFreeBufferCount()>0 then
      local dsp=self.console.machine.apu.dsp
      -- sampleOffset is a cursor capped at 533, not the frame sample count.
      -- The core produces 534 stereo samples per 60 Hz frame (32040 Hz).
      local count=534
      local data=love.sound.newSoundData(count,32040,16,2)
      local volume=self.mute and 0 or .55
      for i=0,count-1 do data:setSample(i,1,math.max(-1,math.min(1,dsp.samplesL[i]*volume)));data:setSample(i,2,math.max(-1,math.min(1,dsp.samplesR[i]*volume))) end
      self.audio:queue(data);release(data)
      -- Two queued frames absorb ordinary host jitter before playback starts.
      if not self.audio:isPlaying() and self.audio:getFreeBufferCount()<=6 then self.audio:play() end
    end
    self.console.machine.apu.dsp.sampleOffset=0
    self.dirty=false
  end
  function Screen:update(dt)
    self.clock=self.clock+dt
    if self.pendingLoad then self.pendingLoad=false;self:loadSelected();self.waitRelease=true;return end
    -- Built-in touch controls still deliver logical GB button edges.
    local input=self.game.input
    if self.mode=='library' and input then
      if input:wasPressed('up') then self:key('up') elseif input:wasPressed('down') then self:key('down')
      elseif input:wasPressed('a') then self:requestLaunch() elseif input:wasPressed('b') or input:wasPressed('start') then self:close() end
    elseif self.mode=='playing' and input and input:wasPressed('start') then self:pause() end
    if self.mode~='playing' then return end
    local mask=self:buttons();if self.mode~='playing' then return end
    self.console:setButtons(mask)
    self.playTime=self.playTime+dt
    if self.playTime<1/60 then return end
    -- Keep a small time debt so occasional expensive frames can catch up.
    -- The shared host deadline still bounds all fixed-step calls together.
    self.playTime=math.min(self.playTime,3/60)
    local start=love.timer.getTime();local completed=0
    local deadline=math.min(start+self.budget,self.hostDeadline or math.huge)
    if start>=deadline then return end
    local ok,err=pcall(function()
      repeat
        local done=self.console:advance(256)
        if done then
          self:video()
          self.playTime=math.max(0,self.playTime-1/60)
          self.frameCount=self.frameCount+1;completed=completed+1
          self:measurePerformance(love.timer.getTime(),true)
        end
      until love.timer.getTime()>=deadline or self.playTime<1/60 or completed>=2
    end)
    if not ok then self.error=tostring(err);self.mode='error';self:stopAudio();self:saveRam();return end
    if completed==0 then self:measurePerformance(love.timer.getTime(),false) end
    if self.clock-(self.lastSave or 0)>30 then self.lastSave=self.clock;self:saveRam() end
  end
  function Screen:measurePerformance(now,completed)
    local p=self.performance;if not p then return end
    if completed then p.windowFrames=p.windowFrames+1 end
    local elapsed=now-p.windowAt
    if elapsed>=2 then
      self.fps=p.windowFrames/elapsed
      if p.warmup>0 then p.warmup=p.warmup-1
      elseif self.fps<20 then p.slowWindows=p.slowWindows+1
      else p.slowWindows=0 end
      if p.slowWindows>=3 then self.slowSession=true end
      p.windowAt=now;p.windowFrames=0
    end
  end
  local function text(font,value,x,y,tint)
    love.graphics.setFont(font);color(tint or 'text');love.graphics.print(value,x,y)
  end
  function Screen:drawPause()
    local g=love.graphics
      if self.mode=='paused' or self.mode=='error' then
        g.setColor(0.02,0.03,0.06,.94);g.rectangle('fill',12,51,296,190,8)
        text(self.titleFont,self.mode=='error' and 'Emulation stopped' or 'Paused',26,65)
        g.setFont(self.small);color('muted');g.printf((self.error or self.notice or 'ESC / P resume  |  R reset  |  M mute') :sub(1,220),26,104,267,'left')
        if self.mode~='error' then text(self.font,'Resume  /  Enter or A',27,148,'mint') end
        text(self.font,'Cartridges  /  Q or B',27,178)
        text(self.font,'Return to room  /  Backspace or Y',27,208)
      end
  end
  -- Coordinates and scales are in physical framebuffer pixels before DPI
  -- conversion, so 125%/150% desktop scaling cannot introduce fractional pixels.
  function Screen:layout(ctx,w,h)
    local dx,dy=ctx.dpiX or 1,ctx.dpiY or 1
    local pw,ph=ctx.pw or ctx.ww*dx,ctx.ph or ctx.wh*dy
    local scale=math.floor(math.min(pw/w,ph/h))
    if scale<1 then scale=math.min(pw/w,ph/h) end
    return {x=(ctx.viewX or 0)+math.floor((pw-w*scale)/2)/dx,
      y=(ctx.viewY or 0)+math.floor((ph-h*scale)/2)/dy,
      sx=scale/dx,sy=scale/dy,scale=scale,w=w,h=h}
  end
  function Screen:present(ctx)
    local g=love.graphics
    g.push('all');g.origin();g.setShader();g.setScissor()
    g.setBlendMode('alpha');g.setColor(0,0,0,1);g.rectangle('fill',0,0,ctx.ww,ctx.wh)
    local ui=self:layout(ctx,W,H);self.presentation=ui
    if self.image and self.mode~='library' and self.mode~='instructions' then
      local p=self.console.machine.ppu
      local width=(p.mode==5 or p.mode==6 or p.pseudoHires) and 512 or 256
      local r=self:layout(ctx,width,self.videoHeight or 224)
      self.cartridgePresentation=r
      g.setColor(1,1,1,1)
      g.draw(self.image,self.quad,r.x,r.y,0,r.sx*width/512,r.sy)
      if self.mode=='paused' or self.mode=='error' then
        g.translate(ui.x,ui.y);g.scale(ui.sx,ui.sy);self:drawPause()
      end
    elseif ctx.uiCanvas then
      g.setColor(1,1,1,1)
      g.draw(ctx.uiCanvas,ui.x,ui.y,0,ui.sx,ui.sy)
    end
    g.pop()
    return true
  end
  function Screen:draw()
    local g=love.graphics;g.push('all');g.origin();g.setShader();color('bg');g.rectangle('fill',0,0,W,H)
    if self.mode=='instructions' then
      text(self.small,'BEFORE YOU PLAY',16,14,'mint')
      text(self.titleFont,'Leaving the SNES',16,33)
      text(self.font,'Keyboard',16,77,'purple')
      text(self.small,'BACKSPACE: return straight to the bedroom.',16,96)
      text(self.small,'ESC / P: pause and open the exit menu.',16,111,'muted')
      text(self.font,'Controller',16,135,'purple')
      text(self.small,'Click the right stick, or hold Start + Select.',16,154)
      text(self.small,'Then press Y to return to the bedroom.',16,169,'muted')
      text(self.small,'TOUCH: tap the picture to pause and exit.',16,196)
      color('purple');g.rectangle('fill',12,220,296,27,5)
      text(self.font,'Play cartridge  /  Enter or A',22,226)
      text(self.small,'Back to cartridges  /  Escape or B',22,258,'muted')
    elseif self.mode=='library' then
      text(self.small,'PALLET TOWN / PLAYER BEDROOM',16,12,'mint')
      text(self.titleFont,'Bedroom SNES',16,28);text(self.small,'EXIT',285,14,'muted')
      text(self.small,'CARTRIDGES',16,66,'muted')
      local first=math.max(1,self.index-3)
      for i=first,math.min(#self.rows,first+4) do
        local y=82+(i-first)*27;color(i==self.index and 'purple' or 'panel');g.rectangle('fill',12,y,296,24,5)
        text(self.font,(self.rows[i].name:gsub('%.s[fm]c$','')):sub(1,36),20,y+4)
      end
      if #self.rows==0 then text(self.font,'No cartridges found.',18,89) end
      local message=self.error or self.notice or 'Add your own .sfc / .smc files to this mod\'s roms folder.'
      g.setFont(self.small);color(self.error and 'purple' or 'muted');g.printf(message,16,224,288,'left')
      text(self.small,'ENTER / A  PLAY     ESC / B  RETURN TO ROOM',16,263,'mint')
      text(self.small,'EXPERIMENTAL  /  NTSC  /  SPEED & COMPATIBILITY VARY',16,278,'muted')
    else
      if self.image then
        g.setColor(1,1,1,1)
        local vh=self.videoHeight or 224
        g.draw(self.image,self.quad,32,math.floor((H-vh)/2),0,.5,1)
      end
      self:drawPause()
    end
    g.pop()
  end
  return Screen
end
