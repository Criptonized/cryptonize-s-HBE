-- CryptsHBE plugin: Packet Cracker -- RETIRED / MERGED (2026-06-19)
-- ============================================================================
-- The Packet Cracker was MERGED into the Remote Spy plugin (tab "Spy") so the full
-- crack loop -- capture -> decode -> forge -> fire -- lives on one tab. Its three
-- groupboxes (Find Serializer / Decode / Forge + Fire) are now part of remotespy.lua.
--
-- This file is no longer registered in the core (the "Packets" tab is gone). It is
-- kept only as a tombstone so a stale cached registration or a manual require
-- degrades gracefully (a small note) instead of erroring or creating duplicate
-- control keys. Do not push this for functionality; you may delete it from the repo.
-- ============================================================================
local Bridge = getgenv().CryptsHBE

return {
	name = "PacketCracker", tab = "Spy", requires = {},
	load = function(ctx)
		pcall(function()
			ctx:Groupbox("Packet Cracker (merged)", "left")
				:AddLabel("The Packet Cracker now lives in the\nRemote Spy plugin on this 'Spy' tab\n(Find Serializer / Decode / Forge).\nThis entry is retired.", true)
		end)
	end,
	unload = function() end,
}
