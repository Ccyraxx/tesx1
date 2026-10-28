-- bq_core.lua : regras do BLOCK QUEST (mini-Minecraft 2D, 2 jogadores).
-- Lua puro (5.1): nao conhece LOVE nem tela. Sem math.random (gerador proprio).
-- Tiles comecam em 0. Entidade = (x centro, y topo) em tiles, com w/h em tiles.
local Core = {}
Core.__index = Core

-- remove t[i] deslocando o resto (nao depende da biblioteca table)
local function remove_at(t, i)
  local n = #t
  for k = i, n - 1 do t[k] = t[k + 1] end
  t[n] = nil
end

Core.W, Core.H = 120, 56
Core.PW, Core.PH = 0.625, 1.75
Core.WIN = 5                      -- diamantes para vencer
Core.GRAVITY, Core.JUMP, Core.MOVE = 0.03, 0.37, 0.11
Core.MAXHP = 20
Core.DAY = 7200                   -- quadros por dia (2 min)
Core.MAXMOBS = 16
Core.REACH = 1.1                  -- alcance da espada

-- ids: 0 ar | 1 grama | 2 terra | 3 pedra | 4 madeira | 5 folha | 6 carvao
--      7 diamante | 8 ferro | 9 lava (nao solida, machuca) | 12 carne (so item)
-- need = nivel minimo da picareta (0 mao, 1 madeira, 2 pedra, 3 ferro)
Core.B = {
  [1] = { name = "GRAMA",    hard = 14,  need = 0, drop = 2 },
  [2] = { name = "TERRA",    hard = 14,  need = 0, drop = 2 },
  [3] = { name = "PEDRA",    hard = 40,  need = 1, drop = 3 },
  [4] = { name = "MADEIRA",  hard = 26,  need = 0, drop = 4 },
  [5] = { name = "FOLHA",    hard = 5,   need = 0, drop = 0 },
  [6] = { name = "CARVAO",   hard = 50,  need = 1, drop = 6 },
  [7] = { name = "DIAMANTE", hard = 100, need = 3, drop = 7 },
  [8] = { name = "FERRO",    hard = 70,  need = 2, drop = 8 },
}
Core.NAME = { [1] = "GRAMA", [2] = "TERRA", [3] = "PEDRA", [4] = "MADEIRA", [5] = "FOLHA",
              [6] = "CARVAO", [7] = "DIAMANTE", [8] = "FERRO", [9] = "LAVA", [12] = "CARNE" }
Core.SHORT = { [2] = "TER", [3] = "PED", [4] = "MAD", [6] = "CRV", [7] = "DIA", [8] = "FER", [12] = "CRN" }
Core.PLACE = { 2, 3, 4 }          -- blocos que da para colocar
Core.TOOLS  = { [0] = "MAO", "MADEIRA", "PEDRA", "FERRO" }
Core.SWORDS = { [0] = "MAO", "MADEIRA", "PEDRA", "FERRO", "DIAM" }
Core.TOOLSPD   = { [0] = 1, 2, 3.2, 4.5 }
Core.SWORD_DMG = { [0] = 2, 4, 6, 8, 11 }

-- receitas: 9 casas da grade 3x3 do menu de criar (tecla E)
-- c = custo {item, qtd}; k = o que melhora; v = nivel
Core.RECIPES = {
  { n = "PICA MAD",  c = { { 4, 3 } },                     k = "tool",  v = 1 },
  { n = "PICA PED",  c = { { 3, 4 }, { 4, 2 } },           k = "tool",  v = 2 },
  { n = "PICA FER",  c = { { 8, 4 }, { 6, 2 }, { 4, 1 } }, k = "tool",  v = 3 },
  { n = "ESP MAD",   c = { { 4, 2 } },                     k = "sword", v = 1 },
  { n = "ESP PED",   c = { { 3, 3 }, { 4, 1 } },           k = "sword", v = 2 },
  { n = "ESP FER",   c = { { 8, 3 }, { 6, 1 }, { 4, 1 } }, k = "sword", v = 3 },
  { n = "ESP DIAM",  c = { { 7, 2 }, { 4, 1 } },           k = "sword", v = 4 },
  { n = "ARMADURA",  c = { { 8, 5 } },                     k = "armor", v = 2 },
  { n = "ARM DIAM",  c = { { 7, 3 } },                     k = "armor", v = 4 },
}

