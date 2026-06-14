-- =====================================================================
--                   GROWTOPIA WORLD FINDER SCRIPT (SAFE EDITION)
-- =====================================================================
-- Deskripsi: Script Lua untuk mencari world yang belum dikunci (unlocked)
--            Dilengkapi dengan fitur Anti-Ban, Deteksi Moderator,
--            Jitter Delay, Istirahat Berkala, dan Gerakan Manusiawi.
-- =====================================================================

-- Inisialisasi random seed agar hasil acak bervariasi setiap dijalankan
math.randomseed(os.time())

-- ==================== KONFIGURASI KUSTOM ====================
local CONFIG = {
    -- Panjang nama world acak yang ingin dicari (tidak termasuk prefix/suffix jika ada)
    world_length = 5,
    
    -- Kumpulan huruf kustom yang diperbolehkan (gunakan huruf kecil/besar)
    custom_letters = "abcdefghijklmnopqrstuvwxyz",
    
    -- Apakah ingin menyertakan angka (0-9) dalam pencarian? (true = Ya, false = Tidak)
    include_numbers = false,
    
    -- Prefix atau Suffix tambahan jika ingin pola tertentu (contoh: prefix = "GT" -> "GTABC")
    -- Kosongkan "" jika ingin acak murni
    prefix = "",
    suffix = "",

    -- Nama atau path file tempat menyimpan world yang ditemukan
    save_path = "found_worlds.txt",
    
    -- Batas maksimal pencarian world (0 untuk tanpa batas / terus menerus)
    max_searches = 0,

    -- ==================== FITUR ANTI-DETEKSI & ANTI-BAN ====================
    -- 1. Randomized Delay (Jitter): Menghindari pola interval konstan yang dicurigai server
    warp_delay_min = 2500,     -- Delay minimal setelah warp/join (dalam milidetik)
    warp_delay_max = 4500,     -- Delay maksimal setelah warp/join (dalam milidetik)
    
    loop_delay_min = 1000,     -- Jeda minimal sebelum warp ke world selanjutnya
    loop_delay_max = 2500,     -- Jeda maksimal sebelum warp ke world selanjutnya

    -- 2. Simulasi Istirahat Berkala (Resting Break): Bot akan berhenti sejenak secara periodik
    enable_resting = true,
    rest_every_min_worlds = 10, -- Minimal jumlah world dikunjungi sebelum istirahat
    rest_every_max_worlds = 25, -- Maksimal jumlah world dikunjungi sebelum istirahat
    rest_duration_min = 15000,  -- Durasi istirahat minimal (15 detik)
    rest_duration_max = 45000,  -- Durasi istirahat maksimal (45 detik)

    -- 3. Deteksi Moderator & Player Lain (Auto Evade)
    enable_safety_check = true,
    leave_on_moderator = true,      -- Otomatis pergi jika ada Moderator/Admin terdeteksi
    leave_on_any_player = true,     -- Otomatis pergi jika ada player lain (mencegah report)
    safe_warp_world = "EXIT",       -- Ke world mana jika harus kabur (biasanya "EXIT")

    -- 4. Simulasi Gerakan Manusiawi (Human-like Micro Movements)
    -- Bot akan berjalan sedikit setelah memasuki world agar tidak terdeteksi diam (AFK Botting)
    enable_micro_movements = true,

    -- 5. Auto Stop ketika Disconnected atau Terbanned
    -- Menghentikan script jika akun keluar ke EXIT atau terlempar ke world BANNED
    stop_on_disconnect_or_ban = true
}
-- ============================================================

-- Daftar ID item Lock (Kunci) di Growtopia yang akan dideteksi
local LOCK_IDS = {
    [202] = "Small Lock",
    [204] = "Big Lock",
    [206] = "Huge Lock",
    [242] = "World Lock",
    [4994] = "Builder's Lock",
    [5638] = "Guild Lock",
    [7188] = "Diamond Lock",
    [9640] = "Blue Gem Lock",
    [11550] = "Ruby Lock"
}

-- Menyimpan daftar world yang sudah dikunjungi di sesi ini agar tidak double
local visited_worlds = {}
local current_session_count = 0
local next_rest_threshold = math.random(CONFIG.rest_every_min_worlds, CONFIG.rest_every_max_worlds)

-- Fungsi untuk tidur/sleep dengan variasi acak (Jitter) dan kompensasi ping
local function sleep_random(min_ms, max_ms)
    local rand_delay = math.random(min_ms, max_ms)
    
    -- Kompensasi ping (jika ping tinggi, delay ditambah sedikit agar aman dari lag warp)
    local ping = GetPing and GetPing() or 0
    if ping > 0 then
        rand_delay = rand_delay + (ping * 2)
    end
    
    Sleep(rand_delay)
