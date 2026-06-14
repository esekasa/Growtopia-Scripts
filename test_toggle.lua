log("--> [TOGGLE-TEST] Menguji EditToggle...")

RunThread(function()
    -- Pengujian 1: Huruf besar "Autocollect"
    log("--> [TOGGLE-TEST] Menguji EditToggle('Autocollect', false)...")
    local success1, err1 = pcall(EditToggle, "Autocollect", false)
    log("--> [TOGGLE-TEST] Status 1: " .. tostring(success1) .. ", Error: " .. tostring(err1))
    Sleep(1000)

    -- Pengujian 2: Huruf kecil "autocollect"
    log("--> [TOGGLE-TEST] Menguji EditToggle('autocollect', false)...")
    local success2, err2 = pcall(EditToggle, "autocollect", false)
    log("--> [TOGGLE-TEST] Status 2: " .. tostring(success2) .. ", Error: " .. tostring(err2))
    Sleep(1000)
    
    log("--> [TOGGLE-TEST] Semua pengujian selesai tanpa crash!")
end)
