from pathlib import Path
import re

root = Path(r'E:\test game\Mobile game development capabilities')

game = root / 'game.gd'
s = game.read_text(encoding='utf-8-sig')
s = s.replace('`r`n', '\n').replace('``', '`')
s = re.sub(r'const PLAYER_ART = preload\("res://assets/starfall/player_ship.png"\)\nconst ELITE_ART = preload\("res://assets/starfall/asteroid_elite.png"\)\nconst BOSS_ART = preload\("res://assets/starfall/sector_boss.png"\)\nconst DRONE_ART = preload\("res://assets/starfall/orbit_drone.png"\)\nconst SALVAGE_ART = preload\("res://assets/starfall/salvage_pickup.png"\)', '''const PLAYER_ART = preload("res://assets/starfall/ships/player_nova_01.png")
const ENEMY_ART = preload("res://assets/starfall/ships/enemy_fighter_01.png")
const BOSS_ART = preload("res://assets/starfall/ships/boss_ship_01.png")
const DRONE_ART = preload("res://assets/starfall/ships/player_interceptor_02.png")
const SALVAGE_ART = preload("res://assets/starfall/environment/salvage_crystal_blue.png")
const ASTEROID_SMALL = preload("res://assets/starfall/environment/asteroid_small.png")
const ASTEROID_MEDIUM = preload("res://assets/starfall/environment/asteroid_medium.png")
const ASTEROID_LARGE = preload("res://assets/starfall/environment/asteroid_large.png")
const PLAYER_PROJECTILE = preload("res://assets/starfall/projectiles/projectile_player_cyan.png")
const ENEMY_PROJECTILE = preload("res://assets/starfall/projectiles/projectile_enemy_magenta.png")
const ENEMY_PROJECTILE_ORANGE = preload("res://assets/starfall/projectiles/projectile_enemy_orange.png")
const EXPLOSION_SMALL = preload("res://assets/starfall/effects/effect_explosion_small.png")
const EXPLOSION_LARGE = preload("res://assets/starfall/effects/effect_explosion_large.png")
const SHIELD_ORB = preload("res://assets/starfall/effects/effect_shield_orb.png")
const UPGRADE_HULL = preload("res://assets/starfall/ui_icons/upgrade_hull_plating.png")
const UPGRADE_AFTERBURNER = preload("res://assets/starfall/ui_icons/upgrade_afterburner.png")
const UPGRADE_TRI_BEAM = preload("res://assets/starfall/ui_icons/upgrade_tri_beam.png")''', s)
s = s.replace('''\tif elite:
\t\tvar art := Sprite2D.new()
\t\tart.texture = ELITE_ART
\t\tart.scale = Vector2(0.036, 0.036)
\t\tart.z_index = 2
\t\tadd_child(art)
\t\tdata["art"] = art''', '''\tvar art := Sprite2D.new()
\tif elite:
\t\tart.texture = ENEMY_ART
\t\tart.scale = Vector2(0.115, 0.115)
\telse:
\t\tart.texture = ASTEROID_LARGE if radius > 25.0 else (ASTEROID_MEDIUM if radius > 22.0 else ASTEROID_SMALL)
\t\tvar asteroid_scale := 0.22 if radius > 25.0 else (0.17 if radius > 22.0 else 0.13)
\t\tart.scale = Vector2(asteroid_scale, asteroid_scale)
\tart.z_index = 2
\tadd_child(art)
\tdata["art"] = art''')
s = s.replace('''\t\tfor bullet in bullets:
\t\t\tvar tail: Vector2 = bullet.pos - bullet.vel.normalized() * 18.0
\t\t\tdraw_line(tail, bullet.pos, Color(bullet.color, 0.35), 4.0)
\t\t\tdraw_circle(bullet.pos, float(bullet.radius), Color(bullet.color, 0.95))
\t\tfor bullet in enemy_bullets:
\t\t\tvar tail: Vector2 = bullet.pos - bullet.vel.normalized() * 14.0
\t\t\tdraw_line(tail, bullet.pos, Color(bullet.color, 0.24), 5.0)
\t\t\tdraw_circle(bullet.pos, float(bullet.radius), Color(bullet.color, 0.92))''', '''\t\tfor bullet in bullets:
\t\t\t_draw_projectile(bullet)
\t\tfor bullet in enemy_bullets:
\t\t\t_draw_projectile(bullet)''')
s = s.replace('''\t\tfor p in particles:
\t\t\tvar alpha := clampf(float(p.life) / float(p.max), 0.0, 1.0)
\t\t\tdraw_circle(p.pos, float(p.size) * (0.6 + alpha), Color(p.color, alpha * 0.7))''', '''\t\tfor p in particles:
\t\t\tvar alpha := clampf(float(p.life) / float(p.max), 0.0, 1.0)
\t\t\tif p.has("texture"):
\t\t\t\t_draw_effect(p)
\t\t\telse:
\t\t\t\tdraw_circle(p.pos, float(p.size) * (0.6 + alpha), Color(p.color, alpha * 0.7))''')
marker = 'func _draw_asteroid(enemy: Dictionary) -> void:'
helpers = '''func _draw_projectile(bullet: Dictionary) -> void:
\tvar direction: Vector2 = bullet.vel.normalized()
\tvar texture: Texture2D = bullet.texture
\tvar tint := Color(bullet.color, 0.96)
\tif texture:
\t\tdraw_set_transform(bullet.pos, direction.angle() + PI * 0.5, Vector2(0.07, 0.07))
\t\tdraw_texture_rect(texture, Rect2(-18, -34, 36, 68), false, tint)
\t\tdraw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
\telse:
\t\tdraw_line(bullet.pos - direction * 18.0, bullet.pos, Color(bullet.color, 0.35), 4.0)
\t\tdraw_circle(bullet.pos, float(bullet.radius), tint)

func _draw_effect(p: Dictionary) -> void:
\tvar alpha := clampf(float(p.life) / float(p.max), 0.0, 1.0)
\tvar texture: Texture2D = p.texture
\tvar effect_scale := 0.12 + (1.0 - alpha) * 0.10
\tif texture:
\t\tdraw_set_transform(p.pos, bg_scroll * 0.5, Vector2(effect_scale, effect_scale))
\t\tdraw_texture_rect(texture, Rect2(-30, -30, 60, 60), false, Color(p.color, alpha * 0.92))
\t\tdraw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

'''
if 'func _draw_projectile' not in s:
    s = s.replace(marker, helpers + marker)
