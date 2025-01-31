
local bit32 = require("libs/bit32")

local vm = {
    screen_width = 160,
    screen_height = 120,
    mem_size = 0x10000,  -- 64KB de memória
    
    -- Endereços de memória importantes
    ADDR_SPRITES = 0x4000,
    ADDR_FRAMEBUFFER = 0x8000,
    ADDR_INPUT = 0xFF00,
    ADDR_AUDIO = 0xA000,
    
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
        channels = {},
        waveforms = {SQUARE = 0, TRIANGLE = 1, SAWTOOTH = 2, NOISE = 3},
        sample_rate = 44100,
        master_volume = 0.5,
        noise_generator = 0,
        source = nil
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
    vm.init_audio()
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

function vm.init_audio()
    for i = 1, 8 do
        vm.audio.channels[i] = {
            frequency = 0, volume = 0, waveform = 0,
            duty = 0.5, enabled = false, phase = 0
        }
    end
    vm.audio.source = love.audio.newQueueableSource(
        vm.audio.sample_rate, 16, 1, 4096
    )
    vm.audio.source:play()
end

-- Manipulação de memória
function vm.peek(addr)
    return vm.mem[addr] or 0
end

function vm.poke(addr, value)
    value = bit32.band(value, 0xFF)
    
    if addr >= vm.ADDR_AUDIO and addr < vm.ADDR_AUDIO + 0x80 then
        vm.handle_audio_register(addr, value)
    else
        vm.mem[addr] = value
    end
end

function vm.handle_audio_register(addr, value)
    local channel_num = math.floor((addr - vm.ADDR_AUDIO) / 16) + 1
    local register = (addr - vm.ADDR_AUDIO) % 16
    
    if channel_num < 1 or channel_num > 8 then return end
    
    local channel = vm.audio.channels[channel_num]
    
    if register == 0 then
        channel.enabled = bit32.band(value, 0x80) ~= 0
        channel.waveform = bit32.rshift(bit32.band(value, 0x60), 5)
        channel.duty = ({0.125, 0.25, 0.5, 0.75})[bit32.rshift(bit32.band(value, 0x18), 3) + 1] or 0.5
    elseif register == 1 then
        channel.volume = bit32.band(value, 0x0F)
    elseif register == 2 then
        channel.frequency = bit32.bor(bit32.band(channel.frequency, 0xFF00), value)
    elseif register == 3 then
        channel.frequency = bit32.bor(bit32.lshift(value, 8), bit32.band(channel.frequency, 0x00FF))
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

-- Sistema de áudio
function vm.generate_waveform(channel)
    local phase_inc = channel.frequency / vm.audio.sample_rate
    channel.phase = (channel.phase + phase_inc) % 1

    if channel.waveform == vm.audio.waveforms.SQUARE then
        return channel.phase < channel.duty and 1 or -1
    elseif channel.waveform == vm.audio.waveforms.TRIANGLE then
        return 2 * math.abs(2 * channel.phase - 1) - 1
    elseif channel.waveform == vm.audio.waveforms.SAWTOOTH then
        return 2 * channel.phase - 1
    elseif channel.waveform == vm.audio.waveforms.NOISE then
        vm.audio.noise_generator = bit32.bxor(
            bit32.lshift(vm.audio.noise_generator, 1),
            bit32.band(bit32.rshift(vm.audio.noise_generator, 7), 1) * 0x80
        )
        return (vm.audio.noise_generator / 255) * 2 - 1
    end
    return 0
end

function vm.update_audio(dt)
    local free_buffers = vm.audio.source:getFreeBufferCount()
    if free_buffers > 0 then
      local samples_needed = vm.audio.source:getFreeBufferCount() * 4096
      local sample_data = love.sound.newSoundData(samples_needed, vm.audio.sample_rate, 16, 1)

      for i = 0, samples_needed - 1 do
          local mixed = 0
          for ch = 1, 8 do
              local channel = vm.audio.channels[ch]
              if channel.enabled then
                  mixed = mixed + (vm.generate_waveform(channel) * (channel.volume / 15))
              end
          end
          sample_data:setSample(i, clamp(mixed * vm.audio.master_volume, -1, 1))
      end
      vm.audio.source:queue(sample_data)
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
        play_note = function(ch, freq, vol, wave)
            if ch < 1 or ch > 8 then return end
            local c = vm.audio.channels[ch]
            c.frequency = freq
            c.volume = vol or 15
            c.waveform = wave or 0
            c.enabled = true
        end,
        stop_note = function(ch)
            if vm.audio.channels[ch] then
                vm.audio.channels[ch].enabled = false
            end
        end,
        peek = vm.peek,
        poke = vm.poke,
        btn = function(key)
            return (bit32.band(vm.input_state, vm.key_map[key] or 0)) ~= 0
        end,
        load_spr = vm.load_spr
    }
    api.love = {
        load = love.load,
        update = love.update,
        draw = love.draw
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
    
end

function love.update(dt)
    vm.poke(vm.ADDR_INPUT, vm.input_state)
    vm.update_audio(dt)
    if vm.update then vm.update(dt) end
end

function love.draw()
    if vm.draw then vm.draw() end
    vm.pixels:mapPixel(function(x, y)
        local color = vm.peek(vm.ADDR_FRAMEBUFFER + y * vm.screen_width + x) % 16
        return unpack(vm.palette[color])
    end)
    vm.screen:replacePixels(vm.pixels)
    love.graphics.draw(vm.screen, 0, 0, 0, 4, 4)
end
