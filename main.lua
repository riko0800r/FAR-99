
local bit32 = require("libs/bit32")

local vm = {
    screen_width = 160,
    screen_height = 120,
    mem_size = 0x10000,  -- 64KB de memória
    
    -- Endereços de memória importantes
    ADDR_SPRITES = 0x4000,
    ADDR_FRAMEBUFFER = 0x8000,
    ADDR_INPUT = 0xFF00,
    ADDR_SOUND_BANK = 0xC000,
    ADDR_SOUND_CTRL = 0xFFF0,
    
    -- Componentes do sistema
    palette = {},
    mem = {},
    input_state = 0,
    draw_color = 7,
    pixels = nil,
    screen = nil,
    
    -- Mapeamento de teclado
    key_map = {
        left = 0x01, right = 0x02, up = 0x04, down = 0x08,
        a = 0x10, b = 0x20, x = 0x40, y = 0x80
    },
    
    -- Sistema de áudio
    audio = {
      samples  = {},
      music    = nil,
      channels = 8,
      sfx_volume   = 1.0,
      music_volume = 1.0
    }
}



-- Funções utilitárias
local function clamp(v, min, max)
    return math.min(math.max(v, min), max)
end

-- Inicialização do sistema
function vm.init()
    vm.init_memory()
    vm.init_palette()
    vm.init_graphics()
end

function vm.init_memory()
    vm.mem = {}
    for i = 0, vm.mem_size - 1 do
        vm.mem[i] = 0
    end
end

function vm.init_palette()
    local colors = {
        {0, 0, 0}, {7, 54, 66}, {88, 110, 117}, {101, 123, 131},
        {131, 148, 150}, {147, 161, 161}, {238, 232, 213}, {253, 246, 227},
        {181, 137, 0}, {203, 75, 22}, {220, 50, 47}, {211, 54, 130},
        {108, 113, 196}, {38, 139, 210}, {42, 161, 152}, {133, 153, 0}
    }
    
    for i = 0, 15 do
        local c = colors[(i % 16) + 1]
        vm.palette[i] = {c[1]/255, c[2]/255, c[3]/255}
    end
end

function vm.init_graphics()
    vm.pixels = love.image.newImageData(vm.screen_width, vm.screen_height)
    vm.screen = love.graphics.newImage(vm.pixels)
    vm.screen:setFilter("nearest", "nearest")
end


-- =====================
-- === MUSICA E SFX ====
-- =====================


function vm.load_sound(sound_id , file_path)
  local sample = love.sound.newSoundData(file_path)
  vm.audio.samples[sound_id] = sample
  print("Som carregado ID : " .. sound_id)
end

function vm.load_music(music_id , file_path)
  vm.audio.music = love.audio.newSource(file_path, "stream")
  vm.audio.music:setLooping(true)
  print("Musica carregada ID : " .. music_id)
end


-- Manipulação de memória
function vm.peek(addr)
    return vm.mem[addr] or 0
end

function vm.poke(addr, value)
    value = bit32.band(value, 0xFF)
    
    if addr >= vm.ADDR_SOUND_CTRL and addr < vm.ADDR_SOUND_CTRL + 0x0F then
        local reg = addr - vm.ADDR_SOUND_CTRL
        local channel = vm.peek(vm.ADDR_SOUND_CTRL + 0x03)
        
        if reg == 0x00 then
            -- controle geral do som
            local music_enable = bit32.band(value,0x01) ~= 0
            local sfx_enable   = bit32.band(value,0x02) ~= 0
            if vm.audio.music then
                vm.audio.music:setVolume(music_enable and vm.audio.music or 0)
            end
            vm.audio.sfx_volume = sfx_enable and 1.0 or 0.0
        end

        if reg == 0x01 then
            -- volume da Musica
            vm.audio.music_volume = value / 255
            if vm.audio.music then
                vm.audio.music:setVolume(vm.sound.music_volume)
            end
        end

        if reg == 0x02 then
            -- volume do SFX
            vm.audio.sfx_volume = value / 255
        end

        if reg == 0x04 then
            -- executar comando
            local sound_id = vm.peek(vm.ADDR_SOUND_CTRL + 0x05)
            if value == 1 then
                if vm.audio.samples[sound_id] then
                    local source = love.audio.newSource(vm.audio.samples[sound_id],"static")
                    source:setVolume(vm.audio.sfx_volume)
                    source:play()
                end
            end
        end
    else
        vm.mem[addr] = value
    end
end

-- Funções gráficas
function vm.px(x, y, color)
    if x >= 0 and x < vm.screen_width and y >= 0 and y < vm.screen_height then
        vm.mem[vm.ADDR_FRAMEBUFFER + y * vm.screen_width + x] = bit32.band(color or vm.draw_color, 0x0F)
    end
