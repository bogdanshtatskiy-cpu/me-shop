-- /lua/casino_config.lua
local config = {}

-- DATABASE URL (without a trailing /)
-- LEAVE EMPTY ON GITHUB! Fill this in on the in-game computer.
config.firebase_url = ""

-- Firebase Database Secret
-- LEAVE EMPTY ON GITHUB! Fill this in on the in-game computer.
config.db_secret = ""

-- Currency name
config.currency_name = "EM"

-- Timezone (offset from UTC in hours). E.g.: 2 (Kiev), 3 (Msk)
config.timezone = 2

-- DATABASE SWITCH
-- true = works with Firebase and web panel
-- false = works completely offline (hard drive only)
config.use_database = true

-- Administrators (who can access the hidden panel)
config.admins = {
    ["DesOope"] = true,
    ["NickName"] = true
}

-- === CASINO SETTINGS ===
config.main_db_path = "casino" -- The main path for casino data in Firebase

-- Colors for item rarity in the roulette
config.rarity_colors = {
    super_rare = 0xFFFF55, -- Yellow (< 5%)
    rare = 0xAA00AA,       -- Purple (< 20%)
    uncommon = 0x5555FF,    -- Blue (< 60%)
    common = 0x55FF55,      -- Green (< 80%)
    trash = 0xAAAAAA        -- Gray (>= 80%)
}

return config