-- Z zumbi | S slime | K esqueleto (flechas) | B chefe
Core.MOB = {
  Z = { w = 0.6, h = 1.7, hp = 14, dmg = 3, spd = 0.05 },
  S = { w = 0.8, h = 0.6, hp = 8,  dmg = 2, spd = 0 },
  K = { w = 0.6, h = 1.7, hp = 10, dmg = 0, spd = 0.04 },
  B = { w = 1.6, h = 2.6, hp = 80, dmg = 5, spd = 0.045 },
}

function Core.isb(id) return id > 0 and id ~= 9 end

-- barra de 9 casas. b = bloco, f = comida, t = ferramenta (so mostra)
Core.HOTBAR = {
  [false] = { { b = 2 }, { b = 3 }, { b = 4 }, { b = 6 }, { b = 8 }, { b = 7 }, { f = 12 },
              { t = "tool" }, { t = "sword" } },
  [true]  = { { b = 2 }, { b = 3 }, { b = 4 }, { b = 1 }, { b = 5 }, { b = 6 }, { b = 8 },
              { b = 7 }, { b = 9 } },   -- criativo: blocos infinitos (inclui lava)
}
function Core:hotbar() return Core.HOTBAR[self.creative] end
function Core:select(p, n) if n >= 1 and n <= 9 then p.sel = n end end

-- no criativo da para quebrar ate lava
function Core:mineable(id) return id > 0 and (id ~= 9 or self.creative) end
function Core:cell(id, solid)
  if solid then return self:mineable(id) end
  return not Core.isb(id)
end

-- Park-Miller (seguro em Lua 5.1)
function Core:rnd(a, b)
  self.seed = (self.seed * 16807) % 2147483647
  return a + (self.seed % (b - a + 1))
end

function Core:get(tx, ty)
  if tx < 0 or tx >= Core.W or ty < 0 or ty >= Core.H then return 0 end
  return self.grid[ty * Core.W + tx + 1]
end

function Core:set(tx, ty, id)
  if tx < 0 or tx >= Core.W or ty < 0 or ty >= Core.H then return end
  self.grid[ty * Core.W + tx + 1] = id
end

-- tempo ------------------------------------------------------------------
function Core:phase() return (self.time % Core.DAY) / Core.DAY end

function Core:dark()   -- 0 dia ... 1 noite
  local ph = self:phase()
  if ph < 0.55 then return 0
  elseif ph < 0.65 then return (ph - 0.55) / 0.10
  elseif ph < 0.90 then return 1
  else return 1 - (ph - 0.90) / 0.10 end
end

