-- Castlevania: Aria of Sorrow - Drop Script by rhebus
-- Adapted for LuaHawk

local RAM = { 
			-- EWRAM
			RNG        = 0x000008,
			DIFFICULTY = 0x0000a1,
			ENEMY      = 0x0012d0,
			PLAYER     = 0x013110,
			BULLETS    = 0x01331c,
			GUARDIANS  = 0x013354,
			ENCHANTS   = 0x01336e,
			ABILITIES  = 0x013392,
			-- ROM
			ENEMY_LOOT_BASE = 0x0e9644,
}
local MAX_ENEMY = 63
local ENEMY_SIZE = 0x84

local Enemy_offset = {
    Bits = { offset = 0x3e, size = 1 },
    Type = { offset = 0x36, size = 1 },
    HP   = { offset = 0x34, size = 2, signed = true },
    MP   = { offset = 0x2e, size = 2 },
    xpos = { offset = 0x40, size = 4, signed = true },
    ypos = { offset = 0x44, size = 4, signed = true },
    valid= { offset = 0x64, size = 1 },
    cooldown1      = { offset = 0x78, size = 1 },
    cooldown2      = { offset = 0x79, size = 1 },
    cooldown3      = { offset = 0x7a, size = 1 },
    cooldown4      = { offset = 0x7b, size = 1 },
    cooldown_type1 = { offset = 0x74, size = 1 },
    cooldown_type2 = { offset = 0x75, size = 1 },
    cooldown_type3 = { offset = 0x76, size = 1 },
    cooldown_type4 = { offset = 0x77, size = 1 },
}

local Enemy_loot_offset = {
    Common_type   = { offset = 0x08, size = 2 },
    Common_rarity = { offset = 0x15, size = 1 },
    Rare_type     = { offset = 0x0a, size = 2 },
    Rare_rarity   = { offset = 0x16, size = 1 },
    Soul_rarity   = { offset = 0x12, size = 1 },
    Soul_type     = { offset = 0x17, size = 1 }, -- bullet, guardian etc
    Soul_index    = { offset = 0x18, size = 1 },
}

local Player_offset = {
    LCK            = { offset = 0xe8,  size = 2 },
    Accessory_type = { offset = 0x15d, size = 1 },
}

local Cooldown_types = {
    '?',
    'K',
    'W',
    'S',
    'B',
    'G',
}

local Enemy_names = {
"Bat", "Zombie", "Skeleton", "Merman", "Axe Armor",
"Skull Archer", "Peeping Eye", "Killer Fish", "Bone Pillar", "Blue Crow",
"Buer", "White Dragon", "Zombie Soldier", "Skeleton Knight", "Ghost",
"Siren", "Tiny Devil", "Durga", "Rock Armor", "Giant Ghost",
"Winged Skeleton", "Minotaur", "Student Witch", "Arachne", "Fleaman",
"Evil Butcher", "Quezlcoatl", "Ectoplasm", "Catoblepas", "Ghost Dancer",
"Waiter Skeleton", "Killer Doll", "Zombie Officer", "Creaking Skull", "Wooden Golem",
"Tsuchinoko", "Persephone", "Lilith", "Nemesis", "Kyoma Demon",
"Chronomage", "Valkyrie", "Witch", "Curly", "Altair",
"Red Crow", "Cockatrice", "Dead Warrior", "Devil", "Imp",
"Werewolf", "Gorgon", "Disc Armor", "Golem", "Manticore",
"Gremlin", "Harpy", "Medusa Head", "Bomber Armor", "Lightning Doll",
"Great Armor", "Une", "Giant Worm", "Needles", "Man-Eater",
"Fish Head", "Nightmare", "Triton", "Slime", "Big Golem",
"Dryad", "Poison Worm", "Arc Demon", "Cagnazzo", "Ripper",
"Werejaguar", "Ukoback", "Alura Une", "Biphron", "Mandragora",
"Flesh Golem", "Sky Fish", "Dead Crusader", "Kicker Skeleton", "Weretiger",
"Killer Mantle", "Mudman", "Gargoyle", "Red Minotaur", "Beam Skeleton",
"Alastor", "Skull Millione", "Giant Skeleton", "Gladiator", "Bael",
"Succubus", "Mimic", "Stolas", "Erinys", "Lubicant",
"Basilisk", "Iron Golem", "Demon Lord", "Final Guard", "Flame Demon",
"Shadow Knight", "Headhunter", "Death", "Legion", "Balore",
"Belmont", "Graham", "Chaos",
}

