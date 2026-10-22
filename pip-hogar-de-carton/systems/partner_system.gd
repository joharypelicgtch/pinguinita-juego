class_name PartnerSystem
extends Node
## Parejas candidatas. Cada una decide si acepta tu regalo (ramita especial, tapa brillante...).
## Si acepta GIFTS_TO_JOIN regalos y el refugio es de tier >= MIN_SHELTER_TIER, se muda contigo.
## Sin herencia de rasgos para las crías (decisión de diseño).

signal gift_accepted(partner_name: String)
signal gift_rejected(partner_name: String)
signal needs_better_shelter(partner_name: String)
signal partner_joined(partner_name: String)

const GIFTS_TO_JOIN := 2
const MIN_SHELTER_TIER := 2
const REJECT_COOLDOWN_DAYS := 1

const NAMES := ["Nube", "Brisa", "Copo", "Tizón", "Mota", "Ceniza", "Musgo", "Rocío"]
const PERSONALITIES := ["valiente", "tímida", "curiosa", "cariñosa"]
const GIFT_POOL := ["special_twig", "bottle_cap", "cloth_scrap", "crumbs", "twig", "leaf", "trash"]

var candidates: Array[Dictionary] = []
var current_partner: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func generate_candidates(seed_value: int, count: int = 4) -> void:
	_rng.seed = seed_value + 7
	candidates.clear()
	var names := NAMES.duplicate()
	names.shuffle()
	for i in mini(count, names.size()):
		var likes: Array = []
		while likes.size() < 2:
			var g: String = GIFT_POOL[_rng.randi() % GIFT_POOL.size()]
			if g not in likes:
				likes.append(g)
		var dislikes: Array = []
		while dislikes.is_empty():
			var g2: String = GIFT_POOL[_rng.randi() % GIFT_POOL.size()]
			if g2 not in likes and g2 != "special_twig":
				dislikes.append(g2)
		candidates.append({
			"name": names[i],
			"personality": PERSONALITIES[_rng.randi() % PERSONALITIES.size()],
			"likes": likes,
			"dislikes": dislikes,
			"trust": 0.0,
			"accepted": 0,
			"cooldown_until_day": 0,
		})


## Devuelve: "no_partner_slot" | "cooldown" | "no_item" | "rejected" | "accepted" | "waiting_shelter" | "joined"
func offer_gift(partner: Dictionary, item_id: String, player: Pinguinita, shelter_tier: int) -> String:
	if not current_partner.is_empty():
		return "no_partner_slot"
	if GameClock.day < partner.cooldown_until_day:
		return "cooldown"
	if not player.spend_items({ item_id: 1 }):
		return "no_item"

	var p := 0.15
	if item_id == "special_twig":
		p += 0.25
	if item_id in partner.likes:
		p += 0.35
	if item_id in partner.dislikes:
		p -= 0.30
	p += partner.trust * 0.2
	if shelter_tier >= MIN_SHELTER_TIER:
		p += 0.10
	p = clampf(p, 0.05, 0.95)

	if _rng.randf() >= p:
		partner.trust = maxf(partner.trust - 0.15, 0.0)
		partner.cooldown_until_day = GameClock.day + REJECT_COOLDOWN_DAYS
		AudioManager.play_sfx("gift_no")
		gift_rejected.emit(partner.name)
		return "rejected"

	partner.trust = minf(partner.trust + 0.35, 1.0)
	partner.accepted += 1
	AudioManager.play_sfx("gift_ok")
	gift_accepted.emit(partner.name)

	if partner.accepted >= GIFTS_TO_JOIN:
		if shelter_tier >= MIN_SHELTER_TIER:
			current_partner = partner
			candidates.erase(partner)
			partner_joined.emit(partner.name)
			return "joined"
		needs_better_shelter.emit(partner.name)
		return "waiting_shelter"
	return "accepted"


## Llamar cuando mejore el refugio: las parejas que esperaban se mudan.
func on_shelter_tier_changed(tier: int) -> void:
	if not current_partner.is_empty() or tier < MIN_SHELTER_TIER:
		return
	for c in candidates:
		if c.accepted >= GIFTS_TO_JOIN:
			current_partner = c
			candidates.erase(c)
			partner_joined.emit(c.name)
			return
