-- =====================================================================
--         GROWTOPIA CHEAPEST VENDING ITEM FINDER (DISCORD INTEGRATED)
-- =====================================================================
-- Deskripsi: Script Lua untuk mencari item termurah di Vending Machine,
--            yang terintegrasi dengan Bot Discord via file bridge.
--            Menerima task pencarian dari Discord, lalu mengirim hasil
--            scan berupa Discord Embed langsung ke channel Discord Anda.
-- =====================================================================

math.randomseed(os.time())

-- ==================== KONFIGURASI KUSTOM ====================
local CONFIG = {
    -- Masukkan URL Discord Webhook Channel Anda di sini
    -- Hasil scan akan diposting sebagai Embed ke Webhook ini
    discord_webhook = "YOUR_DISCORD_WEBHOOK_URL_HERE",

    -- File jembatan untuk menerima request dari Discord Bot (letakkan di folder script)
    request_file = "find_request.txt",

    -- Daftar world target yang ingin di-scan
    worlds_to_scan = {
        "BUYLASER", "BUYLASER1", "BUYLASER2", "BUYLASER3", "BUYLASER4",
        "BUYGRID", "BUYGRID1", "BUYGRID2", "BUYCHAND", "BUYPEPPER",
        "TRADE", "BUYSEEDS", "BUYBLOCK", "BUYDOOR", "BUYDF"
    },

    -- File path untuk list world kustom (jika ada, akan meload dari sini)
    worlds_txt_path = "vending_worlds.txt",

    -- ID blok Vending Machine (Standar Growtopia = 2978)
    vending_machine_id = 2978,

    -- ==================== FITUR ANTI-BAN & AMAN ====================
    warp_delay_min = 3000,
    warp_delay_max = 5000,
    loop_delay_min = 1500,
    loop_delay_max = 3000,

    enable_resting = true,
    rest_every_worlds = 10,
    rest_duration_min = 15000,
    rest_duration_max = 40000,

    enable_safety_check = true,
    leave_on_moderator = true,
    leave_on_any_player = false,
    safe_warp_world = "EXIT",

    stop_on_disconnect_or_ban = true
}
-- ============================================================

local results = {}
local target_item_id = nil
local target_item_real_name = ""
local is_scanning = false

-- Fungsi jeda dengan kompensasi ping
local function sleep_random(min_ms, max_ms)
    local rand_delay = math.random(min_ms, max_ms)
    local ping = GetPing and GetPing() or 0
    if ping > 0 then
        rand_delay = rand_delay + (ping * 2)
    end
    Sleep(rand_delay)
end

-- Load daftar world kustom
local function load_worlds_from_file()
    local file = io.open(CONFIG.worlds_txt_path, "r")
    if file then
        local worlds = {}
        for line in file:lines() do
            local cleaned = string.gsub(line, "%s+", "")
            if cleaned ~= "" then
                table.insert(worlds, string.upper(cleaned))
            end
        end
        file:close()
        if #worlds > 0 then
            CONFIG.worlds_to_scan = worlds
        end
    end
end

-- Cari ID item berdasarkan nama kustom
local function find_item_id_by_name(name)
    name = string.lower(name)
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

-- Cek aksesibilitas world
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

