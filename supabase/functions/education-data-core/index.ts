const cors={"content-type":"application/json","access-control-allow-origin":"*","access-control-allow-headers":"authorization, x-client-info, apikey, content-type","access-control-allow-methods":"GET,POST,OPTIONS"};
const j=(v)=>v===undefined||v===""?null:v;
const n=(v,d)=>{const x=Number(v);return Number.isFinite(x)?x:d};
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 const u=new URL(req.url), p=u.pathname.replace(/^\/education-data-core/,"");
 const q=u.searchParams, seg=p.split("/").filter(Boolean);
 let fn="", body={};
 if(req.method==="GET"&&p==="/v1/health"){fn="health"}
 else if(req.method==="GET"&&p==="/v1/institutions"){fn="search_institutions";body={q:j(q.get("q")),status_filter:j(q.get("status")),country:j(q.get("country")),result_limit:n(q.get("limit"),20),result_offset:n(q.get("offset"),0)}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="institutions"&&seg[2]&&seg.length===3){fn="get_institution_profile";body={institution_id:seg[2],as_of:j(q.get("as_of")),include_provenance:["true","1"].includes(q.get("include_provenance")||"")}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="institutions"&&seg[3]==="history"){fn="get_institution_history";body={institution_id:seg[2]}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="institutions"&&seg[3]==="accreditation"){fn="get_institution_accreditation";body={institution_id:seg[2],as_of:j(q.get("as_of")),include_history:["true","1"].includes(q.get("include_history")||"")}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="institutions"&&seg[3]==="programs"){fn="get_programs_by_institution";body={institution_id:seg[2],degree_type:j(q.get("degree_type")),as_of:j(q.get("as_of")),modality:j(q.get("modality"))}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="institutions"&&seg[3]==="policies"){fn="get_transfer_policy";body={institution_id:seg[2],as_of:j(q.get("as_of")),program_id:j(q.get("program_id")),include_provenance:["true","1"].includes(q.get("include_provenance")||"")}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="institutions"&&seg[3]==="alternative-credit-rules"){fn="get_alternative_credit_rules";body={institution_id:seg[2],as_of:j(q.get("as_of")),provider_id:j(q.get("provider_id"))}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="institutions"&&seg[3]==="policy-history"){fn="get_policy_history";body={institution_id:seg[2],policy_kind:j(q.get("policy_kind"))}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="program-versions"&&seg[3]==="requirements"){fn="get_program_requirements";body={program_version_id:seg[2]}}
 else if(req.method==="GET"&&p==="/v1/programs"){fn="search_programs";body={q:j(q.get("q")),institution_id:j(q.get("institution_id")),degree_type:j(q.get("degree_type")),result_limit:n(q.get("limit"),20),result_offset:n(q.get("offset"),0)}}
 else if(req.method==="GET"&&p==="/v1/courses"){fn="search_courses";body={q:j(q.get("q")),institution_id:j(q.get("institution_id")),result_limit:n(q.get("limit"),20),result_offset:n(q.get("offset"),0)}}
 else if(req.method==="GET"&&p==="/v1/providers"){fn="search_providers";body={q:j(q.get("q")),result_limit:n(q.get("limit"),20),result_offset:n(q.get("offset"),0)}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="providers"&&seg[2]&&seg.length===3){fn="get_provider";body={provider_id:seg[2]}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="providers"&&seg[3]==="courses"){fn="get_provider_courses";body={provider_id:seg[2],q:j(q.get("q")),as_of:j(q.get("as_of"))}}
 else if(req.method==="GET"&&p==="/v1/recommendations"){fn="get_credit_recommendations";body={authority_identifier:j(q.get("authority_identifier")),provider_id:j(q.get("provider_id")),learning_experience_id:j(q.get("learning_experience_id")),as_of:j(q.get("as_of"))}}
 else if(req.method==="GET"&&p==="/v1/equivalencies"){fn="get_known_equivalencies";body={destination_institution_id:j(q.get("destination_institution_id")),source_experience_version_id:j(q.get("source_experience_version_id")),program_version_id:j(q.get("program_version_id")),as_of:j(q.get("as_of"))}}
 else if(req.method==="GET"&&p==="/v1/provenance"){fn="get_record_provenance";body={fact_schema:j(q.get("fact_schema")),fact_table:j(q.get("fact_table")),fact_id:j(q.get("fact_id"))}}
 else if(req.method==="GET"&&seg[0]==="v1"&&seg[1]==="sources"&&seg[2]){fn="get_source";body={source_id:seg[2]}}
 else if(req.method==="POST"&&p==="/v1/transfer/evaluate"){fn="evaluate_transfer";body=await req.json()}
 else return new Response(JSON.stringify({error:{code:"not_found",message:"Route not found"}}),{status:404,headers:cors});
 const base=Deno.env.get("SUPABASE_URL"), key=Deno.env.get("SUPABASE_ANON_KEY");
 const r=await fetch(base+"/rest/v1/rpc/"+fn,{method:"POST",headers:{"content-type":"application/json","apikey":key,"authorization":"Bearer "+key,"accept-profile":"api","content-profile":"api"},body:JSON.stringify(body)});
 const t=await r.text(); return new Response(t,{status:r.status,headers:cors});
});