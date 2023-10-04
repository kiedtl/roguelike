local json = require("rxi-json")

local input = io.read("*a")
local json = json.decode(input)

local data = {}
for set = 1,#json do
    for floor = 1,#json[set] do
        for mobno = 1, #json[set][floor].mobs do
            local mob = json[set][floor].mobs[mobno]
            if not data[mob.id] then
                data[mob.id] = { floors = {} }
                for z = 1, #json[set] do
                    data[mob.id].floors[z] = 0
                end
            end
            data[mob.id].floors[floor] = data[mob.id].floors[floor] + mob.c
        end
    end
end

for mob, dataset in pairs(data) do
    io.stdout:write(mob)
    for _, number in ipairs(dataset.floors) do
        io.stdout:write("," .. number)
    end
    io.stdout:write("\n")
end
