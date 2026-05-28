-- ============================================================
-- GODOT LSP DIAGNOSTIC SCRIPT
-- ============================================================
-- Open a .gd file in Neovim, then run:
--   :luafile /path/to/godot-lsp-debug.lua
-- OR paste this into command mode:
--   :lua dofile('/path/to/godot-lsp-debug.lua')
-- ============================================================

local results = {}

local function log(msg)
  table.insert(results, msg)
end

log("===== GODOT LSP DIAGNOSTIC =====")
log("")

-- 1. Check filetype
local ft = vim.bo.filetype
log("1. Current filetype: '" .. ft .. "'")
if ft == "gdscript" then
  log("   ✅ Correct filetype")
elseif ft == "gd" then
  log("   ⚠️  filetype is 'gd', not 'gdscript' — check vim.filetype.add")
else
  log("   ❌ WRONG FILETYPE — this file won't trigger gdscript LSP")
  log("   Open a .gd file first!")
end

-- 2. Check buffer name / path
local bufname = vim.api.nvim_buf_get_name(0)
log("")
log("2. Current buffer path: " .. bufname)
if bufname:match("^/mnt/") then
  log("   ✅ File is on /mnt/ (Windows drive via WSL)")
elseif bufname:match("^/home/") then
  log("   ❌ File is on WSL filesystem — godot-wsl-lsp needs /mnt/c/... paths!")
else
  log("   ⚠️  Unexpected path format")
end

-- 3. Check CWD
local cwd = vim.fn.getcwd()
log("")
log("3. Current working directory: " .. cwd)
if cwd:match("^/mnt/") then
  log("   ✅ CWD is on Windows drive")
else
  log("   ⚠️  CWD is NOT on /mnt/ — may affect root detection")
end

-- 4. Check for project.godot
log("")
log("4. Looking for project.godot...")
local found = vim.fs.find("project.godot", {
  upward = true,
  path = vim.fs.dirname(bufname),
})
if #found > 0 then
  log("   ✅ Found: " .. found[1])
else
  log("   ❌ project.godot NOT FOUND from current buffer path!")
  log("   This means root_markers won't match and LSP won't start!")
  -- Try from cwd
  local found2 = vim.fs.find("project.godot", { upward = true, path = cwd })
  if #found2 > 0 then
    log("   (But found from CWD: " .. found2[1] .. ")")
  end
end

-- 5. Check executable
log("")
log("5. godot-wsl-lsp executable: " .. tostring(vim.fn.executable("godot-wsl-lsp")))
local handle = io.popen("which godot-wsl-lsp 2>&1")
if handle then
  local path = handle:read("*a"):gsub("%s+$", "")
  handle:close()
  log("   Path: " .. path)
end

-- 6. Check existing LSP configs
log("")
log("6. Checking vim.lsp.config for 'gdscript'...")
local ok, cfg = pcall(function()
  -- In Neovim 0.12+, vim.lsp.config returns the config
  return vim.lsp.config["gdscript"] or vim.lsp.config("gdscript")
end)
if ok and cfg then
  log("   ✅ Config exists")
  if cfg.cmd then
    log("   cmd: " .. vim.inspect(cfg.cmd))
  end
  if cfg.filetypes then
    log("   filetypes: " .. vim.inspect(cfg.filetypes))
  end
  if cfg.root_markers then
    log("   root_markers: " .. vim.inspect(cfg.root_markers))
  end
else
  log("   ❌ Could not retrieve config: " .. tostring(cfg))
end

-- 7. Check active clients
log("")
log("7. Active LSP clients:")
local clients = vim.lsp.get_clients()
if #clients == 0 then
  log("   ❌ No active clients at all")
else
  for _, c in ipairs(clients) do
    log("   - " .. c.name .. " (id=" .. c.id .. ", ft=" .. table.concat(c.config.filetypes or {}, ",") .. ")")
  end
end

-- 8. Try manual start and watch for errors
log("")
log("8. Attempting manual LSP start...")

-- Determine root_dir
local root_dir = nil
if #found > 0 then
  root_dir = vim.fs.dirname(found[1])
else
  root_dir = cwd
end
log("   Using root_dir: " .. root_dir)

local client_id = vim.lsp.start({
  name = "GodotDiag",
  cmd = { "godot-wsl-lsp", "--useMirroredNetworking", "--experimentalFastPathConversion" },
  root_dir = root_dir,
})

log("   vim.lsp.start() returned: " .. tostring(client_id))

-- Schedule a check after 3 seconds to see if client survived
vim.defer_fn(function()
  local results2 = {}
  table.insert(results2, "")
  table.insert(results2, "9. Deferred check (3s later):")

  local alive_clients = vim.lsp.get_clients({ name = "GodotDiag" })
  if #alive_clients > 0 then
    local c = alive_clients[1]
    table.insert(results2, "   ✅ Client ALIVE! id=" .. c.id)
    -- Check if attached to buffer
    local attached = c.attached_buffers or {}
    local buf_list = {}
    for b, _ in pairs(attached) do
      table.insert(buf_list, tostring(b))
    end
    table.insert(results2, "   Attached buffers: " .. (table.concat(buf_list, ", ")))
    table.insert(results2, "   Initialized: " .. tostring(c.initialized))
  else
    table.insert(results2, "   ❌ Client DIED within 3 seconds!")
    table.insert(results2, "   This means godot-wsl-lsp crashed during init.")
    table.insert(results2, "   Likely cause: path conversion failure.")
    table.insert(results2, "")
    table.insert(results2, "   Try running from terminal to see the error:")
    table.insert(results2, "   echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file://" .. root_dir .. "\",\"capabilities\":{}}}' | godot-wsl-lsp --useMirroredNetworking --experimentalFastPathConversion")
  end

  table.insert(results2, "")
  table.insert(results2, "===== END DIAGNOSTIC =====")

  -- Print all deferred results
  for _, line in ipairs(results2) do
    print(line)
  end
end, 3000)

-- Print immediate results
log("")
log("(Waiting 3s to check if client survives...)")
log("")

for _, line in ipairs(results) do
  print(line)
end

