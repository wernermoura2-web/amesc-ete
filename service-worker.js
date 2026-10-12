'use strict';
const CACHE='amesc-ete-shell-v2.1',BASE=new URL('./',self.location.href);
const SHELL=['./','assets/readers-c801e326.html','index.html','manifest.webmanifest','icons/icon-192.png','icons/icon-512.png','icons/apple-touch-icon.png'];
const allowed=new Set(SHELL.map(path=>new URL(path,BASE).href));
const cacheable=(response,url)=>response.ok&&new URL(response.url||url).origin===BASE.origin;
self.addEventListener('install',event=>event.waitUntil((async()=>{
 const cache=await caches.open(CACHE);
 await Promise.allSettled(SHELL.map(async path=>{const url=new URL(path,BASE).href,response=await fetch(url,{cache:'reload',credentials:'same-origin'});if(cacheable(response,url))await cache.put(url,response);}));
 await self.skipWaiting();
})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
 for(const key of await caches.keys())if(key.startsWith('amesc-ete-shell-')&&key!==CACHE)await caches.delete(key);
 await self.clients.claim();
})()));
self.addEventListener('fetch',event=>{
 const request=event.request,url=new URL(request.url);
 // Cache the application shell only; Supabase requests, sessions and documents never enter this cache.
 if(request.method!=='GET'||url.origin!==BASE.origin||url.search||!allowed.has(url.href))return;
 event.respondWith((async()=>{const cache=await caches.open(CACHE);try{const response=await fetch(request);if(cacheable(response,url.href))await cache.put(request,response.clone());return response;}catch(error){const saved=await cache.match(request);if(saved)return saved;throw error;}})());
});
