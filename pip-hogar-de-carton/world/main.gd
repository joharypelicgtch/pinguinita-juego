extends Node3D
## Orquestador. Arranca el mundo con una semilla, mueve el sol, ajusta niebla y gestiona desmayos.
##
## Escena sugerida:
##   Main [este script]
##   ├─ WorldEnvironment (Environment: sin glow/SSAO/GI, fog activado)
##   ├─ DirectionalLight3D (única luz con sombra, shadow_max_distance = 50)
##   ├─ WorldGenerator [world_generator.gd]
##   ├─ Pinguinita [player.gd]
##   ├─ BuildingSystem [building_system.gd]
##   ├─ PartnerSystem [partner_system.gd]
##   └─ ChickManager [chick_manager.gd]

@export var sun: DirectionalLight3D
@export var world_env: WorldEnvironment
@export var world: WorldGenerator
@export var player: Pinguinita
@export var building: BuildingSystem
@export var partners: PartnerSystem
@export var chicks: ChickManager

const DAY_COLOR := Color("fff1d6")
const DUSK_COLOR := Color("ff9a6b")
const NIGHT_COLOR := Color("4a5a92")
const SKY_DAY := Color("9fb4c8")
const SKY_NIGHT := Color("0e1424")

var run_seed: int = 0


func _ready() -> void:
	add_to_group("main")
	run_seed = randi()                 # nueva partida = mapa nuevo. Para repetir un mapa: fija la semilla.
	WeatherManager.seed_weather(run_seed)
	partners.generate_candidates(run_seed)

	building.shelter_tier_changed.connect(partners.on_shelter_tier_changed)
	partners.partner_joined.connect(_on_partner_joined)
	chicks.chick_lost.connect(_on_chick_lost)

	await world.generate(run_seed)
	player.global_position = world.player_spawn


func _process(delta: float) -> void:
	# --- Sol (una sola luz con sombra) ---
	var day := GameClock.daylight()
	sun.rotation_degrees.x = GameClock.sun_pitch_deg()
	var warm := DAY_COLOR.lerp(DUSK_COLOR, 1.0 - absf(day * 2.0 - 1.0) if day < 0.5 else 0.0)
	sun.light_color = NIGHT_COLOR.lerp(warm, day)
	var dim := 1.0 - WeatherManager.intensity() * 0.5          # nublado/lluvia = luz más tenue
	sun.light_energy = lerpf(0.05, 1.0, day) * dim
	sun.shadow_enabled = day > 0.1 and WeatherManager.current != WeatherManager.Weather.STORM

	# --- Fondo y niebla ---
	var env := world_env.environment
	env.background_color = SKY_NIGHT.lerp(SKY_DAY, day)
	env.fog_density = lerpf(env.fog_density, WeatherManager.fog_density(), delta * 0.5)
	env.fog_light_color = env.background_color

	# --- ¿Zona ciudad? (activa lluvia extra y genera la ciudad al acercarse) ---
	var in_city := world.is_in_city(player.global_position)
	if in_city != WeatherManager.in_city:
		WeatherManager.in_city = in_city
	if not world.city_built and player.global_position.x > 40.0:
		world.generate_city()          # async: se reparte en varios frames


# --- Eventos ------------------------------------------------------------------

func on_player_fainted(p: Pinguinita) -> void:
	## Desmayo: sin muerte. Despierta en el refugio más cercano, amanece y pierde parte del inventario.
	p.stats.recover_after_faint()
	GameClock.skip_to_morning()
	for k in p.inventory.keys():
		p.inventory[k] = int(p.inventory[k] * 0.5)
	var target: Variant = building.nearest_shelter_position(p.global_position)
	p.global_position = (target + Vector3(0, 1, 0)) if target is Vector3 else world.player_spawn


func _on_partner_joined(_partner_name: String) -> void:
	var pos: Variant = building.nearest_shelter_position(player.global_position)
	chicks.start_family(pos if pos is Vector3 else player.global_position)


func _on_chick_lost(_id: int, reason: String) -> void:
	# Enlaza aquí tu escena corta y suave (sin gore): "taken_by_human" o "wandered_off".
	print("Cría perdida: ", reason)
