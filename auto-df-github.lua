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
    
    -- Menggunakan header Cache-Control pada curl untuk memaksa bypass cache secara aman
    local command = string.format('curl -s -k -L -H "Cache-Control: no-cache" "%s" > "%s"', GITHUB_PAGES_URL, TEMP_FILE_PATH)
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
    else
        log("--> [LOADER] ERROR: Gagal mengunduh script dari GitHub Pages!")
        MessageBox("Loader Gagal", "Gagal mengunduh script. Periksa koneksi internet Anda.")
    end
end

-- Menjalankan loader di dalam anonymous function untuk mencegah crash pada binder thread Growpai
RunThread(function()
    load_github_script()
end)
