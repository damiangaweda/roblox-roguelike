--!strict
-- Every player-visible English string of the client in one table, so the HUD
-- hard-codes none and in-game localization has one place to start from. Names
-- of classes, skills, passives, utilities and enemies are data in Config.
-- Formats take string.format arguments, noted beside each.

local Strings = {
	pick = {
		title = "Choose your class",
		-- The start skill's name.
		startSkill = "Starts with %s",
		-- Max health, then walk speed.
		stats = "Health %d   Speed %d",
		-- The two synergy names.
		synergies = "Synergies: %s, %s",
		waiting = "A run is in progress, wait for the next one",
	},

	-- Current and max health; with a barrier standing, its absorb too.
	health = "%d / %d",
	healthWithBarrier = "%d / %d  +%d",
	-- Level, experience, experience to the next level.
	experience = "Level %d  -  %d / %d XP",
	kills = "Kills: %d",
	levelUp = "Level %d",
	-- A passive in the column on the right: its name, rank and max rank.
	passiveLine = "%s  %d/%d",
	-- Studs to the chest, under the compass arrow.
	compassDistance = "%d",

	banners = {
		-- The boss's name.
		bossApproaches = "%s approaches!",
		-- The final boss's name ("The Forest Heart").
		finalBossAwakens = "%s awakens!",
		closingRing = "They're closing in!",
		-- The boss's name.
		bossEnraged = "%s is enraged!",
		-- A boss whose name the client cannot find.
		someBoss = "The boss",
		-- Whole seconds.
		finalBossTimer = "Kill it in %ds or the map closes",
		compass = "The chest calls to you",
		chestOpened = "You hold the extraction spell",
		portalOpened = "The portal is open!",
	},
	notices = {
		interrupted = "Interrupted!",
	},
	-- Under the clock: the time left as m:ss, and whole seconds.
	mapClosesIn = "The map closes in %s",
	portalClosesIn = "The portal closes in %d s",

	-- What each button is called in a prompt: a key, or a touch button's label.
	keys = {
		interact = "E",
		cast = "F",
		utilities = { "1", "2", "3" },
	},
	buttons = {
		interact = "USE",
		cast = "CAST",
	},
	-- The key or button's label.
	prompts = {
		open = "Hold %s to open",
		cast = "Press %s to cast the extraction spell",
		portal = "Press %s to enter the portal",
	},
	bars = {
		opening = "Opening...",
		casting = "Casting...",
	},

	cards = {
		title = "Level up! Choose a card",
		newSkill = "New skill",
		-- The rank.
		skillRank = "Rank %d",
		newPassive = "New passive",
		passiveRank = "Passive rank %d",
		heal = "Full heal",
		-- The share of max health restored, in percent.
		healText = "Restores %d%% of your health",
	},

	-- How each targeting kind picks what it lands on, on a card.
	targeting = {
		bolt = "Shoots the nearest enemy",
		strike = "Strikes the nearest enemy",
		melee = "Cuts enemies in reach",
		nova = "Bursts around you",
		cone = "Sweeps a cone ahead",
		ground = "Hits the thickest crowd",
		groundSelf = "Covers the ground around you",
		chain = "Jumps between enemies",
		scatter = "Hits random enemies nearby",
		aura = "Hurts everything near you",
		orbit = "Circles around you",
		totem = "Places a totem that fights",
		shield = "Shields you",
		heal = "Heals you when hurt",
		thorns = "Hurts those who hit you",
	},
	-- The rest of a skill card's lines.
	skill = {
		toughest = "Seeks the toughest",
		-- The amount, rounded.
		damage = "%d damage",
		damagePerTick = "%d damage per tick",
		absorbs = "Absorbs %d",
		heals = "Heals %d",
		reflects = "Reflects %d",
		-- The target count.
		targets = "%d targets",
		extraTarget = "+1 target",
		splash = "Splashes",
		-- Seconds, one decimal.
		cooldown = "%.1fs cooldown",
	},
	-- A skill's effect, on its card.
	effects = {
		slow = "Slows",
		root = "Roots",
		stun = "Stuns",
		fear = "Frightens",
		weaken = "Weakens",
		drain = "Drains life",
		-- The health share, in percent.
		execute = "Executes below %d%%",
		burning = "Burns",
		bleeding = "Bleeds",
		poisoned = "Poisons",
	},
	-- What each stat is called on a passive card.
	stats = {
		damage = "damage",
		maxHealth = "max health",
		speed = "speed",
		regeneration = "health per second",
		haste = "cooldown speed",
		area = "area",
		pickupRange = "pickup range",
		experience = "experience",
		armour = "armour",
		critChance = "critical chance",
	},
	-- A passive's gain per rank: the number, then the stat's name.
	passive = {
		percent = "+%s%% %s per rank",
		flat = "+%s %s per rank",
	},

	-- The local player's overlay before the summary.
	state = {
		deadTitle = "You fell",
		deadText = "The run is over",
		extractedTitle = "Extracted",
		extractedText = "Waiting for the run to end",
	},

	summary = {
		-- By the `ended` event's reason.
		outcomes = {
			allDead = "You fell",
			extracted = "Extracted!",
			finalBossKilled = "The forest is free",
			mapClosed = "The map closed",
		},
		-- The class name.
		class = "Class: %s",
		-- m:ss.
		time = "Time: %s",
		level = "Level: %d",
		kills = "Kills: %d",
		damage = "Damage: %d",
		-- Whole seconds.
		nextIn = "Next run in %d s",
	},
}

return Strings
