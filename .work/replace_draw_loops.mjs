import {readFileSync, writeFileSync} from 'node:fs';
const path='E:/test game/Mobile game development capabilities/game.gd';
let lines=readFileSync(path,'utf8').split(/\r?\n/);
const start=lines.findIndex(x=>x.trim()==='for bullet in bullets:');
const end=lines.findIndex((x,i)=>i>start && x.trim()==='for enemy in enemies:');
if(start>=0 && end>start) lines.splice(start,end-start, '\t\tfor bullet in bullets:', '\t\t\t_draw_projectile(bullet)', '\t\tfor bullet in enemy_bullets:', '\t\t\t_draw_projectile(bullet)');
const pstart=lines.findIndex(x=>x.trim()==='for p in particles:' && lines.slice(Math.max(0,x),x).some(y=>y.includes('func _draw'))===false);
if(pstart>=0){
  const pend=pstart+3;
  lines.splice(pstart,pend-pstart, '\t\tfor p in particles:', '\t\t\tvar alpha := clampf(float(p.life) / float(p.max), 0.0, 1.0)', '\t\t\tif p.has("texture"):', '\t\t\t\t_draw_effect(p)', '\t\t\telse:', '\t\t\t\tdraw_circle(p.pos, float(p.size) * (0.6 + alpha), Color(p.color, alpha * 0.7))');
}
writeFileSync(path,lines.join('\n'));
console.log({start,end,pstart});
