import {render,screen,fireEvent} from '@testing-library/svelte';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import HomeBillboard from './HomeBillboard.svelte';
import type {Item} from '../api/types';
const h=vi.hoisted(()=>({me:{id:'test'},counter:0}));
vi.mock('../stores/session.svelte',()=>({session:{client:{},me:h.me,capabilities:{playback_plan:true}}}));
const films:Item[]=[{id:'one',kind:'movie',title:'First film',added_at:'2026-01-01',versions:[{id:'v',container:'mkv',duration_ms:60000,file_count:1}],user_state:{position_ms:20000,watched:false,play_count:0,updated_at:'2026-01-01',revision:1}},{id:'two',kind:'movie',title:'Second film',added_at:'2026-01-01',versions:[{id:'v2',container:'mkv',duration_ms:60000,file_count:1}]}];
beforeEach(()=>{h.me.id=String(++h.counter);vi.useFakeTimers();vi.stubGlobal('matchMedia',vi.fn(()=>({matches:false,addEventListener:vi.fn(),removeEventListener:vi.fn()})));Object.defineProperty(document,'hidden',{configurable:true,value:false})});
afterEach(()=>{vi.useRealTimers();vi.unstubAllGlobals()});
describe('Home billboard native behavior',()=>{
 it('resumes original item at saved position',()=>{render(HomeBillboard,{items:films});expect(screen.getByRole('link',{name:/^Resume$/})).toHaveAttribute('href','/items/one/play?t=20')});
 it('keeps manual endpoints finite',async()=>{render(HomeBillboard,{items:films});expect(screen.getByRole('button',{name:'Previous featured film'})).toBeDisabled();await fireEvent.click(screen.getByRole('button',{name:'Next featured film'}));expect(screen.getByRole('heading',{name:'Second film'})).toBeInTheDocument();expect(screen.getByRole('button',{name:'Next featured film'})).toBeDisabled()});
 it('rotates after eight seconds and preserves focused CTA',async()=>{render(HomeBillboard,{items:films});const link=screen.getByRole('link',{name:'More info'});link.focus();await vi.advanceTimersByTimeAsync(8200);expect(screen.getByRole('heading',{name:'Second film'})).toBeInTheDocument();expect(screen.getByRole('link',{name:'More info'})).toBe(link);expect(document.activeElement).toBe(link);expect(link).toHaveAttribute('href','/items/two')});
 it('respects reduced motion with manual navigation available',async()=>{vi.stubGlobal('matchMedia',vi.fn(()=>({matches:true,addEventListener:vi.fn(),removeEventListener:vi.fn()})));render(HomeBillboard,{items:films});await vi.advanceTimersByTimeAsync(30000);expect(screen.getByRole('heading',{name:'First film'})).toBeInTheDocument();await fireEvent.click(screen.getByRole('button',{name:'Next featured film'}));expect(screen.getByRole('heading',{name:'Second film'})).toBeInTheDocument()});
});
