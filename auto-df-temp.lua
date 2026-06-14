-- =====================================================================
--                   GROWTOPIA AUTOMATED DIRT FARM BUILDER
-- =====================================================================
-- Deskripsi: Script Lua otomatis untuk membangun world Dirt Farm (DF)
--            sempurna dari awal.
-- =====================================================================

math.randomseed(os.time())

-- ==================== KONFIGURASI KUSTOM ====================
local CONFIG = {
    storage_world = "69prasstorage",
    storage_door_id = "9911",

    seed_world = "69prasstorage",
    seed_door_id = "9911",
    seed_drop_threshold = 180,

    main_world = "",

    dirt_threshold = 50,
    platform_threshold = 20,

    walk_delay_ms = 220,
    punch_delay_ms = 180,
    place_delay_ms = 180,

    enable_safety = true,
    leave_on_mod = true,
    leave_on_player = true,
    safe_warp_world = "EXIT",

    enable_resting = true,
    rest_every_rows = 2,
    rest_duration_min_ms = 7000,
    rest_duration_max_ms = 15000,

    jitter_min_ms = 0,
    jitter_max_ms = 45
}
-- ============================================================

local ITEM_DIRT = 2
local ITEM_PLATFORM = 28

local PROTECTED_BLOCKS = {
    [8] = true,
    [96] = true,
    [242] = true,
    [6] = true
}

local PLATFORM_Y_LEVELS = {53, 50, 47, 44, 41, 38, 35, 32, 29, 26, 23, 20, 17, 14, 11, 8, 5, 2}

-- ============================================================
-- 1. UTILITY (tidak memanggil fungsi lain yang belum ada)
-- ============================================================

local function info_log(msg)
    log("--> [AUTO-DF] " .. msg)
end

local function get_delay(base_delay)
    return base_delay + math.random(CONFIG.jitter_min_ms, CONFIG.jitter_max_ms)
end

local function check_resting(row_index)
    if not CONFIG.enable_resting then return end
    if row_index > 0 and (row_index % CONFIG.rest_every_rows == 0) then
        local rest_time = math.random(CONFIG.rest_duration_min_ms, CONFIG.rest_duration_max_ms)
        info_log(string.format("[ANTI-BAN] Istirahat %.1f detik...", rest_time / 1000))
        Sleep(rest_time)
    end
end

-- ============================================================
-- 2. SAFETY DETECTION (hanya return true/false, tidak ada aksi)
-- ============================================================

local function is_other_player_present()
    if not CONFIG.enable_safety then return false end
    local players = GetPlayers()
    if not players then return false end

    local local_player = GetLocal()
    if not local_player then return false end
    local my_name = string.gsub(local_player.name or "", "`%w", "")

    for _, player in pairs(players) do
        local clean = string.gsub(player.name or "", "`%w", "")
        if clean ~= my_name and clean ~= "" then
            local is_mod = string.find(clean, "@") or
                           string.find(string.lower(clean), "mod") or
                           string.find(string.lower(clean), "admin") or
                           string.find(string.lower(clean), "system")
            if is_mod and CONFIG.leave_on_mod then
                info_log("DANGER! Mod '" .. clean .. "' terdeteksi!")
                return true
            elseif CONFIG.leave_on_player then
                info_log("DANGER! Player '" .. clean .. "' terdeteksi!")
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- 3. WARP (transport murni, TIDAK ada safety check di dalam)
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
-- 4. SAFETY ESCAPE (memanggil do_warp yang sudah ada di atas)
-- ============================================================

local function safety_escape_if_needed()
    if not is_other_player_present() then return false end

    local me = GetLocal()
    if not me then return false end
    local current_world = string.upper(me.world)
    if current_world == "EXIT" or current_world == "" then return false end

    info_log("[EVADE] Kabur ke EXIT! Menunggu 30 detik...")
    SendPacket(3, "action|join_request\nname|EXIT\nshow_camp|0")

    for i = 1, 6 do
        Sleep(1000)
        local lp = GetLocal()
        if lp and string.upper(lp.world) == "EXIT" then break end
    end

    Sleep(30000)

    info_log("[EVADE] Kembali ke " .. current_world)
    do_warp(current_world, "")
    return true
end

-- ============================================================
-- 5. MOVEMENT (memanggil safety_escape_if_needed)
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
-- 6. INVENTORY FUNCTIONS (memanggil do_warp, walk_to)
-- ============================================================