end

function vm.cls()
    for i = vm.ADDR_FRAMEBUFFER, vm.ADDR_FRAMEBUFFER + vm.screen_width * vm.screen_height do
        vm.mem[i] = 0
    end
end

function vm.spr(sprite_id, x, y, flip_x, flip_y)
    local base = vm.ADDR_SPRITES + sprite_id * 256
    for sy = 0, 15 do
        for sx = 0, 15 do
            local color = vm.peek(base + sy * 16 + sx)
            if color ~= 0 then
                local dx = flip_x and (15 - sx) or sx
                local dy = flip_y and (15 - sy) or sy
                vm.px(x + dx, y + dy, color)
            end
        end
    end
end

function vm.line(x1, y1, x2, y2)
    local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
    local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
    local err = dx - dy

    while true do
        vm.px(x1, y1)
        if x1 == x2 and y1 == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then 
            err = err - dy
            x1 = x1 + sx 
        end
        if e2 < dx then 
            err = err + dx 
            y1 = y1 + sy 
        end
    end
end

function vm.load_spr(sprite_id,image_path)
    local function find_color(r,g,b)
      local min_dist   = math.huge
      local best_index = 0
        
      for i=0,15 do
        local color = vm.palette[i]
        local dr    = r - color[1]
        local dg    = g - color[2]
        local db    = b - color[3]
          
        local dist = dr*dr + dg*dg +db*db
          
        if dist < min_dist then
          min_dist = dist
          best_index = i
        end
      end
      return best_index
    end
    local success, img_data = pcall(love.image.newImageData,image_path)
    if not success then
      print("ERRO: erro ao carregar imagem: ", img_data)
      return
    end
    
    if img_data:getWidth() ~= 16 or img_data:getHeight() ~= 16 then
      print("ERRO: A imagem deve ser 16x16 pixels!")
      return
    end
    
    local base_addr = vm.ADDR_SPRITES + sprite_id * 256
    for y = 0,15 do
      for x = 0,15 do
        local r,g,b,a = img_data:getPixel(x,y)
        if a < 0.5 then
          vm.poke(base_addr + y * 16 + x, 0)
        else
          local color_index = find_color(r,g,a)
          vm.poke(base_addr + y * 16 + x, color_index)
        end
      end
    end
end

function vm.rect(x, y, w, h, filled)
    if filled then
        for j = y, y + h - 1 do
            for i = x, x + w - 1 do
                vm.px(i, j)
            end
        end
    else
        for i = x, x + w - 1 do
            vm.px(i, y)
            vm.px(i, y + h - 1)
        end
        for j = y, y + h - 1 do
            vm.px(x, j)
            vm.px(x + w - 1, j)
        end
    end
end

function vm.circ(xc, yc, r)
    local x, y, err = r, 0, 0
    while x >= y do
        vm.px(xc + x, yc + y)
        vm.px(xc + y, yc + x)
        vm.px(xc - y, yc + x)
        vm.px(xc - x, yc + y)
        vm.px(xc - x, yc - y)
        vm.px(xc - y, yc - x)
        vm.px(xc + y, yc - x)
        vm.px(xc + x, yc - y)
        y = y + 1
        err = err + (1 + 2 * y)
        if 2 * (err - x) + 1 > 0 then
            x = x - 1
            err = err + 1 - 2 * x
        end
    end
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

-- API para jogos
function vm.expose_api()
    api = {
        cls = vm.cls,
        px = vm.px,
        spr = vm.spr,
        line = vm.line,
        rect = vm.rect,
        circ = vm.circ,
        color = function(c) vm.draw_color = bit32.band(c, 0x0F) end,
        peek = vm.peek,
        poke = vm.poke,
        btn = function(key)
            return (bit32.band(vm.input_state, vm.key_map[key] or 0)) ~= 0
        end,
        load_spr = vm.load_spr,

        -- som
        load_sfx = vm.load_sound,
        load_music = vm.load_music,
        play_music = function ()
            if vm.audio.music then
                vm.audio.music:play()
            end
        end,
        stop_music = function()
            if vm.audio.music then
                vm.audio.music:stop()
            end
        end,
        play_sfx = function (sfx_id)
            if vm.audio.samples[sfx_id] then
                local src = love.audio.newSource(vm.audio.samples[sfx_id], "static")
                src:setVolume(vm.audio.sfx_volume)
                src:play()
            end
        end
    }
    api.love = {
        load = love.load,
        update = love.update,
        draw = love.draw,
        key_pressed = love.keypressed,
    }
    
    return api
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
    shader:send("resolution", {160*4, 120*4})
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