-- mundo --------------------------------------------------------------------
function Core:gen()
  local W, H = Core.W, Core.H
  self.grid, self.surf = {}, {}
  local p1, p2 = self:rnd(0, 628) / 100, self:rnd(0, 628) / 100
  for x = 0, W - 1 do
    local s = math.floor(18 + 3 * math.sin(x * 0.11 + p1) + 2 * math.sin(x * 0.29 + p2) + 0.5)
    self.surf[x + 1] = s
    local dirt = 3 + self:rnd(0, 1)
    for y = 0, H - 1 do
      local id = 0
      if y == s then id = 1
      elseif y > s and y <= s + dirt then id = 2
      elseif y > s + dirt then
        id = 3
        if y >= s + 5 and self:rnd(1, 100) <= 4 then id = 6 end
        if y >= s + 9 and self:rnd(1, 100) <= 3 then id = 8 end
        if y >= s + 14 and self:rnd(1, 100) <= 2 then id = 7 end
      end
      self.grid[y * W + x + 1] = id
    end
  end
  -- cavernas
  for _ = 1, 18 do
    local cx = self:rnd(4, W - 5)
    local cy = self:rnd(self.surf[cx + 1] + 7, H - 5)
    for _ = 1, 3 do
      local r = self:rnd(2, 4)
      for dy = -r, r do
        for dx = -r, r do
          if dx * dx + dy * dy <= r * r + 1 then
            local tx, ty = cx + dx, cy + dy
            if tx > 0 and tx < W - 1 and ty > self.surf[tx + 1] + 5 and ty < H - 1 then
              self:set(tx, ty, 0)
            end
          end
        end
      end
      cx, cy = cx + self:rnd(-3, 3), cy + self:rnd(-2, 2)
    end
  end
  -- lava: piscinas no fundo das cavernas e lagos
  for y = H - 8, H - 2 do
    for x = 1, W - 2 do
      if self:get(x, y) == 0 then self:set(x, y, 9) end
    end
  end
  for _ = 1, 6 do
    local cx, cy = self:rnd(4, W - 5), self:rnd(H - 12, H - 6)
    if cx < 52 or cx > 68 then
      for dy = -2, 2 do
        for dx = -2, 2 do
          if dx * dx + dy * dy <= 5 then self:set(cx + dx, cy + dy, 9) end
        end
      end
    end
  end
  -- sala do chefe (fundo, no meio) com 2 diamantes no chao
  for y = H - 13, H - 4 do
    for x = 53, 67 do self:set(x, y, 0) end
  end
  self:set(57, H - 4, 7)
  self:set(63, H - 4, 7)
  -- arvores (longe do ponto de inicio)
  local last = -10
  for x = 4, W - 5 do
    if (x < 56 or x > 67) and x - last >= 5 and self:rnd(1, 100) <= 18 then
      last = x
      local s, th = self.surf[x + 1], self:rnd(3, 4)
      for i = 1, th do self:set(x, s - i, 4) end
      local top = s - th
      for dy = -2, 0 do
        for dx = -2, 2 do
          if math.abs(dx) + math.abs(dy) <= 3 and self:get(x + dx, top + dy) == 0 then
            self:set(x + dx, top + dy, 5)
          end
        end
      end
    end
  end
end

-- entidades ------------------------------------------------------------------
local function newp(g, id, x)
  local tx = math.floor(x)
  local s = math.min(g.surf[tx], g.surf[tx + 1], g.surf[tx + 2])
  local y = s - Core.PH - 0.01
  return {
    id = id, x = x, y = y, sx = x, sy = y, w = Core.PW, h = Core.PH,
    vx = 0, vy = 0, kx = 0, face = (id == 1) and 1 or -1, ground = false, blocked = false,
    inv = {}, tool = 0, sword = 0, armor = 0, sel = 1,
    hp = Core.MAXHP, maxhp = Core.MAXHP,
    prog = 0, frac = 0, hx = nil, hy = nil, tgx = nil, tgy = nil,
    prev = {}, msg = "", msgt = 0,
    acd = 0, inv_t = 0, regen = 0, eat = 0, lasth = nil, lastt = 0,
    dead = false, deadt = 0, apex = y, airborne = false, lv = 0,
    swing = 0, menu = false, cur = 1, e = {}, ccd = 0,
  }
end

function Core:addmob(kind, x, y)
  local d = Core.MOB[kind]
  self.mobs[#self.mobs + 1] = {
    kind = kind, x = x, y = y, w = d.w, h = d.h, vx = 0, vy = 0, kx = 0, face = 1,
    hp = d.hp, max = d.hp, ground = false, blocked = false, cd = 30, burn = 0, lv = 0,
  }
end

function Core.new(seed, n, creative)
  local g = setmetatable({}, Core)
  g.n = (n == 1) and 1 or 2   -- numero de jogadores
  g.creative = creative and true or false
  g.seed = (math.floor(seed or 1) % 2147483646) + 1
  for _ = 1, 5 do g:rnd(0, 1) end
  g:gen()
  g.players = { newp(g, 1, 60.5), newp(g, 2, 64.5) }
  if g.n == 1 then   -- solo: jogador 2 fica "desligado" (como morto para sempre)
    local p2 = g.players[2]
    p2.off, p2.dead, p2.deadt, p2.hp = true, true, 1e9, 0
  end
  g.mobs, g.arrows = {}, {}
  g.time = 0
  if not g.creative then g:addmob("B", 60.5, Core.H - 3 - Core.MOB.B.h - 0.01) end
  g.mode, g.winner = "play", nil
  return g