-- Kirim hasil ke Discord menggunakan Webhook
local function send_discord_report()
    -- Ambil top 10 termurah agar muat di 1 pesan Discord
    local max_items = 10
    
    table.sort(results, function(a, b)
        if a.price_per_item == b.price_per_item then
            return a.stock > b.stock
        end
        return a.price_per_item < b.price_per_item
    end)

    local description = ""
    if #results == 0 then
        description = "❌ Vending Machine berisi **" .. target_item_real_name .. "** tidak ditemukan di world yang di-scan."
    else
        description = "Berikut adalah daftar Vending Machine termurah untuk **" .. target_item_real_name .. "**:\\n\\n"
        for i = 1, math.min(#results, max_items) do
            local v = results[i]
            description = description .. string.format(
                "**#%d. World: `%s`** (X: %d, Y: %d)\\n" ..
                "➔ Harga: **%d** (%s) | Stok: `%d` | Satuan: `%.4f WL`\\n\\n",
                i, v.world, v.x, v.y, v.price, v.mode, v.stock, v.price_per_item
            )
        end
        if #results > max_items then
            description = description .. "*Dan " .. (#results - max_items) .. " world lainnya terdeteksi lebih mahal.*"
        end
    end

    -- Escaping JSON string
    description = string.gsub(description, "\"", "\\\"")

    local payload = [[{
        "embeds": [{
            "title": "🔍 Vending Finder Report",
            "description": "]] .. description .. [[",
            "color": 3447003,
            "footer": {
                "text": "Sended from Growtopia Bot | Total world di-scan: ]] .. #CONFIG.worlds_to_scan .. [["
            },
            "timestamp": "]] .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. [["
        }]
    }]]

    SendWebhook(CONFIG.discord_webhook, payload)
    log("--> Laporan hasil scan berhasil dikirim ke Discord!")
end

-- Scan Vending Machines di world aktif
local function scan_vending_machines(world_name)
    local tiles = GetTiles()
    if not tiles then return end
    
    for _, tile in pairs(tiles) do
        if tile.fg == CONFIG.vending_machine_id then
            if tile.extra then
                local item_id = tile.extra.item_id or tile.extra.itemid or tile.extra.item
                local price = tile.extra.price
                local count = tile.extra.count or tile.extra.amount or tile.extra.item_count
                local each = tile.extra.each
                
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
                end
            end
        end
    end
end

-- Jalankan scan penuh untuk satu item
local function run_full_scan(item_name)
    is_scanning = true
    results = {}
    
    load_worlds_from_file()
    
    local id, real_name = find_item_id_by_name(item_name)
    if not id then
        log("--> ERROR: Nama item '" .. item_name .. "' tidak ditemukan.")
        local fail_payload = [[{
            "embeds": [{
                "title": "🔍 Vending Finder Report",
                "description": "❌ Item dengan nama **]] .. item_name .. [[** tidak ditemukan di database Growtopia.",
                "color": 15158332
            }]
        }]]
        SendWebhook(CONFIG.discord_webhook, fail_payload)
        is_scanning = false
        return
    end
    
    target_item_id = id
    target_item_real_name = real_name
    log("--> Memulai scan item: " .. target_item_real_name .. " di " .. #CONFIG.worlds_to_scan .. " world...")

    local scanned_worlds_count = 0
    for _, world_name in ipairs(CONFIG.worlds_to_scan) do
        world_name = string.upper(world_name)
        
        -- Cek status koneksi / Banned
        local local_player = GetLocal()
        if local_player then
            local cur_world = string.upper(local_player.world)
            if CONFIG.stop_on_disconnect_or_ban and (cur_world == "EXIT" or cur_world == "BANNED") then
                log("--> Terputus! Menghentikan scan demi keamanan.")
                break
            end
        end

        -- Cek Istirahat Berkala
        if CONFIG.enable_resting and scanned_worlds_count > 0 and (scanned_worlds_count % CONFIG.rest_every_worlds == 0) then
            local rest_time = math.random(CONFIG.rest_duration_min, CONFIG.rest_duration_max)
            Sleep(rest_time)
        end

        -- Warp Request
        SendPacket(3, "action|join_request\nname|" .. world_name .. "\nshow_camp|0")
        sleep_random(CONFIG.warp_delay_min, CONFIG.warp_delay_max)
        
        local accessible, err_reason = can_access_world(world_name)
        if accessible then
            local unsafe, threat_type, threat_name = check_players_safety()
            if unsafe then
                SendPacket(3, "action|join_request\nname|" .. CONFIG.safe_warp_world .. "\nshow_camp|0")
                sleep_random(4000, 6000)
            else
                scan_vending_machines(world_name)
            end
        end

        scanned_worlds_count = scanned_worlds_count + 1
        sleep_random(CONFIG.loop_delay_min, CONFIG.loop_delay_max)
    end

    -- Kirim hasil akhir ke Discord
    send_discord_report()
    is_scanning = false
end

-- Listener untuk request dari file bridge
local function listen_for_requests()
    log("=========================================")
    log(" DISCORD VENDING FINDER INTERACTION ON    ")
    log(" Menunggu perintah dari bot Discord...   ")
    log("=========================================")
    
    while true do
        if not is_scanning then
            local file = io.open(CONFIG.request_file, "r")
            if file then
                local item_to_find = file:read("*line")
                file:close()
                os.remove(CONFIG.request_file) -- Hapus file bridge agar tidak loop
                
                if item_to_find and item_to_find ~= "" then
                    log("--> Menerima request Discord untuk item: " .. item_to_find)
                    -- Menjalankan scan dalam thread agar game tidak freeze
                    RunThread(function()
                        run_full_scan(item_to_find)
                    end)
                end
            end
        end
        Sleep(1000) -- Cek file request setiap 1 detik
    end
end

-- Mulai listener request
RunThread(listen_for_requests)
