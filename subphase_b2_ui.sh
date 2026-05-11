#!/bin/bash
set -e
echo "=== Sub-phase B2: Maicha UI — Orange/White Theme + n8n + All Features ==="

BASE="/opt/ai-server"
cd "$BASE"

python3 << 'PYSCRIPT'
html = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title>Maicha — AI Automation Platform</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0%25' stop-color='%23F97316'/><stop offset='100%25' stop-color='%23EA580C'/></linearGradient></defs><rect width='64' height='64' rx='16' fill='url(%23g)'/><text x='32' y='46' font-size='36' text-anchor='middle' font-weight='900' fill='white' font-family='serif'>M</text></svg>">
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500&family=Instrument+Serif:ital@0;1&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/react/18.2.0/umd/react.production.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/react-dom/18.2.0/umd/react-dom.production.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/babel-standalone/7.23.9/babel.min.js"></script>
<style>
:root{--bg:#FAFAF8;--bg2:#FFFFFF;--bg3:#F5F3EF;--bg4:#EDE9E1;--border:rgba(234,88,12,.12);--border2:rgba(234,88,12,.22);--text:#1C1412;--text2:#6B5B50;--text3:#9C8B80;--accent:#F97316;--accent2:#EA580C;--accentBg:#FFF7ED;--blue:#2563EB;--green:#059669;--red:#DC2626;--purple:#7C3AED;--pink:#DB2777;--amber:#D97706;--teal:#0D9488;--radius:14px}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:var(--bg);color:var(--text);font-family:'Outfit',sans-serif;overflow:hidden}
::-webkit-scrollbar{width:5px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:var(--bg4);border-radius:10px}
input:focus,select:focus,textarea:focus{outline:none}
button{cursor:pointer;font-family:inherit}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:0;
background:radial-gradient(ellipse at 10% 15%,rgba(249,115,22,.08) 0%,transparent 45%),radial-gradient(ellipse at 90% 80%,rgba(234,88,12,.06) 0%,transparent 45%)}
@keyframes fadeIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes pulse{0%,100%{opacity:.4}50%{opacity:1}}
@keyframes float{0%,100%{transform:translateY(0)}50%{transform:translateY(-8px)}}
.fade{animation:fadeIn .3s ease}
.glass{background:rgba(255,255,255,.75);backdrop-filter:blur(12px);border:1.5px solid var(--border)}
</style>
</head>
<body>
<div id="root"></div>
<script type="text/babel">
const{useState,useEffect,useRef,useCallback}=React;
const API=window.location.origin;

const AGENTS=[
{name:"restaurant",icon:"\u{1F37D}\uFE0F",label:"Restaurant",desc:"Orders, menu, reservations",color:"#F97316"},
{name:"real-estate",icon:"\u{1F3E0}",label:"Real Estate",desc:"Property listings & inquiries",color:"#2563EB"},
{name:"social-media",icon:"\u{1F4F1}",label:"Social Media",desc:"Content & hashtags",color:"#DB2777"},
{name:"marketing",icon:"\u{1F4E3}",label:"Marketing",desc:"Ads, emails, campaigns",color:"#7C3AED"},
{name:"video",icon:"\u{1F3AC}",label:"Video",desc:"Scripts & production",color:"#059669"},
{name:"hermes",icon:"\u{1F9E0}",label:"Hermes",desc:"Orchestrator + Nepali",color:"#D97706"},
];

const TABS=[
{id:"chat",label:"Chat",icon:"\u{1F4AC}"},
{id:"explore",label:"Explore",icon:"\u{1F50D}"},
{id:"stats",label:"Dashboard",icon:"\u{1F4CA}"},
{id:"n8n",label:"Workflows",icon:"\u2699\uFE0F"},
{id:"models",label:"Models",icon:"\u{1F916}",admin:true},
{id:"settings",label:"Settings",icon:"\u{1F527}",admin:true},
];

async function api(path,opts={}){
const h={"Content-Type":"application/json",...(opts.headers||{})};
const token=localStorage.getItem("maicha_token");
if(token)h["Authorization"]="Bearer "+token;
const r=await fetch(API+path,{...opts,headers:h});
if(!r.ok){const e=await r.json().catch(()=>({}));throw new Error(e.detail||"HTTP "+r.status)}
return r.json()}

function Btn({children,onClick,color,small,disabled,full,outline}){
const bg=outline?"transparent":disabled?"var(--bg4)":color||"var(--accent)";
const c=outline?color||"var(--accent)":"#fff";
const bd=outline?"1.5px solid "+(color||"var(--accent)")+"40":"none";
return <button onClick={onClick} disabled={disabled} style={{
padding:small?"7px 16px":"11px 22px",borderRadius:12,border:bd,
background:bg,color:c,fontSize:small?12:14,fontWeight:600,transition:"all .2s",
opacity:disabled?.5:1,width:full?"100%":"auto",
boxShadow:!outline&&!disabled?"0 2px 12px "+((color||"var(--accent)")+"25"):"none"
}}>{children}</button>}

function Input({value,onChange,placeholder,type,label}){
return <div style={{marginBottom:14}}>
{label&&<div style={{fontSize:12,color:"var(--text2)",marginBottom:5,fontWeight:600}}>{label}</div>}
<input value={value} onChange={e=>onChange(e.target.value)} placeholder={placeholder} type={type||"text"}
style={{width:"100%",padding:"11px 16px",borderRadius:12,border:"1.5px solid var(--border)",
background:"var(--bg)",color:"var(--text)",fontSize:14}}/>
</div>}