end

function Core:count(p, id) return p.inv[id] or 0 end
function Core:tell(p, s) p.msg, p.msgt = s, 70 end

function Core:give(p, id, n)
  p.inv[id] = (p.inv[id] or 0) + n
  if id == 7 then
    self:tell(p, "DIAMANTE! " .. p.inv[7] .. "/" .. Core.WIN)
    if p.inv[7] >= Core.WIN and self.mode == "play" then self.mode, self.winner = "win", p.id end
  end
end

-- fisica -----------------------------------------------------------------------
function Core:solid(tx, ty)
  if tx < 0 or tx >= Core.W or ty >= Core.H then return true end
  if ty < 0 then return false end
  local id = self.grid[ty * Core.W + tx + 1]
  return id ~= 0 and id ~= 9
end

function Core:hit(x, y, w, h)
  local l, r, t, b = x - w / 2, x + w / 2, y, y + h
  for ty = math.floor(t), math.floor(b - 1e-4) do
    for tx = math.floor(l), math.floor(r - 1e-4) do
      if self:solid(tx, ty) then return true end
    end
  end
  return false
end

function Core:inlava(e)
  local l, r, t, b = e.x - e.w / 2, e.x + e.w / 2, e.y, e.y + e.h
  for ty = math.floor(t), math.floor(b - 1e-4) do
    for tx = math.floor(l), math.floor(r - 1e-4) do
      if self:get(tx, ty) == 9 then return true end
    end
  end
  return false
end

local function overlap(a, b)
  return a.x - a.w / 2 < b.x + b.w / 2 and a.x + a.w / 2 > b.x - b.w / 2
     and a.y < b.y + b.h and a.y + a.h > b.y
end

function Core:inbody(tx, ty)
  local box = { x = tx + 0.5, y = ty, w = 1, h = 1 }
  for i = 1, 2 do
    if not self.players[i].dead and overlap(self.players[i], box) then return true end
  end
  for i = 1, #self.mobs do
    if overlap(self.mobs[i], box) then return true end
  end
  return false
end

function Core:move(e)
  e.blocked = false
  local vx = e.vx + e.kx
  e.kx = e.kx * 0.8
  if math.abs(e.kx) < 0.01 then e.kx = 0 end
  if vx ~= 0 then
    local n = math.ceil(math.abs(vx) / 0.05)
    local s = vx / n
    for _ = 1, n do
      if self:hit(e.x + s, e.y, e.w, e.h) then e.blocked = true; break end
      e.x = e.x + s
    end
  end
  e.ground = false
  local m = math.max(1, math.ceil(math.abs(e.vy) / 0.05))
  local sy = e.vy / m
  for _ = 1, m do
    if self:hit(e.x, e.y + sy, e.w, e.h) then
      if e.vy > 0 then e.ground = true end
      e.vy = 0
      break
    end
    e.y = e.y + sy
  end
end

-- dano / morte ------------------------------------------------------------------
function Core:hurt(p, dmg, src, dir)
  if p.dead or p.inv_t > 0 or self.creative then return end
  dmg = math.max(1, dmg - p.armor)
  p.hp = p.hp - dmg
  p.inv_t, p.regen = 30, 0
  if dir then p.kx = dir * 0.22; p.vy = -0.18 end
  if src then p.lasth, p.lastt = src, 240 end
  if p.hp <= 0 then self:die(p) end
end

function Core:die(p)
  p.hp, p.dead, p.deadt, p.prog, p.tgx = 0, true, 150, 0, nil
  p.menu = false
  local lose = { 2, 3, 4, 6, 8, 12 }
  for i = 1, #lose do p.inv[lose[i]] = math.floor((p.inv[lose[i]] or 0) / 2) end
  if (p.inv[7] or 0) > 0 then
    p.inv[7] = p.inv[7] - 1
    if p.lasth and p.lastt > 0 then
      self:give(self.players[p.lasth], 7, 1)
      self:tell(self.players[p.lasth], "ROUBOU 1 DIAMANTE!")
    end
  end
  self:tell(p, "VOCE CAIU!")