--[ AoS RNG simulator ] --------------------------------------------------------
-- Original code by gocha

local function AoS_RNG_func(seed)
	seed = bit.rshift(seed, 8)
	return bit.band(bit.lshift(0x3243 * seed, 16) + 0xf6ad * seed + 0x1b0cb175, 0xffffffff)
end

--------------------------------------------------------------------------------

local function mem_read(addr,size,signed)
    if size == 1 then
        if signed then
            return memory.read_s8(addr)
        else
            return memory.read_u8(addr)
        end
    elseif size == 2 then
        if signed then
            return memory.read_s16_le(addr)
        else
            return memory.read_u16_le(addr)
        end
    elseif size == 4 then
        if signed then
            return memory.read_s32_le(addr)
        else
            return memory.read_u32_le(addr)
        end
    else
        error("invalid size")
    end
end

local function soul_table_read(tab,index)
    local entry  = bit.rshift(index,1)
    local nibble = index % 2
    local byte   = mem_read(tab+entry,1,0)
    if (nibble == 1) then
        return bit.rshift(byte,4)
    else
        return byte % 0x10
    end
end

local function enemy_read(base,attr)
    local loc = Enemy_offset[attr]
    return mem_read(base + loc.offset,loc.size,loc.signed)
end

-- precache all monster loot tables, since they're stored in ROM
local Monster_loot = {}
memory.usememorydomain("ROM")

for mon_id = 0,112 do
    local loottable = {}
    for attr, details in pairs(Enemy_loot_offset) do
        local mon_base = RAM.ENEMY_LOOT_BASE + 0x24 * mon_id
        local loc = Enemy_loot_offset[attr]
        loottable[attr] = mem_read(
            mon_base + loc.offset, loc.size, loc.signed
            )
    end
    table.insert(Monster_loot, loottable)
end

memory.usememorydomain("EWRAM")

local function monster_loot(mon_id, attr)
    return Monster_loot[mon_id+1][attr]
end


local function player_read(attr)
    local loc = Player_offset[attr]
    return mem_read(RAM.PLAYER + loc.offset,loc.size,loc.signed)
end

local function enemy_type_as_string(mon_id)
    return Enemy_names[mon_id+1] or 'N/A'
end

local function enemy_cooldownstring(base)
    local cooldowns = {
        {enemy_read(base,"cooldown1"),enemy_read(base,"cooldown_type1")},
        {enemy_read(base,"cooldown2"),enemy_read(base,"cooldown_type2")},
        {enemy_read(base,"cooldown3"),enemy_read(base,"cooldown_type3")},
        {enemy_read(base,"cooldown4"),enemy_read(base,"cooldown_type4")},
    }
    table.sort(cooldowns,function(a,b) return a[2] < b[2] end)
    local str = ""
    for i,v in ipairs(cooldowns) do
        if v[2] ~= 0 then
            str = str .. string.format("%d%s ", v[1], Cooldown_types[v[2]])
        end
    end
    return str
end

local function enemy_string(base)
    local mon_id = enemy_read(base,"Type")
    return string.format("%dH %s%s",
        enemy_read(base,"HP"),
        enemy_cooldownstring(base),
        enemy_type_as_string(mon_id))
end

-- list all outcomes of upcoming random numbers on function f
local function list_rng(f)
    local searchMax = 40
    local rng_seed = memory.read_u32_le(RAM.RNG)
    local retstr = ""
    for i = 0, searchMax do
        local result = f(rng_seed)
        if result then
            retstr = retstr .. i .. result .. " "
        end
        rng_seed = AoS_RNG_func(rng_seed)
    end
    return retstr
end

local function souls_collected(mon_id)
    local soul_type = monster_loot(mon_id,"Soul_type")
    local soul_index= monster_loot(mon_id,"Soul_index")
    if soul_index == 0 then return nil end
    local tab
    if soul_type == 0 then
        tab = RAM.BULLETS
    elseif soul_type == 1 then
        tab = RAM.GUARDIANS
    elseif soul_type == 2 then
        tab = RAM.ENCHANTS
    elseif soul_type == 3 then
        tab = RAM.ABILITIES
    else
        return nil
    end
    return soul_table_read(tab,soul_index-1)
end

local function wearing_rare_ring()
    return player_read("Accessory_type") == 0x27
end

local function wearing_soul_ring()
    return player_read("Accessory_type") == 0x28
end

local function wearing_gold_ring()
    return player_read("Accessory_type") == 0x2b
end

local function wearing_heart_pendant()
    return player_read("Accessory_type") == 0x1d
end

