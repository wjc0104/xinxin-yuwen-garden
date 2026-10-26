export const PLAYBACK_RATES = [0.5,0.75,1,1.25,1.5,2];
// A session owns exactly one resource and one video node. No upstream locator
// crosses this boundary, and disposed sessions cannot attach a late response.
export function createPlayerSession({video,resourceID,fetchImpl=globalThis.fetch,onStatus=()=>{},position=0,rate=1}) {
  let generation=0,disposed=false,loading=true,controller,timer,resume=position,quality='';
  const currentTime=()=>!disposed&&!loading&&video.readyState>=1&&Number.isFinite(video.currentTime)?Math.floor(video.currentTime):null;
  const remember=()=>{const time=currentTime();if(time!==null)resume=time;};
  const clear=()=>{video.pause();video.removeAttribute('src');video.load();};
  const seek=seconds=>{
    if(currentTime()===null||!Number.isFinite(seconds)||seconds<0||!Number.isFinite(video.duration)||seconds>video.duration)return false;
    video.currentTime=seconds;resume=seconds;return true;
  };
  const loaded=()=>{
    if(disposed||!video.src)return;loading=false;video.playbackRate=rate;
    if(resume>0&&Number.isFinite(video.duration))video.currentTime=Math.min(resume,video.duration);
    onStatus(`视频已就绪${quality}。请点击系统播放按钮。`,false);
  };
  // Errors before loadedmetadata must also surface, but not errors raised by clear().
  const mediaError=()=>{if(!disposed&&video.getAttribute?.('src')){remember();onStatus('视频未能播放，可能受原站限制或网络影响。请重试；笔记保留。',true);}};
  video.addEventListener('loadedmetadata',loaded);video.addEventListener('error',mediaError);video.addEventListener('timeupdate',remember);
  return {
    resourceID,currentTime,seek,
    setRate(value){if(PLAYBACK_RATES.includes(value)){rate=value;video.playbackRate=value;}},
    async fullscreen(){
      if(disposed)return;
      try{if(video.webkitEnterFullscreen)video.webkitEnterFullscreen();else if(video.requestFullscreen)await video.requestFullscreen();else onStatus('请使用系统播放器中的全屏按钮。',false);}
      catch{onStatus('当前浏览器未进入全屏，请使用系统播放器中的全屏按钮。',true);}
    },
    async retry(){
      if(disposed)return;remember();const mine=++generation;controller?.abort();clearTimeout(timer);loading=true;clear();
      controller=new AbortController();const signal=controller.signal;
      timer=setTimeout(()=>controller.abort(),25000);onStatus('正在连接此分集的公开视频…',false);
      try{
        const response=await fetchImpl(`/api/video/${resourceID}`,{signal,credentials:'same-origin',cache:'no-store',redirect:'error'});
        if(disposed||mine!==generation)return;
        if(!response.ok)throw new Error(response.status===401?'请联网并重新登录所有者账号后重试。':response.status===503?'原站暂时限流，请稍后重试。':'此视频暂不可用，请稍后重试。');
        if(!response.headers.get('content-type')?.includes('application/json'))throw new Error('媒体服务未接通或登录已失效，请重新登录后重试。');
        const metadata=await response.json();if(disposed||mine!==generation)return;
        if(metadata.resourceID!==resourceID||metadata.streamURL!==`/api/video/${resourceID}/stream`)throw new Error('视频来源校验失败，未加载其他视频。');
        quality=Number.isInteger(metadata.height)&&metadata.height>0?` · 原站返回 ${metadata.height}P`:' · 原站未提供清晰度';
        video.src=metadata.streamURL;video.load();onStatus(`已连接媒体${quality}，正在读取视频…`,false);
      }catch(error){if(!disposed&&mine===generation)onStatus(signal.aborted?'连接超时，请重试。笔记与播放位置已保留。':error.message||'连接失败，请重试。',true);}
      finally{if(mine===generation)clearTimeout(timer);}
    },
    dispose(){if(disposed)return {position:resume,rate};remember();disposed=true;generation++;controller?.abort();clearTimeout(timer);video.removeEventListener('loadedmetadata',loaded);video.removeEventListener('error',mediaError);video.removeEventListener('timeupdate',remember);clear();return {position:resume,rate};}
  };
}
