// GPS → 시·구·동 주소 (/api/place)
import { fail, hide, mapsKey } from './config.js';

// 사진 GPS 좌표 → 시·구·동 주소 (예: "서울특별시 성동구 성수2가3동")
// GOOGLE_MAPS_API_KEY 가 있으면 구글 지도, 없으면 OpenStreetMap(Nominatim, 키 불필요)을 쓴다.
const PLACE_TYPES = ['administrative_area_level_1', 'locality', 'sublocality_level_1', 'sublocality_level_2'];
async function googlePlace(lat, lng) {
  const url = 'https://maps.googleapis.com/maps/api/geocode/json?language=ko&latlng=' + lat.toFixed(6) + ',' + lng.toFixed(6) + '&key=' + encodeURIComponent(mapsKey());
  let r;
  try { r = await fetch(url, { signal: AbortSignal.timeout(10000) }); } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'maps_unreachable'); }
  const j = await r.json().catch(() => ({}));
  if (j.status === 'ZERO_RESULTS') return null;
  if (j.status !== 'OK') { console.error('Google 지오코딩 오류', j.status, hide(j.error_message || '')); throw fail('maps_' + String(j.status || r.status).toLowerCase()); }
  const comps = j.results?.[0]?.address_components || [];
  const parts = [];
  for (const t of PLACE_TYPES) {
    const c = comps.find(c => c.types?.includes(t));
    if (c && !parts.includes(c.long_name)) parts.push(c.long_name);
  }
  return parts.join(' ') || String(j.results?.[0]?.formatted_address || '').replace(/^대한민국\s*/, '') || null;
}

// Nominatim 이용 정책: 초당 1회 이하 → 인스턴스 안에서 요청 간격을 1.1초 이상으로
let osmQueue = Promise.resolve();
const osmTurn = () => { const t = osmQueue.then(() => new Promise(ok => setTimeout(ok, 1100))); osmQueue = t; return osmQueue; };
const OSM_ORDER = [['province', 'state'], ['city'], ['county'], ['borough', 'city_district'], ['town', 'village'], ['quarter', 'suburb', 'neighbourhood']];
async function osmPlace(lat, lng) {
  const run = osmQueue;
  osmTurn();
  await run;
  const url = 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=16&addressdetails=1&accept-language=ko&lat=' + lat.toFixed(6) + '&lon=' + lng.toFixed(6);
  let r;
  try { r = await fetch(url, { headers: { 'User-Agent': 'Snapback/1.0' }, signal: AbortSignal.timeout(10000) }); } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'maps_unreachable'); }
  if (!r.ok) { console.error('OSM 지오코딩 오류', r.status); throw fail('maps_' + r.status); }
  const a = (await r.json().catch(() => ({}))).address || {};
  const parts = [];
  for (const keys of OSM_ORDER) {
    const v = keys.map(k => a[k]).find(Boolean); // 같은 단계는 첫 값만 (법정동 quarter → 행정동 suburb)
    if (v && !parts.includes(v)) parts.push(v);
  }
  return parts.join(' ') || null;
}

async function place(b) {
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return [400, { error: 'bad_request' }];
  const name = mapsKey() ? await googlePlace(lat, lng) : await osmPlace(lat, lng);
  return [200, { name, source: mapsKey() ? 'google' : 'osm' }];
}

export { PLACE_TYPES, googlePlace, osmQueue, osmTurn, OSM_ORDER, osmPlace, place };
