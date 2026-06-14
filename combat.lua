-- CryptsHBE plugin: Combat  (gate, not an extraction)
-- ============================================================================
-- The Combat tab (Weapon Reader, Target Groups, Silent Melee, Tool Hitbox Editor) is too
-- deeply integrated to move out of the core safely -- it publishes Bridge.Weapon and
-- Bridge.TargetGroup and shares helpers with the rest of the script. So the CODE stays
-- inline in mainscript; this plugin just GATES it:
--   * enable  -> Bridge.CombatActive = true  (EnablePlugin also un-hides the Combat tab)
--   * disable -> Bridge.CombatActive = false (UnloadPlugin re-hides the tab)
-- While inactive, every Combat action loop (melee swing, kill-aura, crosshair, weapon-reader
-- auto, drag-select) early-returns, so nothing runs even if a saved profile left a toggle on.
-- The tab + its controls are owned by the core, so there is nothing to build/tear down here.
-- ============================================================================
return {
	name = "Combat", tab = "Combat", requires = {},
	load = function(ctx)
		local Bridge = getgenv().CryptsHBE
		if Bridge then Bridge.CombatActive = true end
		if Library then Library:Notify("Combat enabled") end
	end,
	unload = function()
		local Bridge = getgenv().CryptsHBE
		if Bridge then Bridge.CombatActive = false end
	end,
}
