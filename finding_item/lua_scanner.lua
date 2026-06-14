-- =====================================================================
--               GROWTOPIA DATABASE VENDING SCANNER CLIENT
-- =====================================================================
-- Deskripsi: Script Lua Growtopia yang bertugas memindai vending machine
--            di world target sesuai perintah dari bridge_controller.py,
--            lalu menulis hasilnya ke file JSON lokal.
-- =====================================================================

math.randomseed(os.time())

-- ==================== KONFIGURASI KUSTOM ====================
local CONFIG = {
    -- File jembatan lokal (harus sama dengan Python)
    queue_file = "local_scan_queue.txt",
    results_file = "local_scan_results.json",

    -- ID blok Vending Machine (Standar Growtopia = 2978)
    vending_machine_id = 2978,

    -- ==================== FITUR ANTI-BAN & AMAN ====================
    warp_delay_min = 3500,       -- Delay setelah warp agar data termuat (ms)
    warp_delay_max = 5000,       
    
    enable_safety_check = true,  -- Deteksi Moderator / Player lain
    leave_on_moderator = true,   -- Kabur jika ada Mod
    leave_on_any_player = false, -- Kabur jika ada Player biasa
    safe_warp_world = "EXIT",

    stop_on_disconnect_or_ban = true
}
-- ============================================================

local current_task_world = ""

-- Fungsi jeda acak (jitter)
local function sleep_random(min_ms, max_ms)
    local rand_delay = math.random(min_ms, max_ms)
    local ping = GetPing and GetPing() or 0
    if ping > 0 then
        rand_delay = rand_delay + (ping * 2)
    end
    Sleep(rand_delay)
end

-- Validasi world
local function can_access_world(target_world)
    local local_player = GetLocal()
    if not local_player then return false, "Gagal mengambil data player" end
    local current_world = string.upper(local_player.world)
    if current_world ~= target_world then return false, "Dialihkan ke world " .. current_world end
    if current_world == "EXIT" or current_world == "BANNED" then return false, "World dialihkan ke EXIT/BANNED" end
    
    local tiles = GetTiles()
    if not tiles or #tiles == 0 then return false, "Data tile kosong" end
    return true, nil
end

-- Deteksi Mod / Player lain
local function check_players_safety()
    if not CONFIG.enable_safety_check then return false, nil end
    local players = GetPlayers()
    if not players then return false, nil end

    local local_player = GetLocal()
    local my_name = local_player and local_player.name or ""
    my_name = string.gsub(my_name, "`%w", "")

    for _, player in pairs(players) do
        local p_name = player.name
        local clean_p_name = string.gsub(p_name, "`%w", "")
        
        if clean_p_name ~= my_name and clean_p_name ~= "" then
            local is_mod = string.find(clean_p_name, "@") or 
                           string.find(string.lower(clean_p_name), "mod") or 
                           string.find(string.lower(clean_p_name), "admin") or
                           string.find(string.lower(clean_p_name), "system")

            if is_mod then
                if CONFIG.leave_on_moderator then return true, "MODERATOR", clean_p_name end
            elseif CONFIG.leave_on_any_player then
                return true, "PLAYER", clean_p_name
            end
        end
    end
    return false, nil
end

-- Serialisasi manual ke format JSON (menghindari penggunaan library eksternal)
local function serialize_to_json(vends)
    local parts = {}
    for _, item in ipairs(vends) do
        -- Escape tanda kutip ganda pada nama item
        local clean_name = string.gsub(item.item_name, "\"", "\\\"")
        table.insert(parts, string.format(
            '{"x":%d,"y":%d,"item_name":"%s","price":%d,"mode":"%s","stock":%d,"price_per_item":%.6f}',
            item.x, item.y, clean_name, item.price, item.mode, item.stock, item.price_per_item
        ))
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- Menulis hasil scan ke file JSON lokal
local function write_results_file(vends)
    local json_str = serialize_to_json(vends)
    local file = io.open(CONFIG.results_file, "w")
    if file then
        file:write(json_str)
        file:close()
        return true
    else
        log("--> ERROR: Gagal menulis file hasil scan lokal!")
        return false
    end