local function hard_difficulty()
    return mem_read(RAM.DIFFICULTY,1,0) >= 0x10
end


-- create a loot function to evaluate rng values for a given enemy
local function loot_func(mon_id, luck)
    -- cache useful values
    local soul_rarity   = monster_loot(mon_id,"Soul_rarity")
    local soul_index    = monster_loot(mon_id,"Soul_index")
    local rare_rarity   = monster_loot(mon_id,"Rare_rarity")
    local rare_type     = monster_loot(mon_id,"Rare_type"  )
    local common_rarity = monster_loot(mon_id,"Common_rarity")
    local common_type   = monster_loot(mon_id,"Common_type"  )
    local rare_ring     = wearing_rare_ring()
    local soul_ring     = wearing_soul_ring()
    local heart_pendant = wearing_heart_pendant()
    local gold_ring     = wearing_gold_ring()
    local drops         = common_type ~= 0 or rare_type ~= 0
    return function(initial_rng)
        local rng = initial_rng
        --FIXME
        if (soul_rarity ~= 0 and soul_index ~= 0) then
            local target = 3
            if souls_collected(mon_id) == 0 then
                if hard_difficulty() then
                    target = 7
                else
                    target = 6
                end
            end
            if soul_ring then target = target + 8 end
            local range = 32 + soul_rarity * 8 - bit.rshift(luck,4)
            if range < 16 then range = 16 end

            if ((bit.rshift(rng,2) % range) < target) then
                return 's' -- win!
            end
            rng = AoS_RNG_func(rng)

        end
        -- can't drop anything else unless monster has either a common or a
        -- rare drop
        if drops then
            -- choose common or rare
            local target = 0x40
            local item_rarity = common_rarity
            local item_type   = common_type
            local item_code   = 'c'
            if rare_ring then target = 0x60 end
            if bit.rshift(rng,1) % 256 < target then
                item_rarity = rare_rarity
                item_type   = rare_type
                item_code   = 'r'
            end
            rng = AoS_RNG_func(rng)

            if item_type ~= 0 then
                local drop_target = 4
                if rare_ring then drop_target = 8 end
                local range = 16 + item_rarity * 4 - bit.rshift(luck,4)
                if range < 16 then range = 16 end
                if ((bit.rshift(rng,3) % range) < drop_target) then
                    return item_code -- win!
                end
                rng = AoS_RNG_func(rng)
            end
            -- can't drop gold or hearts unless you can also drop items
            local gold_target = 7
            if gold_ring then gold_target = 0x3f end
            if bit.rshift(rng,3) % 0x400 <= target then
                -- to report gold drops, change this line to return 'g'
                return nil
            end
            rng = AoS_RNG_func(rng)

            local heart_target = 7
            if heart_pendant then heart_target = 0x3f end
            if bit.rshift(rng,4) % 0x400 <= target then
                -- large or small?
                rng = AoS_RNG_func(rng)
                if bit.band(rng,0xc0) == 0 then
                    return 'H'
                else
                    return 'h'
                end
            end
        end
        return nil
    end
end

local function loot_string(mon_id)
    local monster_type = mon_id
    return string.format("%s%s",list_rng(
                                    loot_func(monster_type, player_read("LCK"))
                                ),
                                enemy_type_as_string(mon_id))
end


local enemy_table = {}
local screen = {}

event.onframeend(function()
	screen.x_add = client.borderwidth()
	screen.y_add = client.borderheight()
	screen.x_mul = (client.screenwidth() - screen.x_add * 2) / 240
	screen.y_mul = (client.screenheight() - screen.y_add * 2) / 160

    -- calculate monster table
    enemy_table = {}
	local num_monsters = 0
    for i=0,MAX_ENEMY do
        local enemy = RAM.ENEMY + i*ENEMY_SIZE
        local mon_id = enemy_read(enemy,"Type")
        if enemy_read(enemy,"HP") > 0 then
            table.insert(enemy_table, enemy)
			gui.text(0, 19 * screen.y_mul + 12 * num_monsters + screen.y_add, loot_string(mon_id))
			num_monsters = num_monsters + 1
        end
    end
	
    local i = 1
    for num,enemy in pairs(enemy_table) do
        -- print enemy info at the enemy's feet
        gui.text(enemy_read(enemy, "xpos") / 0x10000 * screen.x_mul + screen.x_add, enemy_read(enemy, "ypos") / 0x10000 * screen.y_mul + screen.y_add,
            string.format("%d/%d", enemy_read(enemy, "HP"), enemy_read(enemy, "MP")))
        i = i+1
    end
end)