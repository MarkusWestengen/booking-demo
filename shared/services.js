/* ============================================================
   Westengen Klinikk — Services loader / cache
   ------------------------------------------------------------
   Sentralt API for lesing av services + staff_services. Bruker
   PostgREST direkte via fetch (samme stil som booking-engine.js)
   slik at både anon-flyt (bestilling.html) og authenticated-flyt
   (kalender FAB, tjenester.html) kan dele samme modul uten å
   måtte ha en innlogget Supabase-klient.

   Skriving (insert/update/delete) skjer i tjenester.html mot
   en authenticated sb-klient — de funksjonene tar `sb` som
   parameter og bruker SDK-en (RLS + retur-data + audit-rad).

   Cache: 60s TTL på loadActiveServices() og loadStaffMap().
   Alle skriveoperasjoner invaliderer cache.

   Eksporterer:
     window.WestengenKlinikkServices = {
       slugify(text),
       loadActiveServices(),                 // anon-safe
       loadAllServices(sb),                  // admin: inkl. inaktive
       loadStaffMap(),                       // { staffId: [serviceId, ...] }
       servicesForStaff(staffId, opts?),     // filtert + ordered
       findBySlug(slug),                     // siste lastede liste
       invalidate(),
       createService(sb, payload),
       updateService(sb, id, patch),
       setActive(sb, id, isActive),
       setStaffForService(sb, serviceId, staffIds)
     };
   ============================================================ */
