import {readFileSync, writeFileSync} from 'node:fs';
const root='E:/test game/Mobile game development capabilities';
let s=readFileSync(root+'/game.gd','utf8');
s=s.replace(/\t\tfor bullet in bullets:[\s\S]*?\t\tfor enemy in enemies:/, '\t\tfor bullet in bullets:\n\t\t\t_draw_projectile(bullet)\n\t\tfor bullet in enemy_bullets:\n\t\t\t_draw_projectile(bullet)\n\t\tfor enemy in enemies:');
s=s.replace(/\t\tfor p in particles:\n\t\t\tvar alpha := clampf\(float\(p\.life\) \/ float\(p\.max\), 0\.0, 1\.0\)\n\t\t\tdraw_circle\(p\.pos, float\(p\.size\) \* \(0\.6 \+ alpha\), Color\(p\.color, alpha \* 0\.7\)\)/, '\t\tfor p in particles:\n\t\t\tvar alpha := clampf(float(p.life) / float(p.max), 0.0, 1.0)\n\t\t\tif p.has("texture"):\n\t\t\t\t_draw_effect(p)\n\t\t\telse:\n\t\t\t\tdraw_circle(p.pos, float(p.size) * (0.6 + alpha), Color(p.color, alpha * 0.7))');
writeFileSync(root+'/game.gd',s);
let t=readFileSync(root+'/title_screen.gd','utf8').replace('\n\t_draw_ship(ship_center, 1.7)','');
writeFileSync(root+'/title_screen.gd',t);
console.log('finished');