local function restock(item_id)
    local lp = GetLocal()
    if not lp then return end
    local return_world = string.upper(lp.world)

    info_log("Restock item ID: " .. tostring(item_id))
    if not do_warp(CONFIG.storage_world, CONFIG.storage_door_id) then return end

    for retry = 1, 20 do
        if GetItemCount(item_id) >= 180 then break end
        local objects = GetObjects()
        if not objects then break end

        local me = GetLocal()
        if not me then break end

        local best = nil
        local best_dist = 99999
        for _, obj in pairs(objects) do
            if obj.id == item_id then
                local ox = math.floor(obj.pos_x / 32)
                local oy = math.floor(obj.pos_y / 32)
                local d = math.abs(ox - me.tile_x) + math.abs(oy - me.tile_y)
                if d < best_dist then
                    best_dist = d
                    best = obj
                end
            end
        end

        if not best then
            info_log("Bahan ID " .. tostring(item_id) .. " habis di storage!")
            break
        end

        walk_to(math.floor(best.pos_x / 32), math.floor(best.pos_y / 32))
        Sleep(800)
    end

    info_log("Restock selesai. Kembali ke: " .. return_world)
    do_warp(return_world, "")
end

local function check_inventory_for(item_id)
    local threshold = (item_id == ITEM_DIRT) and CONFIG.dirt_threshold or CONFIG.platform_threshold
    if GetItemCount(item_id) < threshold then
        restock(item_id)
    end
end

local function drop_all_seeds(force)
    local seed_ids = {3, 15, 11, 5}
    local total_seeds = 0
    for _, id in ipairs(seed_ids) do
        total_seeds = total_seeds + GetItemCount(id)
    end

    -- Hanya warp ke storage jika dipaksa (di akhir run) atau jumlah total seed di tas sudah mencapai threshold (180)
    if not force and total_seeds < CONFIG.seed_drop_threshold then 
        return 
    end

    local lp = GetLocal()
    if not lp then return end
    local return_world = string.upper(lp.world)

    info_log(string.format("Menuju seed storage (Total seed di tas: %d)...", total_seeds))
    EditToggle("autocollect", false) -- Matikan autocollect agar seed tidak terambil lagi
    Sleep(500)

    if not do_warp(CONFIG.seed_world, CONFIG.seed_door_id) then 
        EditToggle("autocollect", true) -- Aktifkan kembali jika warp gagal
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

    for _, id in ipairs(seed_ids) do
        local count = GetItemCount(id)
        if count > 0 then
            info_log("Drop seed ID " .. id .. " x" .. count)
            SendPacket(2, "action|drop\n|itemID|" .. tostring(id))
            Sleep(500)
            SendPacket(2, "action|dialog_return\ndialog_name|drop_item\nitemID|" .. tostring(id) .. "|\ncount|" .. tostring(count))
            Sleep(800)
            
            -- Pindah secara vertikal ke atas (step 2 tile) agar seed bertumpuk vertikal dan tidak tercollect kembali saat karakter bergerak
            drop_y = drop_y - 2
            walk_to(drop_x, drop_y)
            Sleep(200)
        end
    end

    info_log("Drop selesai. Kembali ke: " .. return_world)
    do_warp(return_world, "")
    EditToggle("autocollect", true) -- Aktifkan kembali autocollect setelah kembali
end

-- ============================================================
-- 7. BLOCK FUNCTIONS (memanggil safety_escape, check_inventory)
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

local function place_tile(x, y, item_id)
    if safety_escape_if_needed() then return false end

    local tile = GetTile(x, y)
    if not tile then return false end
    if tile.fg == item_id then return true end

    if tile.fg ~= 0 and not PROTECTED_BLOCKS[tile.fg] then
        break_tile(x, y, false)
    end

    tile = GetTile(x, y)
    if not tile or PROTECTED_BLOCKS[tile.fg] then return false end

    check_inventory_for(item_id)

    local packet = {}
    packet.type = 3
    packet.int_data = item_id
    packet.int_x = x
    packet.int_y = y
    local me = GetLocal()
    if me then
        packet.pos_x = me.pos_x
        packet.pos_y = me.pos_y
    end
    SendPacketRaw(packet)
    Sleep(get_delay(CONFIG.place_delay_ms))
    return true
end

-- ============================================================
-- 8. BUILD FUNCTIONS
-- ============================================================

