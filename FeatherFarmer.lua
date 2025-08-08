--[[
@title Feather Farmer
@author CuTGuArDiAn
@version 1.0

* Start this script in a chicken pen
* The script will automatically attack chickens.
* It will only loot Feathers.
* Make sure you have a weapon equipped.
* Based on Feather Farmer from Erekyu
--]]

local API = require('api')

-- ===================================================================
-- CONSTANTS AND CONFIGURATION
-- ===================================================================

local STATES = {
    IDLE = "Idle",
    FIGHTING = "Fighting",
    LOOTING = "Looting"
}

local CONFIG = {
    -- A list of NPC IDs for Chickens. This list covers most common chicken types.
    CHICKEN_IDS = { 41, 6333, 10178, 1017 },
    
    -- Item IDs for the loot we want
    FEATHER_ID = 314,
    
    -- The maximum distance to look for chickens and loot
    SEARCH_DISTANCE = 30,
    
    -- Number of kills before looting
    KILLS_BEFORE_LOOT = 2,
    
    -- Delay settings (in milliseconds)
    DELAYS = {
        ATTACK = { base = 1000, min = 300, max = 500 },
        KILL = { base = 1000, min = 200, max = 400 },
        LOOT = { base = 1000, min = 800, max = 1200 },
        NO_CHICKEN = { base = 2000, min = 500, max = 500 },
        MAIN_LOOP = { base = 200, min = 100, max = 200 }
    }
}

-- ===================================================================
-- STATE VARIABLES
-- ===================================================================

local state = {
    current_task = STATES.IDLE,
    last_target_id = nil,
    kill_counter = 0,
    session_feather_count = 0,
    initial_feather_count = Inventory:GetItemAmount(CONFIG.FEATHER_ID)
}

-- ===================================================================
-- UTILITY FUNCTIONS
-- ===================================================================

--- Performs a random sleep with given parameters
--- @param delay_config table Configuration table with base, min, max values
local function random_sleep(delay_config)
    API.RandomSleep2(delay_config.base, delay_config.min, delay_config.max)
end

--- Checks if the game is in a valid state
--- @return boolean True if game state is valid
local function is_game_state_valid()
    return API.GetGameState2() == 3 and API.PlayerLoggedIn()
end

-- ===================================================================
-- GAME LOGIC FUNCTIONS
-- ===================================================================

--- Finds the next available chicken to attack
--- @return table|nil Chicken object or nil if none found
local function find_next_chicken()
    print("Searching for a new chicken to attack...")
    local all_chickens = API.GetAllObjArrayInteract(
        CONFIG.CHICKEN_IDS, 
        CONFIG.SEARCH_DISTANCE, 
        {1}
    )
    
    if not all_chickens or #all_chickens == 0 then
        return nil
    end
    
    for _, chicken in ipairs(all_chickens) do
        local is_attackable = (chicken.Health == nil or chicken.Health > 0)
        if is_attackable then
            return chicken
        end
    end
    
    return nil
end

--- Finds loot on the ground
--- @return table|nil Loot object or nil if none found
local function find_loot()
    print("Searching for loot...")
    local loot_to_get = { CONFIG.FEATHER_ID }
    local loot_on_ground = API.GetAllObjArray1(
        loot_to_get, 
        CONFIG.SEARCH_DISTANCE, 
        {3}
    )
    
    if #loot_on_ground > 0 then
        return loot_on_ground[1]
    end
    
    return nil
end

--- Counts and reports newly collected feathers
--- @return number Number of new feathers collected
local function count_feathers_collected()
    local current_feather_count = Inventory:GetItemAmount(CONFIG.FEATHER_ID)
    local total_collected = current_feather_count - state.initial_feather_count
    
    if total_collected > state.session_feather_count then
        local new_feathers = total_collected - state.session_feather_count
        state.session_feather_count = total_collected
        print(string.format("✓ New feathers collected: %d | Session total: %d", 
              new_feathers, state.session_feather_count))
        return new_feathers
    end
    
    return 0