end

function Core:respawn(p)
  p.dead, p.hp = false, Core.MAXHP
  p.x, p.y = p.sx, p.sy
  while self:hit(p.x, p.y, p.w, p.h) and p.y > 2 do p.y = p.y - 1 end
  p.vx, p.vy, p.kx = 0, 0, 0
  p.inv_t, p.apex, p.airborne, p.lastt = 90, p.y, false, 0
end

-- jogador -----------------------------------------------------------------------
-- escolhe o tile alvo. solid=true: quer um bloco; false: quer um espaco livre
function Core:aim(p, h, solid)
  local col = math.floor(p.x)
  if h.up then return col, math.floor(p.y) - 1 end
  if h.down then return col, math.floor(p.y + p.h + 0.05) end
  local tx = math.floor(p.x + p.face * (p.w / 2 + 0.35))
  local feet = math.floor(p.y + p.h - 0.05)
  if self:cell(self:get(tx, feet), solid) then return tx, feet end
  if self:cell(self:get(tx, feet - 1), solid) then return tx, feet - 1 end
  return nil
end

function Core:find_target(p)
  local x0, x1
  if p.face > 0 then x0, x1 = p.x, p.x + p.w / 2 + Core.REACH
  else x0, x1 = p.x - p.w / 2 - Core.REACH, p.x end
  local reach = { x = (x0 + x1) / 2, y = p.y, w = x1 - x0, h = p.h }
  local best, isp, bd = nil, false, 1e9
  for i = 1, #self.mobs do
    local e = self.mobs[i]
    if overlap(reach, e) and math.abs(e.x - p.x) < bd then best, isp, bd = e, false, math.abs(e.x - p.x) end
  end
  local q = self.players[3 - p.id]
  if not q.dead and overlap(reach, q) and math.abs(q.x - p.x) < bd then best, isp = q, true end
  return best, isp
end

function Core:kill_mob(e, p)
  e.dead = true
  local r = self:rnd(1, 100)
  if e.kind == "Z" and r <= 60 then self:give(p, 12, 1)
  elseif e.kind == "S" and r <= 30 then self:give(p, 12, 1)
  elseif e.kind == "K" then
    self:give(p, 6, 1)
    if r <= 30 then self:give(p, 12, 1) end
  elseif e.kind == "B" then
    self:give(p, 8, 2)
    self:give(p, 7, 3)
    self:tell(p, "BOSS CAIU! +3 DIAM")
  end
end

function Core:strike(p, t, isp)
  local dmg = Core.SWORD_DMG[p.sword]
  p.acd, p.swing = 18, 8
  if isp then
    self:hurt(t, dmg, p.id, p.face)
  else
    t.hp = t.hp - dmg
    t.kx, t.vy = p.face * 0.2, -0.15
    if t.hp <= 0 and not t.dead then self:kill_mob(t, p) end
  end
end

function Core:mine(p, tx, ty)
  local id = tx and self:get(tx, ty) or 0
  if not self:mineable(id) then p.prog, p.tgx = 0, nil; return end
  if self.creative then   -- quebra instantanea, sem tirar item
    if p.ccd <= 0 then self:set(tx, ty, 0); p.ccd, p.swing = 4, 4 end
    return
  end
  local b = Core.B[id]
  if p.tool < b.need then
    p.prog, p.tgx = 0, nil
    if p.msgt <= 0 then self:tell(p, "PRECISA PICARETA " .. Core.TOOLS[b.need]) end
    return
  end
  if p.tgx ~= tx or p.tgy ~= ty then p.prog, p.tgx, p.tgy = 0, tx, ty end
  p.prog = p.prog + Core.TOOLSPD[p.tool]
  p.swing = 4
  p.frac = p.prog / b.hard
  if p.prog >= b.hard then
    self:set(tx, ty, 0)
    p.prog, p.tgx = 0, nil
    if b.drop > 0 then self:give(p, b.drop, 1) end
  end
