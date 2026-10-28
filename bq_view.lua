-- bq_view.lua : desenha o jogo via interface gfx:
--   gfx.clear gfx.fill gfx.box gfx.text  +  gfx.clip(x,y,w,h) / gfx.noclip()
-- Tela 480x270: duas telas divididas de 238x206 (tile = 16 px) + painel de status.
local Core = require("bq_core")
local View = {}
View.W, View.H = 480, 270
View.CHAR_W = 8
View.lite = false                                   -- modo leve (console): menos chamadas de desenho
View.back_hint = "BACKSPACE: VOLTAR AO MENU"        -- dica do criativo

local T = 16
local VW, VH, VY = 238, 206, 2   -- VW muda para 478 no modo solo
local VX1, VX2 = { 1 }, { 1, 241 }
local VX = VX2

local C = {
  black = 0x000000, ink = 0x222034, white = 0xffffff, dim = 0x9badb7,
  gold = 0xfbf236, good = 0x6abe30, bad = 0xac3232, line = 0x595652,
  cave = 0x1b1a2b, skin = 0xeec39a, p1 = 0x3b5dc9, p2 = 0xd95763,
  orange = 0xdf7126, red = 0xd95763,
}
local PCOL = { C.p1, C.p2 }
local PTXT = { 0x639bff, C.p2 }
local SKY = { 0x9bd4f0, 0xdf9a60, 0x524070, 0x1b1a2b }
local SHADE = { 1, 0.82, 0.62, 0.45 }
local SWORDC = { [1] = 0x8f563b, [2] = 0x9badb7, [3] = 0xcbdbfc, [4] = 0x5fcde4 }
local TIERC = { 0x8f563b, 0x9badb7, 0xcbdbfc, 0x5fcde4 }   -- madeira pedra ferro diamante
local HAIR = { 0x663931, 0x222034 }
local SLOTBG = 0x323c39

local cache = {}
local function sh(c, lvl)
  if lvl <= 0 then return c end
  local t = cache[lvl]
  if not t then t = {}; cache[lvl] = t end
  local v = t[c]
  if v then return v end
  local f = SHADE[lvl + 1]
  local r = math.floor(math.floor(c / 65536) * f)
  local g = math.floor((math.floor(c / 256) % 256) * f)
  local b = math.floor((c % 256) * f)
  v = r * 65536 + g * 256 + b
  t[c] = v
  return v
end

