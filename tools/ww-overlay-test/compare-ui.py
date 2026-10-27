#!/usr/bin/env python3
import subprocess as sp,time,json,os,sys
out=sys.argv[1]; w='/work/B_overlay'; os.makedirs(out+'/diag',exist_ok=True)
def cmd(args):
 return sp.run(args,text=True,stdout=sp.PIPE,stderr=sp.STDOUT).stdout.strip()
def shot(name):
 cmd(['import','-window','root',out+'/diag/'+name+'.png'])
def game():
 return cmd(['xdotool','search','--onlyvisible','--name','Dolphin 2609a.*Mario Kart Wii']).splitlines()[:1]
def align():
 ids=game()
 if not ids: return False
 i=ids[0]; cmd(['xdotool','windowsize',i,'640','480'])
 ext=cmd(['xprop','-id',i,'_NET_FRAME_EXTENTS']).split('=')[-1].strip().split(',')
 try: left,right,top,bottom=map(int,ext)
 except: left,top=1,18
 cmd(['xdotool','windowmove',i,str(320-left),str(164-top)])
 cmd(['xdotool','windowactivate','--sync',i]);time.sleep(2)
 info=cmd(['xwininfo','-id',i]);open(out+'/diag/geometry.txt','a').write(info+'\n')
 return True
def inspect(label):
 if not align():
  shot(label+'-no-render-window');return
 shot(label+'-title')
 # One known A input, then capture resulting screen; no further input.
 cmd(['xdotool','mousemove','640','400','mousedown','1']);time.sleep(.5);cmd(['xdotool','mouseup','1']);time.sleep(9)
 shot(label+'-after-A')
inspect('WW-B-Vulkan')
cmd(['pkill','-f','^/app/bin/dolphin-emu']);time.sleep(3)
base=json.load(open('/work/run/CT-MKWII/RR.json'))
for label,xml,backend in [('direct-B-Vulkan','RetroRewind6.xml','Vulkan'),('direct-A-Vulkan','official-diagnostic.xml','Vulkan'),('direct-B-OGL','RetroRewind6.xml','OGL')]:
 d=json.loads(json.dumps(base));d['riivolution']['patches'][0]['xml']=w+'/user/Load/Riivolution/WheelWizard/riivolution/'+xml
 p='/work/run/'+label+'.json';json.dump(d,open(p,'w'))
 log=open(out+'/diag/'+label+'-stderr.txt','w')
 proc=sp.Popen(['/usr/games/dolphin-emu','-b','-u',w+'/user','-e',p,'--config=Dolphin.Core.GFXBackend='+backend,'--config=Dolphin.Core.EnableCheats=False'],stdout=log,stderr=log)
 time.sleep(25);inspect(label)
 proc.terminate();cmd(['pkill','-f','^/app/bin/dolphin-emu']);time.sleep(3);log.close()
# Only the newly added diagnostic stderr files can contain verbose local logs; keep concise errors, never payload.
for name in os.listdir(out+'/diag'):
 if name.endswith('-stderr.txt'):
  p=out+'/diag/'+name
  lines=open(p,errors='replace').readlines()
  keep=[line[:220] for line in lines if any(t in line.lower() for t in ['error','failed','vulkan','opengl','video backend'])]
  open(p,'w').writelines(keep[-50:])
