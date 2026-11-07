class_name Goals
extends RefCounted
## Contracts, achievements and rotating challenges, all as data.
## Every goal counts a named lifetime stat, so adding one is a single line.

# Daily contracts: three are drawn from here each day.
const CONTRACTS := [
	{"id": "kills", "text": "Destroy %d enemies", "stat": "kill", "goal": 120, "reward": 60},
	{"id": "fighters", "text": "Destroy %d fighters", "stat": "kill_fighter", "goal": 30, "reward": 50},
	{"id": "rocks", "text": "Break %d rocks", "stat": "kill_rock", "goal": 40, "reward": 45},
	{"id": "crystals", "text": "Collect %d crystals", "stat": "crystal", "goal": 80, "reward": 60},
	{"id": "nova", "text": "Fire Nova Burst %d times", "stat": "nova", "goal": 5, "reward": 55},
	{"id": "clears", "text": "Clear %d levels", "stat": "clear", "goal": 3, "reward": 70},
	{"id": "flawless", "text": "Clear %d levels without losing hull", "stat": "flawless", "goal": 2, "reward": 90},
	{"id": "evolve", "text": "Evolve %d module", "stat": "evolve", "goal": 1, "reward": 100},
	{"id": "elites", "text": "Destroy %d elites or heavies", "stat": "kill_heavy", "goal": 6, "reward": 80},
	{"id": "graze", "text": "Graze %d shots", "stat": "graze", "goal": 40, "reward": 70},
	{"id": "boss", "text": "Defeat %d boss", "stat": "boss", "goal": 1, "reward": 110},
	{"id": "mutated", "text": "Clear %d levels with a Hazard Dial on", "stat": "mutated_clear", "goal": 2, "reward": 100},
]

const ACHIEVEMENTS := [
	{"id": "first_kill", "name": "FIRST BLOOD", "desc": "Destroy your first enemy", "stat": "kill", "goal": 1, "reward": 10},
	{"id": "kill_1k", "name": "LANE CLEANER", "desc": "Destroy 1,000 enemies", "stat": "kill", "goal": 1000, "reward": 150},
	{"id": "kill_10k", "name": "ONE-SHIP ARMADA", "desc": "Destroy 10,000 enemies", "stat": "kill", "goal": 10000, "reward": 800},
	{"id": "crystal_1k", "name": "PROSPECTOR", "desc": "Collect 1,000 crystals", "stat": "crystal", "goal": 1000, "reward": 150},
	{"id": "crystal_10k", "name": "CRYSTAL BARON", "desc": "Collect 10,000 crystals", "stat": "crystal", "goal": 10000, "reward": 800},
	{"id": "nova_50", "name": "LIGHT THE SKY", "desc": "Fire Nova Burst 50 times", "stat": "nova", "goal": 50, "reward": 120},
	{"id": "boss_1", "name": "GIANT KILLER", "desc": "Defeat a boss", "stat": "boss", "goal": 1, "reward": 50},
	{"id": "boss_all", "name": "STARFALL ENDS", "desc": "Defeat 6 different bosses", "stat": "boss_unique", "goal": 6, "reward": 500},
	{"id": "flawless_10", "name": "UNTOUCHED", "desc": "Clear 10 levels without losing hull", "stat": "flawless", "goal": 10, "reward": 150},
	{"id": "boss_flawless", "name": "NOT A SCRATCH", "desc": "Defeat a boss without losing hull", "stat": "boss_flawless", "goal": 1, "reward": 200},
	{"id": "evolve_1", "name": "EVOLUTION", "desc": "Evolve a module", "stat": "evolve", "goal": 1, "reward": 60},
	{"id": "evolve_all", "name": "COMPLETE THEORY", "desc": "Discover all 10 evolutions", "stat": "evolve_unique", "goal": 10, "reward": 600},
	{"id": "combo_50", "name": "ON A ROLL", "desc": "Reach a 50 combo", "stat": "best_combo", "goal": 50, "reward": 100},
	{"id": "combo_150", "name": "UNSTOPPABLE", "desc": "Reach a 150 combo", "stat": "best_combo", "goal": 150, "reward": 400},
	{"id": "graze_500", "name": "CLOSE ENOUGH", "desc": "Graze 500 shots", "stat": "graze", "goal": 500, "reward": 200},
	{"id": "wave_20", "name": "HOLDING OUT", "desc": "Reach wave 20 in Endless", "stat": "endless_wave", "goal": 20, "reward": 200},
	{"id": "wave_40", "name": "THE LONG NIGHT", "desc": "Reach wave 40 in Endless", "stat": "endless_wave", "goal": 40, "reward": 600},
	{"id": "expedition_1", "name": "EXPEDITION LEADER", "desc": "Complete an Expedition", "stat": "expedition_win", "goal": 1, "reward": 200},
	{"id": "expedition_6", "name": "CARTOGRAPHER", "desc": "Complete Expeditions in all 6 sectors", "stat": "expedition_unique", "goal": 6, "reward": 800},
	{"id": "ships_all", "name": "FULL HANGAR", "desc": "Own all 5 ships", "stat": "ships_owned", "goal": 5, "reward": 300},
	{"id": "mastery_10", "name": "ACE", "desc": "Reach mastery 10 with any ship", "stat": "best_mastery", "goal": 10, "reward": 500},
	{"id": "stars_90", "name": "RISING STAR", "desc": "Earn 90 stars", "stat": "stars", "goal": 90, "reward": 300},
	{"id": "stars_180", "name": "CONSTELLATION", "desc": "Earn all 180 stars", "stat": "stars", "goal": 180, "reward": 1500},
	{"id": "side_6", "name": "BLACK BOX RECOVERED", "desc": "Finish all 6 side missions", "stat": "side", "goal": 6, "reward": 400},
	{"id": "treasure_10", "name": "GOLD RUSH", "desc": "Catch 10 Gold Couriers", "stat": "kill_treasure", "goal": 10, "reward": 200},
	{"id": "brittle", "name": "ONE MISTAKE", "desc": "Clear a level with the Brittle dial", "stat": "brittle_clear", "goal": 1, "reward": 150},
]

const DAILY_DIALS := ["swift", "swarm", "armor", "frenzy", "elites", "noregen"]

## Rotating events are data, so a future season only needs a new row here.
const SEASONS := [
	{"id": "launch", "name": "FIRST STARFALL", "start": 0, "days": 100000, "banner": "Season One", "bonus_stat": "", "bonus": 1.0},
]
