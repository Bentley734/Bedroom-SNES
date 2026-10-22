-- Exercise the real renderer endFrame, not just Screen:draw: the host's
-- color-remap and final shader passes are where the installed bug occurred.
return function(screen,loaded,check)
  local Renderer=require('src.render.Renderer')
  local View=require('src.render.GameViewport')
  local Palette=require('src.render.PaletteFX')
  local FX=require('src.render.ShaderFX')
  local oldDimensions,oldPixels,oldTarget=View.dimensions,View.pixelDimensions,View.setTarget
  local oldMode,oldActive,oldRender=Palette.mode,FX.active,FX.render
  local width,height,target=640,480
  local shaded=0
  View.dimensions=function() return width,height end
  View.pixelDimensions=function() return width,height end
  View.setTarget=function() love.graphics.setCanvas(target) end
  FX.active=function() return true end
  FX.render=function() shaded=shaded+1 end
  Renderer:init();Renderer:setUISize(320,288)
  local oldRenderer=screen.game.renderer;screen.game.renderer=Renderer
  local zones={{colors={{255,0,255},{0,255,255},{255,0,0},{0,0,0}},x=0,y=0,w=320,h=288}}
  local function render(mode,w,h)
    width,height=w,h
    target=love.graphics.newCanvas(w,h,{dpiscale=1})
    Palette.setMode(mode)
    Renderer:beginFrame(false)
    if screen.mode=='playing' then
      local originalDraw=love.graphics.draw;local draws=0
      love.graphics.draw=function(...) draws=draws+1;return originalDraw(...) end
      screen:draw();love.graphics.draw=originalDraw
      assert(draws==0,'cartridge texture was drawn twice through the UI canvas')
    else screen:draw() end
    Renderer:endFrame(zones)
    love.graphics.setCanvas()
    local data=target:newImageData();target:release();return data
  end
  for _,size in ipairs({{640,480,2},{1570,1268,5},{1137,779,3}}) do
    local data=render('redpp',size[1],size[2])
    local r=screen.cartridgePresentation
    assert(r.scale==size[3] and r.x==math.floor((size[1]-256*r.scale)/2) and r.y==math.floor((size[2]-224*r.scale)/2))
    local output=screen.console.machine.ppu.pixelOutput
    for y=0,223,13 do for x=0,255,11 do
      local a,b,c=data:getPixel(r.x+x*r.scale,r.y+y*r.scale)
      local i=(y+1)*1536+x*6
      assert(math.abs(a-output[i]/255)<.005 and math.abs(b-output[i+1]/255)<.005 and math.abs(c-output[i+2]/255)<.005,'final pipeline recolored a cartridge pixel')
    end end
    local a,b,c=data:getPixel(5,5);assert(a==0 and b==0 and c==0,'HUD/controls painted over the clean letterbox')
    if size[1]==1570 then data:encode('png','integer-presentation.png') end
    data:release()
  end
  check(true,'final renderer preserves RGB and uses maximum centered integer scale at three window sizes')
  for _,mode in ipairs({'playing','paused','instructions','library'}) do
    screen.mode=mode
    local a=render('og',640,480);local b=render('redpp',640,480)
    assert(a:getString()==b:getString(),'Pokemon palette changed '..mode)
    a:release();b:release()
  end
  check(shaded==0,'gameplay and menus bypass Pokemon palette and final shader passes')
  local drawDirect=screen.drawDirect;local directCalls=0
  screen.drawDirect=function() directCalls=directCalls+1;return true end
  screen.mode='playing';screen.game:draw()
  assert(directCalls==1,'cartridge did not bypass the host draw pipeline')
  screen.mode='paused';screen.game:draw();assert(directCalls==2,'pause did not use direct presentation')
  screen.drawDirect=drawDirect
  check(true,'playing and pause bypass the unused host draw pipeline')
  local r=screen:layout({ww=800,wh=600,pw=1200,ph=900,dpiX=1.5,dpiY=1.5,viewX=0,viewY=0},256,224)
  assert(r.scale==4 and r.sx*1.5==4 and r.sy*1.5==4 and r.x*1.5==88 and r.y*1.5==2,'DPI scaling lost whole physical pixels')
  screen.mode='paused'
  screen.presentation={x=100,y=50,sx=2,sy=2}
  screen:pointer({phase='pressed',gameX=100+100*2,gameY=50+155*2,id='mapped'})
  assert(screen.mode=='playing','resized pointer missed the resume menu')
  local mode,height=screen.console.machine.ppu.mode,screen.videoHeight
  screen.console.machine.ppu.mode=5;screen.videoHeight=239;screen.quad:setViewport(0,0,512,239)
  local data=render('redpp',1137,779)
  assert(screen.cartridgePresentation.w==512 and screen.cartridgePresentation.h==239 and screen.cartridgePresentation.scale==2,'hires/overscan fit lost native dimensions')
  data:release();screen.console.machine.ppu.mode=mode;screen.videoHeight=height;screen.quad:setViewport(0,0,512,height)
  check(true,'DPI integer layout and resized pause-menu pointer mapping remain correct')
  screen.presentation=nil
  screen.mode='playing'
  screen.game.renderer=oldRenderer
  View.dimensions,View.pixelDimensions,View.setTarget=oldDimensions,oldPixels,oldTarget
  Palette.setMode(oldMode);FX.active,FX.render=oldActive,oldRender
end
