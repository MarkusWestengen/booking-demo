/* ============================================================
   Westengen Klinikk — demobackend i nettleseren
   ------------------------------------------------------------
   Demoen har ingen database og ingen server. Denne fila står i
   stedet for begge deler:

     1. window.supabase.createClient() gir en klient med samme
        overflate som supabase-js v2 (from/select/insert/update/
        delete/upsert med filtre, rpc, auth, storage, channel), men
        alt skjer mot data i nettleserens localStorage.

     2. window.fetch fanges for https://demo.invalid/… slik at
        PostgREST-kallene i shared/booking-engine.js og
        shared/services.js, og kontaktskjemaets kall til
        /functions/v1/submit-contact, får svar herfra. Alle andre
        adresser går til nettverket som før.

   demo.invalid er et reservert toppdomene (RFC 2606) og kan aldri
   peke noe sted. Selv om fangsten skulle svikte, kan ingenting
   lekke til en ekte backend.

   DATAENE
   shared/demo-seed.js bygger innholdet ut fra dagens dato i Oslo.
   Det som endres i demoen lagres bare i denne nettleseren. Når
   datoen skifter, bygges alt på nytt, slik den nattlige
   nullstillingen gjorde før.

   RETTIGHETENE
   Radnivå-reglene fra migrasjonene er gjenskapt i forenklet form,
   slik at rolleskillet fortsatt vises: en terapeut ser bare egne
   bestillinger, bare administrator ser loggen og ventelista, og
   journalen nås bare via de to journalfunksjonene, som logger
   oppslaget.

   Lastes som vanlig <script> FØR shared/booking-config.js, etter
   shared/demo-seed.js.
   ============================================================ */
