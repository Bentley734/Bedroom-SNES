-- Common SPC700 addressing paths; uncommon indirect modes use the reference.
return function(spc)
  local original=spc.getAdr
  local function readPC(c)
    local pc=c.br[0];c.br[0]=(pc+1)%65536;return c.mem:read(pc)
  end
  spc.getAdr=function(c,mode)
    local page=c.p and 256 or 0
    if mode==0 then return 0,0 end
    if mode==1 then local n=readPC(c);return n>=128 and n-256 or n,0 end
    if mode==2 then local adr=readPC(c);return page+adr,page+(adr+1)%256 end
    if mode==3 or mode==17 then
      local adr=readPC(c);local rel=readPC(c)
      if mode==17 then adr=(adr+c.r[1])%256 end
      return page+adr,rel>=128 and rel-256 or rel
    end
    if mode==4 or mode==9 or mode==10 or mode==16 then
      local low=readPC(c);local high=readPC(c);local adr=low+high*256
      if mode==16 then return adr%8192,math.floor(adr/8192) end
      if mode==9 then adr=(adr+c.r[1])%65536 elseif mode==10 then adr=(adr+c.r[2])%65536 end
      return adr,0
    end
    if mode==5 then return page+c.r[1],0 end
    if mode==7 then local pc=c.br[0];c.br[0]=(pc+1)%65536;return pc,0 end
    if mode==8 or mode==15 then local adr=readPC(c);return page+(adr+c.r[mode==8 and 1 or 2])%256,0 end
    if mode==12 then local a=readPC(c);local b=readPC(c);return page+a,page+b end
    if mode==13 then return page+c.r[2],page+c.r[1] end
    if mode==14 then local pc=c.br[0];c.br[0]=(pc+1)%65536;local adr=readPC(c);return pc,page+adr end
    if mode==19 then local x=c.r[1];c.r[1]=(x+1)%256;return page+x,0 end
    return original(c,mode)
  end
end
