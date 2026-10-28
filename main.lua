-- BLOCK QUEST para o console Lupi (2D, 1 ou 2 jogadores, sobrevivencia ou criativo).
-- Os modulos bq_core, bq_app e bq_view sao Lua puro e iguais aos da versao do computador.
-- Este arquivo e so o "adaptador" da SDK: desenho (ui.*), botoes (ui.btn) e paleta DB32.
-- Se algo falhar, o erro aparece na TELA (em vez de tela preta).
require "palette"
require "sprites"

local W, H = 480, 270
local floor = math.floor
local App, View, app          -- carregados no primeiro quadro, dentro de pcall
local crashed = nil
local ready = false

-- pcall e a unica coisa "extra" que este arquivo supoe da biblioteca padrao
local safe = pcall or function(f, ...) return true, f(...) end

-- ================================================================ BOTOES (EDITE AQUI)
-- Cada entrada e uma funcao que devolve a constante da SDK. Assim, se uma constante nao
-- existir (ou a SDK barrar variavel global desconhecida), so aquele botao fica indisponivel.
-- Jogador 1 (usa o que o Tetris ja usa) e jogador 2 (SUPOSICAO: botoes de letra BTN_<LETRA>).
local NAMES = { "left", "right", "up", "down", "mine", "place", "next", "craft" }
local P1 = {
  left  = function() return LEFT end,  right = function() return RIGHT end,
  up    = function() return UP end,    down  = function() return DOWN end,
  mine  = function() return BTN_Z end, place = function() return BTN_X end,
  next  = function() return BTN_F end, craft = function() return BTN_G end,
}
local P2 = {   -- J2: A D andar, W pular, S baixo, Q minera, E coloca, R troca item, T criar
  left  = function() return BTN_A end, right = function() return BTN_D end,
  up    = function() return BTN_W end, down  = function() return BTN_S end,
  mine  = function() return BTN_Q end, place = function() return BTN_E end,
  next  = function() return BTN_R end, craft = function() return BTN_T end,
}
local P2_LABEL = { left = "A", right = "D", up = "W", down = "S", mine = "Q", place = "E", next = "R", craft = "T" }

local map1, map2, p2ok, missing2 = {}, {}, true, ""

local function resolve_buttons()
  for i = 1, #NAMES do
    local n = NAMES[i]
    local ok1, v = safe(P1[n])
    local ok2, w = safe(P2[n])
    if not ok1 or type(v) ~= "number" then v = nil end   -- erro/nao-numero => botao indisponivel
    if not ok2 or type(w) ~= "number" then w = nil end
    map1[n], map2[n] = v, w
    if w == nil then
      p2ok = false
      if #missing2 < 40 then missing2 = missing2 .. " " .. P2_LABEL[n] end
    end
  end
end

local function read_buttons(map, h)
  for i = 1, #NAMES do
    local n = NAMES[i]
    local b, on = map[n], false
    if b ~= nil then
      local r = ui.btn(b)
      on = (r ~= nil and r ~= false and r ~= 0)
    end
    h[n] = on
  end
end

-- ================================================================ CORES (paleta DB32)
-- O jogo pensa em RGB livre (0xRRGGBB); a tela so tem a paleta DB32 (db32.png).
-- Para cada cor pedimos a mais parecida da DB32 e convertemos com Palette.hex.
local DB32 = {
  0x000000, 0x222034, 0x45283c, 0x663931, 0x8f563b, 0xdf7126, 0xd9a066, 0xeec39a,
  0xfbf236, 0x99e550, 0x6abe30, 0x37946e, 0x4b692f, 0x524b24, 0x323c39, 0x3f3f74,
  0x306082, 0x5b6ee1, 0x639bff, 0x5fcde4, 0xcbdbfc, 0xffffff, 0x9badb7, 0x847e87,
  0x696a6a, 0x595652, 0x76428a, 0xac3232, 0xd95763, 0xd77bba, 0x8f974a, 0x8a6f30,
}
local DR, DG, DB = {}, {}, {}
for i = 1, #DB32 do
  local c = DB32[i]
  DR[i], DG[i], DB[i] = floor(c / 65536), floor(c / 256) % 256, c % 256
