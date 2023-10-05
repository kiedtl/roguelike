local json = require("rxi-json")

local input = io.read("*a")
local json = json.decode(input)

local mode = nil
if not arg[1] then
    io.stderr:write("Need arg ('total'/'occurred')\n")
    return
elseif arg[1] == "total" then
    mode = "total"
elseif arg[1] == "occurred" then
    mode = "occurred"
else
    io.stderr:write("Invalid arg\n")
    return
end

local data = {}
for set = 1,#json do
    local temp = {}
    for floor = 1,#json[set] do
        for fabno = 1, #json[set][floor].prefabs do
            local fab = json[set][floor].prefabs[fabno]
            if not data[fab.id] then
                data[fab.id] = { floors = {} }
                data[fab.id].type = fab.t
                for z = 1, #json[set] do data[fab.id].floors[z] = 0 end
            end
            if not temp[fab.id] then
                temp[fab.id] = { floors = {} }
                for z = 1, #json[set] do temp[fab.id].floors[z] = 0 end
            end
                data[fab.id].floors[floor] = data[fab.id].floors[floor] + fab.c
                temp[fab.id].floors[floor] = temp[fab.id].floors[floor] + fab.c
            if mode == "occurred" then
                data[fab.id].floors[floor] = data[fab.id].floors[floor]
                    - (temp[fab.id].floors[floor] - 1)
            end
        end
    end
end

for fab, dataset in pairs(data) do
    io.stdout:write(fab)
    for _, number in ipairs(dataset.floors) do
        io.stdout:write("," .. number)
    end
    io.stdout:write("\n")
end
