#!/bin/bash
set -e
echo "=== Sub-phase B: Maicha UI v2 — Full Platform UI ==="

BASE="/opt/ai-server"
cd "$BASE"

# Generate the UI using Python to avoid shell escaping issues
python3 << 'PYSCRIPT'
html = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title>Maicha — AI Platform</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><rect width='64' height='64' rx='16' fill='%230EA5E9'/><text x='32' y='44' font-size='32' text-anchor='middle' font-weight='900' fill='white'>M</text></svg>">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/react/18.2.0/umd/react.production.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/react-dom/18.2.0/umd/react-dom.production.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/babel-standalone/7.23.9/babel.min.js"></script>
<style>
:root{--bg:#0B0F1A;--bg2:#111827;--bg3:#1F2937;--border:#374151;--text:#F9FAFB;--text2:#9CA3AF;--text3:#6B7280;--blue:#3B82F6;--green:#10B981;--red:#EF4444;--orange:#F97316;--purple:#8B5CF6;--pink:#EC4899;--amber:#F59E0B;--teal:#14B8A6;--radius:12px}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:var(--bg);color:var(--text);font-family:'Inter',sans-serif;overflow:hidden}
::-webkit-scrollbar{width:4px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:var(--bg3);border-radius:4px}
input:focus,select:focus,textarea:focus{outline:none}
button{cursor:pointer;font-family:inherit}
@keyframes fadeIn{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:translateY(0)}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes pulse{0%,100%{opacity:.4}50%{opacity:1}}
.fade{animation:fadeIn .3s ease}
</style>
</head>
<body>
<div id="root"></div>
<script type="text/babel">
const{useState,useEffect,useRef,useCallback}=React;
const API=window.location.origin;

const AGENTS=[
{name:"restaurant",icon:"\u{1F37D}\uFE0F",label:"Restaurant",desc:"Orders, menu, reservations",color:"#F97316"},
{name:"real-estate",icon:"\u{1F3E0}",label:"Real Estate",desc:"Property listings & inquiries",color:"#3B82F6"},
{name:"social-media",icon:"\u{1F4F1}",label:"Social Media",desc:"Content & hashtags",color:"#EC4899"},
{name:"marketing",icon:"\u{1F4E3}",label:"Marketing",desc:"Ads, emails, campaigns",color:"#8B5CF6"},
{name:"video",icon:"\u{1F3AC}",label:"Video",desc:"Scripts & production",color:"#10B981"},
{name:"hermes",icon:"\u{1F9E0}",label:"Hermes",desc:"Orchestrator + Nepali",color:"#F59E0B"},
];

async function api(path,opts={}){
const h={"Content-Type":"application/json",...(opts.headers||{})};
const token=localStorage.getItem("maicha_token");
if(token)h["Authorization"]="Bearer "+token;
const r=await fetch(API+path,{...opts,headers:h});
if(!r.ok){const e=await r.json().catch(()=>({}));throw new Error(e.detail||"HTTP "+r.status)}
return r.json();
}

function Btn({children,onClick,color,small,disabled,full}){
return <button onClick={onClick} disabled={disabled} style={{
padding:small?"6px 14px":"10px 20px",borderRadius:10,border:"none",
background:disabled?"var(--bg3)":color||"var(--blue)",color:"#fff",
fontSize:small?12:14,fontWeight:600,transition:"all .2s",opacity:disabled?.5:1,
width:full?"100%":"auto"
}}>{children}</button>
}

function Input({value,onChange,placeholder,type,label}){
return <div style={{marginBottom:12}}>
{label&&<div style={{fontSize:12,color:"var(--text2)",marginBottom:4,fontWeight:500}}>{label}</div>}
<input value={value} onChange={e=>onChange(e.target.value)} placeholder={placeholder} type={type||"text"}
style={{width:"100%",padding:"10px 14px",borderRadius:10,border:"1px solid var(--border)",
background:"var(--bg2)",color:"var(--text)",fontSize:14}}/>
</div>
}

// ═══ AUTH SCREEN ═══
function AuthScreen({onAuth}){
const[mode,setMode]=useState("guest");
const[email,setEmail]=useState("");
const[password,setPassword]=useState("");
const[name,setName]=useState("");
const[error,setError]=useState("");
const[loading,setLoading]=useState(false);

const handleGuest=async()=>{
setLoading(true);
try{const d=await api("/auth/guest",{method:"POST"});
localStorage.setItem("maicha_token",d.token);
onAuth(d.user)}catch(e){setError(e.message)}
setLoading(false)};

const handleSubmit=async()=>{
setLoading(true);setError("");
try{
const endpoint=mode==="login"?"/auth/login":"/auth/register";
const body=mode==="login"?{email,password}:{email,password,full_name:name||undefined};
const d=await api(endpoint,{method:"POST",body:JSON.stringify(body)});
if(d.status==="error"){setError(d.message);setLoading(false);return}
localStorage.setItem("maicha_token",d.token);
onAuth(d.user)}catch(e){setError(e.message)}
setLoading(false)};

return <div style={{minHeight:"100vh",display:"flex",alignItems:"center",justifyContent:"center",
background:"linear-gradient(135deg,#0B0F1A 0%,#1a1040 50%,#0B0F1A 100%)"}}>
<div style={{width:400,maxWidth:"90vw",padding:36,background:"var(--bg2)",borderRadius:20,
border:"1px solid var(--border)"}} className="fade">
<div style={{textAlign:"center",marginBottom:28}}>
<div style={{width:56,height:56,borderRadius:16,background:"linear-gradient(135deg,#3B82F6,#8B5CF6)",
display:"inline-flex",alignItems:"center",justifyContent:"center",fontSize:28,fontWeight:900,color:"#fff",marginBottom:12}}>M</div>
<div style={{fontSize:24,fontWeight:800,letterSpacing:"-.02em"}}>Maicha</div>
<div style={{fontSize:12,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace",letterSpacing:".1em",marginTop:4}}>AI AUTOMATION PLATFORM</div>
</div>

<div style={{display:"flex",gap:4,background:"var(--bg)",borderRadius:10,padding:3,marginBottom:20}}>
{["guest","login","register"].map(m=><button key={m} onClick={()=>{setMode(m);setError("")}}
style={{flex:1,padding:"8px",borderRadius:8,border:"none",fontSize:13,fontWeight:600,
background:mode===m?"var(--bg3)":"transparent",color:mode===m?"var(--text)":"var(--text3)",
textTransform:"capitalize"}}>{m}</button>)}
</div>

{mode==="guest"?<div style={{textAlign:"center",padding:"20px 0"}}>
<div style={{fontSize:14,color:"var(--text2)",marginBottom:16,lineHeight:1.6}}>
No account needed. Start chatting with AI agents instantly.</div>
<Btn onClick={handleGuest} full disabled={loading} color="linear-gradient(135deg,#3B82F6,#8B5CF6)">
{loading?"Loading...":"Continue as Guest"}</Btn>
</div>:<div>
{mode==="register"&&<Input value={name} onChange={setName} placeholder="Full name" label="Name"/>}
<Input value={email} onChange={setEmail} placeholder="you@email.com" label="Email" type="email"/>
<Input value={password} onChange={setPassword} placeholder="Password" label="Password" type="password"/>
{error&&<div style={{color:"var(--red)",fontSize:13,marginBottom:12,padding:"8px 12px",
background:"#EF444415",borderRadius:8}}>{error}</div>}
<Btn onClick={handleSubmit} full disabled={loading}>{loading?"Loading...":mode==="login"?"Sign In":"Create Account"}</Btn>
</div>}
</div></div>
}

// ═══ MAIN APP ═══
function App(){
const[user,setUser]=useState(null);
const[tab,setTab]=useState("chat");
const[agent,setAgent]=useState("restaurant");
const[models,setModels]=useState(null);
const[selectedModel,setSelectedModel]=useState("");
const[messages,setMessages]=useState([]);
const[input,setInput]=useState("");
const[loading,setLoading]=useState(false);
const[sessionId,setSessionId]=useState(null);
const[stats,setStats]=useState(null);
const[menuData,setMenuData]=useState(null);
const[propertiesData,setPropertiesData]=useState(null);
const[ordersData,setOrdersData]=useState(null);
const[eventsData,setEventsData]=useState(null);
const[settings,setSettings]=useState(null);
const[settingsTab,setSettingsTab]=useState("smtp");
const[settingsForm,setSettingsForm]=useState({});
const[settingsMsg,setSettingsMsg]=useState("");
const[exploreTab,setExploreTab]=useState("menu");
const[sidebar,setSidebar]=useState(true);
const[serverOk,setServerOk]=useState(false);
const chatEnd=useRef(null);
const inputRef=useRef(null);

const isAdmin=user?.role==="admin";
const activeAgent=AGENTS.find(a=>a.name===agent);

useEffect(()=>{chatEnd.current?.scrollIntoView({behavior:"smooth"})},[messages,loading]);
useEffect(()=>{api("/health").then(()=>setServerOk(true)).catch(()=>setServerOk(false))},[]);
useEffect(()=>{api("/models").then(d=>{setModels(d);setSelectedModel(d.default?.name||"qwen3:8b")}).catch(()=>{})},[]);

const TABS=[
{id:"chat",label:"Chat",icon:"\u{1F4AC}"},
{id:"explore",label:"Explore",icon:"\u{1F50D}"},
{id:"stats",label:"Dashboard",icon:"\u{1F4CA}"},
...(isAdmin?[{id:"models",label:"Models",icon:"\u{1F916}"},{id:"settings",label:"Settings",icon:"\u2699\uFE0F"}]:[]),
];

const send=useCallback(async()=>{
if(!input.trim()||loading)return;
const msg=input.trim();setInput("");
setMessages(p=>[...p,{role:"user",content:msg}]);setLoading(true);
try{const d=await api("/chat",{method:"POST",body:JSON.stringify({message:msg,agent_type:agent,model:selectedModel,session_id:sessionId||"new"})});
setSessionId(d.session_id);
setMessages(p=>[...p,{role:"assistant",content:d.response,elapsed:d.elapsed_seconds,model:d.model_used}])}
catch(e){setMessages(p=>[...p,{role:"assistant",content:"Error: "+e.message}])}
setLoading(false)},[input,loading,agent,selectedModel,sessionId]);

const clearChat=()=>{setMessages([]);setSessionId(null)};

const download=()=>{
const t=messages.map(m=>(m.role==="user"?"You":activeAgent.label)+": "+m.content).join("\n\n---\n\n");
const b=new Blob([t],{type:"text/plain"});const u=URL.createObjectURL(b);
const a=document.createElement("a");a.href=u;a.download="maicha-"+agent+"-"+new Date().toISOString().slice(0,10)+".txt";a.click();URL.revokeObjectURL(u)};

const loadExplore=useCallback(async(s)=>{
setExploreTab(s);
try{
if(s==="menu"&&!menuData)setMenuData(await api("/menu"));
if(s==="properties"&&!propertiesData)setPropertiesData(await api("/properties"));
if(s==="orders"&&!ordersData)setOrdersData(await api("/orders"));
if(s==="events"&&!eventsData)setEventsData(await api("/events"));
}catch(e){console.error(e)}},[menuData,propertiesData,ordersData,eventsData]);

const loadStats=useCallback(async()=>{try{setStats(await api("/stats"))}catch(e){}},[]);
const loadSettings=useCallback(async()=>{try{setSettings(await api("/settings"))}catch(e){}},[]);

useEffect(()=>{if(tab==="stats")loadStats()},[tab]);
useEffect(()=>{if(tab==="explore")loadExplore("menu")},[tab]);
useEffect(()=>{if(tab==="settings"&&isAdmin)loadSettings()},[tab]);

const saveSettings=async(category)=>{
setSettingsMsg("");
try{
const endpoints={smtp:"/settings/smtp",telegram:"/settings/telegram",slack:"/settings/slack",discord:"/settings/discord",whatsapp:"/settings/whatsapp"};
await api(endpoints[category],{method:"POST",body:JSON.stringify(settingsForm)});
setSettingsMsg("Saved!");loadSettings()}catch(e){setSettingsMsg("Error: "+e.message)}};

const testChannel=async(ch)=>{
setSettingsMsg("Testing...");
try{const d=await api("/settings/"+ch+"/test",{method:"POST"});
setSettingsMsg(d.status==="ok"?"Test passed!":"Failed: "+(d.message||"unknown"))}catch(e){setSettingsMsg("Error: "+e.message)}};

const pullModel=async(name)=>{
try{await api("/models/ollama/pull",{method:"POST",body:JSON.stringify({name})});
setModels(await api("/models"))}catch(e){alert(e.message)}};

const logout=()=>{localStorage.removeItem("maicha_token");setUser(null)};

const quickPrompts={
"restaurant":["What's on the menu?","Order a Neural Burger","Reserve table for 4"],
"real-estate":["Show properties","Under $3000","Schedule viewing"],
"social-media":["Instagram post about food","TikTok captions","Hashtags for travel"],
"marketing":["Email subject line","Ad copy summer sale","Blog post about AI"],
"video":["30s TikTok script","YouTube intro","Create voiceover job"],
"hermes":["Create post and translate to Nepali","Route order to restaurant","Generate bilingual content"],
};

if(!user)return <AuthScreen onAuth={setUser}/>;

return <div style={{height:"100vh",display:"flex",flexDirection:"column"}}>
{/* HEADER */}
<header style={{display:"flex",alignItems:"center",justifyContent:"space-between",padding:"10px 16px",
borderBottom:"1px solid var(--border)",background:"var(--bg2)",flexShrink:0,gap:8,flexWrap:"wrap"}}>
<div style={{display:"flex",alignItems:"center",gap:10}}>
<button onClick={()=>setSidebar(!sidebar)} style={{background:"none",border:"none",color:"var(--text2)",fontSize:20,padding:4,display:"flex"}}>
{sidebar?"\u2630":"\u2630"}</button>
<div style={{width:32,height:32,borderRadius:10,background:"linear-gradient(135deg,#3B82F6,#8B5CF6)",
display:"flex",alignItems:"center",justifyContent:"center",fontSize:16,fontWeight:900,color:"#fff"}}>M</div>
<span style={{fontWeight:800,fontSize:18,letterSpacing:"-.02em"}}>Maicha</span>
</div>

<div style={{display:"flex",gap:3,background:"var(--bg)",borderRadius:10,padding:3,overflow:"auto"}}>
{TABS.map(t=><button key={t.id} onClick={()=>setTab(t.id)} style={{
padding:"6px 14px",borderRadius:8,border:"none",fontSize:12,fontWeight:600,whiteSpace:"nowrap",
background:tab===t.id?"var(--bg3)":"transparent",color:tab===t.id?"var(--text)":"var(--text3)",
display:"flex",alignItems:"center",gap:4
}}><span>{t.icon}</span>{t.label}</button>)}
</div>

<div style={{display:"flex",alignItems:"center",gap:10}}>
{models&&<select value={selectedModel} onChange={e=>setSelectedModel(e.target.value)}
style={{background:"var(--bg)",border:"1px solid var(--border)",borderRadius:8,padding:"6px 10px",
color:"var(--text2)",fontSize:11,fontFamily:"'JetBrains Mono',monospace"}}>
{(models.ollama_installed||[]).map(m=><option key={m.name} value={m.name}>{m.name} ({m.details?.parameter_size})</option>)}
{(models.registered||[]).filter(m=>m.provider!=="ollama").map(m=><option key={m.name} value={m.name}>{m.name} ({m.provider})</option>)}
</select>}
<div style={{display:"flex",alignItems:"center",gap:5,fontSize:11,color:"var(--text3)"}}>
<div style={{width:6,height:6,borderRadius:"50%",background:serverOk?"var(--green)":"var(--red)",
animation:"pulse 2s infinite"}}/>{serverOk?"Online":"Offline"}</div>
<div style={{fontSize:11,color:"var(--text3)",padding:"4px 10px",background:"var(--bg)",borderRadius:8,
border:"1px solid var(--border)"}}>{user.name||user.email?.split("@")[0]}
<span style={{color:isAdmin?"var(--amber)":"var(--text3)",marginLeft:4,fontSize:10}}>({user.role})</span></div>
<button onClick={logout} style={{background:"none",border:"none",color:"var(--text3)",fontSize:16}} title="Logout">{"\u{1F6AA}"}</button>
</div>
</header>

<div style={{flex:1,display:"flex",overflow:"hidden"}}>

{/* SIDEBAR */}
{tab==="chat"&&sidebar&&<aside style={{width:220,padding:"12px 10px",borderRight:"1px solid var(--border)",
display:"flex",flexDirection:"column",gap:6,overflowY:"auto",flexShrink:0,background:"var(--bg2)"}}>
<div style={{fontSize:10,fontWeight:700,color:"var(--text3)",letterSpacing:".1em",padding:"0 6px 6px",
fontFamily:"'JetBrains Mono',monospace"}}>AGENTS</div>
{AGENTS.map(a=><button key={a.name} onClick={()=>{setAgent(a.name);clearChat()}} style={{
display:"flex",alignItems:"center",gap:10,padding:"10px 12px",borderRadius:10,width:"100%",textAlign:"left",
background:agent===a.name?a.color+"18":"transparent",border:agent===a.name?"1px solid "+a.color+"40":"1px solid transparent",
transition:"all .2s"}}>
<span style={{fontSize:20}}>{a.icon}</span>
<div><div style={{fontSize:13,fontWeight:600,color:agent===a.name?a.color:"var(--text)"}}>{a.label}</div>
<div style={{fontSize:10,color:"var(--text3)"}}>{a.desc}</div></div>
</button>)}
<div style={{flex:1}}/>
<div style={{padding:"10px 12px",borderRadius:10,background:"var(--bg)",border:"1px solid var(--border)",fontSize:11,color:"var(--text3)"}}>
{user.role==="guest"?"Guest session (24h)":"Logged in as "+user.role}
</div>
</aside>}

{/* ═══ CHAT ═══ */}
{tab==="chat"&&<main style={{flex:1,display:"flex",flexDirection:"column",minWidth:0}}>
<div style={{padding:"10px 16px",borderBottom:"1px solid var(--border)",display:"flex",alignItems:"center",justifyContent:"space-between",background:"var(--bg2)"}}>
<div style={{display:"flex",alignItems:"center",gap:8}}>
<span style={{fontSize:20}}>{activeAgent?.icon}</span>
<span style={{fontWeight:700,fontSize:14,color:activeAgent?.color}}>{activeAgent?.label}</span>
<span style={{fontSize:11,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>{selectedModel}</span>
</div>
<div style={{display:"flex",gap:6}}>
{messages.length>0&&<><Btn small onClick={download} color="var(--bg3)">{"\u2B07"} Save</Btn>
<Btn small onClick={clearChat} color="#EF444430">{"\u2715"} Clear</Btn></>}
</div></div>

<div style={{flex:1,overflowY:"auto",padding:"20px 24px"}}>
{messages.length===0&&<div className="fade" style={{textAlign:"center",paddingTop:60}}>
<div style={{fontSize:48,marginBottom:12}}>{activeAgent?.icon}</div>
<div style={{fontSize:20,fontWeight:700,marginBottom:6}}>Chat with {activeAgent?.label}</div>
<div style={{fontSize:13,color:"var(--text3)",maxWidth:360,margin:"0 auto",lineHeight:1.6}}>{activeAgent?.desc}</div>
<div style={{display:"flex",gap:6,justifyContent:"center",marginTop:24,flexWrap:"wrap"}}>
{(quickPrompts[agent]||[]).map(q=><button key={q} onClick={()=>{setInput(q);inputRef.current?.focus()}} style={{
padding:"7px 16px",borderRadius:20,border:"1px solid "+activeAgent.color+"30",background:activeAgent.color+"10",
color:activeAgent.color,fontSize:12,fontWeight:600}}>{q}</button>)}
</div></div>}

{messages.map((m,i)=><div key={i} className="fade" style={{display:"flex",justifyContent:m.role==="user"?"flex-end":"flex-start",marginBottom:14}}>
<div style={{maxWidth:"80%",padding:"12px 16px",borderRadius:m.role==="user"?"16px 16px 4px 16px":"16px 16px 16px 4px",
background:m.role==="user"?"var(--blue)":"var(--bg3)",fontSize:14,lineHeight:1.65,whiteSpace:"pre-wrap",wordBreak:"break-word"}}>
{m.content}
{m.elapsed&&<div style={{fontSize:10,color:"var(--text3)",marginTop:6,textAlign:"right",fontFamily:"'JetBrains Mono',monospace"}}>{m.elapsed}s \u00B7 {m.model}</div>}
</div></div>)}

{loading&&<div style={{display:"flex",gap:5,padding:12}}>
{[0,1,2].map(i=><div key={i} style={{width:8,height:8,borderRadius:"50%",background:activeAgent?.color,animation:"pulse 1.2s ease infinite "+(i*.2)+"s"}}/>)}</div>}
<div ref={chatEnd}/>
</div>

<div style={{padding:"12px 16px",borderTop:"1px solid var(--border)",background:"var(--bg2)"}}>
<div style={{display:"flex",gap:8,background:"var(--bg)",border:"1px solid "+(input.trim()?activeAgent?.color+"50":"var(--border)"),
borderRadius:14,padding:"4px 4px 4px 16px",transition:"all .2s"}}>
<input ref={inputRef} value={input} onChange={e=>setInput(e.target.value)}
onKeyDown={e=>{if(e.key==="Enter"&&!e.shiftKey)send()}}
placeholder={"Message "+activeAgent?.label+"..."} disabled={loading}
style={{flex:1,background:"transparent",border:"none",color:"var(--text)",fontSize:14,padding:"10px 0",opacity:loading?.5:1}}/>
<Btn onClick={send} disabled={loading||!input.trim()} color={input.trim()?activeAgent?.color:"var(--bg3)"}>{loading?"\u00B7\u00B7\u00B7":"Send"}</Btn>
</div></div>
</main>}

{/* ═══ EXPLORE ═══ */}
{tab==="explore"&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{fontSize:22,fontWeight:700,marginBottom:4}}>Explore data</div>
<div style={{fontSize:13,color:"var(--text3)",marginBottom:20}}>Live data from your AI platform</div>
<div style={{display:"flex",gap:6,marginBottom:20,flexWrap:"wrap"}}>
{[{id:"menu",label:"\u{1F37D}\uFE0F Menu"},{id:"properties",label:"\u{1F3E0} Properties"},{id:"orders",label:"\u{1F4CB} Orders"},{id:"events",label:"\u26A1 Events"}].map(t=>
<Btn key={t.id} onClick={()=>loadExplore(t.id)} small color={exploreTab===t.id?"var(--blue)":"var(--bg3)"}>{t.label}</Btn>)}
</div>

{exploreTab==="menu"&&menuData&&<div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(260px,1fr))",gap:12}}>
{menuData.menu_items?.map((item,i)=><div key={i} className="fade" style={{background:"var(--bg2)",border:"1px solid var(--border)",borderRadius:14,padding:18}}>
<div style={{display:"flex",justifyContent:"space-between",marginBottom:6}}>
<span style={{fontWeight:700,fontSize:15}}>{item.name}</span>
<span style={{fontWeight:800,color:"var(--orange)",fontFamily:"'JetBrains Mono',monospace"}}>${item.price}</span></div>
<div style={{fontSize:13,color:"var(--text2)",marginBottom:8}}>{item.description}</div>
<div style={{display:"flex",gap:4,flexWrap:"wrap"}}>
<span style={{fontSize:10,padding:"3px 8px",borderRadius:12,background:"var(--bg3)",color:"var(--text3)"}}>{item.category}</span>
{(item.dietary_tags||[]).map((t,j)=><span key={j} style={{fontSize:10,padding:"3px 8px",borderRadius:12,background:"#10B98115",color:"var(--green)"}}>{t}</span>)}
</div></div>)}</div>}

{exploreTab==="properties"&&propertiesData&&<div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(300px,1fr))",gap:12}}>
{propertiesData.properties?.map((p,i)=><div key={i} className="fade" style={{background:"var(--bg2)",border:"1px solid var(--border)",borderRadius:14,padding:18}}>
<div style={{fontWeight:700,fontSize:15,marginBottom:4}}>{p.title}</div>
<div style={{fontSize:20,fontWeight:800,color:"var(--blue)",fontFamily:"'JetBrains Mono',monospace",marginBottom:6}}>${Number(p.price).toLocaleString()}/mo</div>
<div style={{fontSize:13,color:"var(--text2)",marginBottom:8}}>{p.description}</div>
<div style={{display:"flex",gap:12,fontSize:12,color:"var(--text3)"}}>
<span>{"\u{1F6CF}"} {p.bedrooms} bed</span><span>{"\u{1F6BF}"} {p.bathrooms} bath</span><span>{"\u{1F4CD}"} {p.city}, {p.state}</span>
</div></div>)}
{propertiesData.properties?.length===0&&<div style={{color:"var(--text3)",padding:40,textAlign:"center"}}>No properties</div>}
</div>}

{exploreTab==="orders"&&ordersData&&<div>
{ordersData.orders?.length===0&&<div style={{color:"var(--text3)",padding:40,textAlign:"center"}}>No orders yet</div>}
{ordersData.orders?.map((o,i)=><div key={i} className="fade" style={{background:"var(--bg2)",border:"1px solid var(--border)",
borderRadius:12,padding:"14px 18px",marginBottom:8,display:"flex",justifyContent:"space-between",alignItems:"center"}}>
<div><div style={{fontWeight:700,fontSize:14}}>{o.customer_name||"Guest"}</div>
<div style={{fontSize:11,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>#{String(o.id).slice(0,8)}</div></div>
<div style={{textAlign:"right"}}><div style={{fontWeight:800,color:"var(--green)",fontFamily:"'JetBrains Mono',monospace"}}>${Number(o.total).toFixed(2)}</div>
<span style={{fontSize:10,padding:"2px 8px",borderRadius:6,background:o.status==="confirmed"?"#10B98118":"#EF444418",
color:o.status==="confirmed"?"var(--green)":"var(--red)"}}>{o.status}</span></div></div>)}</div>}

{exploreTab==="events"&&eventsData&&<div>
{eventsData.events?.length===0&&<div style={{color:"var(--text3)",padding:40,textAlign:"center"}}>No events</div>}
{eventsData.events?.map((e,i)=><div key={i} className="fade" style={{background:"var(--bg2)",border:"1px solid var(--border)",
borderRadius:10,padding:"10px 14px",marginBottom:6,display:"flex",gap:10,alignItems:"center",fontSize:12}}>
<span style={{padding:"3px 8px",borderRadius:6,background:"var(--bg3)",color:"var(--amber)",fontFamily:"'JetBrains Mono',monospace",fontSize:10,whiteSpace:"nowrap"}}>{e.event_type}</span>
<span style={{color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>{e.source}</span>
<span style={{color:"var(--text3)",flex:1,overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{JSON.stringify(e.data)}</span>
</div>)}</div>}
</div>}

{/* ═══ DASHBOARD ═══ */}
{tab==="stats"&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:20}}>
<div><div style={{fontSize:22,fontWeight:700}}>Dashboard</div>
<div style={{fontSize:13,color:"var(--text3)"}}>System statistics</div></div>
<Btn small onClick={loadStats} color="var(--bg3)">{"\u21BB"} Refresh</Btn>
</div>
{stats?<div style={{display:"flex",flexWrap:"wrap",gap:12}}>
{[["Conversations",stats.stats?.conversations,"\u{1F4AC}","var(--blue)"],
["Messages",stats.stats?.messages,"\u2709\uFE0F","var(--purple)"],
["Orders",stats.stats?.orders,"\u{1F37D}\uFE0F","var(--orange)"],
["Reservations",stats.stats?.reservations,"\u{1F4C5}","var(--pink)"],
["Properties",stats.stats?.property_listings,"\u{1F3E0}","var(--blue)"],
["Inquiries",stats.stats?.property_inquiries,"\u{1F4E9}","var(--green)"],
["Content Queue",stats.stats?.content_queue,"\u{1F4F1}","var(--amber)"],
["Scripts",stats.stats?.generated_scripts,"\u{1F3AC}","var(--purple)"],
["Events",stats.stats?.events,"\u26A1","var(--amber)"],
["n8n Workflows",stats.stats?.n8n_workflows,"\u2699\uFE0F","var(--teal)"],
["n8n Executions",stats.stats?.n8n_executions,"\u{1F504}","var(--teal)"],
].map(([label,val,icon,color])=><div key={label} style={{background:"var(--bg2)",border:"1px solid var(--border)",
borderRadius:14,padding:"18px 20px",flex:"1 1 150px",minWidth:150}}>
<div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:8}}>
<span style={{fontSize:20}}>{icon}</span>
<span style={{fontSize:10,color,fontFamily:"'JetBrains Mono',monospace",background:color+"15",padding:"2px 8px",borderRadius:6}}>{label}</span></div>
<div style={{fontSize:28,fontWeight:800}}>{val??"\u2014"}</div>
</div>)}</div>:<div style={{textAlign:"center",paddingTop:60,color:"var(--text3)"}}>Loading...</div>}
</div>}

{/* ═══ MODELS (admin) ═══ */}
{tab==="models"&&isAdmin&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{fontSize:22,fontWeight:700,marginBottom:4}}>Model management</div>
<div style={{fontSize:13,color:"var(--text3)",marginBottom:20}}>Pull, add, and manage AI models</div>

<div style={{marginBottom:24}}>
<div style={{fontSize:14,fontWeight:600,marginBottom:10}}>Installed Ollama models</div>
<div style={{display:"flex",flexDirection:"column",gap:8}}>
{(models?.ollama_installed||[]).map(m=><div key={m.name} style={{background:"var(--bg2)",border:"1px solid var(--border)",
borderRadius:12,padding:"12px 16px",display:"flex",justifyContent:"space-between",alignItems:"center"}}>
<div><div style={{fontWeight:600,fontSize:14}}>{m.name}</div>
<div style={{fontSize:11,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>{m.details?.parameter_size} \u00B7 {m.details?.quantization_level} \u00B7 {(m.size/1e9).toFixed(1)}GB</div></div>
<div style={{display:"flex",alignItems:"center",gap:8}}>
{models?.default?.name===m.name&&<span style={{fontSize:10,padding:"3px 8px",borderRadius:6,background:"var(--green)18",color:"var(--green)"}}>default</span>}
</div></div>)}
</div></div>

<div style={{marginBottom:24}}>
<div style={{fontSize:14,fontWeight:600,marginBottom:10}}>Pull new model</div>
<div style={{display:"flex",gap:8}}>
<input id="pull-input" placeholder="e.g. qwen3:4b, mistral:7b, deepseek-coder-v2"
style={{flex:1,padding:"10px 14px",borderRadius:10,border:"1px solid var(--border)",background:"var(--bg2)",color:"var(--text)",fontSize:13}}/>
<Btn onClick={()=>{const v=document.getElementById("pull-input").value;if(v)pullModel(v)}} color="var(--blue)">Pull</Btn>
</div></div>

<div>
<div style={{fontSize:14,fontWeight:600,marginBottom:10}}>Registered paid models</div>
{(models?.registered||[]).filter(m=>m.provider!=="ollama").map(m=><div key={m.name} style={{background:"var(--bg2)",border:"1px solid var(--border)",
borderRadius:12,padding:"12px 16px",marginBottom:8,display:"flex",justifyContent:"space-between",alignItems:"center"}}>
<div><span style={{fontWeight:600}}>{m.name}</span>
<span style={{fontSize:11,color:"var(--text3)",marginLeft:8}}>{m.provider}</span></div>
<span style={{fontSize:10,color:"var(--green)"}}>active</span></div>)}
<div style={{fontSize:12,color:"var(--text3)",marginTop:8}}>Add via API: POST /models/paid</div>
</div>
</div>}

{/* ═══ SETTINGS (admin) ═══ */}
{tab==="settings"&&isAdmin&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{fontSize:22,fontWeight:700,marginBottom:4}}>Settings</div>
<div style={{fontSize:13,color:"var(--text3)",marginBottom:20}}>Configure notification channels</div>

<div style={{display:"flex",gap:6,marginBottom:20,flexWrap:"wrap"}}>
{["smtp","telegram","slack","discord","whatsapp"].map(ch=><Btn key={ch} small
onClick={()=>{setSettingsTab(ch);setSettingsForm({});setSettingsMsg("")}}
color={settingsTab===ch?"var(--blue)":"var(--bg3)"}>{ch.charAt(0).toUpperCase()+ch.slice(1)}</Btn>)}
</div>

{settings?.categories?.[settingsTab]&&<div className="fade" style={{background:"var(--bg2)",border:"1px solid var(--border)",borderRadius:14,padding:24,maxWidth:500}}>
<div style={{fontSize:16,fontWeight:600,marginBottom:4}}>{settings.categories[settingsTab].label}</div>
<div style={{fontSize:12,color:"var(--text3)",marginBottom:16}}>{settings.categories[settingsTab].description}</div>

{settings.categories[settingsTab].fields?.map(f=><Input key={f.key} label={f.label}
type={f.type==="password"?"password":"text"} placeholder={f.placeholder||""}
value={settingsForm[f.key]||""} onChange={v=>setSettingsForm(p=>({...p,[f.key]:v}))}/>)}

{settingsMsg&&<div style={{fontSize:13,color:settingsMsg.startsWith("Error")?"var(--red)":"var(--green)",marginBottom:12,padding:"8px 12px",
background:settingsMsg.startsWith("Error")?"#EF444415":"#10B98115",borderRadius:8}}>{settingsMsg}</div>}

<div style={{display:"flex",gap:8}}>
<Btn onClick={()=>saveSettings(settingsTab)}>Save</Btn>
<Btn onClick={()=>testChannel(settingsTab)} color="var(--bg3)">Test connection</Btn>
</div>

{settings.settings?.[settingsTab]&&Object.keys(settings.settings[settingsTab]).length>0&&
<div style={{marginTop:16,padding:"12px 16px",background:"var(--bg)",borderRadius:10,border:"1px solid var(--border)"}}>
<div style={{fontSize:11,color:"var(--text3)",marginBottom:6,fontWeight:600}}>Current config</div>
{Object.entries(settings.settings[settingsTab]).map(([k,v])=><div key={k} style={{fontSize:12,marginBottom:2,display:"flex",gap:8}}>
<span style={{color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace",minWidth:100}}>{k}</span>
<span style={{color:"var(--text2)"}}>{v}</span></div>)}
</div>}
</div>}
</div>}

</div></div>
}

function Root(){
const[user,setUser]=useState(null);
const[checking,setChecking]=useState(true);

useEffect(()=>{
const token=localStorage.getItem("maicha_token");
if(token){
fetch(API+"/auth/me",{headers:{"Authorization":"Bearer "+token}})
.then(r=>r.json()).then(d=>{if(d.user?.role)setUser(d.user);setChecking(false)})
.catch(()=>setChecking(false))
}else setChecking(false)},[]);

if(checking)return <div style={{minHeight:"100vh",display:"flex",alignItems:"center",justifyContent:"center",
background:"var(--bg)"}}><div style={{width:24,height:24,border:"3px solid var(--bg3)",borderTopColor:"var(--blue)",
borderRadius:"50%",animation:"spin 1s linear infinite"}}/></div>;

return user?<App/>:<AuthScreen onAuth={u=>{setUser(u)}}/>;
}

ReactDOM.createRoot(document.getElementById("root")).render(<Root/>);
</script>
</body>
</html>'''

with open("/opt/ai-server/nginx/maicha.html", "w") as f:
    f.write(html)
print("maicha.html written: " + str(len(html)) + " bytes")
PYSCRIPT

echo ""
echo "=== Maicha UI v2 deployed ==="

# Git commit
cd /opt/ai-server
git add -A
git commit -m "Sub-phase B: Maicha UI v2 — full platform interface

Complete UI rewrite with:
- Auth screen: guest/login/register with JWT
- Chat: all 7 agents with quick prompts, download, model selector
- Explore: menu, properties, orders, events from live API
- Dashboard: 11 stat cards including n8n workflows/executions
- Models tab (admin): view installed, pull new, see paid models
- Settings tab (admin): configure SMTP/Telegram/Slack/Discord/WhatsApp
  with form fields, save, test connection, view current config
- Dynamic model dropdown populated from /models API
- Mobile responsive (collapsible sidebar)
- Role-based UI (admin sees Models + Settings tabs)
- Token auto-restored on page reload
- Dark theme, Inter font, clean design"

echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose up -d --force-recreate nginx"
echo "  git push"
echo ""
echo "Open: http://20.41.122.188/"