end

-- Fungsi membuat daftar karakter berdasarkan konfigurasi
local function build_char_pool()
    local pool = CONFIG.custom_letters
    if CONFIG.include_numbers then
        pool = pool .. "0123456789"
    end
    return pool
end

-- Fungsi menghasilkan nama world acak
local function generate_world_name(pool)
    local name = ""
    for i = 1, CONFIG.world_length do
        local rand_idx = math.random(1, #pool)
        name = name .. string.sub(pool, rand_idx, rand_idx)
    end
    
    -- Gabungkan dengan prefix dan suffix jika ada, lalu ubah ke huruf kapital
    local full_name = CONFIG.prefix .. name .. CONFIG.suffix
    return string.upper(full_name)
end

-- Fungsi mengecek apakah world bisa diakses
local function can_access_world(target_world)
    local local_player = GetLocal()
    if not local_player then
        return false, "Gagal mengambil data local player"
    end
    
    local current_world = string.upper(local_player.world)
    if current_world ~= target_world then
        return false, "Dialihkan ke world " .. current_world
    end
    
    -- Skip jika dialihkan ke world sistem/exit/banned
    if current_world == "EXIT" or current_world == "BANNED" then
        return false, "World dialihkan ke EXIT/BANNED"
    end
    
    local tiles = GetTiles()
    if not tiles or #tiles == 0 then
        return false, "Data tile world kosong/tidak termuat"
    end
    
    return true, nil
end

-- Fungsi mendeteksi keberadaan Moderator atau Player lain
local function check_players_safety()
    if not CONFIG.enable_safety_check then
        return false, nil
    end

    local players = GetPlayers()
    if not players then
        return false, nil
    end

    local local_player = GetLocal()
    local my_name = local_player and local_player.name or ""
    -- Bersihkan kode warna Growtopia (e.g. `w, `1, dll.) pada nama lokal
    my_name = string.gsub(my_name, "`%w", "")
    
    for _, player in pairs(players) do
        local p_name = player.name
        local clean_p_name = string.gsub(p_name, "`%w", "")
        
        if clean_p_name ~= my_name and clean_p_name ~= "" then
            -- Cek apakah nama mengandung prefix moderator "@" atau kata mod/admin
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

-- Fungsi untuk simulasi gerakan manusiawi (berjalan beberapa langkah acak)
local function simulate_human_movement()
    if not CONFIG.enable_micro_movements then
        return
    end

    local local_player = GetLocal()
    if not local_player then return end

    local current_x = local_player.tile_x
    local current_y = local_player.tile_y

    -- Pilih langkah acak ke kiri atau ke kanan (maksimal 3 blok)
    local move_offset = math.random(-3, 3)
    if move_offset ~= 0 then
        local target_x = current_x + move_offset
        local target_y = current_y

        -- Pastikan koordinat target masih berada di dalam batas world standar Growtopia (100x60)
        if target_x >= 1 and target_x <= 99 then
            -- Gunakan fungsi FindPath bawaan executor jika tersedia untuk berjalan secara alami
            if FindPath then
                FindPath(target_x, target_y)
                -- Berikan jeda waktu agar karakter menyelesaikan perjalanannya
                sleep_random(500, 1200)
            end
        end
    end
end

-- Fungsi memeriksa apakah world memiliki lock (kunci)
local function has_any_lock()
    local tiles = GetTiles()
    if not tiles then
        return false, nil
    end
    
    for _, tile in pairs(tiles) do
        if LOCK_IDS[tile.fg] then
            -- Ditemukan block kunci pada tile foreground
            return true, LOCK_IDS[tile.fg]
        end
    end
    return false, nil
end

-- Fungsi menulis world yang ditemukan ke file text
local function save_unlocked_world(world_name)
    local file = io.open(CONFIG.save_path, "a")
    if file then
        file:write(world_name .. "\n")
        file:close()
        return true
    else
        log("--> ERROR: Gagal menulis ke file " .. CONFIG.save_path)
        return false
    end
end

-- Fungsi utama pencari world dengan peningkatan keamanan
local function start_finder()
    local char_pool = build_char_pool()
    
    log("=========================================")
    log("  STARTING WORLD FINDER LUA (SAFE MODE)  ")
    log("=========================================")
    log("Panjang Nama : " .. CONFIG.world_length)
    log("Gunakan Angka: " .. tostring(CONFIG.include_numbers))
    log("Pool Huruf   : " .. CONFIG.custom_letters)
    log("File Output  : " .. CONFIG.save_path)
    log("Deteksi Player: " .. tostring(CONFIG.enable_safety_check))
    log("Gerak Mikro  : " .. tostring(CONFIG.enable_micro_movements))
    log("Istirahat    : " .. tostring(CONFIG.enable_resting))
    log("=========================================")
    
    local search_count = 0
    
    while true do
        -- 0. Cek Status Koneksi / Ban sebelum melangkah lebih jauh
        local local_player = GetLocal()
        if local_player then
            local current_world = string.upper(local_player.world)
            if CONFIG.stop_on_disconnect_or_ban and (current_world == "EXIT" or current_world == "BANNED") then
                log("==================================================")
                log("--> PERINGATAN: Karakter berada di world " .. current_world .. "!")
                log("--> Menghentikan script untuk menghindari deteksi/ban berkelanjutan.")
                log("==================================================")
                MessageBox("Anti-Ban Triggered", "Script berhenti otomatis karena mendeteksi world " .. current_world)
                break
            end
        end

        -- Cek limit pencarian
        if CONFIG.max_searches > 0 and search_count >= CONFIG.max_searches then
            log("Pencarian selesai! Mencapai batas " .. CONFIG.max_searches .. " world.")
            break
        end

        -- Cek Istirahat Berkala
        if CONFIG.enable_resting and current_session_count >= next_rest_threshold then
            local rest_duration = math.random(CONFIG.rest_duration_min, CONFIG.rest_duration_max)
            log(string.format("--> [ANTI-BAN] Beristirahat sejenak selama %.1f detik...", rest_duration / 1000))
            Sleep(rest_duration)
            
            -- Reset penghitung sesi dan tentukan batas selanjutnya secara acak
            current_session_count = 0
            next_rest_threshold = math.random(CONFIG.rest_every_min_worlds, CONFIG.rest_every_max_worlds)
        end
        
        -- Buat nama world acak yang belum pernah dikunjungi di sesi ini
        local target_world = generate_world_name(char_pool)
        while visited_worlds[target_world] do
            target_world = generate_world_name(char_pool)
        end
        visited_worlds[target_world] = true
        search_count = search_count + 1
        current_session_count = current_session_count + 1
        
        log(string.format("[%d] Mencoba masuk ke: %s...", search_count, target_world))
        
        -- Kirim packet join_request (Packet tipe 3) ke server
        SendPacket(3, "action|join_request\nname|" .. target_world .. "\nshow_camp|0")
        
        -- Tunggu acak agar proses loading world selesai (menggunakan Jitter Delay)
        sleep_random(CONFIG.warp_delay_min, CONFIG.warp_delay_max)
        
        -- 1. Cek apakah world bisa diakses
        local accessible, err_reason = can_access_world(target_world)
        if not accessible then
            log("--> [SKIP] World " .. target_world .. " dilewati: " .. tostring(err_reason))
        else
            -- 2. Cek keamanan di dalam world (apakah ada Mod atau Player lain)
            local unsafe, threat_type, threat_name = check_players_safety()
            if unsafe then
                log(string.format("--> [DANGER!] Mendeteksi %s %s di world %s! Segera kabur...", threat_type, threat_name, target_world))
                
                -- Kabur ke safe world
                SendPacket(3, "action|join_request\nname|" .. CONFIG.safe_warp_world .. "\nshow_camp|0")
                sleep_random(3000, 5000)
            else
                -- Tunggu tambahan waktu acak sebentar agar data tile termuat sepenuhnya
                sleep_random(300, 800)
                
                -- 3. Lakukan simulasi gerakan manusiawi (berjalan sedikit)
                simulate_human_movement()
                
                -- 4. Cek apakah world sudah dikunci oleh Small/Big/Huge/World Lock, dll.
                local locked, lock_type = has_any_lock()
                if locked then
                    log("--> [SKIP] World " .. target_world .. " dilewati: Terkunci oleh " .. lock_type)
                else
                    -- World kosong dan berhasil diakses!
                    log("--> [FOUND!] World " .. target_world .. " UNLOCKED!")
                    save_unlocked_world(target_world)
                    MessageBox("World Found!", "Ditemukan world kosong: " .. target_world)
                end
            end
        end
        
        -- Jeda acak sebelum beralih ke world selanjutnya
        sleep_random(CONFIG.loop_delay_min, CONFIG.loop_delay_max)
    end
end

-- Menjalankan script di thread terpisah agar game tidak freeze saat Sleep()
RunThread(start_finder)