end

function Core:place(p, h)
  local slot = self:hotbar()[p.sel]
  if slot.f then   -- comida: "colocar" = comer
    if self.creative then return end
    if self:count(p, slot.f) <= 0 then self:tell(p, "SEM CARNE")
    elseif p.hp >= p.maxhp then self:tell(p, "VIDA JA ESTA CHEIA")
    else
      p.inv[slot.f] = p.inv[slot.f] - 1
      p.hp = math.min(p.maxhp, p.hp + 8)
      p.eat = 60
      self:tell(p, "COMEU CARNE +8")
    end
    return
  end
  if not slot.b then self:tell(p, "ESSE ITEM NAO COLOCA"); return end
  local id = slot.b
  local tx, ty = self:aim(p, h, false)
  if not tx or tx < 0 or tx >= Core.W or ty < 0 or ty >= Core.H then return end
  if Core.isb(self:get(tx, ty)) then return end
  if self:inbody(tx, ty) then self:tell(p, "LUGAR OCUPADO"); return end
  if not self.creative then
    if self:count(p, id) <= 0 then self:tell(p, "SEM " .. Core.NAME[id]); return end
    p.inv[id] = p.inv[id] - 1
  end
  self:set(tx, ty, id)
end

local function owned(p, r) return p[r.k] >= r.v end
Core.owns = owned

function Core:afford(p, r)
  for i = 1, #r.c do
    if self:count(p, r.c[i][1]) < r.c[i][2] then return false end
  end
  return true
end

-- cria a receita idx (usada pelo menu de criar)
function Core:craft_at(p, idx)
  local r = Core.RECIPES[idx]
  if not r then return end
  if owned(p, r) then self:tell(p, "VOCE JA TEM ISSO"); return end
  if not self:afford(p, r) then self:tell(p, "FALTA MATERIAL"); return end
  for j = 1, #r.c do p.inv[r.c[j][1]] = p.inv[r.c[j][1]] - r.c[j][2] end
  p[r.k] = r.v
  self:tell(p, r.n .. " CRIADA!")
end

local KEYN = { "left", "right", "up", "down", "mine", "place", "next", "craft" }

