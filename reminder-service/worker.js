const json = (value, status = 200) => Response.json(value, {status});
export function validate(input, now = Date.now()) {
  if (!input || !Number.isSafeInteger(input.revision) || input.revision <= 0 || !/^[A-Za-z0-9_-]{6,128}$/.test(input.deviceKey) || !Array.isArray(input.jobs) || input.jobs.length > 2000) throw Error('invalid schedule');
  const ids = new Set();
  for (const j of input.jobs) {
    if (!j || typeof j.id !== 'string' || j.id.length > 150 || ids.has(j.id) || !Number.isFinite(j.fireAt) || !Number.isFinite(j.expiresAt) || j.fireAt >= j.expiresAt || j.expiresAt > now + 250 * 86400000 || typeof j.title !== 'string' || j.title.length > 200 || typeof j.body !== 'string' || j.body.length > 600) throw Error('invalid reminder');
    ids.add(j.id);
  }
  return {...input, jobs: input.jobs.filter(j => j.expiresAt > now).sort((a,b) => a.fireAt-b.fireAt)};
}
export default {
  async fetch(request, env) {
    if (!env.PAIRING_TOKEN || env.PAIRING_TOKEN.length < 32) return json({code:503,message:'not configured'},503);
    if (request.headers.get('Authorization') !== 'Bearer ' + env.PAIRING_TOKEN) return json({code:401},401);
    if (new URL(request.url).pathname !== '/schedule') return json({code:404},404);
    if (!['GET','PUT','DELETE'].includes(request.method)) return json({code:405},405);
    if (Number(request.headers.get('Content-Length') || 0) > 1500000) return json({code:413},413);
    const id = env.SCHEDULE.idFromName('xinyu-private-timetable');
    return env.SCHEDULE.get(id).fetch(request);
  }
};

export class ReminderQueue {
  constructor(state, env) { this.state = state; this.env = env; }
  async fetch(request) {
    if (request.method === 'GET') {
      const value = await this.state.storage.get('plan');
      return json({code:200,count:value?.jobs.length || 0,revision:value?.revision || 0});
    }
    let input;
    try { const text = await request.text(); if (text.length > 1500000) return json({code:413},413); input = JSON.parse(text); } catch { return json({code:400},400); }
    return this.state.blockConcurrencyWhile(async () => {
      const old = await this.state.storage.get('plan');
      if (!Number.isSafeInteger(input.revision) || input.revision <= 0) return json({code:400},400);
      if (old && input.revision <= old.revision) return json({code:409,message:'stale update'},409);
      if (request.method === 'DELETE') {
        await this.state.storage.put('plan',{revision:input.revision,jobs:[]});
        await this.state.storage.deleteAlarm();
        return json({code:200,count:0});
      }
      try { input = validate(input); } catch { return json({code:400},400); }
      // A single atomic replacement cancels removed/moved lessons; preserve delivery identity across retries.
      const delivered = await this.state.storage.get('delivered') || {};
      input.jobs = input.jobs.filter(j => !delivered[j.id + ':' + j.fireAt]);
      await this.state.storage.put('plan', input);
      await this.arm(input.jobs);
      return json({code:200,count:input.jobs.length,revision:input.revision});
    });
  }
  async arm(jobs) {
    if (jobs.length) await this.state.storage.setAlarm(Math.max(Date.now()+1000, Math.min(...jobs.map(j=>j.retryAt || j.fireAt))));
    else await this.state.storage.deleteAlarm();
  }
  async alarm() {
    // Block timetable mutations while deciding and sending due notifications (each request has a deadline).
    return this.state.blockConcurrencyWhile(async () => {
      const plan = await this.state.storage.get('plan');
      if (!plan) return;
      let delivered = await this.state.storage.get('delivered') || {};
      const now = Date.now();
      delivered = Object.fromEntries(Object.entries(delivered).filter(([,t]) => t > now-250*86400000));
      const remaining = [];
      let attempts = 0;
      for (const job of plan.jobs) {
        const identity = job.id + ':' + job.fireAt;
        if (delivered[identity] || job.expiresAt <= now) continue;
        if ((job.retryAt || job.fireAt) > now) { remaining.push(job); continue; }
        // More than five minutes late is stale: do not issue misleading one-hour notices.
        if (now-job.fireAt > 5*60000) continue;
        if (attempts >= 2) { remaining.push(job); continue; }
        attempts++;
        try {
          const response = await fetch('https://api.day.app/push', {method:'POST',headers:{'Content-Type':'application/json'},redirect:'error',signal:AbortSignal.timeout(7000),body:JSON.stringify({device_key:plan.deviceKey,title:job.title,body:job.body,group:'欣语上课提醒',sound:'bell',level:'timeSensitive'})});
          const result = await response.json();
          if (!response.ok || result.code !== 200) throw Error('push failed');
          delivered[identity] = now;
          await this.state.storage.put('delivered',delivered);
        } catch { remaining.push({...job,retryAt:now+60000}); }
      }
      plan.jobs = remaining;
      await this.state.storage.put('plan',plan);
      await this.arm(remaining);
    });
  }
}
