local bit32 = require("libs/bit32")

local vm = {
    screen_width = 160,
    screen_height = 120,
    mem_size = 0x10000,
    palette = {},
    input_state = 0,
    draw_color = 7,
    mem = {},
    key_map = {
        left = 0x01, right = 0x02, up = 0x04, down = 0x08,
        a = 0x10, b = 0x20, x = 0x40, y = 0x80
    },
    ADDR_SPRITES = 0x4000,
    ADDR_FRAMEBUFFER = 0x8000,
    ADDR_INPUT = 0xFF00,
    ADDR_AUDIO = 0xA000,
    pixels = nil,
    screen = nil,
    audio = {
        channels = {},
        waveforms = {SQUARE = 0, TRIANGLE = 1, SAWTOOTH = 2, NOISE = 3},
        sample_rate = 44100,
        master_volume = 0.5,
        noise_generator = 0,
        source = nil
    }
}

vm.clamp = function(v, min, max) return math.min(math.max(v, min), max) end

function vm.init()
    vm.mem = {}
    for i = 0, vm.mem_size - 1 do
        vm.mem[i] = 0
    end

    local colors = {
        {0, 0, 0}, {29, 43, 83}, {126, 37, 83}, {0, 135, 81},
        {171, 82, 54}, {95, 87, 79}, {194, 195, 199}, {255, 241, 232},
        {255, 0, 77}, {255, 163, 0}, {255, 236, 39}, {0, 228, 54},
        {41, 173, 255}, {131, 118, 156}, {255, 119, 168}, {255, 204, 170}
    }
    for i = 0, 15 do
        local r, g, b = unpack(colors[(i % 16) + 1])
        vm.palette[i] = {r / 255, g / 255, b / 255}
    end

    vm.pixels = love.image.newImageData(vm.screen_width, vm.screen_height)
    vm.screen = love.graphics.newImage(vm.pixels)
    vm.screen:setFilter("nearest", "nearest")

    vm.init_audio()
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

function vm.update_audio(dt)
    local samples_needed = vm.audio.source:getFreeBufferCount() * 4096
    local sample_data = love.sound.newSoundData(samples_needed, vm.audio.sample_rate, 16, 1)

    for i = 0, samples_needed - 1 do
        local mixed = 0
        for ch = 1, 8 do
            local c = vm.audio.channels[ch]
            if c.enabled then
                local value = 0
                local phase_inc = c.frequency / vm.audio.sample_rate

                if c.waveform == vm.audio.waveforms.SQUARE then
                    c.phase = (c.phase + phase_inc) % 1
                    value = c.phase < c.duty and 1 or -1
                elseif c.waveform == vm.audio.waveforms.TRIANGLE then
                    c.phase = (c.phase + phase_inc) % 1
                    value = 2 * math.abs(2 * c.phase - 1) - 1
                elseif c.waveform == vm.audio.waveforms.SAWTOOTH then
                    c.phase = (c.phase + phase_inc) % 1
                    value = 2 * c.phase - 1
                elseif c.waveform == vm.audio.waveforms.NOISE then
                    vm.audio.noise_generator = bit32.bxor(
                        bit32.lshift(vm.audio.noise_generator, 1),
                        bit32.band(bit32.rshift(vm.audio.noise_generator, 7), 1) * 0x80
                    )
                    value = (vm.audio.noise_generator / 255) * 2 - 1
                end

                mixed = mixed + (value * (c.volume / 15))
            end
        end
        sample_data:setSample(i, vm.clamp(mixed * vm.audio.master_volume, -1, 1))
    end
    vm.audio.source:queue(sample_data)
end

function vm.peek(addr)
    return vm.mem[addr] or 0
end

function vm.poke(addr, value)
    value = bit32.band(value, 0xFF)

    if addr >= vm.ADDR_AUDIO and addr <= vm.ADDR_AUDIO + 0x7F then
        local ch = math.floor((addr - vm.ADDR_AUDIO) / 16) + 1
        local reg = (addr - vm.ADDR_AUDIO) % 16

        if ch >= 1 and ch <= 8 then
            local c = vm.audio.channels[ch]
            if reg == 0 then
                c.enabled = bit32.band(value, 0x80) ~= 0
                c.waveform = bit32.rshift(bit32.band(value, 0x60), 5)
                c.duty = ({0.125, 0.25, 0.5, 0.75})[bit32.rshift(bit32.band(value, 0x18), 3) + 1] or 0.5
            elseif reg == 1 then
                c.volume = bit32.band(value, 0x0F)
            elseif reg == 2 then
                c.frequency = bit32.bor(bit32.band(c.frequency, 0xFF00), value)
            elseif reg == 3 then
                c.frequency = bit32.bor(bit32.lshift(value, 8), bit32.band(c.frequency, 0x00FF))
            end
        end
    else
        vm.mem[addr] = value
    end
end

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

function love.keypressed(key)
    local mask = vm.key_map[key]
    if mask then vm.input_state = bit32.bor(vm.input_state, mask) end
end

function love.keyreleased(key)
    local mask = vm.key_map[key]
    if mask then vm.input_state = bit32.band(vm.input_state, bit32.bnot(mask)) end
end

function love.load()
    vm.init()
    local game = love.filesystem.load("game.lua")
    if game then setfenv(game, vm.expose_api()) end
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

function vm.expose_api()
    return {
        cls = vm.cls, px = vm.px, spr = vm.spr,
        line = vm.line, rect = vm.rect, circ = vm.circ,
        color = function(c) vm.draw_color = bit32.band(c, 0x0F) end,
        play_note = function(ch, freq, vol, wave)
            if ch < 1 or ch > 8 then return end
            local c = vm.audio.channels[ch]
            c.frequency = freq; c.volume = vol or 15
            c.waveform = wave or 0; c.enabled = true
        end,
        stop_note = function(ch) if vm.audio.channels[ch] then vm.audio.channels[ch].enabled = false end end,
        peek = vm.peek, poke = vm.poke,
        btn = function(key) return (vm.input_state and vm.key_map[key]) ~= 0 end
    }
end
