-- =====================================================================
--               GROWTOPIA CHEAPEST VENDING ITEM FINDER SCRIPT
-- =====================================================================
-- Deskripsi: Script Lua untuk mencari item termurah di Vending Machine
--            pada daftar world tertentu, dilengkapi fitur pencarian nama
--            custom, anti-ban, dan mengekspor hasilnya ke format Excel (CSV).
-- =====================================================================

math.randomseed(os.time())

-- ==================== KONFIGURASI KUSTOM ====================
local CONFIG = {
    -- Nama item yang ingin dicari (tidak sensitif huruf besar/kecil)
    -- Contoh: "Laser Grid", "Chandelier", "Pepper Tree Seed", dll.
    target_item_name = "Laser Grid",

    -- Nama file output hasil pencarian (bisa langsung dibuka di Microsoft Excel)
    output_csv_path = "cheapest_vends.csv",

    -- Daftar world target yang ingin di-scan vending machine-nya
    -- Jika file "vending_worlds.txt" ada di folder Growtopia, script akan membaca dari file tersebut
    worlds_to_scan = {
        "BUYLASER", "BUYLASER1", "BUYLASER2", "BUYLASER3", "BUYLASER4",
        "BUYGRID", "BUYGRID1", "BUYGRID2", "BUYCHAND", "BUYPEPPER",
        "TRADE", "BUYSEEDS", "BUYBLOCK", "BUYDOOR", "BUYDF"
    },

    -- File path untuk list world kustom (jika ingin meload dari file txt)
    worlds_txt_path = "vending_worlds.txt",

    -- ID blok Vending Machine (Standar Growtopia = 2978)
    vending_machine_id = 2978,

    -- ==================== FITUR ANTI-BAN & AMAN ====================
    warp_delay_min = 3000,       -- Jeda minimal setelah join world agar data termuat (ms)
    warp_delay_max = 5000,       -- Jeda maksimal setelah join (ms)

    loop_delay_min = 1500,       -- Jeda sebelum warp ke world berikutnya (ms)
    loop_delay_max = 3000,       -- Jeda maksimal sebelum warp berikutnya (ms)

    enable_resting = true,       -- Istirahat berkala untuk meniru perilaku manusia
    rest_every_worlds = 10,      -- Istirahat setelah men-scan X world
    rest_duration_min = 20000,   -- Istirahat minimal (20 detik)
    rest_duration_max = 50000,   -- Istirahat maksimal (50 detik)

    enable_safety_check = true,  -- Deteksi Moderator / Player lain
    leave_on_moderator = true,   -- Kabur jika ada moderator (@)
    leave_on_any_player = false, -- Kabur jika ada player biasa (set ke true jika ingin sangat aman)
    safe_warp_world = "EXIT",

    stop_on_disconnect_or_ban = true
}
-- ============================================================

local results = {}
local scanned_worlds_count = 0
local target_item_id = nil
local target_item_real_name = ""

-- Fungsi jeda dengan kompensasi ping
local function sleep_random(min_ms, max_ms)
    local rand_delay = math.random(min_ms, max_ms)
    local ping = GetPing and GetPing() or 0
    if ping > 0 then
        rand_delay = rand_delay + (ping * 2)
    end
    Sleep(rand_delay)
end