function Core:upd_player(p, h)
  -- bordas (apertou agora) de todas as teclas
  local pr, e = p.prev, p.e
  for i = 1, #KEYN do
    local k = KEYN[i]
    e[k] = (h[k] and not pr[k]) and true or false
    pr[k] = h[k] and true or false
  end
  if p.dead then
    p.menu = false
    p.deadt = p.deadt - 1
    if p.msgt > 0 then p.msgt = p.msgt - 1 end
    if p.deadt <= 0 then self:respawn(p) end
    return
  end
  if p.msgt > 0 then p.msgt = p.msgt - 1 end
  if p.inv_t > 0 then p.inv_t = p.inv_t - 1 end
  if p.acd > 0 then p.acd = p.acd - 1 end
  if p.eat > 0 then p.eat = p.eat - 1 end
  if p.lastt > 0 then p.lastt = p.lastt - 1 end
  if p.swing > 0 then p.swing = p.swing - 1 end
  if p.ccd > 0 then p.ccd = p.ccd - 1 end

  -- E abre/fecha o menu de criar (grade 3x3)
  if e.craft then
    if self.creative then self:tell(p, "MODO CRIATIVO: SEM CRIAR")
    else p.menu = not p.menu end
  end
  local inmenu = p.menu
  if inmenu then
    local c = p.cur
    if e.left and (c - 1) % 3 > 0 then c = c - 1 end
    if e.right and (c - 1) % 3 < 2 then c = c + 1 end
    if e.up and c > 3 then c = c - 3 end
    if e.down and c <= 6 then c = c + 3 end
    p.cur = c
    if e.mine then self:craft_at(p, c) end
    if e.place then p.menu = false end
  end

  local dir = 0
  if not inmenu then dir = (h.right and 1 or 0) - (h.left and 1 or 0) end
  p.vx = dir * Core.MOVE * (self.creative and 1.4 or 1)
  if dir ~= 0 then p.face = dir end
  if self.creative then   -- criativo: voa com CIMA/BAIXO (sem gravidade)
    local vd = 0
    if not inmenu and not (h.mine or h.place) then vd = (h.down and 1 or 0) - (h.up and 1 or 0) end
    p.vy = vd * 0.14
  else
    if not inmenu and h.up and p.ground and not (h.mine or h.place) then p.vy = -Core.JUMP end
    p.vy = math.min(p.vy + Core.GRAVITY, 0.55)
  end
  self:move(p)

  -- queda
  if p.ground then
    if p.airborne then
      local d = p.y - p.apex
      if d > 3.6 then self:hurt(p, math.floor(d - 3), nil, nil) end
    end
    p.apex, p.airborne = p.y, false
  else
    p.airborne = true
    if p.y < p.apex then p.apex = p.y end
  end
  -- lava
  if self:inlava(p) then self:hurt(p, 2, nil, nil) end
  if p.dead then return end
  -- regeneracao e comida
  p.regen = p.regen + 1
  if p.regen >= 150 and p.regen % 60 == 0 and p.hp < p.maxhp then p.hp = p.hp + 1 end
  if p.hp <= p.maxhp - 8 and self:count(p, 12) > 0 and p.eat <= 0 then
    p.inv[12] = p.inv[12] - 1
    p.hp = math.min(p.maxhp, p.hp + 8)
    p.eat = 60
    self:tell(p, "COMEU CARNE +8")
  end

  if inmenu then
    p.prog, p.tgx, p.hx, p.hy = 0, nil, nil, nil
    return
  end

  if e.place then self:place(p, h) end
  if e.next then p.sel = p.sel % 9 + 1 end

  p.hx, p.hy = self:aim(p, h, true)
  if h.mine then
    local t, isp
    if not (h.up or h.down) and not self.creative then t, isp = self:find_target(p) end
    if t then
      p.prog, p.tgx = 0, nil
      if p.acd <= 0 then self:strike(p, t, isp) end
    else
      self:mine(p, p.hx, p.hy)
    end
  else
    p.prog, p.tgx = 0, nil
  end
end

-- monstros -----------------------------------------------------------------------
function Core:nearest(e)
  local best, bd = nil, 1e9
  for i = 1, 2 do
    local p = self.players[i]
    if not p.dead then
      local d = math.abs(p.x - e.x) + math.abs(p.y - e.y) * 0.5
      if d < bd then best, bd = p, d end
    end
  end
  return best, bd
end

local function colof(x) return math.max(1, math.min(Core.W, math.floor(x) + 1)) end

