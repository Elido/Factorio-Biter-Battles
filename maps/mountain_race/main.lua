local Collapse = require "modules.collapse"
local Immersive_cargo_wagons = require "modules.immersive_cargo_wagons.main"
local Terrain = require 'maps.mountain_race.terrain'
local Team = require 'maps.mountain_race.team'
local Global = require 'utils.global'
local Server = require 'utils.server'

local mountain_race = {}
Global.register(
    mountain_race,
    function(tbl)
        mountain_race = tbl
    end
)

local function on_chunk_generated(event)
	local surface = event.surface
	if surface.index ~= 1 then return end
	local left_top = event.area.left_top
	if left_top.y >= mountain_race.playfield_height or left_top.y < mountain_race.playfield_height * -1 or left_top.x < 0 then
		Terrain.draw_out_of_map_chunk(surface, left_top)
		return
	end
end

local function on_entity_damaged(event)
end

local function on_entity_died(event)
	local entity = event.entity
	if not entity then return end
	if not entity.valid then return end
	if entity.name == "locomotive" then
		if entity == mountain_race.locomotives.north then
			mountain_race.victorious_team = "south"
			mountain_race.gamestate = "game_over"
			return
		end
		if entity == mountain_race.locomotives.south then
			mountain_race.victorious_team = "north"
			mountain_race.gamestate = "game_over"
			return
		end
	end
end

local function on_player_joined_game(event)
	local player = game.players[event.player_index]
	
	if game.tick == 0 then
		if player.character then
			if player.character.valid then
				player.character.destroy()
			end
		end
		player.character = nil
		player.set_controller({type=defines.controllers.god})
		return
	end
	
	Team.setup_player(mountain_race, player)
end

local function init(mountain_race)
	if game.ticks_played % 60 ~= 30 then return end
	game.print("game resetting..")
	
	Immersive_cargo_wagons.reset()
	
	Collapse.set_kill_entities(true)
	Collapse.set_speed(1)
	Collapse.set_amount(4)
	Collapse.set_max_line_size(mountain_race.border_width + mountain_race.playfield_height * 2)
	Collapse.set_surface(surface)
	Collapse.set_position({0, 0})
	Collapse.set_direction("east")
	
	game.reset_time_played()
	
	mountain_race.clone_x = 0
	
	Team.configure_teams(mountain_race)
	
	game.print("rerolling terrain..")
	mountain_race.gamestate = "reroll_terrain"
end

local function prepare_terrain(mountain_race)
	if game.ticks_played % 30 ~= 0 then return end
	Terrain.clone_south_to_north(mountain_race)
	
	if mountain_race.clone_x < 4 then return end	
	game.print("preparing spawn..")
	mountain_race.gamestate = "prepare_spawn"
end

local function prepare_spawn(mountain_race)
	if game.ticks_played % 60 ~= 0 then return end
	Terrain.generate_spawn(mountain_race, "north")
	Terrain.generate_spawn(mountain_race, "south")
	game.print("spawning players..")
	mountain_race.gamestate = "spawn_players"
end

local function spawn_players(mountain_race)
	if game.ticks_played % 60 ~= 0 then return end
	for _, player in pairs(game.players) do
		player.force = game.forces.player
	end
	for _, player in pairs(game.connected_players) do
		Team.setup_player(mountain_race, player)
	end	
	
	mountain_race.reset_counter = mountain_race.reset_counter + 1
	local message = "Mountain race #" .. mountain_race.reset_counter .. " has begun!"
	game.print(message, {255, 155, 0})
	Server.to_discord_bold(table.concat{'*** ', message, ' ***'})	
	mountain_race.gamestate = "game_in_progress"
end



local function game_in_progress(mountain_race)
	local tick = game.ticks_played
	if tick % 120 == 0 then
		Terrain.clone_south_to_north(mountain_race)
	end
end

local function game_over(mountain_race)
	local tick = game.ticks_played
	if tick % 60 ~= 0 then return end
	
	if not mountain_race.reset_countdown then
		mountain_race.reset_countdown = 10
		local message = "Team " .. mountain_race.victorious_team .. " has won the race!"
		game.print(message, {255, 155, 0})
		Server.to_discord_bold(table.concat{'*** ', message, ' ***'})	
		return
	end
	
	mountain_race.reset_countdown = mountain_race.reset_countdown - 1
	if mountain_race.reset_countdown <= 0 then 	
		mountain_race.gamestate = "init"
		mountain_race.reset_countdown = nil
	end
end

local gamestates = {
	["init"] = init,
	["reroll_terrain"] = Terrain.reroll_terrain,
	["prepare_terrain"] = prepare_terrain,
	["prepare_spawn"] = prepare_spawn,
	["spawn_players"] = spawn_players,
	["game_in_progress"] = game_in_progress,
	["game_over"] = game_over,
}

local function on_tick()
	gamestates[mountain_race.gamestate](mountain_race)	
end

local function on_init()
	mountain_race.reset_counter = 0
	mountain_race.gamestate = "init"
	mountain_race.border_width = 4
	mountain_race.border_half_width = mountain_race.border_width * 0.5
	mountain_race.playfield_height = 128
	mountain_race.locomotives = {}
	Team.init_teams()
end


local Event = require 'utils.event'
Event.on_init(on_init)
Event.add(defines.events.on_tick, on_tick)
Event.add(defines.events.on_chunk_generated, on_chunk_generated)
Event.add(defines.events.on_entity_damaged, on_entity_damaged)
Event.add(defines.events.on_entity_died, on_entity_died)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)