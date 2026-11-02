import {expect,it} from 'vitest';
import {setupDestination} from './route';
for(const allowed of [true,false])for(const next of [null,'/setup','https://bad.test','//bad.test','/setup?bad=1','/admin'])it(`loginreturn ${next} admin=${allowed}`,()=>{expect(setupDestination(next,allowed)).toBe(next==='/setup'&&allowed?'/setup':'/');});
