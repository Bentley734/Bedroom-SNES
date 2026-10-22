-- Common 65816 address modes in direct Lua. The reference decoder remains
-- the fallback for indirect and interrupt modes. Bus-read ordering is retained.
return function(cpu)
  local original=cpu.getAdr
  local floor=math.floor
  local function readPC(c)
    local pc=c.br[4];c.br[4]=(pc+1)%65536
    return c.mem:read(c.r[1]*65536+pc)
  end
  cpu.getAdr=function(c,opcode,mode)
    if mode==0 then return 0,0 end
    if mode>=1 and mode<=4 then
      local pc=c.br[4];local bank=c.r[1]*65536
      c.br[4]=(pc+1)%65536
      if mode==1 or (mode==2 and c.m) or (mode==3 and c.x) then return bank+pc,0 end
      local second=c.br[4];c.br[4]=(second+1)%65536
      return bank+pc,bank+second
    end
    if mode>=5 and mode<=7 then
      local adr=readPC(c)
      if c.br[5]%256~=0 then c.cyclesLeft=c.cyclesLeft+1 end
      local index=mode==6 and c.br[1] or mode==7 and c.br[2] or 0
      local address=(c.br[5]+adr+index)%65536
      return address,(address+1)%65536
    end
    if mode>=16 and mode<=22 then
      local low=readPC(c);local high=readPC(c)
      local adr=low+high*256
      if mode>=21 then
        local bank=readPC(c);adr=adr+bank*65536
        if mode==22 then adr=adr+c.br[1] end
      else
        local index=(mode==17 or mode==18) and c.br[1] or (mode==19 or mode==20) and c.br[2] or 0
        if (mode==18 or mode==20) and (not c.x or floor(adr/256)~=floor((adr+index)/256)) then c.cyclesLeft=c.cyclesLeft+1 end
        adr=c.r[0]*65536+adr+index
      end
      return adr,adr+1
    end
    if mode==26 then local value=readPC(c);return value>=128 and value-256 or value,0 end
    if mode==27 then
      local low=readPC(c);local high=readPC(c);local value=low+high*256
      return value>=32768 and value-65536 or value,0
    end
    if mode==28 then local dest=readPC(c);local source=readPC(c);return dest,source end
    if mode==14 then local offset=readPC(c);local adr=(c.br[3]+offset)%65536;return adr,(adr+1)%65536 end
    return original(c,opcode,mode)
  end
end