(function (root) {
  'use strict';

  if (root.WestengenKlinikkDemoBackend) return;   // idempotent

  var Seed = root.WestengenKlinikkDemoSeed;
  if (!Seed) {
    // Uten generatoren finnes det ingen data å vise. Siden starter
    // likevel, men med tomme lister.
    Seed = { build: function () { return { day: '', tables: {} }; },
             osloToday: function () { return ''; },
             osloWallToIso: function (d, t) { return d + 'T' + (t || '00:00') + ':00Z'; },
             uuid: function () { return String(Math.random()).slice(2); } };
  }

  var BASE = 'https://demo.invalid';
  var DB_KEY = 'wk-demo-db';
  var FILES_KEY = 'wk-demo-filer';
  var AUTH_KEY = 'sb-demo-auth-token';
  var SCHEMA = 1;            // bump når seed-strukturen endres
  var uuid = Seed.uuid;

  // ============================================================
  // Lagring
  // ============================================================
  function lsGet(k) { try { return root.localStorage.getItem(k); } catch (_) { return null; } }
  function lsSet(k, v) { try { root.localStorage.setItem(k, v); return true; } catch (_) { return false; } }
  function lsDel(k) { try { root.localStorage.removeItem(k); } catch (_) {} }

  // Innloggingen mot det gamle Supabase-prosjektet kan ligge igjen i
  // nettlesere som har vært innom før. Den peker ingen steder lenger,
  // men auth.js teller den som en sesjon. Ryddes bort.
  try {
    var gamle = [];
    for (var i = 0; i < root.localStorage.length; i++) {
      var k = root.localStorage.key(i);
      if (k && /^sb-.*-auth-token$/.test(k) && k !== AUTH_KEY) gamle.push(k);
    }
    gamle.forEach(lsDel);
  } catch (_) {}

  var mem = null;
  var lagringFeilet = false;

  function db() {
    var today = Seed.osloToday();
    if (mem && mem.day === today) return mem;
    mem = null;
    var raw = lsGet(DB_KEY);
    if (raw) {
      try {
        var parsed = JSON.parse(raw);
        if (parsed && parsed.schema === SCHEMA && parsed.day === today && parsed.tables) mem = parsed;
      } catch (_) {}
    }
    if (!mem) {
      var built = Seed.build();
      mem = { schema: SCHEMA, day: built.day, tables: built.tables };
      // Ny dag, nye data: filer lastet opp i går hører til gårsdagens rader.
      lsDel(FILES_KEY);
      persist();
    }
    return mem;
  }

  function persist() {
    if (!mem) return;
    if (!lsSet(DB_KEY, JSON.stringify(mem)) && !lagringFeilet) {
      lagringFeilet = true;
      console.warn('Demo: nettleseren lot oss ikke lagre. Endringer gjelder bare denne siden.');
    }
  }

  // En annen fane har skrevet: les på nytt ved neste spørring.
  try {
    root.addEventListener('storage', function (e) {
      if (e.key === DB_KEY) mem = null;
    });
  } catch (_) {}

  function table(name) {
    var t = db().tables;
    if (!t[name]) t[name] = [];
    return t[name];
  }

  function clone(x) { return x == null ? x : JSON.parse(JSON.stringify(x)); }
  function nowIso() { return new Date().toISOString(); }

  // ============================================================
  // Tabellbeskrivelser: nøkler, standardverdier, klokkeslett
  // ============================================================
  var ACTIVE = { confirmed: 1, completed: 1 };

  var META = {
    bookings: {
      unique: [
        { name: 'bookings_pkey', cols: ['id'] },
        { name: 'bookings_active_slot_unique', cols: ['staff_id', 'date', 'time'],
          where: function (r) { return r.staff_id != null && ACTIVE[r.status]; } }
      ],
      times: ['time'],
      defaults: function () {
        return { notes: '', status: 'confirmed', created_at: nowIso(),
          journal_consent: false, journal_consent_at: null, newsletter_opt_in: false,
          cancel_token: uuid(), review_token: uuid(), reminder_sent_at: null };
      }
    },
    blocked_slots: {
      unique: [{ name: 'blocked_slots_pkey', cols: ['staff_id', 'date', 'time'] }],
      times: ['time'],
      defaults: function () { return { description: null }; }
    },
    holidays: { unique: [{ name: 'holidays_pkey', cols: ['date'] }] },
    special_open_days: {
      unique: [{ name: 'special_open_days_pkey', cols: ['date', 'staff_id'] }],
      times: ['open_time', 'close_time'],
      defaults: function () { return { created_at: nowIso() }; }
    },
    services: {
      unique: [{ name: 'services_pkey', cols: ['id'] }, { name: 'services_slug_key', cols: ['slug'] }],
      updated: true,
      defaults: function () {
        return { id: uuid(), description: null, color: null, icon: null, sort_order: 0,
          is_active: true, is_public: true, created_at: nowIso(), updated_at: nowIso() };
      }
    },
    staff_services: { unique: [{ name: 'staff_services_pkey', cols: ['staff_id', 'service_id'] }] },
    staff_members: {
      unique: [{ name: 'staff_members_pkey', cols: ['staff_id'] }],
      updated: true,
      defaults: function () {
        return { role: '', bio: '', bookable: false, is_pool: false, aktiv: true,
          sortering: 100, color: '', created_at: nowIso(), updated_at: nowIso() };
      }
    },
    waitlist: {
      unique: [{ name: 'waitlist_pkey', cols: ['id'] }, { name: 'waitlist_ref_key', cols: ['ref'] }],
      times: ['preferred_time_from', 'preferred_time_to'],
      updated: true,
      defaults: function () {
        return { id: uuid(), service_id: null, staff_id: null, preferred_date_to: null,
          preferred_time_from: null, preferred_time_to: null, notes: '', status: 'waiting',
          created_at: nowIso(), updated_at: nowIso() };
      }
    },
    reviews: {
      unique: [{ name: 'reviews_pkey', cols: ['id'] },
               { name: 'reviews_booking_id_key', cols: ['booking_id'],
                 where: function (r) { return r.booking_id != null; } }],
      defaults: function () {
        return { id: uuid(), name: null, body: null, booking_id: null, status: 'pending',
          approved_by: null, approved_at: null, created_at: nowIso() };
      }
    },
    contact_messages: {
      unique: [{ name: 'contact_messages_pkey', cols: ['id'] }],
      updated: true,
      defaults: function () { return { id: uuid(), status: 'new', created_at: nowIso(), updated_at: nowIso() }; }
    },
    exercise_documents: {
      unique: [{ name: 'exercise_documents_pkey', cols: ['id'] }],
      defaults: function () {
        return { id: uuid(), file_name: null, mime_type: null, uploaded_by: null,
          uploaded_by_name: null, created_at: nowIso() };
      }
    },
    document_sends: {
      unique: [{ name: 'document_sends_pkey', cols: ['id'] }],
      defaults: function () { return { id: uuid(), sent_by: null, sent_by_name: null, created_at: nowIso() }; }
    },
    journal_entries: {
      unique: [{ name: 'journal_entries_pkey', cols: ['id'] }],
      defaults: function () { return { id: uuid(), booking_id: null, created_at: nowIso() }; }
    },
    audit_log: {
      unique: [{ name: 'audit_log_pkey', cols: ['id'] }],
      defaults: function () { return { id: uuid(), target_id: null, metadata: null, created_at: nowIso() }; }
    },
    push_subscriptions: {
      unique: [{ name: 'push_subscriptions_pkey', cols: ['id'] },
               { name: 'push_subscriptions_endpoint_key', cols: ['endpoint'] }],
      defaults: function () { return { id: uuid(), user_agent: null, created_at: nowIso() }; }
    }
  };

  function meta(t) { return META[t] || { unique: [] }; }

  // Postgres gir klokkeslett tilbake som HH:MM:SS. Sidene skriver
  // HH:MM, så alt som går inn normaliseres.
  function normTime(v) {
    if (typeof v === 'string' && /^\d{1,2}:\d{2}$/.test(v)) return (v.length === 4 ? '0' : '') + v + ':00';
    return v;
  }
  function normRow(t, row) {
    (meta(t).times || []).forEach(function (c) {
      if (Object.prototype.hasOwnProperty.call(row, c)) row[c] = normTime(row[c]);
    });
    return row;
  }

  // ============================================================
  // Rettigheter (forenklet RLS)
  // ============================================================
  function isStaff(c) { return c.role === 'admin' || c.role === 'therapist'; }
  function isAdmin(c) { return c.role === 'admin'; }
  function own(c, r) { return c.role === 'therapist' && r.staff_id === c.staffId; }

  var POLICY = {
    bookings: {
      select: function (c, r) { return isAdmin(c) || own(c, r); },
      insert: function (c, r) { return c.role === 'anon' || isAdmin(c) || own(c, r); },
      update: function (c, r) { return isAdmin(c) || own(c, r); },
      'delete': isAdmin
    },
    blocked_slots: {
      select: function () { return true; },
      insert: function (c, r) { return isAdmin(c) || own(c, r); },
      update: function (c, r) { return isAdmin(c) || own(c, r); },
      'delete': function (c, r) { return isAdmin(c) || own(c, r); }
    },
    holidays: { select: function () { return true; }, insert: isAdmin, update: isAdmin, 'delete': isAdmin },
    special_open_days: { select: function () { return true; }, insert: isAdmin, update: isAdmin, 'delete': isAdmin },
    services: {
      select: function (c, r) { return isStaff(c) || (r.is_active && r.is_public); },
      insert: isAdmin, update: isAdmin, 'delete': isAdmin
    },
    staff_services: { select: function () { return true; }, insert: isAdmin, update: isAdmin, 'delete': isAdmin },
    staff_members: {
      select: function (c, r) { return isStaff(c) || r.aktiv === true; },
      insert: isAdmin, update: isAdmin, 'delete': function () { return false; }
    },
    waitlist: {
      select: isAdmin,
      insert: function () { return true; },
      update: isAdmin, 'delete': isAdmin
    },
    reviews: {
      select: function (c, r) { return isAdmin(c) || r.status === 'approved'; },
      insert: function (c, r) { return r.status === 'pending'; },
      update: isAdmin, 'delete': isAdmin
    },
    contact_messages: { select: isStaff, insert: isStaff, update: isStaff, 'delete': isAdmin },
    exercise_documents: { select: isStaff, insert: isAdmin, update: isAdmin, 'delete': isAdmin },
    document_sends: { select: isStaff, insert: isStaff, update: function () { return false; }, 'delete': function () { return false; } },
    // Journalen nås bare via get_journal_entries/create_journal_entry (0051).
    journal_entries: {
      select: function () { return false; }, insert: function () { return false; },
      update: function () { return false; }, 'delete': function () { return false; }
    },
    audit_log: {
      select: isAdmin,
      insert: function (c, r) {
        if (c.role === 'anon') return r.action === 'login_failed';
        return isAdmin(c) || r.actor_staff_id === c.staffId;
      },
      update: function () { return false; }, 'delete': function () { return false; }
    },
    push_subscriptions: {
      select: function (c, r) { return isStaff(c) && r.staff_id === c.userId; },
      insert: isStaff,
      update: function () { return false; },
      'delete': function (c, r) { return isStaff(c) && r.staff_id === c.userId; }
    }
  };

  function allowed(t, op, c, r) {
    if (c.role === 'service') return true;
    var p = POLICY[t];
    if (!p || !p[op]) return false;
    return !!p[op](c, r);
  }

  // ============================================================
  // Feil i samme form som PostgREST
  // ============================================================
  function pgError(code, message, details, hint) {
    return { code: code, message: message, details: details == null ? null : details, hint: hint == null ? null : hint };
  }
  var STATUS = { '23505': 409, '23514': 400, '23502': 400, '42501': 403, 'PGRST116': 406,
                 '22P02': 400, '22023': 400, 'P0002': 404, '42P01': 404, 'PGRST202': 404 };
  function statusFor(err) { return STATUS[err.code] || 400; }

  function rlsError(t) {
    return pgError('42501', 'new row violates row-level security policy for table "' + t + '"');
  }

  // ============================================================
  // Filtre
  // ============================================================
  var TS = /^\d{4}-\d{2}-\d{2}T/;

  function cmp(a, b) {
    if (typeof a === 'number' || typeof b === 'number') {
      var x = +a, y = +b;
      if (!isNaN(x) && !isNaN(y)) return x < y ? -1 : (x > y ? 1 : 0);
    }
    var sa = String(a), sb = String(b);
    if (TS.test(sa) && TS.test(sb)) {
      var pa = Date.parse(sa), pb = Date.parse(sb);
      if (!isNaN(pa) && !isNaN(pb)) return pa < pb ? -1 : (pa > pb ? 1 : 0);
    }
    return sa < sb ? -1 : (sa > sb ? 1 : 0);
  }

  function likeToRegex(pattern, ci) {
    var s = String(pattern).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      .replace(/%/g, '.*').replace(/_/g, '.');
    return new RegExp('^' + s + '$', ci ? 'i' : '');
  }

  function testOp(t, col, op, val, row) {
    var v = row[col];
    var isTime = (meta(t).times || []).indexOf(col) !== -1;
    function n(x) { return isTime ? normTime(x) : x; }
    switch (op) {
      case 'eq':    return v != null && val != null && cmp(v, n(val)) === 0;
      case 'neq':   return v != null && val != null && cmp(v, n(val)) !== 0;
      case 'gt':    return v != null && cmp(v, n(val)) > 0;
      case 'gte':   return v != null && cmp(v, n(val)) >= 0;
      case 'lt':    return v != null && cmp(v, n(val)) < 0;
      case 'lte':   return v != null && cmp(v, n(val)) <= 0;
      case 'like':  return v != null && likeToRegex(val, false).test(String(v));
      case 'ilike': return v != null && likeToRegex(val, true).test(String(v));
      case 'is':
        if (val === null || val === 'null') return v == null;
        if (val === true || val === 'true') return v === true;
        if (val === false || val === 'false') return v === false;
        return false;
      case 'in':
        return v != null && (val || []).some(function (x) { return cmp(v, n(x)) === 0; });
      default:
        return false;
    }
  }

  function matches(t, filters, row) {
    for (var i = 0; i < filters.length; i++) {
      var f = filters[i];
      var ok;
      if (f.any) {
        ok = f.any.some(function (g) { return matches(t, [g], row); });
      } else {
        ok = testOp(t, f.col, f.op, f.val, row);
      }
      if (f.not) ok = !ok;
      if (!ok) return false;
    }
    return true;
  }

  // PostgREST-verdier: «eq.markus», «in.(a,b)», «not.is.null».
  function parseInList(s) {
    s = String(s).replace(/^\(/, '').replace(/\)$/, '');
    if (!s) return [];
    var out = [], cur = '', q = false;
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      if (ch === '"') { q = !q; continue; }
      if (ch === ',' && !q) { out.push(cur); cur = ''; continue; }
      cur += ch;
    }
    out.push(cur);
    return out;
  }
  function parseFilterValue(col, expr) {
    var not = false;
    if (expr.indexOf('not.') === 0) { not = true; expr = expr.slice(4); }
    var dot = expr.indexOf('.');
    var op = dot === -1 ? expr : expr.slice(0, dot);
    var raw = dot === -1 ? '' : expr.slice(dot + 1);
    var val = raw;
    if (op === 'in') val = parseInList(raw);
    else if (op === 'is') val = raw === 'null' ? null : raw;
    else if (op === 'like' || op === 'ilike') val = raw.replace(/\*/g, '%');
    return { col: col, op: op, val: val, not: not };
  }
  // or=(a.eq.1,b.eq.2) og .or('a.eq.1,b.eq.2')
  function parseOr(s) {
    var parts = parseInList(s);
    return {
      any: parts.map(function (p) {
        var dot = p.indexOf('.');
        return parseFilterValue(p.slice(0, dot), p.slice(dot + 1));
      })
    };
  }

  // ============================================================
  // Utvalg av kolonner
  // ============================================================
  function parseColumns(cols) {
    if (!cols || cols === '*') return null;
    var list = String(cols).split(',').map(function (s) { return s.trim(); }).filter(Boolean);
    if (list.indexOf('*') !== -1) return null;
    return list.map(function (c) {
      var i = c.indexOf(':');
      var alias = i === -1 ? c : c.slice(0, i);
      var src = i === -1 ? c : c.slice(i + 1);
      src = src.replace(/::\w+$/, '').replace(/^"|"$/g, '');
      return { alias: alias.replace(/^"|"$/g, ''), src: src };
    });
  }
  function project(rows, cols) {
    var spec = parseColumns(cols);
    return rows.map(function (r) {
      if (!spec) return clone(r);
      var o = {};
      spec.forEach(function (s) { o[s.alias] = r[s.src] === undefined ? null : clone(r[s.src]); });
      return o;
    });
  }

  function sortRows(rows, order) {
    if (!order || !order.length) return rows;
    return rows.slice().sort(function (a, b) {
      for (var i = 0; i < order.length; i++) {
        var o = order[i];
        var x = a[o.col], y = b[o.col];
        var nullsFirst = o.nullsFirst == null ? !o.asc : o.nullsFirst;
        if (x == null && y == null) continue;
        if (x == null) return nullsFirst ? -1 : 1;
        if (y == null) return nullsFirst ? 1 : -1;
        var c;
        if (typeof x === 'string' && typeof y === 'string' && /[^\d\s:.\-+TZ]/.test(x + y)) {
          c = x.localeCompare(y, 'nb');
        } else {
          c = cmp(x, y);
        }
        if (c !== 0) return o.asc ? c : -c;
      }
      return 0;
    });
  }

  // ============================================================
  // Unike nøkler
  // ============================================================
  function keyOf(cols, r) {
    return cols.map(function (c) { return String(r[c]); }).join('\u0001');
  }
  function conflict(t, row, rows, skip) {
    var u = meta(t).unique || [];
    for (var i = 0; i < u.length; i++) {
      var uq = u[i];
      if (uq.where && !uq.where(row)) continue;
      if (uq.cols.some(function (c) { return row[c] == null; })) continue;
      var k = keyOf(uq.cols, row);
      for (var j = 0; j < rows.length; j++) {
        var other = rows[j];
        if (other === skip) continue;
        if (uq.where && !uq.where(other)) continue;
        if (keyOf(uq.cols, other) === k) {
          return pgError('23505', 'duplicate key value violates unique constraint "' + uq.name + '"',
            'Key (' + uq.cols.join(', ') + ')=(' + uq.cols.map(function (c) { return row[c]; }).join(', ') + ') already exists.');
        }
      }
    }
    return null;
  }

  // 0020: maks fem ufordelte bestillinger på samme tidspunkt.
  function bookingTrigger(row, rows) {
    if (row.staff_id == null && ACTIVE[row.status]) {
      var n = rows.filter(function (b) {
        return b.staff_id == null && b.date === row.date && b.time === row.time && ACTIVE[b.status];
      }).length;
      if (n >= 5) {
        return pgError('23514', 'Ingen ledige terapeuter på ' + row.date + ' kl. ' + String(row.time).slice(0, 5),
          null, 'enforce_unassigned_capacity');
      }
    }
    return null;
  }

  // ============================================================
  // Kjøring av en spørring
  // ============================================================
  // q = { table, op, columns, count, head, filters, order, from, to,
  //       limit, single, maybe, values, returning, onConflict,
  //       ignoreDuplicates }
  function execute(q, c) {
    try {
      return run(q, c);
    } catch (e) {
      console.error('Demo-backend:', e);
      return { data: null, error: pgError('XX000', String((e && e.message) || e)), count: null, status: 500, statusText: 'Error' };
    }
  }

  function finish(q, rows, status) {
    var out = { data: rows, error: null, count: null, status: status, statusText: 'OK' };
    if (q.single || q.maybe) {
      if (rows.length === 1) out.data = rows[0];
      else if (rows.length === 0 && q.maybe) out.data = null;
      else {
        out.data = null;
        out.error = pgError('PGRST116', 'JSON object requested, multiple (or no) rows returned',
          'The result contains ' + rows.length + ' rows');
        out.status = 406;
      }
    }
    return out;
  }

  function fail(err) {
    return { data: null, error: err, count: null, status: statusFor(err), statusText: 'Error' };
  }

  function run(q, c) {
    var t = q.table;
    if (!META[t]) return fail(pgError('42P01', 'relation "public.' + t + '" does not exist'));
    var rows = table(t);
    var filters = q.filters || [];

    if (q.op === 'select') {
      var hit = rows.filter(function (r) { return allowed(t, 'select', c, r) && matches(t, filters, r); });
      hit = sortRows(hit, q.order);
      var total = hit.length;
      var from = q.from || 0;
      var to = q.to != null ? q.to : Infinity;
      if (q.limit != null) to = Math.min(to, from + q.limit - 1);
      hit = hit.slice(from, to === Infinity ? undefined : to + 1);
      var res = finish(q, q.head ? [] : project(hit, q.columns), 200);
      if (q.head) res.data = null;
      if (q.count) res.count = total;
      return res;
    }

    var values = q.values;
    var list = Array.isArray(values) ? values : (values ? [values] : []);
    var changed = [];

    if (q.op === 'insert' || q.op === 'upsert') {
      var staged = rows.slice();
      var inserted = [];
      var updates = [];
      for (var i = 0; i < list.length; i++) {
        var input = normRow(t, clone(list[i]) || {});
        if (q.op === 'upsert') {
          var u = meta(t).unique || [];
          var cols = q.onConflict
            ? String(q.onConflict).split(',').map(function (s) { return s.trim(); })
            : (u[0] ? u[0].cols : []);
          var k = keyOf(cols, input);
          var existing = null;
          for (var j = 0; j < staged.length; j++) {
            if (keyOf(cols, staged[j]) === k) { existing = staged[j]; break; }
          }
          if (existing) {
            if (q.ignoreDuplicates) continue;
            if (!allowed(t, 'update', c, existing)) return fail(rlsError(t));
            updates.push({ target: existing, patch: input });
            continue;
          }
        }
        var defs = meta(t).defaults ? meta(t).defaults() : {};
        var row = Object.assign(defs, input);
        normRow(t, row);
        if (!allowed(t, 'insert', c, row)) return fail(rlsError(t));
        var err = conflict(t, row, staged) || (t === 'bookings' ? bookingTrigger(row, staged) : null);
        if (err) return fail(err);
        staged.push(row);
        inserted.push(row);
      }
      // Alt eller ingenting, som en transaksjon.
      updates.forEach(function (x) {
        Object.assign(x.target, x.patch);
        if (meta(t).updated) x.target.updated_at = nowIso();
        changed.push(x.target);
      });
      inserted.forEach(function (r) { rows.push(r); changed.push(r); });
      persist();
      notify(t, 'INSERT', inserted);
      return q.returning ? finish(q, project(changed, q.columns), 201)
                         : { data: null, error: null, count: null, status: 201, statusText: 'Created' };
    }

    if (q.op === 'update') {
      var patch = normRow(t, clone(values) || {});
      var targets = rows.filter(function (r) { return allowed(t, 'update', c, r) && matches(t, filters, r); });
      for (var m = 0; m < targets.length; m++) {
        var next = Object.assign({}, targets[m], patch);
        if (!allowed(t, 'update', c, next) && c.role !== 'service') return fail(rlsError(t));
        var e2 = conflict(t, next, rows, targets[m]);
        if (e2) return fail(e2);
      }
      targets.forEach(function (r) {
        Object.assign(r, patch);
        if (meta(t).updated) r.updated_at = nowIso();
        changed.push(r);
      });
      if (targets.length) persist();
      return q.returning ? finish(q, project(changed, q.columns), 200)
                         : { data: null, error: null, count: null, status: 204, statusText: 'No Content' };
    }

    if (q.op === 'delete') {
      var doomed = rows.filter(function (r) { return allowed(t, 'delete', c, r) && matches(t, filters, r); });
      if (doomed.length) {
        var keep = rows.filter(function (r) { return doomed.indexOf(r) === -1; });
        rows.length = 0;
        Array.prototype.push.apply(rows, keep);
        persist();
      }
      return q.returning ? finish(q, project(doomed, q.columns), 200)
                         : { data: null, error: null, count: null, status: 204, statusText: 'No Content' };
    }

    return fail(pgError('PGRST000', 'Ukjent operasjon'));
  }

  // ============================================================
  // Sanntid (kanaler) — bare innenfor samme side
  // ============================================================
  var channels = [];
  function notify(t, event, rows) {
    if (!rows || !rows.length) return;
    channels.forEach(function (ch) {
      if (!ch.subscribed) return;
      ch.handlers.forEach(function (h) {
        if (h.table !== t || (h.event !== '*' && h.event !== event)) return;
        rows.forEach(function (r) {
          setTimeout(function () {
            try { h.cb({ eventType: event, schema: 'public', table: t, new: clone(r), old: {} }); } catch (_) {}
          }, 0);
        });
      });
    });
  }
  function makeChannel(name) {
    var ch = {
      name: name, handlers: [], subscribed: false,
      on: function (type, filter, cb) {
        if (type === 'postgres_changes' && filter && typeof cb === 'function') {
          ch.handlers.push({ table: filter.table, event: filter.event || '*', cb: cb });
        }
        return ch;
      },
      subscribe: function (cb) {
        ch.subscribed = true;
        if (typeof cb === 'function') setTimeout(function () { cb('SUBSCRIBED'); }, 0);
        return ch;
      },
      unsubscribe: function () {
        ch.subscribed = false;
        channels = channels.filter(function (x) { return x !== ch; });
        return Promise.resolve('ok');
      }
    };
    channels.push(ch);
    return ch;
  }

  // ============================================================
  // Funksjoner (rpc)
  // ============================================================
  var UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  function badUuid(v) {
    return pgError('22P02', 'invalid input syntax for type uuid: "' + v + '"');
  }
  function hhmm(t) { return String(t || '').slice(0, 5); }
  function startsAt(b) { return Date.parse(Seed.osloWallToIso(b.date, hhmm(b.time))); }
  function lower(s) { return String(s == null ? '' : s).trim().toLowerCase(); }
  var SERVICE = { role: 'service' };

  function audit(c, action, targetType, targetId, metadata) {
    table('audit_log').push({
      id: uuid(),
      actor_staff_id: c.staffId || (c.role === 'admin' ? 'admin' : 'unknown'),
      actor_staff_name: c.staffName || (c.role === 'admin' ? 'Admin' : 'Ukjent'),
      action: action, target_type: targetType, target_id: targetId,
      metadata: metadata || null, created_at: nowIso()
    });
  }

  function cancelBooking(b) {
    if (b.status === 'cancelled') return { ok: false, reason: 'already_cancelled' };
    if (b.status === 'completed') return { ok: false, reason: 'already_completed' };
    if (startsAt(b) < Date.now() + 24 * 3600 * 1000) return { ok: false, reason: 'too_late' };
    b.status = 'cancelled';
    persist();
    return null;
  }

  function reviewGate(b) {
    if (b.status === 'cancelled' || b.status === 'no_show') return { ok: false, reason: 'not_eligible' };
    if (startsAt(b) > Date.now()) return { ok: false, reason: 'too_early' };
    if (table('reviews').some(function (r) { return r.booking_id === b.id; })) return { ok: false, reason: 'already_reviewed' };
    return null;
  }

  function journalRole(c) {
    if (!isStaff(c)) throw pgError('42501', 'Ingen tilgang til journal');
  }

  var RPC = {
    get_booked_slots: function (a) {
      a = a || {};
      return table('bookings').filter(function (b) {
        return ACTIVE[b.status]
          && (a.p_staff_id == null || b.staff_id === a.p_staff_id)
          && (a.p_from == null || b.date >= a.p_from)
          && (a.p_to == null || b.date <= a.p_to);
      }).map(function (b) {
        return { staff_id: b.staff_id, date: b.date, time: b.time, duration: b.duration };
      });
    },

    cancel_booking_by_ref: function (a) {
      var email = lower(a.p_email);
      var b = table('bookings').filter(function (x) { return x.ref === a.p_ref && lower(x.email) === email; })[0];
      if (!b) return { ok: false, reason: 'not_found' };
      var no = cancelBooking(b);
      if (no) return no;
      return { ok: true, ref: b.ref, date: b.date, time: hhmm(b.time), staff_name: b.staff_name };
    },

    lookup_booking_by_token: function (a) {
      if (!UUID_RE.test(String(a.p_token))) throw badUuid(a.p_token);
      var b = table('bookings').filter(function (x) { return x.cancel_token === a.p_token; })[0];
      if (!b) return { ok: false, reason: 'not_found' };
      return { ok: true, ref: b.ref, date: b.date, time: hhmm(b.time),
        staff_name: b.staff_name, service_name: b.service_name, status: b.status };
    },

    cancel_booking_by_token: function (a) {
      if (!UUID_RE.test(String(a.p_token))) throw badUuid(a.p_token);
      var b = table('bookings').filter(function (x) { return x.cancel_token === a.p_token; })[0];
      if (!b) return { ok: false, reason: 'not_found' };
      var no = cancelBooking(b);
      if (no) return no;
      return { ok: true, ref: b.ref, date: b.date, time: hhmm(b.time),
        staff_name: b.staff_name, service_name: b.service_name };
    },

    cancel_waitlist_by_ref: function (a) {
      var email = lower(a.p_email);
      var w = table('waitlist').filter(function (x) { return x.ref === a.p_ref && lower(x.email) === email; })[0];
      if (!w) return { ok: false, reason: 'not_found' };
      if (w.status === 'cancelled') return { ok: false, reason: 'already_cancelled' };
      if (w.status === 'accepted') return { ok: false, reason: 'already_accepted' };
      w.status = 'cancelled';
      w.updated_at = nowIso();
      persist();
      return { ok: true, ref: w.ref, staff_name: w.staff_name };
    },

    get_waitlist_position: function (a) {
      var list = table('waitlist');
      var w = list.filter(function (x) { return x.ref === a.p_ref && x.status === 'waiting'; })[0];
      if (!w) return null;
      return list.filter(function (x) {
        return x.status === 'waiting' && (x.staff_id == null ? w.staff_id == null : x.staff_id === w.staff_id)
          && Date.parse(x.created_at) <= Date.parse(w.created_at);
      }).length;
    },

    lookup_review_by_token: function (a) {
      if (!UUID_RE.test(String(a.p_token))) throw badUuid(a.p_token);
      var b = table('bookings').filter(function (x) { return x.review_token === a.p_token; })[0];
      if (!b) return { ok: false, reason: 'not_found' };
      var no = reviewGate(b);
      if (no) return no;
      return { ok: true, staff_name: b.staff_name, service_name: b.service_name, date: b.date };
    },

    submit_review_by_token: function (a) {
      var rating = a.p_rating == null ? null : +a.p_rating;
      if (rating == null || isNaN(rating) || rating < 1 || rating > 5) return { ok: false, reason: 'bad_rating' };
      if (a.p_body == null || !String(a.p_body).trim()) return { ok: false, reason: 'no_body' };
      if (!UUID_RE.test(String(a.p_token))) throw badUuid(a.p_token);
      var b = table('bookings').filter(function (x) { return x.review_token === a.p_token; })[0];
      if (!b) return { ok: false, reason: 'not_found' };
      var no = reviewGate(b);
      if (no) return no;
      var name = a.p_name == null ? '' : String(a.p_name).trim();
      table('reviews').push(Object.assign(META.reviews.defaults(), {
        name: name || null, rating: Math.round(rating), body: String(a.p_body).trim(),
        booking_id: b.id, status: 'pending'
      }));
      persist();
      return { ok: true };
    },

    get_journal_entries: function (a, c) {
      journalRole(c);
      var email = lower(a.p_email) || null;
      var phone = String(a.p_phone == null ? '' : a.p_phone).trim() || null;
      if (!email && !phone) return [];
      audit(c, 'journal_view', 'patient', email || phone, { via: 'rpc' });
      persist();
      var bookings = table('bookings');
      return table('journal_entries').filter(function (j) {
        var hit = (email && lower(j.patient_email) === email) || (phone && j.patient_phone === phone);
        if (!hit) return false;
        if (isAdmin(c) || j.staff_id === c.staffId) return true;
        return bookings.some(function (b) {
          return b.staff_id === c.staffId && (
            (j.patient_email && lower(b.email) === lower(j.patient_email)) ||
            (j.patient_phone && b.phone === j.patient_phone));
        });
      }).sort(function (x, y) { return Date.parse(y.created_at) - Date.parse(x.created_at); }).map(clone);
    },

    create_journal_entry: function (a, c) {
      journalRole(c);
      if (a.p_content == null || !String(a.p_content).trim()) {
        throw pgError('23514', 'Notatet kan ikke være tomt');
      }
      var row = Object.assign(META.journal_entries.defaults(), {
        booking_id: a.p_booking_id == null ? null : a.p_booking_id,
        patient_email: lower(a.p_patient_email),
        patient_phone: String(a.p_patient_phone == null ? '' : a.p_patient_phone).trim(),
        staff_id: c.staffId || (isAdmin(c) ? 'admin' : 'unknown'),
        staff_name: c.staffName || (isAdmin(c) ? 'Admin' : 'Ukjent'),
        content: String(a.p_content).trim()
      });
      table('journal_entries').push(row);
      audit(c, 'journal_create', 'journal_entry', row.id, { booking_id: row.booking_id });
      persist();
      return clone(row);
    },

    gdpr_export_patient: function (a, c) {
      if (!isAdmin(c)) throw pgError('42501', 'Kun admin kan eksportere pasientdata');
      var email = lower(a.p_email);
      if (!email) throw pgError('22023', 'Mangler e-post');
      function by(t, col, sortCol) {
        return table(t).filter(function (r) { return lower(r[col]) === email; })
          .sort(function (x, y) { return cmp(x[sortCol], y[sortCol]); }).map(clone);
      }
      var bookings = by('bookings', 'email', 'date');
      var ids = bookings.map(function (b) { return b.id; });
      var out = {
        patient_email: email,
        bookings: bookings,
        journal_entries: by('journal_entries', 'patient_email', 'created_at'),
        audit_log: by('audit_log', 'target_id', 'created_at'),
        waitlist: by('waitlist', 'email', 'created_at'),
        contact_messages: by('contact_messages', 'email', 'created_at'),
        document_sends: by('document_sends', 'customer_email', 'created_at'),
        reviews: table('reviews').filter(function (r) { return ids.indexOf(r.booking_id) !== -1; }).map(clone)
      };
      audit(c, 'gdpr_export', 'patient', email, {
        bookings_count: out.bookings.length,
        journal_entries_count: out.journal_entries.length,
        audit_log_count: out.audit_log.length,
        waitlist_count: out.waitlist.length,
        contact_messages_count: out.contact_messages.length,
        document_sends_count: out.document_sends.length,
        reviews_count: out.reviews.length
      });
      persist();
      return out;
    },

    gdpr_erase_patient: function (a, c) {
      if (!isAdmin(c)) throw pgError('42501', 'Kun admin kan pseudonymisere pasientdata');
      var email = lower(a.p_email);
      if (!email) throw pgError('22023', 'Mangler e-post');
      var pseudo = 'pseudonym_' + uuid();
      var pem = pseudo + '@anon.local';
      var ids = table('bookings').filter(function (b) { return lower(b.email) === email; }).map(function (b) { return b.id; });
      function upd(t, col, patch) {
        var n = 0;
        table(t).forEach(function (r) {
          if (lower(r[col]) === email) { Object.assign(r, patch); n++; }
        });
        return n;
      }
      var nReviews = 0;
      table('reviews').forEach(function (r) {
        if (ids.indexOf(r.booking_id) !== -1) { r.name = 'Pseudonymisert'; nReviews++; }
      });
      var nBookings = upd('bookings', 'email', { name: 'Pseudonymisert', email: pem, phone: '000000000', notes: null });
      var nJournal = upd('journal_entries', 'patient_email', { patient_email: pem, patient_phone: '000000000' });
      var nWait = upd('waitlist', 'email', { name: 'Pseudonymisert', email: pem, phone: '000000000', notes: null });
      var nContact = upd('contact_messages', 'email', { name: 'Pseudonymisert', email: pem,
        message: '[Slettet etter GDPR art. 17-forespørsel]' });
      var nDocs = upd('document_sends', 'customer_email', { customer_email: pem, link_url: '' });
      var nAudit = upd('audit_log', 'target_id', { target_id: pseudo });
      if (nBookings + nJournal + nWait + nContact + nDocs + nAudit === 0) {
        throw pgError('P0002', 'Fant ingen rader for denne e-posten');
      }
      var counts = {
        pseudonym_id: pseudo,
        bookings_updated: nBookings, journals_updated: nJournal, waitlist_updated: nWait,
        contact_messages_updated: nContact, document_sends_updated: nDocs,
        reviews_updated: nReviews, audit_rows_retargeted: nAudit
      };
      audit(c, 'gdpr_pseudonymize', 'patient', pseudo, counts);
      persist();
      return Object.assign({ ok: true }, counts, {
        manual_followup: [
          'Sjekk reviews-fritekst manuelt hvis kunden kan identifiseres av egen tekst',
          'Slett kundens e-poster i Resend-loggen (ekstern retensjon)'
        ]
      });
    }
  };

  function callRpc(fn, args, c) {
    var f = RPC[fn];
    if (!f) {
      return { data: null, error: pgError('PGRST202', 'Could not find the function public.' + fn + ' in the schema cache'), status: 404 };
    }
    try {
      return { data: clone(f(args || {}, c)), error: null, status: 200 };
    } catch (e) {
      if (e && e.code) return { data: null, error: e, status: statusFor(e) };
      console.error('Demo-backend:', e);
      return { data: null, error: pgError('XX000', String((e && e.message) || e)), status: 500 };
    }
  }

  // ============================================================
  // Spørringsbyggeren (samme kjeder som supabase-js)
  // ============================================================
  function later(fn) {
    return new Promise(function (resolve) { setTimeout(function () { resolve(fn()); }, 0); });
  }

  function Query(client, t) {
    this._client = client;
    this._q = { table: t, op: 'select', columns: '*', filters: [], order: [] };
  }
  var QP = Query.prototype;
  QP.select = function (cols, opts) {
    var q = this._q;
    if (q.op === 'select') {
      q.columns = cols || '*';
      if (opts) { q.count = opts.count || null; q.head = !!opts.head; }
    } else {
      q.returning = true;
      q.columns = cols || '*';
    }
    return this;
  };
  QP.insert = function (v) { this._q.op = 'insert'; this._q.values = v; return this; };
  QP.upsert = function (v, o) {
    this._q.op = 'upsert'; this._q.values = v;
    this._q.onConflict = o && o.onConflict;
    this._q.ignoreDuplicates = !!(o && o.ignoreDuplicates);
    return this;
  };
  QP.update = function (v) { this._q.op = 'update'; this._q.values = v; return this; };
  QP['delete'] = function () { this._q.op = 'delete'; return this; };
  ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'is', 'in'].forEach(function (op) {
    QP[op] = function (col, val) {
      this._q.filters.push({ col: col, op: op, val: op === 'in' ? (val || []).slice() : val });
      return this;
    };
  });
  QP.not = function (col, op, val) {
    var f = (op === 'in' && typeof val === 'string') ? parseFilterValue(col, 'in.' + val) : { col: col, op: op, val: val };
    f.not = true;
    this._q.filters.push(f);
    return this;
  };
  QP.filter = function (col, op, val) {
    if (op.indexOf('not.') === 0) return this.not(col, op.slice(4), val);
    var f = (op === 'in' && typeof val === 'string') ? parseFilterValue(col, 'in.' + val) : { col: col, op: op, val: val };
    this._q.filters.push(f);
    return this;
  };
  QP.match = function (obj) {
    for (var k in obj) if (Object.prototype.hasOwnProperty.call(obj, k)) this.eq(k, obj[k]);
    return this;
  };
  QP.or = function (s) { this._q.filters.push(parseOr(s)); return this; };
  QP.order = function (col, o) {
    o = o || {};
    this._q.order.push({ col: col, asc: o.ascending !== false, nullsFirst: o.nullsFirst });
    return this;
  };
  QP.limit = function (n) { this._q.limit = n; return this; };
  QP.range = function (a, b) { this._q.from = a; this._q.to = b; return this; };
  QP.single = function () { this._q.single = true; return this; };
  QP.maybeSingle = function () { this._q.maybe = true; return this; };
  QP.abortSignal = function () { return this; };
  QP.returns = function () { return this; };
  QP.throwOnError = function () { this._throw = true; return this; };
  QP.then = function (ok, bad) {
    var self = this;
    var p = later(function () { return execute(self._q, self._client._ctx()); });
    if (self._throw) p = p.then(function (r) { if (r.error) throw r.error; return r; });
    return p.then(ok, bad);
  };
  QP['catch'] = function (bad) { return this.then(null, bad); };
  QP['finally'] = function (f) { return this.then(function (r) { f(); return r; }, function (e) { f(); throw e; }); };

  // ============================================================
  // Innlogging
  // ============================================================
  // Samme to kontoer som shared/auth.js og migrasjon 0065/0069.
  var ACCOUNTS = {
    'admin@westengenklinikk.example': {
      password: 'demo-admin-2026', id: '00000000-0000-4000-a000-000000000a01',
      role: 'admin', staff_id: 'markus', staff_name: 'Markus Westengen'
    },
    'terapeut@westengenklinikk.example': {
      password: 'demo-terapeut-2026', id: '00000000-0000-4000-a000-000000000a02',
      role: 'therapist', staff_id: 'sofie', staff_name: 'Sofie Aune'
    }
  };

  function b64(s) {
    try { return btoa(unescape(encodeURIComponent(s))).replace(/=+$/, ''); } catch (_) { return 'demo'; }
  }

  function makeSession(email) {
    var a = ACCOUNTS[email];
    var now = Math.floor(Date.now() / 1000);
    var iso = new Date().toISOString();
    var user = {
      id: a.id, aud: 'authenticated', role: 'authenticated', email: email,
      email_confirmed_at: '2026-09-01T08:00:00.000Z', phone: '',
      app_metadata: { provider: 'email', providers: ['email'], role: a.role,
        staff_id: a.staff_id, staff_name: a.staff_name, demo: true },
      user_metadata: { full_name: a.staff_name },
      created_at: '2026-09-01T08:00:00.000Z', updated_at: iso, last_sign_in_at: iso
    };
    return {
      access_token: 'demo.' + b64(JSON.stringify({ sub: a.id, role: a.role })) + '.' + uuid(),
      token_type: 'bearer', expires_in: 604800, expires_at: now + 604800,
      refresh_token: uuid(), user: user
    };
  }

  function memoryStorage() {
    var m = {};
    return {
      getItem: function (k) { return Object.prototype.hasOwnProperty.call(m, k) ? m[k] : null; },
      setItem: function (k, v) { m[k] = String(v); },
      removeItem: function (k) { delete m[k]; }
    };
  }
  var localStore = {
    getItem: lsGet, setItem: lsSet, removeItem: lsDel
  };

  function authError(message, status) {
    return { name: 'AuthApiError', message: message, status: status || 400, code: 'invalid_credentials' };
  }

  function Auth(client, opts) {
    var a = (opts && opts.auth) || {};
    this._storage = a.storage || (a.persistSession === false ? memoryStorage() : localStore);
    this._key = a.storageKey || AUTH_KEY;
    this._listeners = [];
  }
  var AP = Auth.prototype;
  AP._read = function () {
    var raw = null;
    try { raw = this._storage.getItem(this._key); } catch (_) {}
    if (!raw || typeof raw !== 'string') return null;
    try {
      var s = JSON.parse(raw);
      if (!s || !s.user || !ACCOUNTS[s.user.email]) return null;
      if (s.expires_at && s.expires_at * 1000 < Date.now()) return null;
      return s;
    } catch (_) { return null; }
  };
  AP._write = function (s) {
    try {
      if (s) this._storage.setItem(this._key, JSON.stringify(s));
      else this._storage.removeItem(this._key);
    } catch (_) {}
  };
  AP._emit = function (event, session) {
    var ls = this._listeners.slice();
    setTimeout(function () {
      ls.forEach(function (l) { if (l.active) { try { l.cb(event, session); } catch (e) { console.error(e); } } });
    }, 0);
  };
  AP.getSession = function () {
    var s = this._read();
    return later(function () { return { data: { session: s }, error: null }; });
  };
  AP.getUser = function () {
    var s = this._read();
    return later(function () {
      return s ? { data: { user: s.user }, error: null }
               : { data: { user: null }, error: { name: 'AuthSessionMissingError', message: 'Auth session missing!', status: 400 } };
    });
  };
  AP.refreshSession = AP.getSession;
  AP.signInWithPassword = function (cred) {
    var self = this;
    cred = cred || {};
    var email = lower(cred.email);
    return later(function () {
      var a = ACCOUNTS[email];
      if (!a || a.password !== cred.password) {
        return { data: { user: null, session: null }, error: authError('Invalid login credentials') };
      }
      var s = makeSession(email);
      self._write(s);
      self._emit('SIGNED_IN', s);
      return { data: { user: s.user, session: s }, error: null };
    });
  };
  AP.signOut = function () {
    var self = this;
    return later(function () {
      self._write(null);
      self._emit('SIGNED_OUT', null);
      return { error: null };
    });
  };
  // Invitasjons- og tilbakestillingslenker finnes ikke i demoen.
  // Har nettleseren en sesjon, beholdes den; ellers blir man admin.
  AP.setSession = function () {
    var self = this;
    return later(function () {
      var s = self._read() || makeSession('admin@westengenklinikk.example');
      self._write(s);
      self._emit('SIGNED_IN', s);
      return { data: { session: s, user: s.user }, error: null };
    });
  };
  // Passordet byttes ikke på ekte: da ville den automatiske
  // innloggingen sluttet å virke for alle som kom etterpå.
  AP.updateUser = function () {
    var self = this;
    return later(function () {
      var s = self._read();
      if (!s) return { data: { user: null }, error: { name: 'AuthSessionMissingError', message: 'Auth session missing!', status: 400 } };
      self._emit('USER_UPDATED', s);
      return { data: { user: s.user }, error: null };
    });
  };
  AP.resetPasswordForEmail = function () {
    return later(function () { return { data: {}, error: null }; });
  };
  AP.onAuthStateChange = function (cb) {
    var l = { cb: cb, active: true };
    this._listeners.push(l);
    return { data: { subscription: { id: uuid(), unsubscribe: function () { l.active = false; } } } };
  };
  AP.startAutoRefresh = function () { return Promise.resolve(); };
  AP.stopAutoRefresh = function () { return Promise.resolve(); };

  function contextFromSession(s) {
    if (!s || !s.user) return { role: 'anon' };
    var m = s.user.app_metadata || {};
    return { role: m.role === 'admin' ? 'admin' : (m.role === 'therapist' ? 'therapist' : 'anon'),
             staffId: m.staff_id || null, staffName: m.staff_name || null, userId: s.user.id };
  }

  // ============================================================
  // Lagring av filer (Dokumenter)
  // ============================================================
  var fileMem = {};
  function readFiles() {
    try { return JSON.parse(lsGet(FILES_KEY) || '{}') || {}; } catch (_) { return {}; }
  }
  function writeFiles(f) { return lsSet(FILES_KEY, JSON.stringify(f)); }

  // En liten, gyldig PDF med én tekstlinje. Brukes for dokumentene
  // som følger med demoen: de har aldri hatt en ekte fil bak seg.
  function placeholderPdf(title) {
    var text = String(title || 'Demodokument').replace(/[^\x20-\x7e]/g, '?').replace(/([()\\])/g, '\\$1');
    var stream = 'BT /F1 18 Tf 72 760 Td (' + text + ') Tj 0 -28 Td /F1 12 Tf ' +
      '(Demodokument fra Westengen Klinikk. Klinikken er oppdiktet.) Tj ET';
    var objs = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
      '<< /Length ' + stream.length + ' >>\nstream\n' + stream + '\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    ];
    var out = '%PDF-1.4\n';
    var offs = [];
    objs.forEach(function (o, i) { offs.push(out.length); out += (i + 1) + ' 0 obj\n' + o + '\nendobj\n'; });
    var xref = out.length;
    out += 'xref\n0 ' + (objs.length + 1) + '\n0000000000 65535 f \n';
    offs.forEach(function (o) { out += String(o).padStart(10, '0') + ' 00000 n \n'; });
    out += 'trailer\n<< /Size ' + (objs.length + 1) + ' /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF\n';
    return new Blob([out], { type: 'application/pdf' });
  }

  function dataUrlToBlob(u) {
    var parts = String(u).split(',');
    var mime = (/data:([^;]+)/.exec(parts[0]) || [])[1] || 'application/octet-stream';
    var bin = atob(parts[1] || '');
    var arr = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    return new Blob([arr], { type: mime });
  }

  function Bucket(name) { this._name = name; }
  var BP = Bucket.prototype;
  BP.upload = function (path, file, opts) {
    var full = this._name + '/' + path;
    return new Promise(function (resolve) {
      var done = function (dataUrl) {
        var files = readFiles();
        if (files[full] && !(opts && opts.upsert)) {
          resolve({ data: null, error: { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' } });
          return;
        }
        fileMem[full] = file;
        // Små filer huskes til i morgen. Store filer bare så lenge siden er åpen.
        if (dataUrl && dataUrl.length < 1500000) {
          files[full] = { type: (file && file.type) || '', data: dataUrl };
          writeFiles(files);
        }
        resolve({ data: { path: path, id: uuid(), fullPath: full }, error: null });
      };
      try {
        var r = new FileReader();
        r.onload = function () { done(String(r.result)); };
        r.onerror = function () { done(null); };
        r.readAsDataURL(file);
      } catch (_) { done(null); }
    });
  };
  BP.remove = function (paths) {
    var name = this._name;
    return later(function () {
      var files = readFiles();
      (paths || []).forEach(function (p) { delete files[name + '/' + p]; delete fileMem[name + '/' + p]; });
      writeFiles(files);
      return { data: (paths || []).map(function (p) { return { name: p }; }), error: null };
    });
  };
  BP.createSignedUrl = function (path) {
    var full = this._name + '/' + path;
    return later(function () {
      var blob = fileMem[full];
      if (!blob) {
        var f = readFiles()[full];
        if (f && f.data) { try { blob = dataUrlToBlob(f.data); } catch (_) {} }
      }
      if (!blob) {
        var doc = table('exercise_documents').filter(function (d) { return d.storage_path === path; })[0];
        blob = placeholderPdf(doc ? doc.title : path);
      }
      return { data: { signedUrl: URL.createObjectURL(blob) }, error: null };
    });
  };
  BP.download = function (path) {
    var full = this._name + '/' + path;
    return later(function () {
      var f = fileMem[full] || (readFiles()[full] && dataUrlToBlob(readFiles()[full].data)) || placeholderPdf(path);
      return { data: f, error: null };
    });
  };
  BP.getPublicUrl = function (path) { return { data: { publicUrl: 'demo://' + this._name + '/' + path } }; };

  // ============================================================
  // Klienten
  // ============================================================
  function Client(url, key, opts) {
    this.supabaseUrl = url;
    this.supabaseKey = key;
    this.auth = new Auth(this, opts);
    var self = this;
    this.storage = { from: function (b) { return new Bucket(b); } };
    this.realtime = { channels: channels };
    this._ctx = function () { return contextFromSession(self.auth._read()); };
  }
  Client.prototype.from = function (t) { return new Query(this, t); };
  Client.prototype.schema = function () { return this; };
  Client.prototype.rpc = function (fn, args) {
    var self = this;
    var p = later(function () {
      var r = callRpc(fn, args, self._ctx());
      return { data: r.data, error: r.error, count: null, status: r.status, statusText: r.error ? 'Error' : 'OK' };
    });
    // Noen kallsteder kjeder videre. Ingen trenger mer enn then/catch.
    return p;
  };
  Client.prototype.channel = function (name) { return makeChannel(name); };
  Client.prototype.removeChannel = function (ch) { return ch && ch.unsubscribe ? ch.unsubscribe() : Promise.resolve('ok'); };
  Client.prototype.removeAllChannels = function () {
    return Promise.all(channels.slice().map(function (c) { return c.unsubscribe(); }));
  };
  Client.prototype.getChannels = function () { return channels.slice(); };

  root.supabase = {
    createClient: function (url, key, opts) { return new Client(url, key, opts); }
  };

  // ============================================================
  // fetch-fangst: PostgREST og Edge Functions på demo.invalid
  // ============================================================
  function header(init, name) {
    var h = init && init.headers;
    if (!h) return '';
    try {
      if (typeof h.get === 'function') return h.get(name) || '';
      var lowerName = name.toLowerCase();
      for (var k in h) if (k.toLowerCase() === lowerName) return String(h[k]);
    } catch (_) {}
    return '';
  }

  function json(status, body, extra) {
    var headers = { 'Content-Type': 'application/json; charset=utf-8' };
    if (extra) for (var k in extra) headers[k] = extra[k];
    if (status === 204) return new Response(null, { status: 204, headers: headers });
    return new Response(body === undefined ? '' : JSON.stringify(body), { status: status, headers: headers });
  }

  // REST-kall fra booking-engine/services går som anon, akkurat som
  // før: de sender anon-nøkkelen, ikke en brukers token.
  function restContext(init) {
    var authz = header(init, 'Authorization').replace(/^Bearer\s+/i, '');
    var s = (new Auth(null, {}))._read();
    if (s && authz && authz === s.access_token) return contextFromSession(s);
    return { role: 'anon' };
  }

  function parseOrder(s) {
    return String(s).split(',').filter(Boolean).map(function (part) {
      var bits = part.split('.');
      var o = { col: bits[0], asc: true, nullsFirst: null };
      bits.slice(1).forEach(function (b) {
        if (b === 'desc') o.asc = false;
        if (b === 'asc') o.asc = true;
        if (b === 'nullsfirst') o.nullsFirst = true;
        if (b === 'nullslast') o.nullsFirst = false;
      });
      return o;
    });
  }

  function handleRest(path, params, method, init) {
    var body = null;
    if (init && init.body != null && init.body !== '') {
      try { body = JSON.parse(init.body); } catch (_) { return json(400, pgError('PGRST102', 'Empty or invalid json')); }
    }
    var ctx = restContext(init);

    var rpc = /^\/rest\/v1\/rpc\/([A-Za-z0-9_]+)$/.exec(path);
    if (rpc) {
      var r = callRpc(rpc[1], body || {}, ctx);
      return r.error ? json(r.status, r.error) : json(200, r.data === undefined ? null : r.data);
    }

    var m = /^\/rest\/v1\/([A-Za-z0-9_]+)$/.exec(path);
    if (!m) return json(404, pgError('PGRST125', 'Invalid path specified in request URL'));

    var q = { table: m[1], op: 'select', columns: '*', filters: [], order: [] };
    var prefer = header(init, 'Prefer');
    params.forEach(function (val, key) {
      if (key === 'select') q.columns = val;
      else if (key === 'order') q.order = parseOrder(val);
      else if (key === 'limit') q.limit = +val;
      else if (key === 'offset') q.from = +val;
      else if (key === 'on_conflict') q.onConflict = val;
      else if (key === 'or') q.filters.push(parseOr(val));
      else if (key === 'columns') { /* ignorert */ }
      else q.filters.push(parseFilterValue(key, val));
    });
    if (q.limit != null && q.from == null) q.from = 0;
    if (/count=exact/.test(prefer)) q.count = 'exact';

    if (method === 'GET' || method === 'HEAD') {
      q.op = 'select';
    } else if (method === 'POST') {
      q.op = /resolution=(merge|ignore)-duplicates/.test(prefer) ? 'upsert' : 'insert';
      q.ignoreDuplicates = /resolution=ignore-duplicates/.test(prefer);
      q.values = body;
      q.returning = /return=representation/.test(prefer);
    } else if (method === 'PATCH') {
      q.op = 'update'; q.values = body;
      q.returning = /return=representation/.test(prefer);
    } else if (method === 'DELETE') {
      q.op = 'delete';
      q.returning = /return=representation/.test(prefer);
    } else {
      return json(405, pgError('PGRST117', 'Unsupported HTTP method'));
    }

    var res = execute(q, ctx);
    if (res.error) return json(res.status, res.error);
    var extra = {};
    if (res.count != null) extra['Content-Range'] = '0-' + Math.max(0, (res.data || []).length - 1) + '/' + res.count;
    if (q.op === 'select') return json(200, res.data, extra);
    if (!q.returning) return json(q.op === 'insert' || q.op === 'upsert' ? 201 : 204, undefined, extra);
    return json(q.op === 'insert' || q.op === 'upsert' ? 201 : 200, res.data, extra);
  }

  // Kontaktskjemaet. I drift sjekker funksjonen Turnstile og en
  // grense per IP før den legger meldingen inn med service_role.
  function submitContact(init) {
    var p = {};
    try { p = JSON.parse((init && init.body) || '{}') || {}; } catch (_) { return json(400, { ok: false, error: 'bad_json' }); }
    if (String(p.company || '').trim()) return json(200, { ok: true });
    var name = String(p.name || '').trim();
    var email = String(p.email || '').trim();
    var message = String(p.message || '').trim();
    if (!name || !email || !message || email.indexOf('@') === -1) return json(400, { ok: false, error: 'missing_fields' });
    if (message.length > 2000 || name.length > 200 || email.length > 320) return json(400, { ok: false, error: 'too_long' });
    var res = execute({ table: 'contact_messages', op: 'insert', values: { name: name, email: email, message: message } }, SERVICE);
    if (res.error) return json(500, { ok: false, error: 'insert_failed' });
    return json(200, { ok: true });
  }

  var nativeFetch = root.fetch ? root.fetch.bind(root) : null;
  root.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input
      : (input && typeof input.url === 'string') ? input.url : String(input);
    if (url.indexOf(BASE) !== 0) {
      if (!nativeFetch) return Promise.reject(new TypeError('fetch er ikke tilgjengelig'));
      return nativeFetch(input, init);
    }
    init = init || {};
    var method = String(init.method || (input && input.method) || 'GET').toUpperCase();
    return later(function () {
      var u = new URL(url);
      if (u.pathname === '/functions/v1/submit-contact') return submitContact(init);
      if (u.pathname.indexOf('/rest/v1/') === 0) return handleRest(u.pathname, u.searchParams, method, init);
      return json(404, { error: 'not_found', message: 'Finnes ikke i demoen' });
    });
  };

  // ============================================================
  // Eksport (for feilsøking i konsollen)
  // ============================================================
  root.WestengenKlinikkDemoBackend = {
    url: BASE,
    /** Bygger dagens data på nytt og glemmer alt som er endret. */
    reset: function () {
      lsDel(DB_KEY); lsDel(FILES_KEY);
      mem = null; db();
    },
    day: function () { return db().day; },
    _table: function (t) { return clone(table(t)); }
  };
})(window);
