import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeFloorMaterial,
  normalizeHex,
  normalizeWallMaterial,
  parseMaterialJson,
} from './room-material.service';

test('parseMaterialJson reads floor and wall from fenced JSON', () => {
  const raw = '```json\n{"floor":{"material":"woodPlanks","hex":"#B08D6B"},' +
    '"wall":{"material":"paint","hex":"#F5F3EE"}}\n```';
  assert.deepEqual(parseMaterialJson(raw), {
    floor: { material: 'woodPlanks', hex: '#B08D6B' },
    wall: { material: 'paint', hex: '#F5F3EE' },
  });
});

test('parseMaterialJson keeps unknown surfaces as nulls', () => {
  const raw = '{"floor":{"material":"unknown","hex":"#123456"},' +
    '"wall":{"material":"unknown","hex":""}}';
  assert.deepEqual(parseMaterialJson(raw), {
    floor: { material: 'unknown', hex: '#123456' },
    wall: { material: 'unknown', hex: '' },
  });
});

test('parseMaterialJson takes the first object span out of prose', () => {
  const raw = 'Here you go: {"floor":{"material":"cement","hex":"#C9C6BF"}} — done.';
  assert.deepEqual(parseMaterialJson(raw), {
    floor: { material: 'cement', hex: '#C9C6BF' },
    wall: null,
  });
});

test('parseMaterialJson never invents a surface from garbage', () => {
  assert.equal(parseMaterialJson('no json here'), null);
  assert.equal(parseMaterialJson('{broken'), null);
  assert.equal(parseMaterialJson('[1,2,3]'), null);
  assert.deepEqual(parseMaterialJson('{"floor":42}'), {
    floor: null,
    wall: null,
  });
});

test('normalizeFloorMaterial folds model spellings onto the app vocabulary', () => {
  assert.equal(normalizeFloorMaterial('woodPlanks'), 'woodPlanks');
  assert.equal(normalizeFloorMaterial('Hardwood'), 'woodPlanks');
  assert.equal(normalizeFloorMaterial('wood planks'), 'woodPlanks');
  assert.equal(normalizeFloorMaterial('laminate'), 'woodPlanks');
  assert.equal(normalizeFloorMaterial('polished concrete'), 'cement');
  assert.equal(normalizeFloorMaterial('Tiles'), 'ceramicTiles');
  assert.equal(normalizeFloorMaterial('porcelain'), 'ceramicTiles');
  assert.equal(normalizeFloorMaterial('parquet flooring'), 'parquet');
  assert.equal(normalizeFloorMaterial('marble'), null);
  assert.equal(normalizeFloorMaterial(''), null);
});

test('normalizeWallMaterial folds model spellings onto the app vocabulary', () => {
  assert.equal(normalizeWallMaterial('paint'), 'paint');
  assert.equal(normalizeWallMaterial('painted wall'), 'paint');
  assert.equal(normalizeWallMaterial('wood paneling'), 'woodPanels');
  assert.equal(normalizeWallMaterial('Panelling'), 'woodPanels');
  assert.equal(normalizeWallMaterial('exposed brick'), 'brick');
  assert.equal(normalizeWallMaterial('wallpaper'), null);
});

test('normalizeHex accepts 3 and 6 digit hex and rejects the rest', () => {
  assert.equal(normalizeHex('#B08D6B'), '#B08D6B');
  assert.equal(normalizeHex('b08d6b'), '#B08D6B');
  assert.equal(normalizeHex('#fff'), '#FFFFFF');
  assert.equal(normalizeHex('nope'), undefined);
  assert.equal(normalizeHex('#12345'), undefined);
  assert.equal(normalizeHex(''), undefined);
});
