import argparse,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--commit',required=True);p.add_argument('runs',nargs='+');a=p.parse_args()
for run in a.runs:
    data=json.loads(subprocess.check_output(['gh','run','view',run,'--repo','wm0104/xinxin-yuwen-garden','--json','status,conclusion,headSha,name'],text=True,encoding='utf-8'))
    assert data['headSha']==a.commit,(run,'unexpected commit',data['headSha'])
    assert data['status']=='completed' and data['conclusion']=='success',(run,data)
    print(f"PASS {data['name']} run {run} at {data['headSha'][:7]}")
