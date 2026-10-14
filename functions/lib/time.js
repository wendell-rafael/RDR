// Contas de data no fuso do racha (America/Sao_Paulo).
//
// O Brasil não usa horário de verão desde 2019, mas o cálculo aqui não assume
// isso: o deslocamento é lido do próprio Intl a cada conversão. Se o país
// voltar a mudar o relógio, a quinta-feira continua caindo na hora certa.

export const ZONE = 'America/Sao_Paulo';

const OFFSET_FORMAT = new Intl.DateTimeFormat('en-US', {
  timeZone: ZONE,
  timeZoneName: 'longOffset',
});

const PARTS_FORMAT = new Intl.DateTimeFormat('en-US', {
  timeZone: ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

/** Deslocamento do fuso, em minutos, no instante informado. */
function offsetMinutes(date) {
  const found = OFFSET_FORMAT.formatToParts(date)
    .find((part) => part.type === 'timeZoneName');
  const match = /GMT([+-])(\d{2}):(\d{2})/.exec(found?.value ?? 'GMT+00:00');
  if (!match) return 0;
  const sign = match[1] === '-' ? -1 : 1;
  return sign * (Number(match[2]) * 60 + Number(match[3]));
}

/** Ano/mês/dia/hora/minuto e dia da semana (0=domingo) vistos no fuso. */
export function zonedParts(date) {
  const parts = {};
  for (const part of PARTS_FORMAT.formatToParts(date)) {
    if (part.type !== 'literal') parts[part.type] = Number(part.value);
  }
  // `hour12: false` devolve 24 na virada da meia-noite em alguns runtimes.
  const hour = parts.hour === 24 ? 0 : parts.hour;
  const weekday = new Date(Date.UTC(parts.year, parts.month - 1, parts.day)).getUTCDay();
  return {
    year: parts.year,
    month: parts.month,
    day: parts.day,
    hour,
    minute: parts.minute,
    weekday,
  };
}

/**
 * Converte uma data/hora local do fuso para o instante UTC correspondente.
 *
 * O deslocamento depende do próprio instante, então a primeira conta é um
 * palpite e a segunda corrige caso o palpite tenha caído do outro lado de uma
 * eventual mudança de horário.
 */
export function zonedTimeToDate({ year, month, day, hour = 0, minute = 0 }) {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  const firstOffset = offsetMinutes(new Date(guess));
  const firstTry = guess - firstOffset * 60000;
  const secondOffset = offsetMinutes(new Date(firstTry));
  if (secondOffset === firstOffset) return new Date(firstTry);
  return new Date(guess - secondOffset * 60000);
}

/** Soma dias a uma data civil (sem hora), sem passar pelo fuso. */
export function addDays({ year, month, day }, amount) {
  const shifted = new Date(Date.UTC(year, month - 1, day + amount));
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

/** `2026-09-19` — usado como id do evento. */
export function dateId({ year, month, day }) {
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}
