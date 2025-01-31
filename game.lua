-- game.lua
function love.load()
    -- Carregar um sprite simples na memória (smiley)
    local sprite_addr = 0x4000  -- Endereço base dos sprites
    local smiley = {
        0,0,0,0,0,0,8,8,8,8,0,0,0,0,0,0,
        0,0,0,8,8,8,1,1,1,1,8,8,8,0,0,0,
        0,0,8,1,1,1,1,1,1,1,1,1,1,8,0,0,
        0,8,1,1,1,15,15,1,1,15,15,1,1,1,8,0,
        0,8,1,1,15,15,15,15,15,15,15,15,1,1,8,0,
        8,1,1,15,15,15,15,15,15,15,15,15,15,1,1,8,
        8,1,1,15,15,15,15,15,15,15,15,15,15,1,1,8,
        8,1,1,1,15,15,15,15,15,15,15,15,1,1,1,8,
        8,1,1,1,1,15,15,15,15,15,15,1,1,1,1,8,
        0,8,1,1,1,1,1,1,1,1,1,1,1,1,8,0,
        0,8,1,1,1,8,1,1,1,1,8,1,1,1,8,0,
        0,0,8,1,1,1,1,1,1,1,1,1,1,8,0,0,
        0,0,0,8,8,1,1,1,1,1,1,8,8,0,0,0,
        0,0,0,0,0,8,8,8,8,8,8,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    }
    
    for i = 0, 255 do
        poke(sprite_addr + i, smiley[i+1] or 0)
    end
end

local player = {
    x = 60,
    y = 50,
    speed = 1.5
}

local time = 0

function update(dt)
    time = time + dt
    
    -- Movimento do jogador
    if btn("left") then player.x = player.x - player.speed end
    if btn("right") then player.x = player.x + player.speed end
    if btn("up") then player.y = player.y - player.speed end
    if btn("down") then player.y = player.y + player.speed end
    
    -- Limitar movimento na tela
    player.x = math.max(0, math.min(144, player.x))
    player.y = math.max(0, math.min(104, player.y))
    
    -- Tocar sons quando pressionar A/B
    if btn("a") then
        play_note(1, 440 + math.sin(time*5)*100, 15, 0)
    else
        stop_note(1)
    end
    
    if btn("b") then
        play_note(2, 220, 10, 3)
    else
        stop_note(2)
    end
end

function draw()
    cls()
    
    -- Desenhar sprite do jogador
    spr(0, math.floor(player.x), math.floor(player.y))
    
    -- Desenhar borda colorida que muda com o tempo
    color((math.floor(time*5) % 15) + 1)
    rect(10, 10, 140, 100, false)
    
    -- Desenhar linha animada
    color(12)
    line(20, 20, 20 + math.sin(time)*50, 20 + math.cos(time)*50)
    
    -- Desenhar círculo pulsante
    color(9)
    circ(80 + math.cos(time*2)*30, 60 + math.sin(time*2)*30, 10 + math.sin(time*5)*5)
    
    -- Texto simples usando pixels
    color(15)
    local text = "PIXEL CONSOLE"
    for i = 1, #text do
        px(40 + i*8, 100, (i + math.floor(time*4)) % 15)
    end
end
