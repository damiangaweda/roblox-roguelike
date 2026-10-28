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
	-- At the left end of the experience bar: the level.
	level = "Level %d",
	-- At its right end: experience and experience to the next level.
	experienceShort = "%d / %d XP",
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
		trialStarted = "Trial!",
		trialCompleted = "Trial complete",
		-- The boon's or pact's name, then what it gave (shrineDetails' gains).
		given = "%s: %s",
		springUsed = "Fully restored",
	},
	-- Under the clock: the time left as m:ss, and whole seconds.
	mapClosesIn = "The map closes in %s",
	portalClosesIn = "The portal closes in %d s",

	-- What each button is called in a prompt: a key, or a touch button's label.
	keys = {
		interact = "F",
		dash = "Space",
		utilities = { "Q", "E", "R" },
		cards = { "1", "2", "3" },
	},
	buttons = {
		interact = "USE",
		dash = "DASH",
	},
	-- The key or button's label.
	prompts = {
		open = "Hold %s to open",
		cast = "Press %s to cast the extraction spell",
		portal = "Press %s to enter the portal",
		-- Under a shrine's name.
		hold = "Hold %s",
	},
	bars = {
		opening = "Opening...",
		casting = "Casting...",
		activating = "Activating...",
	},

	-- What a shrine in reach is called; a boon or a pact goes by its own name.
	shrines = {
		boon = "Boon",
		pact = "Pact",
		trial = "Trial",
		spring = "Spring",
	},
	-- Under a shrine's name: what it does and what it costs.
	shrineDetails = {
		-- The gain (a boon's `percentUp` or `flatUp`).
		boon = "%s until the run ends",
		-- The gain, then the cost.
		pact = "%s, %s",
		-- The enemies in the ring, then the ranks each card is worth.
		trial = "Fight a ring of %d enemies for a great offer (cards worth %d ranks)",
		-- The recharge, as m:ss.
		spring = "Full heal, utilities and dash ready; back in %s",
		-- A spring still recharging: the time left, as m:ss.
		springBack = "Back in %s",
		-- The number, then the stat's name (stats).
		percentUp = "+%s%% %s",
		percentDown = "-%s%% %s",
		flatUp = "+%s %s",
		flatDown = "-%s %s",
	},

	cards = {
		title = "Level up! Choose a card",
		-- A trial's reward: every card is worth more than one rank.
		greatTitle = "Great offer",
		newSkill = "New skill",
		-- A great offer's new skill: the rank it arrives at.
		newSkillRank = "New skill, rank %d",
		-- The rank.
		skillRank = "Rank %d",
		-- The rank, then the ranks it adds.
		skillRanks = "Rank %d  (+%d ranks)",
		newPassive = "New passive",
		-- A great offer's new passive: the rank it arrives at.
		newPassiveRank = "New passive, rank %d",
		passiveRank = "Passive rank %d",
		-- The rank, then the ranks it adds.
		passiveRanks = "Passive rank %d  (+%d ranks)",
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
