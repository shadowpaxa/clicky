-- Saved data (ClickyDB, account-wide on this computer) and its migrations. Other files read
-- ClickyDB directly, from their own ADDON_LOADED handlers, which run after this one.
--   ns.DB_VERSION, ns.migrations   game-independent; on ns so offline tests can reach them
--
-- SavedVariables never leave the computer, so nothing that defines a macro's toys is kept here:
-- each macro is the only copy of its own toys (see Macros.lua).
--
-- Current shape (version 2):
--   version    the DB_VERSION the data was last migrated to
-- Nothing else: the toy list comes from the game's data each session (Toys.lua).

local _, ns = ...

local DB_VERSION = 2

-- migrations[n] brings data from version n - 1 up to version n. Data saved before versioning
-- counts as version 0. To change the shape: bump DB_VERSION, add migrations[DB_VERSION], and
-- update the shape above. Migrations must cope with any older shape, since they also run on
-- installs that skipped versions.
local migrations = {
	[1] = function(db)
		db.toys = db.toys or {}
	end,
	-- The known-toys cache isn't needed now that the list comes from the game's data.
	[2] = function(db)
		db.toys = nil
	end,
}

ns.DB_VERSION = DB_VERSION
ns.migrations = migrations

ns.RegisterEvent("ADDON_LOADED", function()
	ClickyDB = ClickyDB or {}
	-- Data from a newer Clicky is left as it is.
	for version = (ClickyDB.version or 0) + 1, DB_VERSION do
		migrations[version](ClickyDB)
		ClickyDB.version = version
	end
end)