function Logo({size}){
const s=size||40;
return <div style={{width:s,height:s,borderRadius:s*.3,
background:"linear-gradient(135deg,#F97316,#EA580C)",display:"flex",alignItems:"center",justifyContent:"center",
fontSize:s*.5,fontWeight:900,color:"#fff",fontFamily:"'Instrument Serif',serif",
boxShadow:"0 4px 20px rgba(249,115,22,.35)",flexShrink:0}}>M</div>}

// ═══ LANDING PAGE ═══
function Landing({onStart}){
return <div style={{minHeight:"100vh",display:"flex",flexDirection:"column",alignItems:"center",justifyContent:"center",
textAlign:"center",padding:24,position:"relative"}}>
<div className="fade" style={{maxWidth:600}}>
<div style={{animation:"float 3s ease infinite",marginBottom:24}}><Logo size={72}/></div>
<h1 style={{fontSize:42,fontWeight:800,letterSpacing:"-.03em",marginBottom:8,
fontFamily:"'Instrument Serif',serif",color:"var(--text)"}}>Maicha</h1>
<div style={{fontSize:12,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace",
letterSpacing:".15em",marginBottom:24}}>AI AUTOMATION PLATFORM</div>
<p style={{fontSize:16,color:"var(--text2)",lineHeight:1.7,marginBottom:32,maxWidth:460,margin:"0 auto 32px"}}>
Self-hosted AI agents for restaurants, real estate, social media, marketing, and video — powered by local LLMs with dynamic model management and workflow automation.</p>
<div style={{display:"flex",gap:16,justifyContent:"center",flexWrap:"wrap",marginBottom:40}}>
{["\u{1F37D}\uFE0F Restaurant","\u{1F3E0} Real Estate","\u{1F4F1} Social Media","\u{1F4E3} Marketing","\u{1F3AC} Video","\u{1F9E0} Hermes AI"].map(a=>
<span key={a} style={{padding:"8px 16px",borderRadius:20,background:"var(--accentBg)",
color:"var(--accent2)",fontSize:12,fontWeight:600,border:"1px solid rgba(249,115,22,.15)"}}>{a}</span>)}
</div>
<div style={{display:"flex",gap:12,justifyContent:"center",flexWrap:"wrap"}}>
<Btn onClick={()=>onStart("guest")} color="linear-gradient(135deg,#F97316,#EA580C)">Try as Guest</Btn>
<Btn onClick={()=>onStart("login")} outline>Sign In</Btn>
<Btn onClick={()=>onStart("register")} outline color="var(--text3)">Create Account</Btn>
</div>
<div style={{marginTop:32,display:"flex",gap:24,justifyContent:"center",fontSize:12,color:"var(--text3)"}}>
<span>6 AI Agents</span><span>Local + Paid LLMs</span><span>n8n Workflows</span><span>Multi-channel Notifications</span>
</div></div></div>}

// ═══ AUTH SCREEN ═══
function AuthScreen({mode,onAuth,onBack}){
const[email,setEmail]=useState("");const[password,setPassword]=useState("");
const[name,setName]=useState("");const[error,setError]=useState("");const[loading,setLoading]=useState(false);

const handleGuest=async()=>{setLoading(true);
try{const d=await api("/auth/guest",{method:"POST"});localStorage.setItem("maicha_token",d.token);onAuth(d.user)}
catch(e){setError(e.message)}setLoading(false)};

const handleSubmit=async()=>{setLoading(true);setError("");
try{const ep=mode==="login"?"/auth/login":"/auth/register";
const body=mode==="login"?{email,password}:{email,password,full_name:name||undefined};
const d=await api(ep,{method:"POST",body:JSON.stringify(body)});
if(d.status==="error"){setError(d.message);setLoading(false);return}
localStorage.setItem("maicha_token",d.token);onAuth(d.user)}catch(e){setError(e.message)}setLoading(false)};

useEffect(()=>{if(mode==="guest")handleGuest()},[mode]);

if(mode==="guest")return <div style={{minHeight:"100vh",display:"flex",alignItems:"center",justifyContent:"center"}}>
<div style={{width:24,height:24,border:"3px solid var(--bg4)",borderTopColor:"var(--accent)",borderRadius:"50%",animation:"spin 1s linear infinite"}}/></div>;

return <div style={{minHeight:"100vh",display:"flex",alignItems:"center",justifyContent:"center",padding:24}}>
<div className="fade glass" style={{width:400,maxWidth:"90vw",padding:36,borderRadius:24,boxShadow:"0 20px 60px rgba(249,115,22,.1)"}}>
<div style={{textAlign:"center",marginBottom:24}}>
<Logo size={48}/>
<div style={{fontSize:22,fontWeight:700,marginTop:12,fontFamily:"'Instrument Serif',serif"}}>{mode==="login"?"Welcome back":"Create account"}</div>
</div>
{mode==="register"&&<Input value={name} onChange={setName} placeholder="Full name" label="Name"/>}
<Input value={email} onChange={setEmail} placeholder="you@email.com" label="Email" type="email"/>
<Input value={password} onChange={setPassword} placeholder="Password" label="Password" type="password"/>
{error&&<div style={{color:"var(--red)",fontSize:13,marginBottom:12,padding:"10px 14px",background:"#DC262612",borderRadius:10}}>{error}</div>}
<Btn onClick={handleSubmit} full disabled={loading} color="linear-gradient(135deg,#F97316,#EA580C)">{loading?"Loading...":mode==="login"?"Sign In":"Create Account"}</Btn>
<button onClick={onBack} style={{display:"block",margin:"16px auto 0",background:"none",border:"none",color:"var(--text3)",fontSize:13}}>Back</button>
</div></div>}