local function build_edge(x, y)
    walk_to(x, y - 1)

    local t1 = GetTile(x, y - 1)
    if t1 and (t1.fg ~= 0 or t1.bg ~= 0) then
        break_tile(x, y - 1, true)
    end
    local t2 = GetTile(x, y - 2)
    if t2 and (t2.fg ~= 0 or t2.bg ~= 0) then
        break_tile(x, y - 2, true)
    end

    local tile = GetTile(x, y)
    if tile and tile.fg ~= ITEM_PLATFORM then
        if tile.fg ~= 0 and not PROTECTED_BLOCKS[tile.fg] then
            break_tile(x, y, false)
        end
        place_tile(x, y, ITEM_PLATFORM)
    end
end

local function build_platform_tile(x, y)
    if y >= 23 then
        local t1 = GetTile(x, y - 1)
        if t1 and (t1.fg ~= 0 or t1.bg ~= 0) then
            break_tile(x, y - 1, true)
        end
        local t2 = GetTile(x, y - 2)
        if t2 and (t2.fg ~= 0 or t2.bg ~= 0) then
            break_tile(x, y - 2, true)
        end
    else
        local t1 = GetTile(x, y - 1)
        if t1 and t1.fg ~= 0 then
            break_tile(x, y - 1, false)
        end
        local t2 = GetTile(x, y - 2)
        if t2 and t2.fg ~= 0 then
            break_tile(x, y - 2, false)
        end
    end

    local tile = GetTile(x, y)
    if tile and tile.fg ~= ITEM_DIRT then
        if not PROTECTED_BLOCKS[tile.fg] then
            if tile.fg ~= 0 then
                break_tile(x, y, false)
            end
            place_tile(x, y, ITEM_DIRT)
        end
    end
end

-- ============================================================
-- 9. MAIN
-- ============================================================

local function main_build_process()
    info_log("Memulai Pembangunan Dirt Farm...")

    EditToggle("modfly", true)
    EditToggle("antibounce", true)
    Sleep(1000)

    if CONFIG.main_world ~= "" then
        if not do_warp(CONFIG.main_world, "") then
            info_log("Gagal warp ke world utama.")
            return
        end
    end

    drop_all_seeds(false)

    for index, y in ipairs(PLATFORM_Y_LEVELS) do
        info_log(string.format("Baris y=%d (%d/%d)...", y, index, #PLATFORM_Y_LEVELS))

        local start_x, end_x, step_x
        if y % 2 == 0 then
            start_x, end_x, step_x = 1, 98, 1
        else
            start_x, end_x, step_x = 98, 1, -1
        end

        build_edge((step_x == 1) and 0 or 99, y)

        for x = start_x, end_x, step_x do
            walk_to(x, y - 1)
            build_platform_tile(x, y)
        end

        build_edge((step_x == 1) and 99 or 0, y)

        drop_all_seeds(false)
        check_resting(index)
        Sleep(500)
    end

    -- Verification
    info_log("Verifikasi...")
    local is_perfect = false
    local scan = 1

    while not is_perfect and scan <= 3 do
        local errors = 0
        info_log("Scan ke-" .. scan)

        for _, y in ipairs(PLATFORM_Y_LEVELS) do
            local t0 = GetTile(0, y)
            if not t0 or t0.fg ~= ITEM_PLATFORM then
                build_edge(0, y)
                errors = errors + 1
            end

            for x = 1, 98 do
                local t = GetTile(x, y)
                if t and t.fg ~= ITEM_DIRT and not PROTECTED_BLOCKS[t.fg] then
                    walk_to(x, y - 1)
                    build_platform_tile(x, y)
                    errors = errors + 1
                end
            end

            local t99 = GetTile(99, y)
            if not t99 or t99.fg ~= ITEM_PLATFORM then
                build_edge(99, y)
                errors = errors + 1
            end
        end

        if errors == 0 then
            is_perfect = true
            info_log("PERFECT! Tidak ada kerusakan.")
        else
            info_log(errors .. " titik diperbaiki.")
            scan = scan + 1
            Sleep(2000)
        end
    end

    drop_all_seeds(true) -- Drop sisa seed di tas ke storage sebelum selesai
    info_log("Selesai! Keluar world...")
    do_warp("EXIT", "")
    MessageBox("Dirt Farm Selesai", "Pembangunan Dirt Farm selesai sempurna!")
end

RunThread(main_build_process)