-- Load daftar world dari file TXT jika ada
local function load_worlds_from_file()
    local file = io.open(CONFIG.worlds_txt_path, "r")
    if file then
        local worlds = {}
        for line in file:lines() do
            -- Bersihkan whitespace dan baris kosong
            local cleaned = string.gsub(line, "%s+", "")
            if cleaned ~= "" then
                table.insert(worlds, string.upper(cleaned))
            end
        end
        file:close()
        if #worlds > 0 then
            log("--> Berhasil memuat " .. #worlds .. " world dari " .. CONFIG.worlds_txt_path)
            CONFIG.worlds_to_scan = worlds
        end
    else
        log("--> File " .. CONFIG.worlds_txt_path .. " tidak ditemukan. Menggunakan daftar world default.")
    end
end

-- Fungsi mencari ID item berdasarkan nama
local function find_item_id_by_name(name)
    name = string.lower(name)
    log("--> Mencari database item untuk: '" .. name .. "'...")
    
    -- Item Growtopia berada di rentang ID 2 hingga sekitar 15000+
    for id = 2, 16000 do
        local info = GetIteminfo(id)
        if info and info.name then
            local info_name = string.lower(info.name)
            if info_name == name or string.find(info_name, name, 1, true) then
                return id, info.name
            end
        end
    end
    return nil, nil
end

-- Mengecek aksesibilitas world
local function can_access_world(target_world)
    local local_player = GetLocal()
    if not local_player then return false, "Gagal mengambil data player" end
    
    local current_world = string.upper(local_player.world)
    if current_world ~= target_world then
        return false, "Dialihkan ke world " .. current_world
    end
    
    if current_world == "EXIT" or current_world == "BANNED" then
        return false, "World dialihkan ke EXIT/BANNED"
    end
    
    local tiles = GetTiles()
    if not tiles or #tiles == 0 then
        return false, "Data tile kosong"
    end
    
    return true, nil
end

-- Mendeteksi Moderator / Player lain
local function check_players_safety()
    if not CONFIG.enable_safety_check then return false, nil end
    local players = GetPlayers()
    if not players then return false, nil end

    local local_player = GetLocal()
    local my_name = local_player and local_player.name or ""
    my_name = string.gsub(my_name, "`%w", "") -- membersihkan kode warna nama

    for _, player in pairs(players) do
        local p_name = player.name
        local clean_p_name = string.gsub(p_name, "`%w", "")
        
        if clean_p_name ~= my_name and clean_p_name ~= "" then
            local is_mod = string.find(clean_p_name, "@") or 
                           string.find(string.lower(clean_p_name), "mod") or 
                           string.find(string.lower(clean_p_name), "admin") or
                           string.find(string.lower(clean_p_name), "system")

            if is_mod then
                if CONFIG.leave_on_moderator then
                    return true, "MODERATOR", clean_p_name
                end
            elseif CONFIG.leave_on_any_player then
                return true, "PLAYER", clean_p_name
            end
        end
    end
    return false, nil
end

-- Scan Vending Machines di world aktif
local function scan_vending_machines(world_name)
    local tiles = GetTiles()
    if not tiles then return end
    
    local found_in_world = 0
    
    for _, tile in pairs(tiles) do
        if tile.fg == CONFIG.vending_machine_id then
            -- Pastikan objek memiliki data ekstra
            if tile.extra then
                -- Mendukung variasi penamaan field C++ pada executor
                local item_id = tile.extra.item_id or tile.extra.itemid or tile.extra.item
                local price = tile.extra.price
                local count = tile.extra.count or tile.extra.amount or tile.extra.item_count
                -- true = "Price WL untuk 1 item" (Each), false = "X item untuk 1 WL" (Per WL)
                local each = tile.extra.each
                
                -- Jika item cocok dengan target
                if item_id == target_item_id then
                    local price_per_item = 0
                    local mode_str = ""
                    
                    if each == true or each == 1 then
                        price_per_item = price
                        mode_str = "WL Each"
                    else
                        price_per_item = 1 / price
                        mode_str = price .. " per WL"
                    end
                    
                    table.insert(results, {
                        world = world_name,
                        x = tile.pos_x or tile.x or 0,
                        y = tile.pos_y or tile.y or 0,
                        item_name = target_item_real_name,
                        price = price,
                        mode = mode_str,
                        stock = count,
                        price_per_item = price_per_item
                    })
                    
                    found_in_world = found_in_world + 1
                end
            end
        end
    end
    
    if found_in_world > 0 then
        log(string.format("--> [FOUND] Menemukan %d Vending berisi '%s' di world %s!", found_in_world, target_item_real_name, world_name))
    end
end

-- Export hasil sorting ke file CSV (Excel)
local function export_results_to_csv()
    local file = io.open(CONFIG.output_csv_path, "w")
    if not file then
        log("--> ERROR: Gagal menulis hasil ke " .. CONFIG.output_csv_path)
        return false
    end

    -- Header CSV
    file:write("No,World,X,Y,Nama Item,Harga Set,Format Penjualan,Sisa Stock,Harga Satuan (WL)\n")

    -- Urutkan berdasarkan harga per satuan termurah
    table.sort(results, function(a, b)
        if a.price_per_item == b.price_per_item then
            return a.stock > b.stock -- jika harga sama, utamakan stok terbanyak
        end
        return a.price_per_item < b.price_per_item
    end)

    for i, v in ipairs(results) do
        file:write(string.format("%d,%s,%d,%d,\"%s\",%d,%s,%d,%.4f\n",
            i,
            v.world,
            v.x,
            v.y,
            v.item_name,
            v.price,
            v.mode,
            v.stock,
            v.price_per_item
        ))
    end

    file:close()
    log("=========================================")
    log("--> SCAN SELESAI!")
    log("--> Hasil tersimpan di: " .. CONFIG.output_csv_path)
    log("--> Total vending cocok ditemukan: " .. #results)
    log("=========================================")
    MessageBox("Vending Finder Complete", "Scan selesai! " .. #results .. " item ditemukan. Hasil tersimpan di " .. CONFIG.output_csv_path)
end

-- Thread utama program
local function start_finder()
    log("=========================================")
    log("     STARTING VENDING FINDER LUA         ")
    log("=========================================")
    
    load_worlds_from_file()
    
    -- Mencari ID item berdasarkan nama kustom
    local id, real_name = find_item_id_by_name(CONFIG.target_item_name)
    if not id then
        log("--> ERROR: Nama item '" .. CONFIG.target_item_name .. "' tidak ditemukan di database.")
        MessageBox("Item Not Found", "Nama item tidak ditemukan di database Growtopia.")
        return
    end
    
    target_item_id = id
    target_item_real_name = real_name
    log("--> Target Item ditemukan: " .. target_item_real_name .. " (ID: " .. target_item_id .. ")")
    log("--> Total world akan di-scan: " .. #CONFIG.worlds_to_scan)
    log("=========================================")

    for _, world_name in ipairs(CONFIG.worlds_to_scan) do
        world_name = string.upper(world_name)
        
        -- 0. Cek koneksi / Banned
        local local_player = GetLocal()
        if local_player then
            local cur_world = string.upper(local_player.world)
            if CONFIG.stop_on_disconnect_or_ban and (cur_world == "EXIT" or cur_world == "BANNED") then
                log("--> Karakter terlempar ke " .. cur_world .. "! Menghentikan pencarian demi keamanan.")
                break
            end
        end

        -- Cek Istirahat Berkala
        if CONFIG.enable_resting and scanned_worlds_count > 0 and (scanned_worlds_count % CONFIG.rest_every_worlds == 0) then
            local rest_time = math.random(CONFIG.rest_duration_min, CONFIG.rest_duration_max)
            log(string.format("--> [ANTI-BAN] Beristirahat sejenak selama %.1f detik...", rest_time / 1000))
            Sleep(rest_time)
        end

        log(string.format("--> [%d/%d] Warp ke world: %s...", scanned_worlds_count + 1, #CONFIG.worlds_to_scan, world_name))
        
        -- Warp Request
        SendPacket(3, "action|join_request\nname|" .. world_name .. "\nshow_camp|0")
        sleep_random(CONFIG.warp_delay_min, CONFIG.warp_delay_max)
        
        -- 1. Validasi World
        local accessible, err_reason = can_access_world(world_name)
        if not accessible then
            log("--> [SKIP] World " .. world_name .. " dilewati: " .. tostring(err_reason))
        else
            -- 2. Validasi Keamanan (Moderator)
            local unsafe, threat_type, threat_name = check_players_safety()
            if unsafe then
                log(string.format("--> [DANGER!] Ada %s '%s' di world %s! Segera kabur...", threat_type, threat_name, world_name))
                SendPacket(3, "action|join_request\nname|" .. CONFIG.safe_warp_world .. "\nshow_camp|0")
                sleep_random(4000, 6000)
            else
                -- 3. Jalankan scanning vending
                scan_vending_machines(world_name)
            end
        end

        scanned_worlds_count = scanned_worlds_count + 1
        sleep_random(CONFIG.loop_delay_min, CONFIG.loop_delay_max)
    end

    -- Selesai, simpan semua hasil
    export_results_to_csv()
end

RunThread(start_finder)