// ═══ MAIN APP ═══
function MainApp({user,onLogout}){
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
const[sidebar,setSidebar]=useState(window.innerWidth>768);
const[serverOk,setServerOk]=useState(false);
const[n8nData,setN8nData]=useState(null);
const[pullName,setPullName]=useState("");
const chatEnd=useRef(null);const inputRef=useRef(null);
const isAdmin=user?.role==="admin";
const activeAgent=AGENTS.find(a=>a.name===agent);
const visTabs=TABS.filter(t=>!t.admin||isAdmin);

useEffect(()=>{chatEnd.current?.scrollIntoView({behavior:"smooth"})},[messages,loading]);
useEffect(()=>{api("/health").then(()=>setServerOk(true)).catch(()=>setServerOk(false))},[]);
useEffect(()=>{api("/models").then(d=>{setModels(d);setSelectedModel(d.default?.name||"qwen3:8b")}).catch(()=>{})},[]);

const send=useCallback(async()=>{
if(!input.trim()||loading)return;const msg=input.trim();setInput("");
setMessages(p=>[...p,{role:"user",content:msg}]);setLoading(true);
try{const d=await api("/chat",{method:"POST",body:JSON.stringify({message:msg,agent_type:agent,model:selectedModel,session_id:sessionId||"new"})});
setSessionId(d.session_id);setMessages(p=>[...p,{role:"assistant",content:d.response,elapsed:d.elapsed_seconds,model:d.model_used}])}
catch(e){setMessages(p=>[...p,{role:"assistant",content:"Error: "+e.message}])}setLoading(false)},[input,loading,agent,selectedModel,sessionId]);

const clearChat=()=>{setMessages([]);setSessionId(null)};
const download=()=>{const t=messages.map(m=>(m.role==="user"?"You":activeAgent.label)+": "+m.content).join("\n\n---\n\n");
const b=new Blob([t],{type:"text/plain"});const u=URL.createObjectURL(b);const a=document.createElement("a");
a.href=u;a.download="maicha-"+agent+".txt";a.click();URL.revokeObjectURL(u)};

const loadExplore=useCallback(async(s)=>{setExploreTab(s);try{
if(s==="menu"&&!menuData)setMenuData(await api("/menu"));
if(s==="properties"&&!propertiesData)setPropertiesData(await api("/properties"));
if(s==="orders"&&!ordersData)setOrdersData(await api("/orders"));
if(s==="events"&&!eventsData)setEventsData(await api("/events"))}catch(e){}},[menuData,propertiesData,ordersData,eventsData]);

const loadStats=useCallback(async()=>{try{setStats(await api("/stats"))}catch(e){}},[]);
const loadSettings=useCallback(async()=>{try{setSettings(await api("/settings"))}catch(e){}},[]);
const loadN8n=useCallback(async()=>{try{setN8nData(await api("/n8n/workflows"))}catch(e){}},[]);

useEffect(()=>{if(tab==="stats")loadStats()},[tab]);
useEffect(()=>{if(tab==="explore")loadExplore("menu")},[tab]);
useEffect(()=>{if(tab==="settings"&&isAdmin)loadSettings()},[tab]);
useEffect(()=>{if(tab==="n8n")loadN8n()},[tab]);

const saveSettings=async(cat)=>{setSettingsMsg("");try{
await api("/settings/"+cat,{method:"POST",body:JSON.stringify(settingsForm)});
setSettingsMsg("Saved!");loadSettings()}catch(e){setSettingsMsg("Error: "+e.message)}};
const testChannel=async(ch)=>{setSettingsMsg("Testing...");try{const d=await api("/settings/"+ch+"/test",{method:"POST"});
setSettingsMsg(d.status==="ok"?"Test passed!":"Failed: "+(d.message||""))}catch(e){setSettingsMsg("Error: "+e.message)}};
const pullModel=async()=>{if(!pullName.trim())return;try{await api("/models/ollama/pull",{method:"POST",body:JSON.stringify({name:pullName})});
setPullName("");setModels(await api("/models"))}catch(e){alert(e.message)}};

const quickPrompts={
"restaurant":["What's on the menu?","Order a Neural Burger","Reserve table for 4"],
"real-estate":["Show properties","Under $3000","Schedule viewing"],
"social-media":["Instagram post about food","TikTok captions","Hashtags for travel"],
"marketing":["Email subject line","Ad copy summer sale","Blog post about AI"],
"video":["30s TikTok script","YouTube intro","Create voiceover"],
"hermes":["Post about Kathmandu food in Nepali","Route order to restaurant","Bilingual content"],
};

return <div style={{height:"100vh",display:"flex",flexDirection:"column",position:"relative"}}>
{/* HEADER */}
<header className="glass" style={{display:"flex",alignItems:"center",justifyContent:"space-between",padding:"10px 16px",
borderBottom:"1.5px solid var(--border)",flexShrink:0,gap:8,flexWrap:"wrap",zIndex:10,position:"relative"}}>
<div style={{display:"flex",alignItems:"center",gap:10}}>
<button onClick={()=>setSidebar(!sidebar)} style={{background:"none",border:"none",color:"var(--text3)",fontSize:18,padding:4}}>{"\u2630"}</button>
<Logo size={34}/>
<div><div style={{fontSize:18,fontWeight:700,fontFamily:"'Instrument Serif',serif",letterSpacing:"-.01em"}}>Maicha</div>
<div style={{fontSize:8,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace",letterSpacing:".12em"}}>AI PLATFORM</div></div>
</div>

<div style={{display:"flex",gap:3,background:"var(--bg3)",borderRadius:12,padding:3,overflow:"auto"}}>
{visTabs.map(t=><button key={t.id} onClick={()=>setTab(t.id)} style={{
padding:"7px 14px",borderRadius:9,border:"none",fontSize:12,fontWeight:600,whiteSpace:"nowrap",
background:tab===t.id?"var(--bg2)":"transparent",color:tab===t.id?"var(--accent)":"var(--text3)",
boxShadow:tab===t.id?"0 1px 6px rgba(249,115,22,.1)":"none",display:"flex",alignItems:"center",gap:4
}}><span>{t.icon}</span>{t.label}</button>)}
</div>

<div style={{display:"flex",alignItems:"center",gap:10}}>
{models&&<select value={selectedModel} onChange={e=>setSelectedModel(e.target.value)}
style={{background:"var(--bg2)",border:"1.5px solid var(--border)",borderRadius:10,padding:"7px 10px",
color:"var(--text2)",fontSize:11,fontFamily:"'JetBrains Mono',monospace",maxWidth:180}}>
{(models.ollama_installed||[]).map(m=><option key={m.name} value={m.name}>{m.name} ({m.details?.parameter_size})</option>)}
{(models.registered||[]).filter(m=>m.provider!=="ollama").map(m=><option key={m.name} value={m.name}>{m.name} ({m.provider})</option>)}
</select>}
<div style={{display:"flex",alignItems:"center",gap:5,fontSize:11,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>
<div style={{width:7,height:7,borderRadius:"50%",background:serverOk?"var(--green)":"var(--red)",
boxShadow:serverOk?"0 0 6px #05966950":"0 0 6px #DC262650",animation:"pulse 2.5s infinite"}}/>{serverOk?"Online":"Offline"}</div>
<div style={{padding:"5px 12px",background:"var(--accentBg)",borderRadius:10,border:"1px solid var(--border)",fontSize:11,fontWeight:600,color:"var(--accent2)"}}>
{user.name||"User"} <span style={{fontSize:10,opacity:.7}}>({user.role})</span></div>
<button onClick={onLogout} style={{background:"none",border:"none",color:"var(--text3)",fontSize:14}} title="Logout">{"\u{1F6AA}"}</button>
</div></header>

<div style={{flex:1,display:"flex",overflow:"hidden",position:"relative",zIndex:5}}>

{/* SIDEBAR */}
{tab==="chat"&&sidebar&&<aside style={{width:230,padding:"14px 10px",borderRight:"1.5px solid var(--border)",
display:"flex",flexDirection:"column",gap:6,overflowY:"auto",flexShrink:0,background:"rgba(255,255,255,.5)",backdropFilter:"blur(8px)"}}>
<div style={{fontSize:10,fontWeight:700,color:"var(--text3)",letterSpacing:".12em",padding:"0 6px 8px",fontFamily:"'JetBrains Mono',monospace"}}>AI AGENTS</div>
{AGENTS.map(a=><button key={a.name} onClick={()=>{setAgent(a.name);clearChat()}} style={{
display:"flex",alignItems:"center",gap:10,padding:"11px 14px",borderRadius:12,width:"100%",textAlign:"left",
background:agent===a.name?a.color+"12":"transparent",border:agent===a.name?"1.5px solid "+a.color+"35":"1.5px solid transparent",
boxShadow:agent===a.name?"0 2px 12px "+a.color+"15":"none",transition:"all .2s"}}>
<div style={{width:36,height:36,borderRadius:10,background:agent===a.name?a.color+"15":"var(--bg3)",
display:"flex",alignItems:"center",justifyContent:"center",fontSize:18}}>{a.icon}</div>
<div><div style={{fontSize:13,fontWeight:600,color:agent===a.name?a.color:"var(--text)"}}>{a.label}</div>
<div style={{fontSize:10,color:"var(--text3)"}}>{a.desc}</div></div>
</button>)}
<div style={{flex:1}}/>
<div style={{padding:"12px 14px",borderRadius:12,background:"var(--bg3)",fontSize:11,color:"var(--text3)"}}>
{user.role==="guest"?"Guest (24h)":"Logged in"} \u00B7 {selectedModel}</div>
</aside>}

{/* ═══ CHAT ═══ */}
{tab==="chat"&&<main style={{flex:1,display:"flex",flexDirection:"column",minWidth:0}}>
<div className="glass" style={{padding:"10px 18px",borderBottom:"1.5px solid var(--border)",display:"flex",alignItems:"center",justifyContent:"space-between"}}>
<div style={{display:"flex",alignItems:"center",gap:8}}>
<div style={{width:32,height:32,borderRadius:10,background:activeAgent?.color+"15",display:"flex",alignItems:"center",justifyContent:"center",fontSize:16}}>{activeAgent?.icon}</div>
<span style={{fontWeight:700,fontSize:14,color:activeAgent?.color}}>{activeAgent?.label} Agent</span>
</div>
<div style={{display:"flex",gap:6}}>
{messages.length>0&&<><Btn small onClick={download} outline>{"\u2B07"} Save</Btn>
<Btn small onClick={clearChat} outline color="var(--red)">{"\u2715"} Clear</Btn></>}
</div></div>

<div style={{flex:1,overflowY:"auto",padding:"20px 24px"}}>
{messages.length===0&&<div className="fade" style={{textAlign:"center",paddingTop:50}}>
<div style={{fontSize:52,marginBottom:14,animation:"float 3s ease infinite"}}>{activeAgent?.icon}</div>
<div style={{fontSize:24,fontWeight:700,fontFamily:"'Instrument Serif',serif",marginBottom:6}}>Chat with {activeAgent?.label}</div>
<div style={{fontSize:14,color:"var(--text3)",maxWidth:380,margin:"0 auto",lineHeight:1.7}}>{activeAgent?.desc}</div>
<div style={{display:"flex",gap:8,justifyContent:"center",marginTop:24,flexWrap:"wrap"}}>
{(quickPrompts[agent]||[]).map(q=><button key={q} onClick={()=>{setInput(q);inputRef.current?.focus()}} style={{
padding:"8px 18px",borderRadius:22,border:"1.5px solid "+activeAgent.color+"25",background:activeAgent.color+"08",
color:activeAgent.color,fontSize:12,fontWeight:600}}>{q}</button>)}</div></div>}

{messages.map((m,i)=><div key={i} className="fade" style={{display:"flex",justifyContent:m.role==="user"?"flex-end":"flex-start",marginBottom:14,gap:8,alignItems:"flex-end"}}>
{m.role!=="user"&&<div style={{width:28,height:28,borderRadius:8,background:activeAgent?.color+"15",display:"flex",alignItems:"center",justifyContent:"center",fontSize:14,flexShrink:0}}>{activeAgent?.icon}</div>}
<div style={{maxWidth:"78%",padding:"13px 17px",borderRadius:m.role==="user"?"18px 18px 4px 18px":"18px 18px 18px 4px",
background:m.role==="user"?"linear-gradient(135deg,var(--accent),var(--accent2))":"var(--bg2)",
color:m.role==="user"?"#fff":"var(--text)",border:m.role==="user"?"none":"1.5px solid var(--border)",
boxShadow:m.role==="user"?"0 4px 16px rgba(249,115,22,.25)":"0 1px 8px rgba(0,0,0,.04)",
fontSize:14,lineHeight:1.7,whiteSpace:"pre-wrap",wordBreak:"break-word"}}>
{m.content}
{m.elapsed&&<div style={{fontSize:10,marginTop:6,opacity:.6,textAlign:"right",fontFamily:"'JetBrains Mono',monospace"}}>{m.elapsed}s \u00B7 {m.model}</div>}
</div></div>)}

{loading&&<div style={{display:"flex",alignItems:"flex-end",gap:8}}>
<div style={{width:28,height:28,borderRadius:8,background:activeAgent?.color+"15",display:"flex",alignItems:"center",justifyContent:"center",fontSize:14}}>{activeAgent?.icon}</div>
<div className="glass" style={{borderRadius:"18px 18px 18px 4px",padding:"10px 16px",display:"flex",gap:5}}>
{[0,1,2].map(i=><div key={i} style={{width:7,height:7,borderRadius:"50%",background:activeAgent?.color,animation:"pulse 1.2s ease infinite "+(i*.2)+"s"}}/>)}</div></div>}
<div ref={chatEnd}/></div>

<div style={{padding:"14px 18px",borderTop:"1.5px solid var(--border)",background:"rgba(255,255,255,.7)",backdropFilter:"blur(12px)"}}>
<div style={{display:"flex",gap:8,background:"var(--bg2)",border:"1.5px solid "+(input.trim()?activeAgent?.color+"40":"var(--border)"),
borderRadius:16,padding:"4px 4px 4px 16px",transition:"all .2s",boxShadow:input.trim()?"0 0 0 3px "+activeAgent?.color+"10":"none"}}>
<input ref={inputRef} value={input} onChange={e=>setInput(e.target.value)}
onKeyDown={e=>{if(e.key==="Enter"&&!e.shiftKey)send()}}
placeholder={"Message "+activeAgent?.label+"..."} disabled={loading}
style={{flex:1,background:"transparent",border:"none",color:"var(--text)",fontSize:14,padding:"11px 0",opacity:loading?.5:1}}/>
<Btn onClick={send} disabled={loading||!input.trim()} color={input.trim()?"linear-gradient(135deg,"+activeAgent?.color+","+activeAgent?.color+"CC)":"var(--bg4)"}>
{loading?"\u00B7\u00B7\u00B7":"Send"}</Btn></div></div>
</main>}

{/* ═══ EXPLORE ═══ */}
{tab==="explore"&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{fontSize:24,fontWeight:700,fontFamily:"'Instrument Serif',serif",marginBottom:4}}>Explore data</div>
<div style={{fontSize:13,color:"var(--text3)",marginBottom:20}}>Live data from your AI platform</div>
<div style={{display:"flex",gap:6,marginBottom:20,flexWrap:"wrap"}}>
{[{id:"menu",l:"\u{1F37D}\uFE0F Menu"},{id:"properties",l:"\u{1F3E0} Properties"},{id:"orders",l:"\u{1F4CB} Orders"},{id:"events",l:"\u26A1 Events"}].map(t=>
<Btn key={t.id} onClick={()=>loadExplore(t.id)} small color={exploreTab===t.id?"var(--accent)":"var(--bg4)"} outline={exploreTab!==t.id}>{t.l}</Btn>)}
</div>
{exploreTab==="menu"&&menuData&&<div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(260px,1fr))",gap:12}}>
{menuData.menu_items?.map((item,i)=><div key={i} className="fade glass" style={{borderRadius:16,padding:20}}>
<div style={{display:"flex",justifyContent:"space-between",marginBottom:8}}>
<span style={{fontWeight:700}}>{item.name}</span>
<span style={{fontWeight:800,color:"var(--accent)",fontFamily:"'JetBrains Mono',monospace"}}>${item.price}</span></div>
<div style={{fontSize:13,color:"var(--text2)",marginBottom:10}}>{item.description}</div>
<div style={{display:"flex",gap:4,flexWrap:"wrap"}}>
<span style={{fontSize:10,padding:"3px 10px",borderRadius:12,background:"var(--bg3)",color:"var(--text3)"}}>{item.category}</span>
{(item.dietary_tags||[]).map((t,j)=><span key={j} style={{fontSize:10,padding:"3px 10px",borderRadius:12,background:"#05966912",color:"var(--green)"}}>{t}</span>)}
</div></div>)}</div>}
{exploreTab==="properties"&&propertiesData&&<div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(300px,1fr))",gap:12}}>
{propertiesData.properties?.map((p,i)=><div key={i} className="fade glass" style={{borderRadius:16,padding:20}}>
<div style={{fontWeight:700,marginBottom:4}}>{p.title}</div>
<div style={{fontSize:22,fontWeight:800,color:"var(--blue)",fontFamily:"'Instrument Serif',serif",marginBottom:8}}>${Number(p.price).toLocaleString()}<span style={{fontSize:13,color:"var(--text3)"}}>/mo</span></div>
<div style={{fontSize:13,color:"var(--text2)",marginBottom:10}}>{p.description}</div>
<div style={{display:"flex",gap:14,fontSize:12,color:"var(--text3)"}}><span>{"\u{1F6CF}"} {p.bedrooms}bed</span><span>{"\u{1F6BF}"} {p.bathrooms}bath</span><span>{"\u{1F4CD}"} {p.city},{p.state}</span></div>
</div>)}{propertiesData.properties?.length===0&&<div style={{color:"var(--text3)",padding:40,textAlign:"center"}}>No properties</div>}</div>}
{exploreTab==="orders"&&ordersData&&<div>{ordersData.orders?.length===0?<div style={{color:"var(--text3)",padding:40,textAlign:"center"}}>No orders yet</div>:
ordersData.orders?.map((o,i)=><div key={i} className="fade glass" style={{borderRadius:14,padding:"14px 18px",marginBottom:8,display:"flex",justifyContent:"space-between",alignItems:"center"}}>
<div><div style={{fontWeight:700}}>{o.customer_name||"Guest"}</div><div style={{fontSize:11,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>#{String(o.id).slice(0,8)}</div></div>
<div style={{textAlign:"right"}}><div style={{fontWeight:800,color:"var(--green)",fontFamily:"'JetBrains Mono',monospace"}}>${Number(o.total).toFixed(2)}</div></div></div>)}</div>}
{exploreTab==="events"&&eventsData&&<div>{eventsData.events?.length===0?<div style={{color:"var(--text3)",padding:40,textAlign:"center"}}>No events</div>:
eventsData.events?.map((e,i)=><div key={i} className="fade" style={{background:"var(--bg2)",border:"1px solid var(--border)",borderRadius:10,padding:"10px 14px",marginBottom:6,display:"flex",gap:10,alignItems:"center",fontSize:12}}>
<span style={{padding:"3px 8px",borderRadius:6,background:"var(--accentBg)",color:"var(--accent)",fontSize:10,fontFamily:"'JetBrains Mono',monospace",whiteSpace:"nowrap"}}>{e.event_type}</span>
<span style={{color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>{e.source}</span>
<span style={{color:"var(--text3)",flex:1,overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"}}>{JSON.stringify(e.data)}</span></div>)}</div>}
</div>}

{/* ═══ DASHBOARD ═══ */}
{tab==="stats"&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:20}}>
<div><div style={{fontSize:24,fontWeight:700,fontFamily:"'Instrument Serif',serif"}}>Dashboard</div>
<div style={{fontSize:13,color:"var(--text3)"}}>System statistics</div></div>
<Btn small onClick={loadStats} outline>{"\u21BB"} Refresh</Btn></div>
{stats?<div style={{display:"flex",flexWrap:"wrap",gap:12}}>
{[["Conversations",stats.stats?.conversations,"\u{1F4AC}","var(--blue)"],["Messages",stats.stats?.messages,"\u2709\uFE0F","var(--purple)"],
["Orders",stats.stats?.orders,"\u{1F37D}\uFE0F","var(--accent)"],["Reservations",stats.stats?.reservations,"\u{1F4C5}","var(--pink)"],
["Properties",stats.stats?.property_listings,"\u{1F3E0}","var(--blue)"],["Inquiries",stats.stats?.property_inquiries,"\u{1F4E9}","var(--green)"],
["Content Queue",stats.stats?.content_queue,"\u{1F4F1}","var(--amber)"],["Scripts",stats.stats?.generated_scripts,"\u{1F3AC}","var(--purple)"],
["Events",stats.stats?.events,"\u26A1","var(--amber)"],["n8n Workflows",stats.stats?.n8n_workflows,"\u2699\uFE0F","var(--teal)"],
["n8n Runs",stats.stats?.n8n_executions,"\u{1F504}","var(--teal)"]].map(([l,v,ic,c])=>
<div key={l} className="glass" style={{borderRadius:16,padding:"20px 22px",flex:"1 1 150px",minWidth:150}}>
<div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:10}}>
<span style={{fontSize:20}}>{ic}</span>
<span style={{fontSize:10,color:c,fontFamily:"'JetBrains Mono',monospace",background:c+"12",padding:"3px 8px",borderRadius:6}}>{l}</span></div>
<div style={{fontSize:30,fontWeight:800,fontFamily:"'Instrument Serif',serif"}}>{v??"\u2014"}</div></div>)}
</div>:<div style={{textAlign:"center",paddingTop:60,color:"var(--text3)"}}>Click Refresh</div>}
</div>}

{/* ═══ N8N WORKFLOWS ═══ */}
{tab==="n8n"&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{display:"flex",justifyContent:"space-between",alignItems:"flex-start",marginBottom:20}}>
<div><div style={{fontSize:24,fontWeight:700,fontFamily:"'Instrument Serif',serif"}}>Workflows</div>
<div style={{fontSize:13,color:"var(--text3)"}}>n8n automation engine</div></div>
<div style={{display:"flex",gap:8}}>
<Btn small onClick={loadN8n} outline>{"\u21BB"} Refresh</Btn>
<Btn small onClick={()=>window.open((n8nData?.n8n_url||"http://20.41.122.188:5678"),"_blank")} color="var(--accent)">Open n8n Dashboard</Btn>
</div></div>

<div className="glass" style={{borderRadius:14,padding:"14px 18px",marginBottom:20,display:"flex",alignItems:"center",gap:10}}>
<div style={{width:10,height:10,borderRadius:"50%",background:n8nData?.n8n_status==="running"?"var(--green)":"var(--red)",
boxShadow:n8nData?.n8n_status==="running"?"0 0 6px #05966950":"0 0 6px #DC262650"}}/>
<span style={{fontSize:13,fontWeight:600}}>n8n Status: {n8nData?.n8n_status||"checking..."}</span>
<span style={{fontSize:11,color:"var(--text3)",marginLeft:"auto",fontFamily:"'JetBrains Mono',monospace"}}>{n8nData?.n8n_url}</span>
</div>

<div style={{fontSize:16,fontWeight:600,marginBottom:12}}>Workflow templates</div>
<div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(300px,1fr))",gap:12}}>
{(n8nData?.workflows||[]).map((w,i)=><div key={i} className="fade glass" style={{borderRadius:16,padding:20}}>
<div style={{fontSize:15,fontWeight:700,marginBottom:6}}>{w.name}</div>
<div style={{fontSize:13,color:"var(--text2)",lineHeight:1.6,marginBottom:12}}>{w.description}</div>
<Btn small outline onClick={async()=>{try{const d=await api("/n8n/workflow/"+w.file);
alert(JSON.stringify(d.setup_instructions||d.nodes_description,null,2))}catch(e){alert(e.message)}}}>View setup guide</Btn>
</div>)}
</div>

{(!n8nData?.workflows||n8nData.workflows.length===0)&&<div style={{textAlign:"center",padding:40,color:"var(--text3)"}}>
<div style={{fontSize:40,marginBottom:12}}>{"\u2699\uFE0F"}</div>
<div>No workflow templates found</div></div>}
</div>}

{/* ═══ MODELS (admin) ═══ */}
{tab==="models"&&isAdmin&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{fontSize:24,fontWeight:700,fontFamily:"'Instrument Serif',serif",marginBottom:4}}>Model management</div>
<div style={{fontSize:13,color:"var(--text3)",marginBottom:20}}>Pull, add, and manage AI models</div>

<div className="glass" style={{borderRadius:14,padding:20,marginBottom:20}}>
<div style={{fontSize:14,fontWeight:600,marginBottom:12}}>Pull new Ollama model</div>
<div style={{display:"flex",gap:8}}>
<input value={pullName} onChange={e=>setPullName(e.target.value)} placeholder="e.g. qwen3:4b, mistral:7b, deepseek-coder-v2"
style={{flex:1,padding:"11px 16px",borderRadius:12,border:"1.5px solid var(--border)",background:"var(--bg)",color:"var(--text)",fontSize:13}}/>
<Btn onClick={pullModel}>Pull model</Btn></div>
<div style={{display:"flex",gap:6,marginTop:10,flexWrap:"wrap"}}>
{["qwen3:4b","mistral:7b","deepseek-coder-v2","llama3.2:3b","phi3:mini","gemma2:2b"].map(m=>
<button key={m} onClick={()=>setPullName(m)} style={{padding:"4px 12px",borderRadius:8,border:"1px solid var(--border)",
background:"var(--bg3)",color:"var(--text2)",fontSize:11,fontFamily:"'JetBrains Mono',monospace"}}>{m}</button>)}
</div></div>

<div style={{fontSize:14,fontWeight:600,marginBottom:12}}>Installed models</div>
{(models?.ollama_installed||[]).map(m=><div key={m.name} className="glass" style={{borderRadius:12,padding:"14px 18px",marginBottom:8,
display:"flex",justifyContent:"space-between",alignItems:"center"}}>
<div><div style={{fontWeight:600}}>{m.name}</div>
<div style={{fontSize:11,color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace"}}>{m.details?.parameter_size} \u00B7 {m.details?.quantization_level} \u00B7 {(m.size/1e9).toFixed(1)}GB</div></div>
{models?.default?.name===m.name&&<span style={{fontSize:10,padding:"4px 10px",borderRadius:8,background:"#05966912",color:"var(--green)",fontWeight:700}}>default</span>}
</div>)}

{(models?.registered||[]).filter(m=>m.provider!=="ollama").length>0&&<>
<div style={{fontSize:14,fontWeight:600,marginBottom:12,marginTop:20}}>Paid API models</div>
{(models?.registered||[]).filter(m=>m.provider!=="ollama").map(m=><div key={m.name} className="glass" style={{borderRadius:12,padding:"14px 18px",marginBottom:8,
display:"flex",justifyContent:"space-between",alignItems:"center"}}>
<div><span style={{fontWeight:600}}>{m.name}</span><span style={{fontSize:11,color:"var(--text3)",marginLeft:8}}>{m.provider}</span></div>
<span style={{fontSize:10,color:"var(--green)"}}>active</span></div>)}</>}
</div>}

{/* ═══ SETTINGS (admin) ═══ */}
{tab==="settings"&&isAdmin&&<div style={{flex:1,overflowY:"auto",padding:24}}>
<div style={{fontSize:24,fontWeight:700,fontFamily:"'Instrument Serif',serif",marginBottom:4}}>Settings</div>
<div style={{fontSize:13,color:"var(--text3)",marginBottom:20}}>Configure notification channels</div>
<div style={{display:"flex",gap:6,marginBottom:20,flexWrap:"wrap"}}>
{["smtp","telegram","slack","discord","whatsapp"].map(ch=><Btn key={ch} small
onClick={()=>{setSettingsTab(ch);setSettingsForm({});setSettingsMsg("")}}
color={settingsTab===ch?"var(--accent)":"var(--bg4)"} outline={settingsTab!==ch}>{ch[0].toUpperCase()+ch.slice(1)}</Btn>)}
</div>
{settings?.categories?.[settingsTab]&&<div className="fade glass" style={{borderRadius:16,padding:24,maxWidth:500}}>
<div style={{fontSize:16,fontWeight:700,marginBottom:4}}>{settings.categories[settingsTab].label}</div>
<div style={{fontSize:12,color:"var(--text3)",marginBottom:16}}>{settings.categories[settingsTab].description}</div>
{settings.categories[settingsTab].fields?.map(f=><Input key={f.key} label={f.label}
type={f.type==="password"?"password":"text"} placeholder={f.placeholder||""}
value={settingsForm[f.key]||""} onChange={v=>setSettingsForm(p=>({...p,[f.key]:v}))}/>)}
{settingsMsg&&<div style={{fontSize:13,color:settingsMsg.includes("Error")||settingsMsg.includes("Failed")?"var(--red)":"var(--green)",
marginBottom:12,padding:"10px 14px",background:settingsMsg.includes("Error")?"#DC262610":"#05966910",borderRadius:10}}>{settingsMsg}</div>}
<div style={{display:"flex",gap:8}}>
<Btn onClick={()=>saveSettings(settingsTab)}>Save</Btn>
<Btn onClick={()=>testChannel(settingsTab)} outline>Test connection</Btn></div>
{settings.settings?.[settingsTab]&&Object.keys(settings.settings[settingsTab]).length>0&&
<div style={{marginTop:16,padding:"14px 16px",background:"var(--bg3)",borderRadius:12}}>
<div style={{fontSize:11,fontWeight:700,color:"var(--text3)",marginBottom:8}}>Current configuration</div>
{Object.entries(settings.settings[settingsTab]).map(([k,v])=><div key={k} style={{fontSize:12,marginBottom:3,display:"flex",gap:8}}>
<span style={{color:"var(--text3)",fontFamily:"'JetBrains Mono',monospace",minWidth:100}}>{k}</span>
<span style={{color:"var(--text2)"}}>{v}</span></div>)}</div>}
</div>}</div>}

</div></div>}

// ═══ ROOT ═══
function Root(){
const[user,setUser]=useState(null);const[screen,setScreen]=useState("landing");const[checking,setChecking]=useState(true);

useEffect(()=>{const token=localStorage.getItem("maicha_token");
if(token){fetch(API+"/auth/me",{headers:{"Authorization":"Bearer "+token}})
.then(r=>r.json()).then(d=>{if(d.user?.role){setUser(d.user);setScreen("app")}setChecking(false)})
.catch(()=>setChecking(false))}else setChecking(false)},[]);

if(checking)return <div style={{minHeight:"100vh",display:"flex",alignItems:"center",justifyContent:"center",background:"var(--bg)"}}>
<div style={{width:24,height:24,border:"3px solid var(--bg4)",borderTopColor:"var(--accent)",borderRadius:"50%",animation:"spin 1s linear infinite"}}/></div>;

const handleAuth=(u)=>{setUser(u);setScreen("app")};
const handleLogout=()=>{localStorage.removeItem("maicha_token");setUser(null);setScreen("landing")};

if(screen==="landing"&&!user)return <Landing onStart={m=>{if(m==="guest"){
api("/auth/guest",{method:"POST"}).then(d=>{localStorage.setItem("maicha_token",d.token);handleAuth(d.user)}).catch(()=>setScreen("login"))
}else setScreen(m)}}/>;
if((screen==="login"||screen==="register")&&!user)return <AuthScreen mode={screen} onAuth={handleAuth} onBack={()=>setScreen("landing")}/>;
if(user)return <MainApp user={user} onLogout={handleLogout}/>;
return <Landing onStart={m=>setScreen(m)}/>;
}

ReactDOM.createRoot(document.getElementById("root")).render(<Root/>);
</script>
</body>
</html>'''

with open("/opt/ai-server/nginx/maicha.html","w") as f:
    f.write(html)
print("maicha.html written: "+str(len(html))+" bytes")
PYSCRIPT

echo ""

# Git commit
cd /opt/ai-server
git add -A
git commit -m "Sub-phase B2: Maicha UI — orange/white theme + n8n workflows tab

Complete UI with:
- Landing page with agent showcase + intro
- Orange/white warm theme with Instrument Serif headings
- Auth: guest/login/register with JWT
- Chat: 7 agents, quick prompts, agent icons in messages, model+time display
- Explore: menu/properties/orders/events with glass-morphism cards
- Dashboard: 11 stats including n8n workflows + executions
- Workflows tab: n8n status, template cards, open n8n dashboard button, setup guides
- Models tab (admin): installed models with details, pull new with suggestions, paid models
- Settings tab (admin): SMTP/Telegram/Slack/Discord/WhatsApp config forms + test + current view
- Dynamic model dropdown in header from /models API
- Mobile responsive with collapsible sidebar
- Logo + favicon with orange gradient M
- Glass-morphism design throughout
- Role-based tabs (admin sees Models + Settings)"

echo ""
echo "=== UI Updated ==="
echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose up -d --force-recreate nginx"
echo "  git push"
echo ""
echo "Open: http://20.41.122.188/"
