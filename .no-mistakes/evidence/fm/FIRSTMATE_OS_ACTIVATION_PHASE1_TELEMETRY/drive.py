import os,pathlib,subprocess,time,json,stat
root=pathlib.Path.cwd(); lab=root/'.telemetry-live/manual'; lab.mkdir(parents=True,exist_ok=True)
evidence=pathlib.Path('/home/chris_wheeler/.no-mistakes/evidence/01M2CQB22ANAWVVCZSAC9ZD8ME')
results=[]
for mode in ['enabled','disabled','blocked','symlink','rotation','recovered']:
 home=lab/mode; state=home/'selected-state'; state.mkdir(parents=True)
 env={k:v for k,v in os.environ.items() if not k.startswith('FM_') and k not in ['STATE']}
 env.update(FM_HOME=str(home),FM_STATE_OVERRIDE=str(state),FM_POLL='1',FM_SIGNAL_GRACE='0',FM_CHECK_INTERVAL='999999',FM_HEARTBEAT='999999',FM_HOME_SUMMARY_INTERVAL='999999')
 file=state/'telemetry.jsonl'
 if mode=='disabled': env['FM_TELEMETRY']='0'
 if mode=='blocked': file.mkdir()
 if mode=='symlink':
  target=home/'target'; target.write_text('preserve me'); file.symlink_to(target)
 if mode=='rotation':
  record=json.dumps(dict(schema='fm-telemetry.v1',ts='2026-09-13T00:00:00Z',event='watch_cycle',signal='prior',source='watch-arm'))+'\n'
  for suffix in ['', '.1','.2','.3']:
   p=state/('telemetry.jsonl'+suffix); p.write_text(record*(1048576//len(record))); p.chmod(0o644)
 if mode=='recovered':
  holder=subprocess.Popen(['bash','-c','. bin/fm-wake-lib.sh; fm_lock_try_acquire "$STATE/telemetry.jsonl.lock"; touch "$STATE/ready"; exec sleep 30'],env=env)
  for _ in range(100):
   if (state/'ready').exists(): break
   time.sleep(.05)
  assert (state/'ready').exists(); holder.kill(); holder.wait()
 proc=subprocess.Popen(['bash','bin/fm-watch-arm.sh'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 try:
  for _ in range(200):
   if (state/'.last-watcher-beat').exists(): break
   if proc.poll() is not None: break
   time.sleep(.1)
  assert (state/'.last-watcher-beat').exists(),mode
  (state/'demo.status').write_text('done: live telemetry validation finished\n')
  out,err=proc.communicate(timeout=25)
 except:
  proc.terminate(); proc.communicate(timeout=10); raise
 assert proc.returncode==0,(mode,out,err)
 assert 'signal:' in out and 'demo.status' in (state/'.wake-queue').read_text(),(mode,out)
 row=dict(mode=mode,exit=proc.returncode,stdout=out,stderr=err,wake_queue=(state/'.wake-queue').read_text(),ledger=(state/'.watch-cycle-exits.log').read_text())
 if mode in ['enabled','rotation','recovered']:
  records=[json.loads(x) for x in file.read_text().splitlines()]; assert len(records)==1 and records[0]['signal']=='actionable-signal'
  row['telemetry']=records; row['files']=[dict(name=p.name,bytes=p.stat().st_size,mode=oct(stat.S_IMODE(p.stat().st_mode))) for p in sorted(state.glob('telemetry.jsonl*'))]
  assert all(x['mode']=='0o600' and x['bytes']<=1048576 for x in row['files'])
  assert len(row['files'])==(4 if mode=='rotation' else 1)
 if mode=='disabled': assert not file.exists()
 if mode=='blocked': assert file.is_dir()
 if mode=='symlink': assert target.read_text()=='preserve me' and file.is_symlink()
 assert not (home/'state'/'telemetry.jsonl').exists()
 results.append(row); (evidence/'live-results.json').write_text(json.dumps(results,indent=2))
 print(mode, 'wake delivered; telemetry contract satisfied',flush=True)