end

local cache, ncache = {}, 0
local function color(rgb)
  local idx = cache[rgb]
  if idx then return idx end
  local r, g, b = floor(rgb / 65536), floor(rgb / 256) % 256, rgb % 256
  local best, bestd = 1, 1e9
  for i = 1, #DB32 do
    local dr, dg, db = r - DR[i], g - DG[i], b - DB[i]
    local d = dr * dr + dg * dg + db * db
    if d < bestd then best, bestd = i, d end
  end
  idx = Palette.hex(DB32[best])
  if ncache >= 1500 then cache, ncache = {}, 0 end   -- limita a memoria
  cache[rgb] = idx
  ncache = ncache + 1
  return idx
end

-- ================================================================ DESENHO
-- ui.rect/rectfill recebem os dois cantos (inclusivos, como no ov_render do Tetris).
local gfx = {
  clear = function(rgb) ui.cls(color(rgb)) end,
  fill = function(x, y, w, h, rgb)
    if w > 0 and h > 0 then ui.rectfill(x, y, x + w - 1, y + h - 1, color(rgb)) end
  end,
  box = function(x, y, w, h, rgb)
    if w > 0 and h > 0 then ui.rect(x, y, x + w - 1, y + h - 1, color(rgb)) end
  end,
  text = function(s, x, y, rgb) ui.print(s, x, y, color(rgb)) end,
  clip = function(x, y, w, h) ui.clip(x, y, w, h) end,
  noclip = function() ui.clip(0, 0, W, H) end,
}

local GOLD, DIM, WHITE, LINE, ACCENT, RED, INK = 0xfbf236, 0x9badb7, 0xffffff, 0x595652, 0x5fcde4, 0xd95763, 0x222034