s = s.replace('''\t\tif enemy.elite and enemy.has("art"):
\t\t\tdraw_arc(center, radius + 12.0 + sin(bg_scroll * 5.0) * 3.0, 0.2, 2.2, 16, Color(MAGENTA, 0.8), 2.0)
\t\t\treturn''', '''\t\tif enemy.has("art"):
\t\t\tdraw_arc(center, radius + 12.0 + sin(bg_scroll * 5.0) * 3.0, 0.2, 2.2, 16, Color(MAGENTA if enemy.elite else CYAN, 0.42), 2.0)
\t\t\treturn''')
s = s.replace('{"id": "spread", "label": "TRI-BEAM", "desc": "Add a side shot.", "color": CYAN}', '{"id": "spread", "label": "TRI-BEAM", "desc": "Add a side shot.", "color": CYAN, "icon": UPGRADE_TRI_BEAM}')
s = s.replace('{"id": "shield", "label": "HULL PLATING", "desc": "+25 max shield.", "color": Color(0.52, 0.78, 1.0)}', '{"id": "shield", "label": "HULL PLATING", "desc": "+25 max shield.", "color": Color(0.52, 0.78, 1.0), "icon": UPGRADE_HULL}')
s = s.replace('{"id": "afterburner", "label": "AFTERBURNER", "desc": "Move faster.", "color": MAGENTA}', '{"id": "afterburner", "label": "AFTERBURNER", "desc": "Move faster.", "color": MAGENTA, "icon": UPGRADE_AFTERBURNER}')
s = s.replace('''\t\t\tdraw_circle(rect.position + Vector2(47, 51), 18.0, Color(color, 0.24))
\t\t\t_text("0%d" % (i + 1), rect.position + Vector2(31, 57), 16, color, BOLD_FONT)''', '''\t\t\tdraw_circle(rect.position + Vector2(47, 51), 18.0, Color(color, 0.24))
\t\t\tif option.has("icon"):
\t\t\t\tdraw_texture_rect(option.icon, Rect2(rect.position + Vector2(20, 22), Vector2(54, 54)), false, Color(1, 1, 1, 0.95))
\t\t\t_text("0%d" % (i + 1), rect.position + Vector2(31, 57), 16, color, BOLD_FONT)''')
game.write_text(s, encoding='utf-8')

title = root / 'title_screen.gd'
t = title.read_text(encoding='utf-8-sig').replace('`r`n', '\n').replace('``', '`')
title.write_text(t, encoding='utf-8')
print('corrected')