end

-- Fungsi utama memindai vending machine di world aktif
local function scan_current_world(world_name)
    local vends_found = {}
    local tiles = GetTiles()
    if not tiles then return vends_found end

    for _, tile in pairs(tiles) do
        if tile.fg == CONFIG.vending_machine_id then
            if tile.extra then
                local item_id = tile.extra.item_id or tile.extra.itemid or tile.extra.item
                -- Hanya scan jika vending berisi item (bukan vending kosong / ID 0)
                if item_id and item_id > 0 then
                    local price = tile.extra.price
                    local count = tile.extra.count or tile.extra.amount or tile.extra.item_count
                    local each = tile.extra.each
                    
                    local info = GetIteminfo(item_id)
                    local item_name = info and info.name or ("Unknown ID: " .. item_id)
                    
                    local price_per_item = 0
                    local mode_str = ""
                    
                    if each == true or each == 1 then
                        price_per_item = price
                        mode_str = "WL Each"
                    else
                        price_per_item = 1 / price
                        mode_str = price .. " per WL"
                    end
                    
                    table.insert(vends_found, {
                        x = tile.pos_x or tile.x or 0,
                        y = tile.pos_y or tile.y or 0,
                        item_name = item_name,
                        price = price,
                        mode = mode_str,
                        stock = count,
                        price_per_item = price_per_item
                    })
                end
            end
        end
    end
    
    return vends_found
end

-- Loop utama mendengarkan antrean tugas lokal
local function listen_tasks()
    log("=========================================")
    log("   GROWTOPIA DB VENDING SCANNER ON       ")
    log(" Menunggu tugas dari bridge_controller... ")
    log("=========================================")
    
    while true do
        -- Cek status koneksi / Banned
        local local_player = GetLocal()
        if local_player then
            local cur_world = string.upper(local_player.world)
            if CONFIG.stop_on_disconnect_or_ban and (cur_world == "EXIT" or cur_world == "BANNED") then
                log("--> Terputus / Banned! Menghentikan scanner.")
                MessageBox("Scanner Stopped", "Terputus dari server. Harap login kembali.")
                break
            end
        end

        -- Baca file antrean
        local file = io.open(CONFIG.queue_file, "r")
        if file then
            local world_to_scan = file:read("*line")
            file:close()
            
            -- Jika ada world baru yang belum di-scan di sesi ini
            if world_to_scan and world_to_scan ~= "" and world_to_scan ~= current_task_world then
                current_task_world = world_to_scan
                log(string.format("--> [TASK] Memulai pemindaian di world: %s...", world_to_scan))
                
                -- Warp ke world target
                SendPacket(3, "action|join_request\nname|" .. world_to_scan .. "\nshow_camp|0")
                sleep_random(CONFIG.warp_delay_min, CONFIG.warp_delay_max)
                
                local vends = {}
                local accessible, err_reason = can_access_world(world_to_scan)
                if accessible then
                    local unsafe, threat_type, threat_name = check_players_safety()
                    if unsafe then
                        log(string.format("--> [ANTI-BAN] Kabur! Ada %s di world %s", threat_type, world_to_scan))
                        SendPacket(3, "action|join_request\nname|" .. CONFIG.safe_warp_world .. "\nshow_camp|0")
                        sleep_random(4000, 6000)
                    else
                        -- Jalankan scan
                        vends = scan_current_world(world_to_scan)
                        log(string.format("--> [SCAN] Menemukan %d Vending aktif di %s", #vends, world_to_scan))
                    end
                else
                    log("--> [SKIP] World dilewati: " .. tostring(err_reason))
                end
                
                -- Tulis hasil scan (walaupun kosong) ke file hasil untuk dibaca bridge
                write_results_file(vends)
            end
        end
        
        Sleep(1000) -- Cek file antrean setiap 1 detik
    end
end

RunThread(listen_tasks)