local function center(gfx, s, y, c)
  gfx.text(s, math.floor((View.W - #s * View.CHAR_W) / 2), y, c)
end

local function bar(gfx, x, y, w, h, v, max, c)
  gfx.fill(x, y, w, h, C.black)
  local f = 0
  if max > 0 and v > 0 then f = math.max(1, math.floor(w * v / max)) end
  if f > 0 then gfx.fill(x, y, f, h, c) end
  gfx.box(x - 1, y - 1, w + 2, h + 2, C.line)
end

local BC = { [1] = 0x663931, [2] = 0x663931, [3] = 0x696a6a, [4] = 0x8f563b,
             [5] = 0x37946e, [6] = 0x696a6a, [7] = 0x696a6a, [8] = 0x696a6a }

local function block(gfx, id, x, y, L)
  gfx.fill(x, y, T, T, sh(BC[id], L))
  if id == 1 then gfx.fill(x, y, T, 4, sh(0x6abe30, L))
  elseif id == 2 then
    gfx.fill(x + 3, y + 5, 2, 2, sh(0x8a6f30, L)); gfx.fill(x + 10, y + 10, 2, 2, sh(0x8a6f30, L))
  elseif id == 3 then
    gfx.fill(x + 4, y + 4, 3, 2, sh(0x595652, L)); gfx.fill(x + 9, y + 10, 4, 2, sh(0x595652, L))
  elseif id == 4 then
    gfx.fill(x + 4, y, 2, T, sh(0x663931, L)); gfx.fill(x + 11, y, 2, T, sh(0x663931, L))
  elseif id == 5 then
    gfx.fill(x + 2, y + 3, 4, 3, sh(0x6abe30, L)); gfx.fill(x + 9, y + 9, 4, 3, sh(0x6abe30, L))
  elseif id == 6 then
    gfx.fill(x + 3, y + 3, 3, 3, C.ink); gfx.fill(x + 9, y + 7, 3, 3, C.ink); gfx.fill(x + 5, y + 10, 3, 3, C.ink)
  elseif id == 7 then
    gfx.fill(x + 3, y + 3, 3, 3, 0x5fcde4); gfx.fill(x + 9, y + 7, 3, 3, 0x5fcde4)
    gfx.fill(x + 5, y + 10, 3, 3, 0xffffff)
  elseif id == 8 then
    gfx.fill(x + 3, y + 3, 3, 3, 0xd9a066); gfx.fill(x + 9, y + 7, 3, 3, 0xd9a066); gfx.fill(x + 5, y + 10, 3, 3, 0xd9a066)
  end
end

local function cam(p)
  local cx = math.max(0, math.min(Core.W - VW / T, p.x - VW / T / 2))
  local cy = math.max(0, math.min(Core.H - VH / T, p.y + p.h / 2 - VH / T / 2))
  return cx, cy
end

local function draw_mob(gfx, e, vx, vy, cx, cy)
  local w, h = math.floor(e.w * T), math.floor(e.h * T)
  local sx = vx + math.floor((e.x - e.w / 2 - cx) * T)
  local sy = vy + math.floor((e.y - cy) * T)
  if sx > vx + VW or sx + w < vx or sy > vy + VH or sy + h < vy then return end
  local k = e.kind
  if k == "Z" then
    gfx.fill(sx, sy + 10, w, h - 10, 0x306082)
    gfx.fill(sx, sy, w, 10, 0x6abe30)
    gfx.fill(sx + (e.face > 0 and w - 4 or 2), sy + 4, 2, 2, C.ink)
    gfx.fill(sx + (e.face > 0 and w or -3), sy + 12, 3, 3, 0x6abe30)
  elseif k == "S" then
    gfx.fill(sx, sy, w, h, 0x6abe30)
    gfx.fill(sx + 3, sy + 3, 2, 2, C.ink); gfx.fill(sx + w - 5, sy + 3, 2, 2, C.ink)
  elseif k == "K" then
    gfx.fill(sx, sy + 10, w, h - 10, 0xcbdbfc)
    gfx.fill(sx, sy, w, 10, 0x9badb7)
    gfx.fill(sx + (e.face > 0 and w - 4 or 2), sy + 4, 2, 2, C.ink)
    gfx.fill(sx + (e.face > 0 and w or -3), sy + 8, 3, 12, 0x8f563b)
  else
    gfx.fill(sx, sy + 14, w, h - 14, C.bad)
    gfx.fill(sx + 2, sy, w - 4, 14, 0x76428a)
    gfx.fill(sx + 6, sy + 5, 4, 3, C.gold); gfx.fill(sx + w - 10, sy + 5, 4, 3, C.gold)
    gfx.box(sx, sy + 14, w, h - 14, C.ink)
  end
  if e.hp < e.max then bar(gfx, sx, sy - 5, w, 2, e.hp, e.max, C.red) end
end

-- boneco: cabelo, olhos, boca, bracos, pernas que andam, braco que bate, armadura
local function draw_player(gfx, q, k, sx, sy, frame)
  local f = q.face
  local col = PCOL[k]
  local walk = q.ground and math.abs(q.vx) > 0.01
  local ph = math.floor(frame / 6) % 2
  local acol = nil
  if q.armor >= 4 then acol = 0x5fcde4 elseif q.armor >= 2 then acol = 0xcbdbfc end
  -- pernas (alternam ao andar)
  local l1, l2 = 8, 8
  if walk then
    if ph == 0 then l2 = 6 else l1 = 6 end
  end
  gfx.fill(sx + 1, sy + 20, 4, l1, 0x45283c)
  gfx.fill(sx + 5, sy + 20, 4, l2, 0x45283c)
  gfx.fill(sx + 1, sy + 18 + l1, 4, 2, acol or C.ink)
  gfx.fill(sx + 5, sy + 18 + l2, 4, 2, acol or C.ink)
  -- braco de tras
  gfx.fill(sx + ((f > 0) and 0 or 7), sy + 11, 3, 9, sh(col, 1))
  gfx.fill(sx + ((f > 0) and 0 or 7), sy + 17, 3, 3, sh(C.skin, 1))
  -- tronco
  gfx.fill(sx + 1, sy + 10, 8, 10, col)
  gfx.fill(sx + 1, sy + 17, 8, 3, sh(col, 1))
  if acol then
    gfx.fill(sx + 2, sy + 11, 6, 6, acol)
    gfx.fill(sx + 3, sy + 12, 4, 4, sh(acol, 1))
  end
  -- braco da frente (bate ao minerar/atacar)
  if q.swing > 0 then
    local ay = (math.floor(frame / 4) % 2 == 0) and 10 or 13
    local hx = (f > 0) and 14 or -4        -- ponta da mao
    gfx.fill(sx + ((f > 0) and 7 or 0), sy + ay, 3, 3, col)
    gfx.fill(sx + ((f > 0) and 10 or -4), sy + ay, 4, 3, C.skin)
    if q.acd > 0 and q.sword > 0 then      -- espada
      gfx.fill(sx + ((f > 0) and 14 or -12), sy + ay + 1, 8, 2, SWORDC[q.sword])
      gfx.fill(sx + ((f > 0) and 14 or -5), sy + ay - 1, 2, 6, 0x8f563b)
    elseif q.tool > 0 then                 -- picareta
      gfx.fill(sx + ((f > 0) and 14 or -7), sy + ay + 1, 3, 1, 0x8f563b)
      gfx.fill(sx + ((f > 0) and 16 or -8), sy + ay - 2, 2, 7, TIERC[q.tool])
    end
  else
    local fx = (f > 0) and 7 or 0
    gfx.fill(sx + fx, sy + 11, 3, 6, col)
    gfx.fill(sx + fx, sy + 17, 3, 3, C.skin)
  end
  -- cabeca
  gfx.fill(sx, sy, 10, 10, C.skin)
  gfx.fill(sx, sy, 10, 3, acol or HAIR[k])
  gfx.fill(sx + ((f > 0) and 0 or 7), sy + 3, 3, 4, acol or HAIR[k])
  local ex = (f > 0) and 5 or 2
  gfx.fill(sx + ex, sy + 4, 3, 2, C.white)
  gfx.fill(sx + ((f > 0) and ex + 2 or ex), sy + 4, 1, 2, C.ink)
  gfx.fill(sx + ((f > 0) and 5 or 3), sy + 8, 2, 1, 0x8a4f3a)
  local lx = sx - 3
  if lx < 0 then lx = 0 elseif lx > 464 then lx = 464 end   -- rotulo sempre dentro da tela
  gfx.text("P" .. k, lx, sy - 10, PTXT[k])
end

-- ---------- menu de criar (tecla E): grade 3x3 ----------
local KL = { tool = "PICARETA", sword = "ESPADA", armor = "ARMADURA" }
local TIERN = { "MADEIRA", "PEDRA", "FERRO", "DIAMANTE" }
local INV = { { 2, "TER", 0x663931 }, { 3, "PED", 0x696a6a }, { 4, "MAD", 0x8f563b }, { 6, "CRV", 0x222034 },
              { 8, "FER", 0xd9a066 }, { 7, "DIA", 0x5fcde4 }, { 12, "CRN", 0xd95763 } }
local MENUHINT = { "F: CRIAR   E: FECHAR", ",: CRIAR  SHIFT: FECHAR" }
View.menu_hint = MENUHINT

local function tier_color(r)
  if r.k == "armor" then return (r.v >= 4) and 0x5fcde4 or 0xcbdbfc end
  return TIERC[r.v]
end

local function draw_icon(gfx, r, x, y, dim)
  local c, br = tier_color(r), 0x8f563b
  if dim then c, br = sh(c, 2), sh(br, 2) end
  local ix, iy = x + 4, y + 4
  if r.k == "tool" then
    gfx.fill(ix + 10, iy + 6, 3, 15, br)
    gfx.fill(ix + 2, iy + 3, 19, 3, c)
    gfx.fill(ix + 2, iy + 6, 3, 4, c)
    gfx.fill(ix + 18, iy + 6, 3, 4, c)
  elseif r.k == "sword" then
    gfx.fill(ix + 10, iy + 1, 3, 14, c)
    gfx.fill(ix + 5, iy + 15, 13, 3, br)
    gfx.fill(ix + 10, iy + 18, 3, 4, br)
  else
    gfx.fill(ix + 1, iy + 3, 7, 8, c)
    gfx.fill(ix + 14, iy + 3, 7, 8, c)
    gfx.fill(ix + 5, iy + 3, 12, 17, c)
    gfx.fill(ix + 8, iy + 3, 6, 4, SLOTBG)
    gfx.fill(ix + 5, iy + 14, 12, 2, sh(c, 2))
  end
end

local function draw_menu(gfx, g, p, vx, vy)
  local px, py = vx + math.floor((VW - 214) / 2), vy + 20
  gfx.fill(px, py, 214, 164, C.ink)
  gfx.box(px, py, 214, 164, C.gold)
  gfx.text("CRIAR", px + 8, py + 6, C.gold)
  local gx, gy = px + 8, py + 18
  for i = 1, #Core.RECIPES do
    local r = Core.RECIPES[i]
    local x, y = gx + ((i - 1) % 3) * 34, gy + math.floor((i - 1) / 3) * 34
    local own = Core.owns(p, r)
    local can = (not own) and g:afford(p, r)
    gfx.fill(x, y, 30, 30, SLOTBG)
    draw_icon(gfx, r, x, y, not (own or can))
    if own then gfx.fill(x + 23, y + 2, 5, 5, C.good)
    elseif can then gfx.fill(x + 23, y + 2, 5, 5, C.gold) end
    if p.cur == i then
      gfx.box(x - 1, y - 1, 32, 32, C.white)
      gfx.box(x, y, 30, 30, C.gold)
    else
      gfx.box(x, y, 30, 30, C.line)
    end
  end
  -- detalhes da receita selecionada
  local r = Core.RECIPES[p.cur]
  local dx = px + 114
  gfx.text(KL[r.k], dx, gy, C.white)
  local tn = (r.k == "armor") and ((r.v >= 4) and "DIAMANTE" or "FERRO") or TIERN[r.v]
  gfx.text(tn, dx, gy + 10, tier_color(r))
  for i = 1, #r.c do
    local id, need = r.c[i][1], r.c[i][2]
    local have = g:count(p, id)
    gfx.text(Core.SHORT[id] .. " " .. have .. "/" .. need, dx, gy + 26 + (i - 1) * 10, (have >= need) and C.good or C.bad)
  end
  local own = Core.owns(p, r)
  local can = (not own) and g:afford(p, r)
  if own then gfx.text("JA TEM", dx, gy + 64, C.good)
  elseif can then gfx.text("PODE CRIAR", dx, gy + 64, C.gold)
  else gfx.text("FALTA ITEM", dx, gy + 64, C.bad) end
  -- inventario (materiais)
  for i = 1, #INV do
    local it = INV[i]
    local x = px + 8 + ((i - 1) % 4) * 50
    local y = py + 122 + math.floor((i - 1) / 4) * 12
    gfx.fill(x, y, 8, 8, it[3])
    gfx.box(x, y, 8, 8, C.line)
    gfx.text(it[2] .. math.min(99, g:count(p, it[1])), x + 11, y + 1, C.dim)
  end
  local hint = View.menu_hint[p.id]
  gfx.text(hint, px + math.floor((214 - #hint * View.CHAR_W) / 2), py + 150, C.dim)
end

-- ---------- barra de 9 casas (estilo Minecraft) ----------
local function slot_icon(gfx, p, sl, x, y, dim)
  if sl.b then
    if sl.b == 9 then   -- lava
      gfx.fill(x + 4, y + 4, 16, 16, C.orange)
      gfx.fill(x + 4, y + 8, 16, 2, C.gold)
      gfx.fill(x + 4, y + 14, 16, 2, C.gold)
    else
      block(gfx, sl.b, x + 4, y + 4, dim and 2 or 0)
    end
  elseif sl.f then   -- carne
    local c = dim and sh(0xd95763, 2) or 0xd95763
    gfx.fill(x + 7, y + 6, 12, 10, c)
    gfx.fill(x + 9, y + 8, 5, 3, dim and sh(0xd77bba, 2) or 0xd77bba)
    gfx.fill(x + 4, y + 14, 6, 4, dim and sh(C.white, 2) or C.white)
    gfx.fill(x + 13, y + 15, 6, 4, dim and sh(C.white, 2) or C.white)
  elseif sl.t == "tool" then
    local c = (p.tool > 0) and TIERC[p.tool] or C.skin
    gfx.fill(x + 11, y + 8, 3, 13, 0x8f563b)
    gfx.fill(x + 4, y + 5, 17, 3, c)
    gfx.fill(x + 4, y + 8, 3, 4, c)
    gfx.fill(x + 18, y + 8, 3, 4, c)
  else
    local c = (p.sword > 0) and SWORDC[p.sword] or C.skin
    gfx.fill(x + 11, y + 3, 3, 12, c)
    gfx.fill(x + 7, y + 15, 11, 3, 0x8f563b)
    gfx.fill(x + 11, y + 18, 3, 4, 0x8f563b)
  end
end

local function draw_hotbar(gfx, g, p, vx, vy)
  local hb = g:hotbar()
  local x0, y0 = vx + math.floor((VW - 224) / 2), vy + VH - 27
  for i = 1, 9 do
    local sl = hb[i]
    local x = x0 + (i - 1) * 25
    gfx.fill(x, y0, 24, 24, SLOTBG)
    local n = nil
    if (sl.b or sl.f) and not g.creative then n = g:count(p, sl.b or sl.f) end
    slot_icon(gfx, p, sl, x, y0, n ~= nil and n <= 0)
    if n and n > 0 then
      local t = tostring(math.min(99, n))
      gfx.text(t, x + 24 - #t * 8, y0 + 16, C.white)
    end
    if p.sel == i then
      gfx.box(x - 1, y0 - 1, 26, 26, C.white)
      gfx.box(x, y0, 24, 24, C.gold)
    else
      gfx.box(x, y0, 24, 24, C.line)
    end
  end
  local sl = hb[p.sel]
  local name
  if sl.b then name = Core.NAME[sl.b]
  elseif sl.f then name = Core.NAME[sl.f]
  elseif sl.t == "tool" then name = "PICARETA " .. Core.TOOLS[p.tool]
  else name = "ESPADA " .. Core.SWORDS[p.sword] end
  gfx.text(name, vx + math.floor((VW - #name * View.CHAR_W) / 2), y0 - 10, C.white)
end

local function draw_view(g, gfx, i, frame, lvl)
  local me = g.players[i]
  local vx, vy = VX[i], VY
  gfx.clip(vx, vy, VW, VH)
  gfx.fill(vx, vy, VW, VH, SKY[lvl + 1])
  -- estrelas, sol e lua
  local ph = g:phase()
  if lvl >= 2 then
    for s = 1, 12 do gfx.fill(vx + (s * 53) % VW, vy + (s * 29) % 70, 2, 2, C.white) end
  end
  if ph < 0.6 then
    local f = ph / 0.6
    local a = (2 * math.abs(f - 0.5))
    gfx.fill(vx + math.floor(f * (VW - 12)), vy + 6 + math.floor(40 * a * a), 12, 12, C.gold)
  end
  if ph >= 0.55 then
    local f = (ph - 0.55) / 0.45
    local a = (2 * math.abs(f - 0.5))
    gfx.fill(vx + math.floor(f * (VW - 10)), vy + 6 + math.floor(40 * a * a), 10, 10, 0xcbdbfc)
  end
  local cx, cy = cam(me)
  local lite = View.lite
  local x0, x1 = math.floor(cx), math.floor(cx + VW / T)
  for ty = math.floor(cy), math.floor(cy + VH / T) do
    local sy = vy + math.floor((ty - cy) * T)
    local rs, rn, rc = 0, 0, nil          -- faixa de tiles lisos seguidos (modo leve)
    for tx = x0, x1 do
      local sx = vx + math.floor((tx - cx) * T)
      local plain = nil                    -- cor, se este tile for liso
      if tx >= 0 and tx < Core.W and ty >= 0 and ty < Core.H then
        local id = g:get(tx, ty)
        local d = ty - g.surf[tx + 1]
        if id == 9 then
          gfx.fill(sx, sy, T, T, C.orange)
          gfx.fill(sx, sy + 3 + (math.floor(frame / 14) + tx + ty) % 2 * 6, T, 2, C.gold)
        elseif id > 0 then
          local L = lvl
          if d > 20 then L = math.max(L, 2) elseif d > 8 then L = math.max(L, 1) end
          if lite and (id == 2 or id == 3 or id == 4 or id == 5) then
            plain = sh(BC[id], L)
          else
            block(gfx, id, sx, sy, L)
          end
        elseif d > 0 then
          if lite then plain = C.cave else gfx.fill(sx, sy, T, T, C.cave) end
        end
      end
      if plain and plain == rc then
        rn = rn + 1
      else
        if rn > 0 then gfx.fill(rs, sy, rn * T, T, rc) end
        if plain then rs, rn, rc = sx, 1, plain else rn, rc = 0, nil end
      end
    end
    if rn > 0 then gfx.fill(rs, sy, rn * T, T, rc) end
  end
  -- alvo
  if me.hx and not me.dead and g:mineable(g:get(me.hx, me.hy)) then
    local sx, sy = vx + math.floor((me.hx - cx) * T), vy + math.floor((me.hy - cy) * T)
    gfx.box(sx, sy, T, T, C.white)
    if me.prog > 0 then gfx.fill(sx + 1, sy + T - 4, math.floor((T - 2) * math.min(1, me.frac)), 3, C.gold) end
  end
  -- monstros e flechas
  for k = 1, #g.mobs do draw_mob(gfx, g.mobs[k], vx, vy, cx, cy) end
  for k = 1, #g.arrows do
    local a = g.arrows[k]
    gfx.fill(vx + math.floor((a.x - cx) * T) - 3, vy + math.floor((a.y - cy) * T), 6, 2, 0xcbdbfc)
  end
  -- jogadores (so os ativos)
  for k = 1, g.n do
    local q = g.players[k]
    local sx = vx + math.floor((q.x - q.w / 2 - cx) * T)
    local sy = vy + math.floor((q.y - cy) * T)
    if sx + 24 < vx or sx - 6 > vx + VW or sy + 34 < vy or sy - 14 > vy + VH then
      -- fora da tela: nao desenha
    elseif q.dead then
      gfx.fill(sx, sy + 14, 10, 14, C.dim)
      gfx.fill(sx + 3, sy + 10, 4, 4, C.dim)
    elseif q.inv_t <= 0 or frame % 4 < 2 then
      draw_player(gfx, q, k, sx, sy, frame)
    end
  end
  if not me.dead then draw_hotbar(gfx, g, me, vx, vy) end
  if me.menu and not me.dead then draw_menu(gfx, g, me, vx, vy) end
  if me.dead then
    gfx.text("VOCE CAIU! VOLTA EM " .. math.ceil(me.deadt / 60), vx + 14, vy + 80, C.gold)
  end
  gfx.noclip()
  gfx.box(vx - 1, vy - 1, VW + 2, VH + 2, C.line)
end

local function draw_hud(g, gfx, i)
  local p = g.players[i]
  local x, y = VX[i] + 4, VY + VH + 4
  if g.creative then
    gfx.text("J" .. i .. " MODO CRIATIVO", x, y, PTXT[i])
    gfx.text(g.is3d and "PULAR: SOBE   CRIAR: DESCE" or "CIMA/BAIXO: VOAR", x, y + 12, C.white)
    gfx.text("BLOCOS INFINITOS, SEM DANO", x, y + 22, C.dim)
    gfx.text(g.is3d and "OLHE PARA O BLOCO E MINERE" or "SEGURE CIMA/BAIXO+MINERAR: CAVAR", x, y + 32, C.dim)
    gfx.text(View.back_hint, x, y + 42, C.dim)
    if p.msgt > 0 then gfx.text(p.msg, x, y + 52, C.gold) end
    return
  end
  gfx.text("J" .. i .. " DIAM " .. g:count(p, 7) .. "/" .. Core.WIN .. "  VIDA " .. p.hp .. "/" .. p.maxhp, x, y, PTXT[i])
  local hpc = (p.hp * 4 <= p.maxhp) and C.bad or C.good
  bar(gfx, x, y + 11, 120, 5, p.hp, p.maxhp, hpc)
  gfx.text("PIC " .. Core.TOOLS[p.tool] .. " ESP " .. Core.SWORDS[p.sword] .. " ARM " .. p.armor, x, y + 19, C.white)
  gfx.text("MAD " .. g:count(p, 4) .. " TER " .. g:count(p, 2) .. " PED " .. g:count(p, 3) .. " CRV " .. g:count(p, 6), x, y + 29, C.dim)
  gfx.text("FER " .. g:count(p, 8) .. " CRN " .. g:count(p, 12), x, y + 39, C.dim)
  if p.msgt > 0 then gfx.text(p.msg, x, y + 49, C.gold) end
end

local function draw_clock(g, gfx)
  local ph = g:phase()
  local label = (ph < 0.55) and "DIA" or (ph < 0.65) and "ANOITECE" or (ph < 0.90) and "NOITE" or "AMANHECE"
  local s = (math.floor(g.time / Core.DAY) + 1) .. " " .. label
  local w = (#s + 2) * View.CHAR_W
  local x = math.floor((View.W - w) / 2)
  gfx.fill(x, VY, w, 11, C.ink)
  gfx.text("D" .. s, x + 4, VY + 2, C.gold)
end

local function draw_title(gfx, frame, menu, cmode, dim, row)
  local d3 = (dim == 2)
  local c2 = (menu == 2) and C.white or C.dim
  gfx.box(8, 8, View.W - 16, View.H - 16, C.line)
  center(gfx, "BLOCK QUEST", 18, C.gold)
  center(gfx, "MINI-MINECRAFT PARA 1 OU 2 JOGADORES", 32, C.dim)
  center(gfx, "SEJA O PRIMEIRO A ACHAR 5 DIAMANTES!", 46, C.white)
  gfx.text("JOGADOR 1 (AZUL)", 24, 66, 0x639bff)
  gfx.text("JOGADOR 2 (VERMELHO)", 248, 66, (menu == 2) and C.p2 or C.dim)
  if d3 then
    gfx.text("A D    GIRAR", 24, 78, C.white)
    gfx.text("W S    ANDAR", 24, 88, C.white)
    gfx.text("ESPACO PULAR", 24, 98, C.white)
    gfx.text("R V    OLHAR CIMA/BAIXO", 24, 108, C.white)
    gfx.text("F G    MINERAR/COLOCAR", 24, 118, C.white)
    gfx.text("Q E    ITEM / CRIAR", 24, 128, C.white)
    gfx.text("SETAS  GIRAR/ANDAR", 248, 78, c2)
    gfx.text("CTRL D PULAR", 248, 88, c2)
    gfx.text("L M    OLHAR CIMA/BAIXO", 248, 98, c2)
    gfx.text(", .    MINERAR/COLOCAR", 248, 108, c2)
    gfx.text("; SH.D ITEM / CRIAR", 248, 118, c2)
    center(gfx, "OLHE PARA O BLOCO E MINERE/COLOQUE (MIRA +)", 138, C.dim)
    center(gfx, "BARRA DE 9 CASAS: Q TROCA, 1-9 ESCOLHE (J1)", 148, C.dim)
    center(gfx, "ARVORE > PICARETA > PEDRA > FERRO > DIAMANTE", 158, C.dim)
    center(gfx, "DIAMANTES FICAM BEM FUNDO. CUIDADO COM A LAVA!", 168, C.dim)
    center(gfx, "CRIATIVO: PULAR SOBE, CRIAR (E) DESCE", 178, C.dim)
  else
    gfx.text("A D   MOVER", 24, 78, C.white)
    gfx.text("W     PULAR/VOAR", 24, 88, C.white)
    gfx.text("F     MINERAR/ATACAR", 24, 98, C.white)
    gfx.text("G     COLOCAR/USAR", 24, 108, C.white)
    gfx.text("Q     TROCAR ITEM", 24, 118, C.white)
    gfx.text("E     MENU DE CRIAR", 24, 128, C.white)
    gfx.text("SETAS  MOVER/PULAR", 248, 78, c2)
    gfx.text(",      MINERAR/ATACAR", 248, 88, c2)
    gfx.text(".      COLOCAR/USAR", 248, 98, c2)
    gfx.text(";      TROCAR ITEM", 248, 108, c2)
    gfx.text("SHIFT DIR.  MENU CRIAR", 248, 118, c2)
    center(gfx, "BAIXO/CIMA + MINERAR OU COLOCAR = DIRECAO", 138, C.dim)
    center(gfx, "BARRA DE 9 CASAS: Q TROCA, 1-9 ESCOLHE (J1)", 148, C.dim)
    center(gfx, "ARVORE > PICARETA > PEDRA > FERRO > DIAMANTE", 158, C.dim)
    center(gfx, "NOITE: ZUMBIS. CAVERNAS: ESQUELETOS E LAVA", 168, C.dim)
    center(gfx, "CHEFE NO FUNDO: 3 DIAMANTES. MATAR AMIGO ROUBA 1", 178, C.dim)
  end
  -- menu: 3 linhas. CIMA/BAIXO muda de linha, ESQUERDA/DIREITA muda a opcao
  gfx.fill(60, 188, 360, 48, C.ink)
  gfx.box(60, 188, 360, 48, C.line)
  local rows = {
    { "1 JOGADOR", "2 JOGADORES", menu },
    { "SOBREVIVENCIA", "CRIATIVO", cmode },
    { "VISAO 2D", "VISAO 3D", dim },
  }
  for r = 1, 3 do
    local y = 194 + (r - 1) * 14
    local sel = rows[r][3]
    if row == r then gfx.text(">", 72, y, C.gold) end
    gfx.text((sel == 1 and "* " or "  ") .. rows[r][1], 100, y, (sel == 1) and C.gold or C.dim)
    gfx.text((sel == 2 and "* " or "  ") .. rows[r][2], 260, y, (sel == 2) and C.gold or C.dim)
  end
  local tag = d3 and "3D" or "2D"
  if cmode == 2 then
    center(gfx, tag .. " CRIATIVO: VOE, BLOCOS INFINITOS, SEM DANO", 242, C.white)
  elseif d3 then
    center(gfx, "3D SOBREVIVENCIA: CRIE E ACHE 5 DIAMANTES", 242, C.white)
  else
    center(gfx, "2D SOBREVIVENCIA: MONSTROS, CRIAR E 5 DIAMANTES", 242, C.white)
  end
  if math.floor(frame / 30) % 2 == 0 then center(gfx, "SETAS: ESCOLHER   Z: INICIAR", 252, C.gold) end
end

local function draw_win(g, gfx, frame, locked)
  local secs = math.floor(g.time / 60)
  local sec = secs % 60
  local t = math.floor(secs / 60) .. ":" .. (sec < 10 and "0" or "") .. sec
  gfx.fill(100, 70, 280, 92, C.ink)
  gfx.box(100, 70, 280, 92, C.gold)
  if g.n == 1 then
    center(gfx, "VITORIA!", 84, C.gold)
    center(gfx, "VOCE ACHOU " .. Core.WIN .. " DIAMANTES", 102, C.white)
    center(gfx, "TEMPO " .. t, 118, C.dim)
  else
    local w = g.winner
    center(gfx, "VITORIA DO JOGADOR " .. w .. "!", 84, PTXT[w])
    center(gfx, "ACHOU " .. Core.WIN .. " DIAMANTES EM " .. t, 102, C.white)
    center(gfx, "J1: " .. g:count(g.players[1], 7) .. "   J2: " .. g:count(g.players[2], 7), 118, C.dim)
  end
  if not locked and math.floor(frame / 30) % 2 == 0 then
    center(gfx, "Z: VOLTAR AO TITULO", 140, C.gold)
  end
end

View.title = draw_title

function View.draw(app, gfx, frame)
  gfx.clear(C.black)
  if app.screen == "title" then View.title(gfx, frame, app.menu, app.cmode, app.dim, app.row); return end
  local g = app.game
  if g.n == 1 then VW, VX = 478, VX1 else VW, VX = 238, VX2 end
  local lvl = math.floor(g:dark() * 3 + 0.5)
  for i = 1, g.n do draw_view(g, gfx, i, frame, lvl); draw_hud(g, gfx, i) end
  draw_clock(g, gfx)
  if g.mode == "win" then
    local locked = app.over_at and frame - app.over_at < 45
    draw_win(g, gfx, frame, locked)
  end
end

-- usado pelo q3_view (modo 3D) para reaproveitar barra, menu de criar, HUD etc.
View.fx = {
  block = block, hotbar = draw_hotbar, menu = draw_menu, hud = draw_hud,
  clock = draw_clock, win = draw_win, VX1 = VX1, VX2 = VX2,
  setvp = function(w, vx) VW, VX = w, vx end,
}

return View
