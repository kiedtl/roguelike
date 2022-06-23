-- Little program for checking chances of a caster overpowering
-- a range of willpowers.
--
-- *** notice to future self ***
-- Ensure that the formula in get_chance() actually matches the formula used
-- in-game before usage -- this file isn't being updated :P
-- ***
--
-- (c) Kiëd Llaentenn
--

math.randomseed(os.time())

function rand()
    return math.ceil(math.random() * (100000 * math.random()))
end

function range_clumping(min, max, clump)
    assert(max >= min)
    if clump <= 1 then
        return range(min, max)
    end

    local sides = (max - min) / clump
    local i = 0
    local total = 0

    while i < ((max - min) % clump) do
        total = total + range(0, sides + 1)
        i = i + 1
    end
    while i < clump do
        total = total + range(0, sides)
        i = i + 1
    end

    return total + min;
end

function range(min, max)
    local diff = (max + 1) - min
    if diff > 0 then
        return (rand() % diff) + min
    else
        return min
    end
end

function get_chance(mine, their)
    local defeated_times = 0

    for i = 1, 10000 do
        local defeated = (range_clumping(1, 100, 2) * their) >
            (range_clumping(1, 180, 2) * mine) and their >= mine;
        if defeated then
            defeated_times = defeated_times + 1
        end
    end

    return defeated_times / 100
end

local their = tonumber(arg[1] or "8")

for mine = 0, their do
    print(their .. " against " .. mine .. ": " .. get_chance(mine, their) .. "%")
end
