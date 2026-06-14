-- =====================================================================
--                   GROWTOPIA AUTOMATED LEVELING BOT
-- =====================================================================
-- Deskripsi: Script untuk menaikkan level dengan melakukan mining di
--            world unowned acak secara otomatis dan aman.
-- =====================================================================

math.randomseed(os.time())

-- ==================== KONFIGURASI KUSTOM ====================
local CONFIG = {
    -- Pengaturan World Leveling
    world_length = 5,          -- Panjang karakter nama world acak
    include_numbers = true,    -- true = nama world kombinasi angka & huruf, false = huruf saja

    -- Pengaturan Storage Tempat Drop Hasil Mining
    storage_world = "69prasstorage",
    storage_door_id = "9911",
    item_drop_threshold = 180, -- Jumlah item sejenis di tas untuk memicu drop ke storage

    -- Item yang akan di-drop ke storage (Dirt, Dirt Seed, Cave BG, Cave Seed, dll)
    drop_items = {2, 3, 14, 15, 4, 5, 10, 11},

    -- Pengaturan Delay
    walk_delay_ms = 220,
    punch_delay_ms = 180,

    -- Pengaturan Keamanan
    enable_safety = true,

    -- Jitter (Variasi delay acak anti-ban)
    jitter_min_ms = 0,
    jitter_max_ms = 45
}
-- ============================================================

local PROTECTED_BLOCKS = {
    [8] = true,
    [96] = true,
    [242] = true,
    [6] = true
}

-- ============================================================
-- 1. UTILITY
-- ============================================================

local function info_log(msg)
    log("--> [LEVELING] " .. msg)
end

local function get_delay(base_delay)
    return base_delay + math.random(CONFIG.jitter_min_ms, CONFIG.jitter_max_ms)
end

