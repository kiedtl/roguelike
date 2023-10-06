local json = require("rxi-json")

local input = io.read("*a")
local json = json.decode(input)

local data = {}
for set = 1,#json do
    for floor = 1,#json[set] do
        for itemno = 1, #json[set][floor].items do
            local item = json[set][floor].items[itemno]
            if not data[item.id] then
                data[item.id] = { floors = {} }
                data[item.id].type = item.t
                for z = 1, #json[set] do
                    data[item.id].floors[z] = 0
                end
            end
            data[item.id].floors[floor] = data[item.id].floors[floor] + item.c
        end
    end
end

for item, dataset in pairs(data) do
    io.stdout:write(item .. "," .. dataset.type)
    for _, number in ipairs(dataset.floors) do
        io.stdout:write("," .. number)
    end
    io.stdout:write("\n")
end
