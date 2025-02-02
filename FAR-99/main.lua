
local bit32 = require("libs/bit32")
local vm = require("libs/vm")


-- Funções utilitárias
local function clamp(v, min, max)
    return math.min(math.max(v, min), max)
end

-- Input handling
function love.keypressed(key)
    local mask = vm.key_map[key]
    if mask then vm.input_state = bit32.bor(vm.input_state, mask) end
end

function love.keyreleased(key)
    local mask = vm.key_map[key]
    if mask then vm.input_state = bit32.band(vm.input_state, bit32.bnot(mask)) end
end


-- Funções principais do LÖVE
function love.load()
    vm.init()
    local game_chunk,error_msg = love.filesystem.load("game.lua")
    
    if not game_chunk then
        error("Failed to load game.lua")
    end
    
    local game_env = setmetatable({},{
        __index = function(_,k)
            return vm.expose_api()[k] or _G[k]
        end,
        __newindex = function(t,k,v)
            rawset(t,k,v)
        end
    })
    
    setfenv(game_chunk,game_env)
    
    pcall(game_chunk)
    
    if game_env.load then
        game_env.load()
        vm.load = game_env.load()
    end
    
    if game_env.update then
       vm.update = game_env.update
    end
    
    if game_env.update then
       vm.draw = game_env.draw
    end
  
 shaderCode = [[
      extern number time;
      extern vec2 resolution;

      vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
          // Coordenadas normalizadas
          vec2 uv = screen_coords / resolution;

          // Distorção de barril para simular curvatura
          vec2 center = uv - 0.5;
          float radius = length(center);
          center *= 1.0 + 0.2 * radius * radius;
          uv = center + 0.5;

          // Verifica se está fora da tela (bordas escuras)
          if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
              return vec4(0.0, 0.0, 0.0, 1.0);
          }

          // Amostra a textura original
          vec4 texColor = Texel(texture, uv);

          // Linhas de varredura horizontais
          float scanline = sin(uv.y * resolution.y * 2.0) * 0.1 + 0.9;
          texColor.rgb *= scanline;

          // Tremulação de brilho
          texColor.rgb *= 0.95 + 0.05 * sin(time * 2.0);

          return texColor * color;
      }
  ]]
  shader = love.graphics.newShader(shaderCode)
end

local time = 0

function love.update(dt)
    vm.poke(vm.ADDR_INPUT, vm.input_state)
    if vm.update then vm.update(dt) end
    time = time + dt
    shader:send("time", time)
    shader:send("resolution", {vm.screen_width*2, vm.screen_height*2})
end

function love.draw()
    love.graphics.setShader(shader)
    if vm.draw then vm.draw() end
    vm.pixels:mapPixel(function(x, y)
        local color = vm.peek(vm.ADDR_FRAMEBUFFER + y * vm.screen_width + x) % 16
        return unpack(vm.palette[color])
    end)
    vm.screen:replacePixels(vm.pixels)
    love.graphics.draw(vm.screen, 0, 0, 0, 4, 4)
end