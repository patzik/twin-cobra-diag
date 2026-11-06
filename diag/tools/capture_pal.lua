-- MAME autoboot script: run the ORIGINAL game and dump its palette RAM
-- ($50000-$50DFF, 1792 xBGR_555 words) at several moments of the attract
-- mode, to PALOUT/pal_<frame>.bin. Used by tools/make_gamepal.py.
local m = manager.machine
local sp = m.devices[":maincpu"].spaces["program"]
local out = os.getenv("PALOUT") or "."
local at = {}
for f = 600, 9000, 300 do at[f] = true end
local n = 0
palcap = emu.add_machine_frame_notifier(function()
  n = n + 1
  if at[n] then
    local fh = assert(io.open(string.format("%s/pal_%05d.bin", out, n), "wb"))
    for i = 0, 1791 do
      local v = sp:read_u16(0x50000 + 2 * i)
      fh:write(string.char(v >> 8, v & 0xff))
    end
    fh:close()
  end
  if n == 9005 then m:exit() end
end)
