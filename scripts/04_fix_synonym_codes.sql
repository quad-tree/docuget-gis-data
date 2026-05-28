-- Audit fixes 2026-05-27: SCIAN 2018 codes verified against actual DENUE data

-- carnicerías: 4621 = minisupers (wrong). No clean standalone butcher code in SCIAN.
-- Remove so it falls through to name search (nom_estab ILIKE '%carnicer%').
DELETE FROM gis.activity_synonym WHERE id = 'syn_carnicerias';

-- comida rápida: remove 722412 (bares/cantinas — not fast food)
UPDATE gis.activity_synonym SET codigo_prefixes = '{722513,722514,722517,722518}'
WHERE id = 'syn_comida_rapida';

-- ferreterías: 4671 too broad (tiles, glass, paint). Use 467111 (ferreterías y tlapalerías).
UPDATE gis.activity_synonym SET codigo_prefixes = '{467111}'
WHERE id = 'syn_ferreterias';

-- lavanderías: 8123 = funerarias (wrong!). Use 81221 (lavanderías y tintorerías).
UPDATE gis.activity_synonym SET codigo_prefixes = '{81221}'
WHERE id = 'syn_lavanderias';

-- panaderías: remove 46211 (minisupers). Keep only 31181 (panificación tradicional).
UPDATE gis.activity_synonym SET codigo_prefixes = '{31181}'
WHERE id = 'syn_panaderias';

-- primarias: 6111 includes preescolar. Use 61112 (primaria only, both sectors).
UPDATE gis.activity_synonym SET codigo_prefixes = '{61112}'
WHERE id = 'syn_primarias';

-- supermercados: 4611 = abarrotes (wrong). Use 46211 (supermercados + minisupers).
UPDATE gis.activity_synonym SET codigo_prefixes = '{46211}'
WHERE id = 'syn_supermercados';
