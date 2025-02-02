-- game ROM V1

function load()
    player = {
        x = 8,
        y = 8,
        speed = 0.85,
    }

    fs.create("intro.txt", "TXT", "BEM VINDO AO TESTE DO FANTASY Console! \n")

    local text = fs.read("intro.txt").data
end

function update()
    for name, info in pairs(fs.list()) do
        print(string.format("%s (%d bytes)",name,info.size))
    end
end

function draw()
    cls(7)

    for name, info in pairs(fs.list()) do
        color(info.size+math.random(1.5))
        rect(16,16,32,32,true)
    end
end