-- Generator Nama World Acak
local function generate_world_name(length, include_numbers)
    local chars = "abcdefghijklmnopqrstuvwxyz"
    if include_numbers then
        chars = chars .. "0123456789"
    end
    
    local name = ""
    for i = 1, length do
        local rand = math.random(1, #chars)
        name = name .. string.sub(chars, rand, rand)
    end
    return string.upper(name)
end

-- ============================================================
-- 2. WARP & COOLDOWN ENGINE
-- ============================================================

local LAST_WARP_TIME = 0

local function do_warp(world_name, door_id)
    world_name = string.upper(world_name)
    local target = world_name
    if door_id and door_id ~= "" then
        target = world_name .. "|" .. string.upper(door_id)
    end

    -- Cek jika sudah berada di world tujuan, lewati jeda cooldown
    local lp_check = GetLocal()
    if lp_check and string.upper(lp_check.world) == world_name then
        local tiles = GetTiles()
        if tiles and #tiles > 0 then
            return true
        end
    end

    -- Terapkan batas waktu tunggu (30 detik) sebelum melakukan warp berikutnya
    local current_time = GetTimeMS()
    local elapsed = current_time - LAST_WARP_TIME
    local cooldown_ms = 30000 -- 30 detik
    if elapsed < cooldown_ms then
        local wait_time = cooldown_ms - elapsed
        info_log(string.format("[WARP-COOLDOWN] Menunggu %.1f detik sebelum warp berikutnya...", wait_time / 1000))
        Sleep(wait_time)
    end

    for attempt = 1, 5 do
        local lp = GetLocal()
        if lp and string.upper(lp.world) == world_name then
            local tiles = GetTiles()
            if tiles and #tiles > 0 then
                Sleep(2000)
                LAST_WARP_TIME = GetTimeMS()
                return true
            end
        end

        info_log("Warping ke: " .. target .. " (attempt " .. attempt .. ")")
        SendPacket(3, "action|join_request\nname|" .. target .. "\nshow_camp|0")

        for wait = 1, 8 do
            Sleep(1000)
            lp = GetLocal()
            if lp and string.upper(lp.world) == world_name then
                local t = GetTiles()
                if t and #t > 0 then
                    Sleep(1500)
                    LAST_WARP_TIME = GetTimeMS()
                    return true
                end
            end
        end
    end
    info_log("Gagal warp ke: " .. target)
    LAST_WARP_TIME = GetTimeMS()
    return false
end

-- ============================================================
-- 3. SAFETY ESCAPE (Kabur instan ke world baru jika ada orang)
-- ============================================================

local function safety_escape_if_needed()
    if not CONFIG.enable_safety then return false end
    
    local players = GetPlayers()
    if not players then return false end

    local local_player = GetLocal()
    if not local_player then return false end
    local my_name = string.gsub(local_player.name or "", "`%w", "")

    local other_present = false
    for _, player in pairs(players) do
        local clean = string.gsub(player.name or "", "`%w", "")
        if clean ~= my_name and clean ~= "" then
            other_present = true
            info_log("Orang terdeteksi: '" .. clean .. "'! Pindah world...")
            break
        end
    end
    
    if other_present then
        -- Langsung buat nama world baru dan warp
        local new_world = generate_world_name(CONFIG.world_length, CONFIG.include_numbers)
        info_log("Kabur ke world baru: " .. new_world)
        do_warp(new_world, "")
        return true
    end
    return false
end

-- ============================================================
-- 4. MOVEMENT
-- ============================================================

local function walk_to(tx, ty)
    local lp = GetLocal()
    if not lp then return false end
    if lp.tile_x == tx and lp.tile_y == ty then return true end

    if safety_escape_if_needed() then return false end

    local path = PathFind(tx, ty)
    if not path or #path == 0 then
        FindPath(tx, ty)
        Sleep(get_delay(CONFIG.walk_delay_ms))
        return true
    end

    for i = 1, #path, 4 do
        local node = path[i]
        FindPath(node.x, node.y)
        Sleep(get_delay(CONFIG.walk_delay_ms) + math.random(5, 20))
    end

    FindPath(tx, ty)
    Sleep(get_delay(CONFIG.walk_delay_ms) + math.random(5, 15))
    return true
end

-- ============================================================
-- 5. DROP & INVENTORY ENGINE
-- ============================================================

local function drop_all_seeds()
    local lp = GetLocal()
    if not lp then return end
    local return_world = string.upper(lp.world)

    info_log("Tas penuh! Menuju storage untuk drop item...")
    EditToggle("autocollect", false) -- Matikan autocollect agar tidak terambil kembali
    Sleep(500)

    if not do_warp(CONFIG.storage_world, CONFIG.storage_door_id) then 
        EditToggle("autocollect", true)
        return 
    end

    local me = GetLocal()
    if not me then 
        EditToggle("autocollect", true)
        return 
    end

    -- Menentukan titik koordinat drop
    local drop_x = me.tile_x + 3
    if drop_x > 98 then drop_x = me.tile_x - 3 end
    local drop_y = me.tile_y
    walk_to(drop_x, drop_y)
    Sleep(300)

    for _, id in ipairs(CONFIG.drop_items) do
        local count = GetItemCount(id)
        if count > 0 then
            info_log("Drop item ID " .. id .. " x" .. count)
            SendPacket(2, "action|drop\n|itemID|" .. tostring(id))
            Sleep(500)
            SendPacket(2, "action|dialog_return\ndialog_name|drop_item\nitemID|" .. tostring(id) .. "|\ncount|" .. tostring(count))
            Sleep(800)
            
            -- Pindah secara vertikal ke atas (step 2 tile) agar seed/item bertumpuk vertikal
            drop_y = drop_y - 2
            walk_to(drop_x, drop_y)
            Sleep(200)
        end
    end

    info_log("Drop selesai. Kembali ke: " .. return_world)
    do_warp(return_world, "")
    EditToggle("autocollect", true) -- Aktifkan kembali autocollect setelah kembali
end

local function check_inventory_and_drop()
    local needs_drop = false
    for _, id in ipairs(CONFIG.drop_items) do
        if GetItemCount(id) >= CONFIG.item_drop_threshold then
            needs_drop = true
            break
        end
    end
    
    if needs_drop then
        drop_all_seeds()
        return true
    end
    return false
end

-- ============================================================
-- 6. MINING ENGINE
-- ============================================================

local function break_tile(x, y, break_bg)
    for punch = 1, 15 do
        if safety_escape_if_needed() then return end

        local tile = GetTile(x, y)
        if not tile then return end
        if PROTECTED_BLOCKS[tile.fg] then return end

        local has_fg = tile.fg ~= 0
        local has_bg = break_bg and (tile.bg ~= 0)
        if not has_fg and not has_bg then return end

        local packet = {}
        packet.type = 3
        packet.int_data = 18
        packet.int_x = x
        packet.int_y = y
        local me = GetLocal()
        if me then
            packet.pos_x = me.pos_x
            packet.pos_y = me.pos_y
        end
        SendPacketRaw(packet)
        Sleep(get_delay(CONFIG.punch_delay_ms))
    end
end

-- Cek apakah world memiliki Lock
local function is_world_locked()
    local tiles = GetTiles()
    if not tiles then return false end
    for _, tile in pairs(tiles) do
        -- ID Kunci: Small Lock (202), Big Lock (204), Huge Lock (206), World/Main Lock (242)
        if tile.fg == 202 or tile.fg == 204 or tile.fg == 206 or tile.fg == 242 or tile.fg == 5814 then
            return true
        end
    end
    return false
end

local function mine_world()
    info_log("Mulai mining di world...")
    
    EditToggle("modfly", true)
    EditToggle("antibounce", true)
    Sleep(500)
    
    -- Mulai mining baris native dirt (y = 25 sampai 53)
    for y = 25, 53, 2 do
        if safety_escape_if_needed() then return end
        if check_inventory_and_drop() then return end
        
        local start_x, end_x, step_x
        if y % 4 == 0 then
            start_x, end_x, step_x = 1, 98, 1
        else
            start_x, end_x, step_x = 98, 1, -1
        end
        
        for x = start_x, end_x, step_x do
            if safety_escape_if_needed() then return end
            
            walk_to(x, y - 1)
            
            -- Hancurkan block di depan
            local t_fg = GetTile(x, y)
            if t_fg and t_fg.fg ~= 0 and not PROTECTED_BLOCKS[t_fg.fg] then
                break_tile(x, y, false)
            end
            
            -- Hancurkan block di bawah kaki
            local t_fg2 = GetTile(x, y + 1)
            if t_fg2 and t_fg2.fg ~= 0 and not PROTECTED_BLOCKS[t_fg2.fg] then
                break_tile(x, y + 1, false)
            end
        end
    end
end

-- ============================================================
-- 7. MAIN PROGRAM
-- ============================================================

local function main_leveling_process()
    info_log("=== BOT LEVELING DIMULAI ===")
    
    while true do
        local target_world = generate_world_name(CONFIG.world_length, CONFIG.include_numbers)
        info_log("Mencari world target: " .. target_world)
        
        if do_warp(target_world, "") then
            if is_world_locked() then
                info_log("World " .. target_world .. " dikunci oleh orang lain. Mencari world baru...")
            else
                mine_world()
            end
        end
        
        Sleep(2000)
    end
end

RunThread(main_leveling_process)
