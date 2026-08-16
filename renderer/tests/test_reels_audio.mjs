import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pickFile, pickStartOffset } from '../reels-audio.mjs';

test('pickFile: lista vazia -> null', () => {
  assert.equal(pickFile([]), null);
});

test('pickFile: rand=0 pega o primeiro, rand perto de 1 pega o último', () => {
  const files = ['a.mp3', 'b.mp3', 'c.mp3'];
  assert.equal(pickFile(files, 0), 'a.mp3');
  assert.equal(pickFile(files, 0.999), 'c.mp3');
});

test('pickStartOffset: faixa mais curta que o clipe -> começa do zero', () => {
  assert.equal(pickStartOffset(5, 7, 0.5), 0);
  assert.equal(pickStartOffset(7, 7, 0.5), 0);
});

test('pickStartOffset: distribui dentro do espaço disponível (duração - clipe)', () => {
  assert.equal(pickStartOffset(100, 7, 0), 0);
  assert.equal(pickStartOffset(100, 7, 1), 93);
  assert.equal(pickStartOffset(100, 7, 0.5), 46.5);
});