end

--- Attacks a chicken
--- @param chicken table The chicken object to attack
local function attack_chicken(chicken)
    print(string.format("Found chicken. Attacking... (Kill %d/%d)", 
          state.kill_counter + 1, CONFIG.KILLS_BEFORE_LOOT))
    Interact:NPC("Chicken", "Attack", 50)
    state.last_target_id = chicken.Id
    state.current_task = STATES.FIGHTING
    random_sleep(CONFIG.DELAYS.ATTACK)
end

--- Loots an item from the ground
--- @param loot_item table The loot item to pick up
local function loot_item(loot_item)
    print("Looting " .. loot_item.Name)
    API.DoAction_G_Items_Direct(0x3e, API.OFF_ACT_Pickup_route, loot_item)
    random_sleep(CONFIG.DELAYS.LOOT)
    count_feathers_collected()
end

-- ===================================================================
-- STATE HANDLERS
-- ===================================================================

--- Handles the IDLE state
local function handle_idle_state()
    -- Priority 1: If we have enough kills, look for loot
    if state.kill_counter >= CONFIG.KILLS_BEFORE_LOOT then
        local loot = find_loot()
        if loot then
            state.current_task = STATES.LOOTING
        else
            print(string.format("No loot found after %d kills. Resetting counter.", 
                  state.kill_counter))
            state.kill_counter = 0
        end
    -- Priority 2: Continue attacking if we don't have enough kills yet
    elseif API.LocalPlayer_IsInCombat_() then
        print("Already in combat, switching to fighting state to wait it out.")
        state.current_task = STATES.FIGHTING
    else
        local chicken = find_next_chicken()
        if chicken then
            attack_chicken(chicken)
        else
            print("No chickens available. Waiting...")
            random_sleep(CONFIG.DELAYS.NO_CHICKEN)
        end
    end
end

--- Handles the FIGHTING state
local function handle_fighting_state()
    if not API.LocalPlayer_IsInCombat_() then
        state.kill_counter = state.kill_counter + 1
        print(string.format("Target defeated. Kill count: %d/%d", 
              state.kill_counter, CONFIG.KILLS_BEFORE_LOOT))
        
        -- If we still don't have enough kills, go back to IDLE to attack another
        if state.kill_counter < CONFIG.KILLS_BEFORE_LOOT then
            state.current_task = STATES.IDLE
        else
            -- We have enough kills, go to loot
            print("Reached kill target. Looking for loot.")
            state.current_task = STATES.LOOTING
        end
        
        state.last_target_id = nil
        random_sleep(CONFIG.DELAYS.KILL)
    end
end

--- Handles the LOOTING state
local function handle_looting_state()
    local loot_item = find_loot()
    if loot_item then
        loot_item(loot_item)
    else
        print("No more loot found. Resetting kill counter and continuing.")
        state.kill_counter = 0  -- Reset counter after collecting all loot
        state.current_task = STATES.IDLE
    end
end

-- ===================================================================
-- MAIN EXECUTION
-- ===================================================================

--- Main state machine dispatcher
local function process_current_state()
    if state.current_task == STATES.IDLE then
        handle_idle_state()
    elseif state.current_task == STATES.FIGHTING then
        handle_fighting_state()
    elseif state.current_task == STATES.LOOTING then
        handle_looting_state()
    end
end

--- Initialize the script
local function initialize()
    API.SetDrawTrackedSkills(true)
    print("Feather Farmer initialized. Ensure you are in a chicken pen.")
    print(string.format("Will attack %d chickens before looting.", CONFIG.KILLS_BEFORE_LOOT))
end

-- ===================================================================
-- MAIN LOOP
-- ===================================================================

initialize()

while API.Read_LoopyLoop() do
    if not is_game_state_valid() then
        print("Invalid game state, exiting.")
        break
    end
    
    process_current_state()
    random_sleep(CONFIG.DELAYS.MAIN_LOOP)
end