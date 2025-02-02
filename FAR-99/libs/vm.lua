-- =================================
-- ======== VM =====================
-- =================================

local bit32 = require("libs/bit32")

vm = {
    screen_width = 256,
    screen_height = 224,
    mem_size = 0x20000,  -- 128KB de memória

    -- Endereços de memória importantes

    ADDR_SPRITES = 0x4000,
    ADDR_FRAMEBUFFER = 0x8000,
    ADDR_INPUT = 0xFF00,
    ADDR_SOUND_BANK = 0xC000,
    ADDR_SOUND_CTRL = 0xFFF0,
    
    -- filesystem

    FS_START = 0x10000,
    FS_HEADER_SIZE = 512,
    File_types = {
        TXT = 0x01,
        LUA = 0x02,
        PNG = 0x03,
        WAV = 0x04,
    },

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

-- =================================
-- ======== FILE SYSTEM ============
-- =================================


local bit32 = require("libs/bit32")

vm.filesystem = {
    entries = {},
    next_address = vm.FS_START + vm.FS_HEADER_SIZE,
}

function vm.init_fs()
   vm.mem[vm.FS_START] = 0x46   -- F
   vm.mem[vm.FS_START+1] = 0x53 -- S
   vm.mem[vm.FS_START+2] = 0x56 -- V
   vm.mem[vm.FS_START+3] = 0x31 -- 1
   vm.mem[vm.FS_START+4] = 0x01 -- versão 1 
   vm.mem[vm.FS_START+5] = 0x00
   vm.mem[vm.FS_START+6] = 0x00 -- numero de arquivos 
   vm.mem[vm.FS_START+7] = 0x00 
end

function vm.fs_create(filename,filetype,data)
    local required = #data + 16
    if (vm.filesystem.next_address + required) >= vm.mem_size then
        return false, "Sem Espaço disponivel!"
    end

    local entry = {
        name = filename,
        type = filetype,
        address = vm.filesystem.next_address,
        size    = #data,
        created = os.time()
    }

    vm.mem[entry.address] = bit32.band(filetype, 0xFF)
    vm:fs_write_string(entry.address+1,filename,12)
    vm:fs_write_int(entry.address+13,entry.size,3)

    for i=1, #data do
        vm.mem[entry.address+15+i] = data:byte(i)
    end

    vm.filesystem.entries[filename] = entry
    vm.filesystem.next_address = entry.address+15
    vm:fs_update_header()

    return true
end


function vm.fs_read(filename)
    local entry = vm.filesystem.entries[filename]

    if not entry then
        return nil
    end

    local data = ""

    for i=entry.address,entry.address+15 + entry.size do
        data = data.. string.char(vm.mem[i] or 0)
    end

    return {
        type = entry.type,
        data = data,
        size = entry.size,
        created = entry.created,
    }
end

function vm.fs_delete(filename)
    local entry = vm.filesystem.entries[filename] 
    if not entry then 
        return false
    end

    -- zerar a memoria

    for i = entry.address, entry.address+15+entry.size do
       vm.mem[i] = 0 
    end

    vm.filesystem.entries[filename] = nil
    vm:fs_update_header()
    return true
end


-- Funções auxiliares

function vm:fs_write_string(addr,str,max_len)
    for i=0 , max_len-1 do
        vm.mem[addr + i] = str:byte(i+1) or 0
    end
end

function vm:fs_write_int(addr,num,bytes)
    for i = 0, bytes-1 do
        vm.mem[addr + i] = bit32.band(bit32.rshift(num,8*i) , 0xFF)
    end
end

function vm:fs_update_header()
    local num_files = 0
    for i in pairs(vm.filesystem.entries) do
        num_files = num_files + 1
    end
    vm.mem[vm.FS_START+6] = bit32.band(num_files,0xFF)
    vm.mem[vm.FS_START+6] = bit32.band(bit32.rshift(num_files,8),0xFF)
end

-- =================================
-- ======== VM =====================
-- =================================

-- init the system!
function vm.init()
    vm.init_memory()
    vm.init_palette()
    vm.init_graphics()
    vm.init_fs()
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
                vm.audio.music:setVolume(vm.audio.music_volume)
            end
            vm.audio.sfx_volume = sfx_enable and 1.0 or 0.0
        end

        if reg == 0x01 then
            -- volume da Musica
            vm.audio.music_volume = value / 255
            if vm.audio.music then
                vm.audio.music:setVolume(vm.audio.music_volume)
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

function vm.cls(color)
    for i = vm.ADDR_FRAMEBUFFER, vm.ADDR_FRAMEBUFFER + vm.screen_width * vm.screen_height do
        vm.mem[i] = color or 0
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

-- API para cartuchos (ROM)
function vm.expose_api()
    api = {
        cls = vm.cls,
        px = vm.px,
        spr = vm.spr,
        line = vm.line,
        rect = vm.rect,
        circ = vm.circ,
        color = function(c) vm.draw_color = bit32.band(c, 0x0F) end,
        print_text = vm.PrintText,
        load_font = vm.load_font_from_image,
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
        end,
        fs = {
            create = function(name,type,data)
                return vm.fs_create(name,vm.File_types[type:upper()],data)
            end,
            read = vm.fs_read,
            delete = vm.fs_delete,
            list   = function ()
                return vm.filesystem.entries
            end
        },
    }
    api.love = {
        load = love.load,
        update = love.update,
        draw = love.draw,
        key_pressed = love.keypressed,
    }
    
    return api
end


return vm