local function center(s, y, c)
  gfx.text(s, floor((W - #s * 8) / 2), y, c)
end

-- tela de erro: mostra a mensagem (quebrada em linhas de 56 caracteres) em vez de tela preta
local function draw_error(msg, frame)
  gfx.clear(0x000000)
  gfx.text("BLOCK QUEST - ERRO", 12, 12, RED)
  gfx.text("COPIE ESTA MENSAGEM E MANDE PARA O ASSISTENTE:", 12, 26, DIM)
  local done = safe(function()
    local y, i, n = 44, 1, #msg
    while i <= n and y < 250 do
      local j = i + 55            -- quebra em 56 colunas
      if j > n then j = n end
      gfx.text(msg:sub(i, j), 12, y, WHITE)
      y, i = y + 10, j + 1
    end
  end)
  if not done then ui.print(msg, 12, 44, color(WHITE)) end
end

-- ================================================================ TEXTOS DO CONSOLE
local function setup_texts()
  View.lite = true                                    -- menos chamadas de desenho por quadro
  View.back_hint = "G: VOLTAR AO MENU"
  View.menu_hint[1] = "Z: CRIAR   G: FECHAR"
  View.menu_hint[2] = "Q: CRIAR   T: FECHAR"

  View.title = function(_g, frame, menu, cmode, _dim, row)
    gfx.box(8, 8, W - 16, H - 16, LINE)
    center("BLOCK QUEST", 18, GOLD)
    center("MINI-MINECRAFT 2D PARA O LUPI", 32, DIM)
    center("ACHE 5 DIAMANTES E VENCA!", 46, WHITE)
    gfx.text("JOGADOR 1", 40, 62, ACCENT)
    gfx.text("SETAS MOVER (CIMA PULA)   Z MINERAR/ATACAR", 40, 72, WHITE)
    gfx.text("X COLOCAR/COMER   F TROCAR ITEM   G CRIAR", 40, 82, WHITE)
    gfx.text("BAIXO/CIMA + Z/X = CAVAR/COLOCAR EM BAIXO/CIMA", 40, 92, DIM)
    if menu == 2 then
      gfx.text("JOGADOR 2", 40, 106, RED)
      gfx.text("A D MOVER (W PULA)   Q MINERAR/ATACAR", 40, 116, WHITE)
      gfx.text("E COLOCAR/COMER   R TROCAR ITEM   T CRIAR", 40, 126, WHITE)
      if not p2ok then
        gfx.text("J2 INDISPONIVEL. FALTAM BOTOES:" .. missing2, 40, 138, RED)
      end
    end
    center("ARVORE > PICARETA > PEDRA > FERRO > DIAMANTE", 156, DIM)
    center("NOITE: ZUMBIS. CAVERNAS: ESQUELETOS E LAVA", 166, DIM)
    gfx.fill(60, 180, 360, 34, INK)
    gfx.box(60, 180, 360, 34, LINE)
    local rows = { { "1 JOGADOR", "2 JOGADORES", menu }, { "SOBREVIVENCIA", "CRIATIVO", cmode } }
    for r = 1, 2 do
      local y = 186 + (r - 1) * 14
      local sel = rows[r][3]
      if row == r then gfx.text(">", 72, y, GOLD) end
      gfx.text((sel == 1 and "* " or "  ") .. rows[r][1], 100, y, (sel == 1) and GOLD or DIM)
      gfx.text((sel == 2 and "* " or "  ") .. rows[r][2], 260, y, (sel == 2) and GOLD or DIM)
    end
    if cmode == 2 then
      center("CRIATIVO: VOE, BLOCOS INFINITOS. G VOLTA AO MENU", 222, WHITE)
    else
      center("SOBREVIVENCIA: MONSTROS, CRIAR E 5 DIAMANTES", 222, WHITE)
    end
    if floor(frame / 30) % 2 == 0 then center("CIMA/BAIXO: LINHA  ESQ/DIR: OPCAO  Z: INICIAR", 242, GOLD) end
  end
end

-- ================================================================ LOOP
local held1, held2, prev = {}, {}, {}
local function pressed(name)
  local now = held1[name]
  local p = now and not prev[name]
  prev[name] = now
  return p
end

local function boot()
  App, View = require("bq_app"), require("bq_view")
  resolve_buttons()
  setup_texts()
  app = App.new()
  app.menu, app.dim, app.row = 1, 1, 2      -- 1 jogador, visao 2D; linha do modo selecionada
  ready = true
end

local function step(frame)
  read_buttons(map1, held1)
  read_buttons(map2, held2)
  local z, l, r, g = pressed("mine"), pressed("left"), pressed("right"), pressed("craft")
  local u, d, f = pressed("up"), pressed("down"), pressed("next")
  pressed("place")

  if app.screen == "title" then
    app.dim = 1
    if u or f then app.row = 1 end          -- F tambem sobe/desce a linha (para quem nao tem CIMA)
    if d then app.row = 2 end
    if l then app:nav(-1, 0) end
    if r then app:nav(1, 0) end
    app.dim = 1
  end
  if z and not (app.screen == "title" and app.menu == 2 and not p2ok) then app:ok(frame) end
  if g then app:back() end                  -- no criativo, G volta ao titulo

  app:update(frame, held1, held2)
  View.draw(app, gfx, frame)
end

function loop(frame)
  for i = 1, #Palette do ui.palset(i - 1, Palette[i]) end
  ui.clip(0, 0, W, H)
  ui.camera(0, 0)
  if crashed then draw_error(crashed, frame); return end
  local ok, err
  if not ready then
    ok, err = safe(boot)
    if not ok then crashed = tostring(err); draw_error(crashed, frame); return end
  end
  ok, err = safe(step, frame)
  if not ok then crashed = tostring(err); draw_error(crashed, frame) end
end