(function (root) {
  'use strict';

  var CFG = root.WestengenKlinikkBackend || {};
  var URL = (CFG.supabaseUrl || '').replace(/\/+$/, '');
  var KEY = CFG.supabaseAnonKey || '';
  var TTL_MS = 60 * 1000;

  // ----- Anon REST helpers (mirror of booking-engine pattern) ----
  function anonHeaders() {
    return {
      'apikey': KEY,
      'Authorization': 'Bearer ' + KEY,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
  }
  function anonGet(path) {
    return fetch(URL + '/rest/v1/' + path, { headers: anonHeaders() })
      .then(function (r) {
        if (!r.ok) throw new Error('services GET ' + r.status);
        return r.json();
      });
  }

  // ----- In-memory cache ----------------------------------------
  var cache = {
    activeServices: null,    // [service]
    activeAt: 0,
    allServices: null,       // admin only (includes inactive)
    allAt: 0,
    staffMap: null,          // { staffId: [serviceId, ...] }
    staffMapAt: 0,
    bySlug: {}               // index for findBySlug()
  };

  function indexBySlug(list) {
    var map = {};
    list.forEach(function (s) { if (s && s.slug) map[s.slug] = s; });
    cache.bySlug = map;
  }

  function findBySlug(slug) {
    return cache.bySlug[slug] || null;
  }

  function invalidate() {
    cache.activeServices = null;
    cache.activeAt = 0;
    cache.allServices = null;
    cache.allAt = 0;
    cache.staffMap = null;
    cache.staffMapAt = 0;
    // bySlug beholdes — findBySlug brukes til fallback-rendering
    // (gamle bookinger). Den oppdateres ved neste load.
  }

  // ----- Slug helper --------------------------------------------
  // Translitterer norske tegn, lowercase, og kollapser ikke-alfanumeriske
  // tegn til bindestrek. Trimmer ledende/etterfølgende bindestreker.
  function slugify(text) {
    if (text == null) return '';
    var s = String(text).toLowerCase();
    var map = { 'æ': 'ae', 'ø': 'o', 'å': 'a', 'ä': 'a', 'ö': 'o', 'ü': 'u', 'é': 'e', 'è': 'e', 'ê': 'e', 'à': 'a', 'á': 'a' };
    s = s.replace(/[æøåäöüéèêàá]/g, function (c) { return map[c] || c; });
    s = s.replace(/[^a-z0-9]+/g, '-');
    s = s.replace(/^-+|-+$/g, '');
    return s;
  }

  // ----- Loaders ------------------------------------------------
  function loadActiveServices() {
    var now = Date.now();
    if (cache.activeServices && (now - cache.activeAt) < TTL_MS) {
      return Promise.resolve(cache.activeServices);
    }
    return anonGet('services?select=*&is_active=eq.true&is_public=eq.true&order=sort_order.asc,name.asc')
      .then(function (rows) {
        cache.activeServices = rows || [];
        cache.activeAt = Date.now();
        indexBySlug(cache.activeServices);
        return cache.activeServices;
      });
  }

  // Admin-only: returnerer ALLE services (inkl. inaktive).
  // Krever authenticated sb-klient (RLS-policyen tillater admin å
  // se inaktive via auth.jwt-OR-grenen). For anon faller den tilbake
  // til loadActiveServices() automatisk.
  function loadAllServices(sb) {
    if (!sb) return loadActiveServices();
    var now = Date.now();
    if (cache.allServices && (now - cache.allAt) < TTL_MS) {
      return Promise.resolve(cache.allServices);
    }
    return sb.from('services').select('*').order('sort_order', { ascending: true }).order('name', { ascending: true })
      .then(function (res) {
        if (res.error) throw res.error;
        cache.allServices = res.data || [];
        cache.allAt = Date.now();
        indexBySlug(cache.allServices);
        return cache.allServices;
      });
  }

  function loadStaffMap() {
    var now = Date.now();
    if (cache.staffMap && (now - cache.staffMapAt) < TTL_MS) {
      return Promise.resolve(cache.staffMap);
    }
    return anonGet('staff_services?select=staff_id,service_id')
      .then(function (rows) {
        var map = {};
        (rows || []).forEach(function (r) {
          if (!map[r.staff_id]) map[r.staff_id] = [];
          map[r.staff_id].push(r.service_id);
        });
        cache.staffMap = map;
        cache.staffMapAt = Date.now();
        return map;
      });
  }

  // Returnerer tjenester filtrert til en gitt staff, sortert.
  // opts.includeInactive (kun admin via loadAllServices) = inkluder inaktive.
  function servicesForStaff(staffId, opts) {
    opts = opts || {};
    var loadFn = (opts.includeInactive && opts.sb) ? function () { return loadAllServices(opts.sb); } : loadActiveServices;
    return Promise.all([loadFn(), loadStaffMap()]).then(function (res) {
      var all = res[0], map = res[1];
      var ids = map[staffId] || [];
      var idSet = {};
      ids.forEach(function (i) { idSet[i] = true; });
      return all.filter(function (s) { return idSet[s.id]; });
    });
  }

  // ----- Mutations (admin only — krever authenticated sb) -------
  function createService(sb, payload) {
    var row = {
      slug: payload.slug,
      name: payload.name,
      description: payload.description || null,
      duration_min: payload.duration_min,
      price_nok: payload.price_nok,
      color: payload.color || null,
      icon: payload.icon || null,
      sort_order: payload.sort_order != null ? payload.sort_order : 0,
      is_active: payload.is_active !== false,
      is_public: payload.is_public !== false
    };
    return sb.from('services').insert(row).select().single()
      .then(function (res) {
        if (res.error) throw res.error;
        invalidate();
        return res.data;
      });
  }

  function updateService(sb, id, patch) {
    // Hvit-list felter for å unngå at en uvelsignet patch endrer id/created_at/updated_at.
    var allowed = ['slug','name','description','duration_min','price_nok','color','icon','sort_order','is_active','is_public'];
    var clean = {};
    allowed.forEach(function (k) { if (patch.hasOwnProperty(k)) clean[k] = patch[k]; });
    return sb.from('services').update(clean).eq('id', id).select().single()
      .then(function (res) {
        if (res.error) throw res.error;
        invalidate();
        return res.data;
      });
  }

  function setActive(sb, id, isActive) {
    return updateService(sb, id, { is_active: !!isActive });
  }

  // Erstatt staff-koblingen for en service med en ny liste staff-IDer.
  // Strategi: hent eksisterende, beregn diff, INSERT manglende + DELETE
  // overflødige. Minimerer skrivinger og lar audit-logg telle endringer.
  function setStaffForService(sb, serviceId, staffIds) {
    var desired = {};
    (staffIds || []).forEach(function (id) { desired[id] = true; });

    return sb.from('staff_services').select('staff_id').eq('service_id', serviceId)
      .then(function (res) {
        if (res.error) throw res.error;
        var existing = {};
        (res.data || []).forEach(function (r) { existing[r.staff_id] = true; });

        var toAdd = Object.keys(desired).filter(function (k) { return !existing[k]; });
        var toRemove = Object.keys(existing).filter(function (k) { return !desired[k]; });

        var ops = [];
        if (toAdd.length) {
          ops.push(sb.from('staff_services').insert(
            toAdd.map(function (sid) { return { staff_id: sid, service_id: serviceId }; })
          ));
        }
        if (toRemove.length) {
          // PostgREST krever én DELETE per stilling-id-liste med .in()
          ops.push(sb.from('staff_services').delete().eq('service_id', serviceId).in('staff_id', toRemove));
        }
        return Promise.all(ops).then(function (results) {
          for (var i = 0; i < results.length; i++) {
            if (results[i] && results[i].error) throw results[i].error;
          }
          invalidate();
          return { added: toAdd, removed: toRemove };
        });
      });
  }

  // ----- Export -------------------------------------------------
  root.WestengenKlinikkServices = {
    slugify: slugify,
    loadActiveServices: loadActiveServices,
    loadAllServices: loadAllServices,
    loadStaffMap: loadStaffMap,
    servicesForStaff: servicesForStaff,
    findBySlug: findBySlug,
    invalidate: invalidate,
    createService: createService,
    updateService: updateService,
    setActive: setActive,
    setStaffForService: setStaffForService
  };
})(window);
