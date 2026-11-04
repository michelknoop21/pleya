/**
 * hls.js 1.7.3 levert de lichte bouw (`hls.js/light`) zonder eigen
 * declaratiebestand; de API is die van de volledige bouw, minus de modules die
 * de speler niet gebruikt.
 */
declare module 'hls.js/light' {
  import Hls from 'hls.js';
  export default Hls;
}