-- devolve true se o monstro deve sumir
function Core:upd_mob(e)
  if e.dead then return true end
  local d = Core.MOB[e.kind]
  if e.cd > 0 then e.cd = e.cd - 1 end
  local tgt, near = self:nearest(e)
  if not tgt or (near > 60 and e.kind ~= "B") then return e.kind ~= "B" and true or false end
  local dx, dy = tgt.x - e.x, tgt.y - e.y
  local adx = math.abs(dx)
  local sgn = (dx >= 0) and 1 or -1
  local k = e.kind
  if k == "Z" or k == "B" then
    local dir = 0
    if adx < 22 and math.abs(dy) < 14 and adx > 0.3 then dir = sgn end
    e.vx = dir * d.spd
    if dir ~= 0 then e.face = dir end
    if e.ground and e.blocked and dir ~= 0 then e.vy = -Core.JUMP end
  elseif k == "S" then
    if e.ground then
      e.vx = 0
      if e.cd <= 0 and adx < 16 then
        e.vy, e.vx, e.face, e.cd = -0.3, sgn * 0.09, sgn, 50
      end
    end
  else -- K
    local dir = 0
    if adx < 16 and math.abs(dy) < 6 then
      e.face = sgn
      if adx > 7 then dir = sgn elseif adx < 4 then dir = -sgn end
      if e.cd <= 0 and adx < 13 then
        local vy = math.max(-0.2, math.min(0.2, dy / math.max(1, adx / 0.3)))
        self.arrows[#self.arrows + 1] = { x = e.x + sgn * 0.4, y = e.y + 0.7, vx = sgn * 0.3, vy = vy, life = 90 }
        e.cd = 80
      end
    end
    e.vx = dir * d.spd
    if e.ground and e.blocked and dir ~= 0 then e.vy = -Core.JUMP end
  end
  e.vy = math.min(e.vy + Core.GRAVITY, 0.55)
  self:move(e)
  -- dano de contato
  if d.dmg > 0 then
    for i = 1, 2 do
      local p = self.players[i]
      if not p.dead and overlap(e, p) then
        self:hurt(p, d.dmg, nil, (p.x >= e.x) and 1 or -1)
      end
    end
  end
  -- zumbi queima de dia
  if k == "Z" and self:dark() < 0.3 and e.y < self.surf[colof(e.x)] + 1 then
    e.burn = e.burn + 1
    if e.burn % 40 == 0 then e.hp = e.hp - 1 end
  end
  if self:inlava(e) then
    e.lv = e.lv + 1
    if e.lv % 15 == 0 then e.hp = e.hp - 2 end
  end
  if e.hp <= 0 then return true end
  return false
end

function Core:spawner()
  if #self.mobs >= Core.MAXMOBS or self.creative then return end
  local night = self:dark() >= 0.6
  for i = 1, 2 do
    local p = self.players[i]
    if not p.dead then
      local side = (self:rnd(0, 1) == 0) and -1 or 1
      local tx = math.floor(p.x) + side * self:rnd(10, 20)
      if tx >= 1 and tx <= Core.W - 2 then
        local ps = self.surf[colof(p.x)]
        if p.y < ps + 6 then
          if night and self:rnd(1, 100) <= 70 then
            local d = Core.MOB.Z
            local y = self.surf[tx + 1] - d.h - 0.01
            if not self:hit(tx + 0.5, y, d.w, d.h) then self:addmob("Z", tx + 0.5, y) end
          end
        else
          local depth = p.y - ps
          for _ = 1, 8 do
            local ty = math.floor(p.y) + self:rnd(-6, 6)
            if ty >= 2 and ty < Core.H - 2 and not self:solid(tx, ty) and not self:solid(tx, ty - 1)
               and not self:solid(tx, ty - 2) and self:solid(tx, ty + 1) then
              local r = self:rnd(1, 100)
              local kind = "Z"
              if depth > 14 and r <= 35 then kind = "K" elseif r > 70 then kind = "S" end
              local d = Core.MOB[kind]
              local y = ty + 1 - d.h - 0.01
              if not self:hit(tx + 0.5, y, d.w, d.h) then self:addmob(kind, tx + 0.5, y) end
              break
            end
          end
        end
      end
    end
  end
end

-- h1, h2: tabelas {left,right,up,down,mine,place,next,craft} = true/false
function Core:update(h1, h2)
  if self.mode ~= "play" then return end
  self.time = self.time + 1
  self:upd_player(self.players[1], h1)
  if self.mode == "play" then self:upd_player(self.players[2], h2) end
  if self.mode ~= "play" then return end
  for i = #self.mobs, 1, -1 do
    if self:upd_mob(self.mobs[i]) then remove_at(self.mobs, i) end
  end
  for i = #self.arrows, 1, -1 do
    local a = self.arrows[i]
    a.x, a.y, a.life = a.x + a.vx, a.y + a.vy, a.life - 1
    local gone = a.life <= 0 or self:solid(math.floor(a.x), math.floor(a.y))
    if not gone then
      for k = 1, 2 do
        local p = self.players[k]
        if not p.dead and a.x > p.x - p.w / 2 and a.x < p.x + p.w / 2 and a.y > p.y and a.y < p.y + p.h then
          self:hurt(p, 3, nil, (a.vx > 0) and 1 or -1)
          gone = true
        end
      end
    end
    if gone then remove_at(self.arrows, i) end
  end
  if self.time % 60 == 0 then self:spawner() end
end

return Core
