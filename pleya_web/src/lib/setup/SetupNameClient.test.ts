import {expect,it} from 'vitest';
import {clientFor,json,apiError} from '../admin/libraryFake';
it('S11 setup server_name blijft buiten de gesloten cookieloginbody',async()=>{
 const bodies:Record<string,unknown>[]=[];
 const client=clientFor(async(input,init)=>{
  const req=input instanceof Request?input:new Request(String(input),init);const p=new URL(req.url).pathname;
  if(p.endsWith('/info'))return json({capabilities:{cookie_auth:true},auth:{setup_required:true}});
  if(p.endsWith('/auth/logout'))return new Response(null,{status:204});
  const body=await req.json() as Record<string,unknown>;bodies.push(body);
  if(p.endsWith('/auth/login')&&body.server_name!==undefined)return apiError('auth.invalid_credentials',400);
  return json({access_token:'new',refresh_token:'synthetic',expires_in_ms:900000});
 });
 await client.info();await client.setup({setup_code:'fixture',username:'owner',password:'synthetic',server_name:'Kelder'});
 expect(bodies).toHaveLength(2);expect(bodies[0]).toHaveProperty('server_name','Kelder');expect(bodies[1]).not.toHaveProperty('server_name');expect(bodies[1]).toHaveProperty('credential_mode','cookie');
});
