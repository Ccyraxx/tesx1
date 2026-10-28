-- bq_app.lua : telas (titulo -> jogo -> fim). Sem LOVE.
local Core = require("bq_core")
local App = {}
App.__index = App
App.LOCK = 45   -- quadros ignorando "ok" apos o fim

-- menu: 1/2 jogadores (esquerda/direita) e cmode: 1 sobrevivencia / 2 criativo (cima/baixo)
function App.new()
  return setmetatable({ screen = "title", game = nil, over_at = nil, menu = 2, cmode = 1, dim = 1, row = 1 }, App)
end

-- CIMA/BAIXO escolhe a linha (jogadores / modo / visao); ESQUERDA/DIREITA muda a opcao
function App:nav(dx, dy)
  if self.screen ~= "title" then return end
  if dy ~= 0 then self.row = math.max(1, math.min(3, self.row + dy)) end
  if dx ~= 0 then
    local v = (dx < 0) and 1 or 2
    if self.row == 1 then self.menu = v elseif self.row == 2 then self.cmode = v else self.dim = v end
  end
end

function App:pick(n)
  if self.screen == "title" then self.menu = n end
end

-- escolhe a casa (1-9) da barra do jogador pid
function App:slot(pid, n)
  if self.screen == "play" and self.game then self.game:select(self.game.players[pid], n) end
end

-- criativo nao tem fim: volta ao titulo por aqui
function App:back()
  if self.screen == "play" and self.game and self.game.creative then
    self.screen, self.game, self.over_at = "title", nil, nil
  end
end

function App:ok(frame)
  if self.screen == "title" then
    local mod = Core
    if self.dim == 2 then mod = require("q3_core") end   -- 3D: so carrega quando pedido
    self.game = mod.new((frame or 1) * 7919 + 13, self.menu, self.cmode == 2)
    self.screen, self.over_at = "play", nil
  elseif self.game.mode == "win" and self.over_at and (frame or 0) - self.over_at >= App.LOCK then
    self.screen, self.game = "title", nil
  end
end

function App:update(frame, h1, h2)
  if self.screen ~= "play" then return end
  local g = self.game
  g:update(h1, h2)
  if g.mode == "win" and not self.over_at then self.over_at = frame end
end

return App
