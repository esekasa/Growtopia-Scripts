-- =====================================================================
--                   GROWTOPIA GITHUB SCRIPT LOADER
-- =====================================================================
-- Deskripsi: Loader script untuk mengunduh dan menjalankan auto-df.lua
--            secara langsung dari GitHub Pages (github.io).
-- =====================================================================

local GITHUB_PAGES_URL = "https://esekasa.github.io/Growtopia-Scripts/auto-df.lua"
local TEMP_FILE_PATH = "d:\\Games\\Growtopia\\Script\\auto-df-temp.lua"

local function load_github_script()
    log("--> [LOADER] Mengunduh versi terbaru dari GitHub Pages...")
    
    -- Menambahkan cache buster (?t=random) untuk memaksa bypass cache
    local cache_buster = "?t=" .. tostring(math.random(100000, 999999))
    local final_url = GITHUB_PAGES_URL .. cache_buster
    
    local command = string.format('curl -s -k -L "%s" > "%s"', final_url, TEMP_FILE_PATH)
    local success, exit_code = pcall(os.execute, command)
    
    if success and (exit_code == 0 or exit_code == true) then
        log("--> [LOADER] Download sukses! Menjalankan script...")
        
        -- Jalankan script menggunakan dofile bawaan
        local run_status, run_err = pcall(dofile, TEMP_FILE_PATH)
        
        if run_status then
            log("--> [LOADER] Script auto-df.lua berhasil diluncurkan!")
        else
            log("--> [LOADER] ERROR: Gagal menjalankan script!")
            log("--> [LOADER] Detail: " .. tostring(run_err))
            MessageBox("Error Script", "Gagal menjalankan script.\nDetail: " .. tostring(run_err))
        end
        
        -- Hapus file sementara setelah dimuat ke memory
        pcall(os.remove, TEMP_FILE_PATH)
    else
        log("--> [LOADER] ERROR: Gagal mengunduh script dari GitHub Pages!")
        MessageBox("Loader Gagal", "Gagal mengunduh script. Periksa koneksi internet Anda.")
    end
end

-- Menjalankan loader di dalam thread agar os.execute tidak membekukan main loop game (mencegah force close)
RunThread(load_github_script)
