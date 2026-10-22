-- Native Lua renderer for all eight background modes. Modes 0/1/3 use batched
-- composition; scrolling modes preserve the reference's main/sub fetch order.
return function(ppu,R)
  local original=ppu.renderLine
  local band,rshift,arshift,bor,bnot,lshift=R.band,R.rshift,R.arshift,R.bor,R.bnot,R.lshift
  if R.nativeBit then
    band,rshift,arshift,bor,bnot,lshift=R.nativeBit.band,R.nativeBit.rshift,R.nativeBit.arshift,R.nativeBit.bor,R.nativeBit.bnot,R.nativeBit.lshift
  end
  local floor,min,max=math.floor,math.min,math.max
  local pixels,ranks,layers={},{},{}
  local subPixels,subRanks,subLayers={},{},{}
  local rankFor,red,green,blue={},{},{},{}
  local rawRed,rawGreen,rawBlue={},{},{}
  -- Cache the 5-bit channel operation, including brightness, rather than doing
  -- three clamps, divisions and brightness conversions for every blended pixel.
  -- Tables are bounded by the sixteen brightness values and four operations.
  local blends={}
  local function blendTable(brightness,mult,subtract,half)
    local key=brightness*4+(subtract and 2 or 0)+(half and 1 or 0)
    local result=blends[key]
    if not result then
      result={}
      for a=0,31 do for b=0,31 do
        local value=a+(subtract and -b or b)
        if half then value=floor(value/2) end
        result[a*32+b]=floor(max(0,min(31,value))*mult)%256
      end end
      blends[key]=result
    end
    return result
  end
  local previousColors,previousBrightness={},nil
  local windowStates,windowCache={},{}
  local windowGeneration=0
  local previousLeft1,previousRight1,previousLeft2,previousRight2
  local spread={}
  for byte=0,255 do
    local value,weight,n=0,1,byte
    for bit=0,7 do value=value+(n%2)*weight;n=floor(n/2);weight=weight*16 end
    spread[byte]=value
  end
  local function window(p,x,l)
    local a=p.window1Enabled[l]
    local b=p.window2Enabled[l]
    if not a and not b then return false end
    local w1=x>=p.window1Left and x<=p.window1Right
    local w2=x>=p.window2Left and x<=p.window2Right
    if p.window1Inversed[l] then w1=not w1 end
    if p.window2Inversed[l] then w2=not w2 end
    if not b then return w1 elseif not a then return w2 end
    local logic=p.windowMaskLogic[l]
    if logic==0 then return w1 or w2 elseif logic==1 then return w1 and w2
    elseif logic==2 then return w1~=w2 else return w1==w2 end
  end
  local function prepareWindows(p)
    local changed=previousLeft1~=p.window1Left or previousRight1~=p.window1Right
      or previousLeft2~=p.window2Left or previousRight2~=p.window2Right
    if changed then windowGeneration=windowGeneration+1 end
    for l=0,5 do
      local key=(p.window1Enabled[l] and 1 or 0)+(p.window2Enabled[l] and 2 or 0)
        +(p.window1Inversed[l] and 4 or 0)+(p.window2Inversed[l] and 8 or 0)+p.windowMaskLogic[l]*16
      if not p.window1Enabled[l] and not p.window2Enabled[l] then key=0 end
      local entry=windowCache[key]
      if not entry then entry={states={}};windowCache[key]=entry end
      if entry.generation~=windowGeneration and (key~=0 or not entry.generation) then
        for x=0,255 do entry.states[x]=window(p,x,l) end
        entry.generation=windowGeneration
      end
      windowStates[l]=entry.states
    end
    previousLeft1=p.window1Left;previousRight1=p.window1Right
    previousLeft2=p.window2Left;previousRight2=p.window2Right
  end
  local function fetch(p,sx,sy,l,bits)
    local x,y=sx,sy
    local big=p.bigTiles[l]
    if big then x=floor(x/2);y=floor(y/2) end
    local address=p.tilemapAdr[l]+floor(band(y,255)/8)*32+floor(band(x,255)/8)
    if band(x,256)~=0 and p.tilemapWider[l] then address=address+1024 end
    if band(y,256)~=0 and p.tilemapHigher[l] then address=address+(p.tilemapWider[l] and 2048 or 1024) end
    local vram=p.vram
    local word=vram[band(address,32767)]
    local flip=band(word,16384)~=0
    local vertical=band(word,32768)~=0
    local row=sy%8;if vertical then row=7-row end
    local number=band(word,1023)
    if big then
      if band(sx,8)==(flip and 0 or 8) then number=number+1 end
      if band(sy,8)==(vertical and 0 or 8) then number=number+16 end
    end
    local base=p.tileAdr[l]+number*bits*4+row
    local a=vram[band(base,32767)]
    local b=bits>2 and vram[band(base+8,32767)] or 0
    local c,d=0,0
    p.tilemapBuffer[l]=word;p.tileBufferP1[l]=a
    if bits>2 then p.tileBufferP2[l]=b end
    if bits>4 then
      c=vram[band(base+16,32767)];d=vram[band(base+24,32767)]
      p.tileBufferP3[l]=c;p.tileBufferP4[l]=d
    end
    return word,a,b,flip,c,d
  end
  local function composeTiles(p,line,enabled,windows,out,depth,layerOut)
    for x=0,255 do out[x]=0;depth[x]=100;layerOut[x]=5 end
    if enabled[4] then
      local mask=windows[4] and (p.window1Enabled[4] or p.window2Enabled[4])
      local size=p.mosaicEnabled[4] and p.mosaicSize or 1
      for x=0,255 do
        local sx=x
        if size>1 then sx=x-x%size end
        local pixel=p.spriteLineBuffer[sx]
        if pixel~=0 and not (mask and windowStates[4][x]) then
          out[x]=pixel;depth[x]=rankFor[16+p.spritePrioBuffer[sx]];layerOut[x]=4
        end
      end
    end
    local lastLayer=p.mode==0 and 3 or p.mode==1 and 2 or 1
    for layer=0,lastLayer do
      if enabled[layer] then
        local sy=line+p.bgVoff[layer]
        local size=p.mosaicEnabled[layer] and p.mosaicSize or 1
        if size>1 then sy=line-R.rem(line-p.mosaicStartLine,size)+p.bgVoff[layer] end
        local sxStart=p.bgHoff[layer]
        local mask=windows[layer] and (p.window1Enabled[layer] or p.window2Enabled[layer])
        local palette,flip,rank,packed,high,lastTile
        local bits=p.bitPerMode[p.mode*4+layer]
        for x=0,255 do
          local sx=x+sxStart
          if size>1 then sx=x-x%size+sxStart end
          local tx=floor(sx/8)
          if tx~=lastTile then
            local word,a,b,c,d
            word,a,b,flip,c,d=fetch(p,sx,sy,layer,bits)
            lastTile=tx;p.lastTileFetchedX[layer]=tx;p.lastTileFetchedY[layer]=sy
            packed=spread[band(a,255)]+2*spread[rshift(a,8)]
            if bits>2 then packed=packed+4*spread[band(b,255)]+8*spread[rshift(b,8)] end
            if bits>4 then high=spread[band(c,255)]+2*spread[rshift(c,8)]+4*spread[band(d,255)]+8*spread[rshift(d,8)] end
            palette=band(rshift(word,10),7)*(bits==2 and 4 or bits==4 and 16 or 256)+(p.mode==0 and layer*32 or 0)
            rank=rankFor[layer*4+band(rshift(word,13),1)]
          end
          if rank<depth[x] and not (mask and windowStates[layer][x]) then
            local shift=flip and sx%8 or 7-sx%8
            local pixel=band(rshift(packed,shift*4),15)
            if bits>4 then pixel=pixel+16*band(rshift(high,shift*4),15) end
            if pixel~=0 then
              out[x]=(bits==8 and p.directColor) and 256+palette+pixel or band(palette+pixel,255)
              depth[x]=rank;layerOut[x]=layer
            end
          end
        end
      end
    end
  end
  -- Keep the narrower 2/4bpp loop for Mode 1: general 8bpp decoding adds
  -- branches to the most common cartridge mode.
  local function fetchMode1(p,sx,sy,l,four)
    local x,y=sx,sy
    local big=p.bigTiles[l]
    if big then x=floor(x/2);y=floor(y/2) end
    local address=p.tilemapAdr[l]+floor(band(y,255)/8)*32+floor(band(x,255)/8)
    if band(x,256)~=0 and p.tilemapWider[l] then address=address+1024 end
    if band(y,256)~=0 and p.tilemapHigher[l] then address=address+(p.tilemapWider[l] and 2048 or 1024) end
    local vram=p.vram
    local word=vram[band(address,32767)]
    local flip=band(word,16384)~=0
    local vertical=band(word,32768)~=0
    local row=sy%8;if vertical then row=7-row end
    local number=band(word,1023)
    if big then
      if band(sx,8)==(flip and 0 or 8) then number=number+1 end
      if band(sy,8)==(vertical and 0 or 8) then number=number+16 end
    end
    local base=p.tileAdr[l]+number*(four and 16 or 8)+row
    local a=vram[band(base,32767)]
    local b=four and vram[band(base+8,32767)] or 0
    p.tilemapBuffer[l]=word;p.tileBufferP1[l]=a
    if four then p.tileBufferP2[l]=b end
    return word,a,b,flip
  end
  local function composeMode1(p,line,enabled,windows,out,depth,layerOut)
    for x=0,255 do out[x]=0;depth[x]=100;layerOut[x]=5 end
    if enabled[4] then
      local mask=windows[4] and (p.window1Enabled[4] or p.window2Enabled[4])
      local size=p.mosaicEnabled[4] and p.mosaicSize or 1
      for x=0,255 do
        local sx=x
        if size>1 then sx=x-x%size end
        local pixel=p.spriteLineBuffer[sx]
        if pixel~=0 and not (mask and windowStates[4][x]) then
          out[x]=pixel;depth[x]=rankFor[16+p.spritePrioBuffer[sx]];layerOut[x]=4
        end
      end
    end
    for layer=0,2 do
      if enabled[layer] then
        local sy=line+p.bgVoff[layer]
        local size=p.mosaicEnabled[layer] and p.mosaicSize or 1
        if size>1 then sy=line-R.rem(line-p.mosaicStartLine,size)+p.bgVoff[layer] end
        local sxStart=p.bgHoff[layer]
        local mask=windows[layer] and (p.window1Enabled[layer] or p.window2Enabled[layer])
        local palette,flip,rank,packed,lastTile
        local four=layer<2
        for x=0,255 do
          local sx=x+sxStart
          if size>1 then sx=x-x%size+sxStart end
          local tx=floor(sx/8)
          if tx~=lastTile then
            local word,a,b
            word,a,b,flip=fetchMode1(p,sx,sy,layer,four)
            lastTile=tx;p.lastTileFetchedX[layer]=tx;p.lastTileFetchedY[layer]=sy
            packed=spread[band(a,255)]+2*spread[rshift(a,8)]
            if four then packed=packed+4*spread[band(b,255)]+8*spread[rshift(b,8)] end
            palette=band(rshift(word,10),7)*(four and 16 or 4)
            rank=rankFor[layer*4+band(rshift(word,13),1)]
          end
          if rank<depth[x] and not (mask and windowStates[layer][x]) then
            local shift=flip and sx%8 or 7-sx%8
            local pixel=band(rshift(packed,shift*4),15)
            if pixel~=0 then out[x]=palette+pixel;depth[x]=rank;layerOut[x]=layer end
          end
        end
      end
    end
  end
  local packedLow,packedHigh={},{}
  local directBrightness
  -- Keys above CGRAM identify direct-color pixels, including the tile's three
  -- palette bits. Channel values are fixed; brightness is applied separately.
  for pixel=0,2047 do
    local key=256+pixel
    rawRed[key]=bor(lshift(band(pixel,7),2),rshift(band(pixel,256),7))
    rawGreen[key]=bor(rshift(band(pixel,56),1),rshift(band(pixel,512),8))
    rawBlue[key]=bor(rshift(band(pixel,192),3),rshift(band(pixel,1024),8))
  end
  local function mapAddress(p,x,y,l)
    if p.bigTiles[l] or p.mode==5 or p.mode==6 then x=floor(x/2) end
    if p.bigTiles[l] then y=floor(y/2) end
    local address=p.tilemapAdr[l]+floor(band(y,255)/8)*32+floor(band(x,255)/8)
    if band(x,256)~=0 and p.tilemapWider[l] then address=address+1024 end
    if band(y,256)~=0 and p.tilemapHigher[l] then address=address+(p.tilemapWider[l] and 2048 or 1024) end
    return band(address,32767)
  end
  local function fetchPacked(p,x,y,l,bits)
    local word=p.vram[mapAddress(p,x,y,l)]
    local flip=band(word,16384)~=0
    local vertical=band(word,32768)~=0
    local row=band(y,7);if vertical then row=7-row end
    local number=band(word,1023)
    if (p.bigTiles[l] or p.mode==5 or p.mode==6) and band(x,8)==(flip and 0 or 8) then number=number+1 end
    if p.bigTiles[l] and band(y,8)==(vertical and 0 or 8) then number=number+16 end
    local base=p.tileAdr[l]+number*4*bits+row
    local a=p.vram[band(base,32767)]
    p.tilemapBuffer[l]=word;p.tileBufferP1[l]=a
    local low=spread[band(a,255)]+2*spread[rshift(a,8)]
    if bits>2 then
      local b=p.vram[band(base+8,32767)];p.tileBufferP2[l]=b
      low=low+4*spread[band(b,255)]+8*spread[rshift(b,8)]
    end
    packedLow[l]=low
    if bits>4 then
      local c=p.vram[band(base+16,32767)];local d=p.vram[band(base+24,32767)]
      p.tileBufferP3[l]=c;p.tileBufferP4[l]=d
      packedHigh[l]=spread[band(c,255)]+2*spread[rshift(c,8)]+4*spread[band(d,255)]+8*spread[rshift(d,8)]
    end
  end
  local function mode7Coords(p,y)
    local ry=p.mode7FlipY and 255-y or y
    local h=p.mode7Hoff-p.mode7X;local v=p.mode7Voff-p.mode7Y
    h=band(h,8192)~=0 and bor(h,bnot(1023)) or band(h,1023)
    v=band(v,8192)~=0 and bor(v,bnot(1023)) or band(v,1023)
    local x=band(p.mode7A*h,bnot(63))+band(p.mode7B*ry,bnot(63))+band(p.mode7B*v,bnot(63))+lshift(p.mode7X,8)
    local z=band(p.mode7C*h,bnot(63))+band(p.mode7D*ry,bnot(63))+band(p.mode7D*v,bnot(63))+lshift(p.mode7Y,8)
    for i=0,255 do
      -- Int32Array wrapping is observable for extreme affine matrices.
      p.mode7Xcoords[i]=R.i32(x);p.mode7Ycoords[i]=R.i32(z)
      x=p.mode7Xcoords[i]+p.mode7A;z=p.mode7Ycoords[i]+p.mode7C
    end
  end
  local function sample(p,sub,x,y,modeIndex)
    local mode=p.mode
    local enabled=sub and p.subScreenEnabled or p.mainScreenEnabled
    local masks=sub and p.subScreenWindow or p.mainScreenWindow
    if p.interlace and (mode==5 or mode==6) then y=y*2+(p.evenFrame and 1 or 0) end
    for j=0,p.layercountPerMode[mode]-1 do
      local l=p.layersPerMode[modeIndex+j]
      local priority=p.prioPerMode[modeIndex+j]
      if enabled[l] and not (masks[l] and windowStates[l][x]) then
        local lx,ly=x,y
        if p.mosaicEnabled[l] then
          lx=lx-lx%p.mosaicSize;ly=ly-R.rem(ly-p.mosaicStartLine,p.mosaicSize)
        end
        if mode~=7 then lx=lx+p.bgHoff[l];ly=ly+p.bgVoff[l] end
        local pixel=0
        if l==4 then
          if p.spritePrioBuffer[lx]==priority then pixel=p.spriteLineBuffer[lx] end
        elseif mode==7 then
          local data=p.tilemapBuffer[0]
          if lx~=p.lastTileFetchedX[0] or ly~=p.lastTileFetchedY[0] then
            local rx=p.mode7FlipX and 255-lx or lx
            local px,py=arshift(p.mode7Xcoords[rx],8),arshift(p.mode7Ycoords[rx],8)
            local transparent=false
            if p.mode7LargeField and (px<0 or px>=1024 or py<0 or py>=1024) then
              if p.mode7Char0fill then px=band(px,7);py=band(py,7) else transparent=true end
            end
            local tile=band(p.vram[floor(band(py,1016)/8)*128+floor(band(px,1016)/8)],255)
            data=transparent and 0 or rshift(p.vram[tile*64+band(py,7)*8+band(px,7)],8)
            p.tilemapBuffer[0]=data;p.lastTileFetchedX[0]=lx;p.lastTileFetchedY[0]=ly
          end
          if l==0 then pixel=data elseif rshift(data,7)==priority then pixel=band(data,127) end
        else
          local optX=lx-p.bgHoff[l]
          if mode==5 or mode==6 then lx=lx*2+(sub and 0 or 1);optX=optX*2+(sub and 0 or 1) end
          if (mode==2 or mode==4 or mode==6) and l<2 then
            if x==0 then p.lastOrigTileX[l]=floor(lx/8) end
            local start=optX-(lx-band(lx,65528))
            local tileX=floor(lx/8)
            if tileX~=p.lastOrigTileX[l] and x>0 then
              local ox=p.bgHoff[2]+band(start-1,504)
              local hor=p.vram[mapAddress(p,ox,p.bgVoff[2],2)]
              p.tilemapBuffer[2]=hor;p.optHorBuffer[l]=hor
              if mode==4 then
                p.optVerBuffer[l]=band(hor,32768)~=0 and hor or 0
                if band(hor,32768)~=0 then p.optHorBuffer[l]=0 end
              else
                local ver=p.vram[mapAddress(p,ox,p.bgVoff[2]+8,2)]
                p.tilemapBuffer[2]=ver;p.optVerBuffer[l]=ver
              end
              p.lastOrigTileX[l]=tileX
            end
            local flag=l==0 and 8192 or 16384
            if band(p.optHorBuffer[l],flag)~=0 then lx=band(lx,7)+band(p.optHorBuffer[l]+band(start+7,504),8184) end
            if band(p.optVerBuffer[l],flag)~=0 then ly=band(p.optVerBuffer[l],8191)+ly-p.bgVoff[l] end
          end
          local bits=p.bitPerMode[mode*4+l]
          local tx=floor(lx/8)
          if tx~=p.lastTileFetchedX[l] or ly~=p.lastTileFetchedY[l] then
            fetchPacked(p,lx,ly,l,bits);p.lastTileFetchedX[l]=tx;p.lastTileFetchedY[l]=ly
          end
          local word=p.tilemapBuffer[l]
          if band(rshift(word,13),1)==priority then
            local shift=(band(word,16384)~=0 and band(lx,7) or 7-band(lx,7))*4
            pixel=band(rshift(packedLow[l],shift),15)
            if bits>4 then pixel=pixel+16*band(rshift(packedHigh[l],shift),15) end
            if pixel~=0 then
              local palette=band(rshift(word,10),7)+(mode==0 and l*8 or 0)
              pixel=pixel+palette*(bits==2 and 4 or bits==4 and 16 or 256)
            end
          end
        end
        if band(pixel,255)~=0 then
          if p.directColor and l<4 and p.bitPerMode[mode*4+l]==8 then return 256+pixel,l end
          return band(pixel,255),l
        end
      end
    end
    return 0,5
  end
  ppu.renderLine=function(p,line)
    if line<1 or line>=(p.frameOverscan and 240 or 225) then return original(p,line) end
    if line==1 then p.mosaicStartLine=1 end
    if p.mode==7 then mode7Coords(p,line) end
    for i=0,3 do p.lastTileFetchedX[i]=-1;p.lastTileFetchedY[i]=-1 end
    p.optHorBuffer[0]=0;p.optHorBuffer[1]=0;p.optVerBuffer[0]=0;p.optVerBuffer[1]=0
    p.lastOrigTileX[0]=-1;p.lastOrigTileX[1]=-1
    if p.forcedBlank then
      local out=p.pixelOutput
      for i=line*1536,line*1536+1535 do out[i]=0 end
      R.clearArray(p.spriteLineBuffer)
      return
    end
    local batched=p.mode==0 or p.mode==1 or p.mode==3
    local hires=p.mode==5 or p.mode==6 or p.pseudoHires
    local modeIndex=(p.mode==1 and p.layer3Prio) and 96 or p.mode*12
    if p.mode==7 and p.mode7ExBg then modeIndex=108 end
    for j=0,p.layercountPerMode[p.mode]-1 do rankFor[p.layersPerMode[modeIndex+j]*4+p.prioPerMode[modeIndex+j]]=j end
    prepareWindows(p)
    local compose=p.mode==1 and composeMode1 or composeTiles
    if batched then compose(p,line,p.mainScreenEnabled,p.mainScreenWindow,pixels,ranks,layers) end
    local anyMath=false
    for i=0,5 do if p.mathEnabled[i] then anyMath=true end end
    if p.preventMath==3 or (p.preventMath==1 and not p.window1Enabled[5] and not p.window2Enabled[5]) then anyMath=false end
    local secondPixels,secondLayers=subPixels,subLayers
    if batched and (hires or (anyMath and p.addSub)) then
      -- Some effects select the same layers on both screens. Their source
      -- composition is identical even though the final color math differs.
      local same=true
      for l=0,4 do
        if p.mainScreenEnabled[l]~=p.subScreenEnabled[l] or
          (p.mainScreenEnabled[l] and p.mainScreenWindow[l]~=p.subScreenWindow[l]
            and (p.window1Enabled[l] or p.window2Enabled[l])) then same=false;break end
      end
      if same then secondPixels=pixels;secondLayers=layers
      else compose(p,line,p.subScreenEnabled,p.subScreenWindow,subPixels,subRanks,subLayers) end
    end
    local mult=p.brightnessMults[p.brightness]
    local brightnessChanged=mult~=previousBrightness
    for i=0,255 do
      local color=p.cgram[i]
      if brightnessChanged or previousColors[i]~=color then
        rawRed[i]=band(color,31);rawGreen[i]=band(rshift(color,5),31);rawBlue[i]=band(rshift(color,10),31)
        red[i]=floor(rawRed[i]*mult)%256
        green[i]=floor(rawGreen[i]*mult)%256
        blue[i]=floor(rawBlue[i]*mult)%256
        previousColors[i]=color
      end
    end
    previousBrightness=mult
    if p.directColor and directBrightness~=mult then
      for i=256,2303 do red[i]=floor(rawRed[i]*mult)%256;green[i]=floor(rawGreen[i]*mult)%256;blue[i]=floor(rawBlue[i]*mult)%256 end
      directBrightness=mult
    end
    local fullBlend,halfBlend
    if anyMath then
      fullBlend=blendTable(p.brightness,mult,p.subtractColors,false)
      halfBlend=p.halfColors and blendTable(p.brightness,mult,p.subtractColors,true) or fullBlend
    end
    local out,row=p.pixelOutput,line*1536
    for x=0,255 do
      local color=pixels[x];local layer=layers[x]
      if not batched then color,layer=sample(p,false,x,line,modeIndex) end
      local r,g,b=red[color],green[color],blue[color]
      local inWindow=false
      if p.colorClip==1 or p.colorClip==2 or (anyMath and (p.preventMath==1 or p.preventMath==2)) then inWindow=windowStates[5][x] end
      local clip=p.colorClip==3 or (p.colorClip==2 and inWindow) or (p.colorClip==1 and not inWindow)
      local mathOn=anyMath and p.mathEnabled[layer] and (layer~=4 or color>=192)
        and not (p.preventMath==2 and inWindow) and not (p.preventMath==1 and not inWindow)
      local second,secondLayer
      if not batched and (hires or (mathOn and p.addSub)) then second,secondLayer=sample(p,true,x,line,modeIndex)
      elseif batched then second=secondPixels[x];secondLayer=secondLayers[x] end
      if mathOn then
        r=clip and 0 or rawRed[color];g=clip and 0 or rawGreen[color];b=clip and 0 or rawBlue[color]
        local useSub=p.addSub and secondLayer<5
        local r1,g1,b1=p.fixedColorR,p.fixedColorG,p.fixedColorB
        if useSub then r1=rawRed[second];g1=rawGreen[second];b1=rawBlue[second] end
        local blend=(useSub or not p.addSub) and halfBlend or fullBlend
        r=blend[r*32+r1];g=blend[g*32+g1];b=blend[b*32+b1]
      elseif clip then r=0;g=0;b=0 end
      local i=row+x*6
      if hires then
        out[i]=red[second];out[i+1]=green[second];out[i+2]=blue[second]
      else out[i]=r;out[i+1]=g;out[i+2]=b end
      out[i+3]=r;out[i+4]=g;out[i+5]=b
    end
    R.clearArray(p.spriteLineBuffer)
    p:evaluateSprites(line)
  end
end
