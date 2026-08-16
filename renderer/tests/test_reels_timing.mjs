import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  easeOutQuad, easeOutBack, revealStyle, punchStyle, wipeStyle, splitLastWord,
} from '../reels-timing.mjs';

test('easeOutQuad: extremos e monotonia', () => {
  assert.equal(easeOutQuad(0), 0);
  assert.equal(easeOutQuad(1), 1);
  assert.ok(easeOutQuad(0.5) > 0.5); // ease-out: sobe rápido no início
});

test('easeOutBack: chega em 1 no fim (pode ultrapassar antes)', () => {
  assert.equal(easeOutBack(1), 1);
  assert.ok(Math.abs(easeOutBack(0)) < 1e-9); // ~0 (arredondamento de ponto flutuante)
});

test('revealStyle: opacidade 0 antes do início, 1 ao final', () => {
  assert.match(revealStyle(0, 10, 20), /opacity:0\.000/);
  assert.match(revealStyle(30, 10, 20), /opacity:1\.000/);
  assert.match(revealStyle(30, 10, 20), /translateY\(0px\)/);
});

test('punchStyle: opacidade cresce e escala converge pra 1', () => {
  const inicio = punchStyle(0, 0, 20);
  const fim = punchStyle(20, 0, 20);
  assert.match(inicio, /opacity:0\.000/);
  assert.match(fim, /opacity:1\.000/);
  assert.match(fim, /scale\(1\.000\)/);
});

test('wipeStyle: começa 100% oculto e termina revelado (0%)', () => {
  assert.match(wipeStyle(0, 0, 20), /inset\(0 100\.00% 0 0\)/);
  assert.match(wipeStyle(20, 0, 20), /inset\(0 0\.00% 0 0\)/);
});

test('splitLastWord: separa a última palavra do resto', () => {
  assert.deepEqual(splitLastWord('Automação não troca gente por robô'),
    { rest: 'Automação não troca gente por', last: 'robô' });
});

test('splitLastWord: título de uma palavra só vira "last" sem "rest"', () => {
  assert.deepEqual(splitLastWord('Automatize'), { rest: '', last: 'Automatize' });
});

test('splitLastWord: espaços extras não geram palavras vazias', () => {
  assert.deepEqual(splitLastWord('  Menos   tarefa  chata  '),
    { rest: 'Menos tarefa', last: 'chata' });
});
