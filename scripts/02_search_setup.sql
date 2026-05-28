-- 02 — search layer setup (run AFTER restoring the DENUE data dumps).
--
-- Creates everything the natural-language search route needs that is NOT in
-- the feature dumps (the denue_*.sql.gz only carry gis_dataset/gis_layer/
-- gis_feature):
--   gis.search_normalize(text)  lowercase + accent-strip helper (IMMUTABLE)
--   gis.activity_synonym         NL phrase → SCIAN code prefixes (rule-based)
--   gis.gaz_state                32 INEGI states + aliases + envelope geoms
--   gis.gaz_region               named non-administrative regions (unions)
--
-- Idempotent: re-running preserves manual edits via ON CONFLICT DO UPDATE.
-- Self-contained: creates the gis schema + pg_trgm if missing, so it can run
-- standalone. After this, run 03_search_indexes.sql then 04_gaz_municipio.sql
-- (both need gis_feature loaded).
--
-- Apply:
--   psql "$PGURL" -v ON_ERROR_STOP=1 -f scripts/02_search_setup.sql
-- Or via the helper:
--   ./scripts/quickstart.sh search
--
-- SCIAN note: DENUE 2025 uses SCIAN 2018 (restaurants = 7225, not 7222).
-- The synonym codes below were audited against the actual corpus 2026-05-27.

CREATE SCHEMA IF NOT EXISTS gis;
SET search_path TO gis, public;

-- pg_trgm powers fuzzy place-name + municipality lookup ("aguas" →
-- "Aguascalientes", "monterey" → "Monterrey"). Installed into the gis schema;
-- the route fully-qualifies gis.similarity / OPERATOR(gis.%) / OPERATOR(gis.<->)
-- because Neon's pooler doesn't always honour a connection-init search_path.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ─── normalisation helper ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION gis.search_normalize(input text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT translate(lower(coalesce(input, '')), 'áéíóúñü', 'aeiounu')
$$;

-- ─── activity_synonym ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gis.activity_synonym (
  id               text        PRIMARY KEY,
  phrase           text        NOT NULL,
  phrase_norm      text        NOT NULL,
  codigo_prefixes  text[]      NOT NULL,
  source           text        NOT NULL DEFAULT 'manual',
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (phrase_norm)
);
CREATE INDEX IF NOT EXISTS activity_synonym_phrase_trgm
  ON gis.activity_synonym USING gin (phrase_norm gin_trgm_ops);

-- ─── gaz_state ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gis.gaz_state (
  slug         text        PRIMARY KEY,
  code         text        NOT NULL,
  name_es      text        NOT NULL,
  name_norm    text        NOT NULL,
  names_alt    text[]      NOT NULL DEFAULT '{}'::text[],
  geom         geometry(Geometry, 4326) NOT NULL,
  centroid     geometry(Point, 4326)    NOT NULL,
  feature_count bigint     NOT NULL DEFAULT 0,
  UNIQUE (code)
);
CREATE INDEX IF NOT EXISTS gaz_state_geom_gist ON gis.gaz_state USING gist (geom);
CREATE INDEX IF NOT EXISTS gaz_state_name_trgm ON gis.gaz_state USING gin (name_norm gin_trgm_ops);

-- ─── gaz_region ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gis.gaz_region (
  id           text        PRIMARY KEY,
  name_es      text        NOT NULL,
  name_norm    text        NOT NULL,
  names_alt    text[]      NOT NULL DEFAULT '{}'::text[],
  state_slugs  text[]      NOT NULL,
  geom         geometry(Geometry, 4326) NOT NULL,
  notes        text,
  UNIQUE (name_norm)
);
CREATE INDEX IF NOT EXISTS gaz_region_geom_gist ON gis.gaz_region USING gist (geom);
CREATE INDEX IF NOT EXISTS gaz_region_name_trgm ON gis.gaz_region USING gin (name_norm gin_trgm_ops);

-- ─── State seed ────────────────────────────────────────────────────────────
-- v0 polygon = bbox envelope (ST_MakeEnvelope(minLon,minLat,maxLon,maxLat)).
-- Population-weighted centroids. feature_count is the 2025 vintage snapshot.
INSERT INTO gis.gaz_state (slug, code, name_es, name_norm, names_alt, geom, centroid, feature_count) VALUES
  ('ags','01','Aguascalientes',                gis.search_normalize('Aguascalientes'),                ARRAY['aguas','ags'],                            ST_MakeEnvelope(-102.7232, 21.7521, -101.9650, 22.3650, 4326), ST_SetSRID(ST_MakePoint(-102.2957, 21.9317), 4326), 71871),
  ('bc', '02','Baja California',               gis.search_normalize('Baja California'),               ARRAY['baja','bcn','tijuana','mexicali'],        ST_MakeEnvelope(-117.1163, 30.4715, -114.7303, 32.7156, 4326), ST_SetSRID(ST_MakePoint(-116.4125, 32.3554), 4326), 139208),
  ('bcs','03','Baja California Sur',           gis.search_normalize('Baja California Sur'),           ARRAY['baja sur','la paz','los cabos'],          ST_MakeEnvelope(-114.0528, 22.8796, -109.6587, 27.9722, 4326), ST_SetSRID(ST_MakePoint(-110.4775, 24.0091), 4326), 42577),
  ('cam','04','Campeche',                      gis.search_normalize('Campeche'),                      ARRAY[]::text[],                                  ST_MakeEnvelope(-92.2906,  18.1843, -89.3940,  20.4473, 4326), ST_SetSRID(ST_MakePoint(-90.8715, 19.3379), 4326),  47821),
  ('coa','05','Coahuila de Zaragoza',          gis.search_normalize('Coahuila de Zaragoza'),          ARRAY['coahuila','saltillo','torreon'],          ST_MakeEnvelope(-103.4693, 25.3494, -100.5154, 29.3338, 4326), ST_SetSRID(ST_MakePoint(-101.8616, 26.2962), 4326), 126952),
  ('col','06','Colima',                        gis.search_normalize('Colima'),                        ARRAY['manzanillo'],                              ST_MakeEnvelope(-104.3903, 18.7505, -103.5719, 19.3887, 4326), ST_SetSRID(ST_MakePoint(-103.9058, 19.1496), 4326), 42073),
  ('chp','07','Chiapas',                       gis.search_normalize('Chiapas'),                       ARRAY['tuxtla','san cristobal'],                  ST_MakeEnvelope(-93.9020,  14.6803, -90.8804,  17.8602, 4326), ST_SetSRID(ST_MakePoint(-92.7073, 16.3681), 4326),  250960),
  ('chh','08','Chihuahua',                     gis.search_normalize('Chihuahua'),                     ARRAY['ciudad juarez','juarez'],                  ST_MakeEnvelope(-108.2269, 26.4299, -104.4142, 31.7732, 4326), ST_SetSRID(ST_MakePoint(-106.3130, 29.5435), 4326), 142295),
  ('cmx','09','Ciudad de México',              gis.search_normalize('Ciudad de México'),              ARRAY['cdmx','df','distrito federal','mexico df','ciudad de mexico'], ST_MakeEnvelope(-99.2996, 19.1905, -98.9758, 19.5604, 4326), ST_SetSRID(ST_MakePoint(-99.1273, 19.3817), 4326), 462732),
  ('dur','10','Durango',                       gis.search_normalize('Durango'),                       ARRAY[]::text[],                                  ST_MakeEnvelope(-106.5723, 23.6192, -103.3529, 26.4400, 4326), ST_SetSRID(ST_MakePoint(-104.3519, 24.6231), 4326), 75111),
  ('gua','11','Guanajuato',                    gis.search_normalize('Guanajuato'),                    ARRAY['gto','leon','irapuato','celaya'],          ST_MakeEnvelope(-101.9609, 20.0146, -100.2174, 21.6115, 4326), ST_SetSRID(ST_MakePoint(-101.2940, 20.8087), 4326), 296441),
  ('gro','12','Guerrero',                      gis.search_normalize('Guerrero'),                      ARRAY['acapulco','chilpancingo'],                 ST_MakeEnvelope(-101.6380, 16.4713, -98.2407,  18.6490, 4326), ST_SetSRID(ST_MakePoint(-99.6255, 17.4776), 4326),  185797),
  ('hid','13','Hidalgo',                       gis.search_normalize('Hidalgo'),                       ARRAY['pachuca'],                                 ST_MakeEnvelope(-99.6534,  19.6576, -98.1645,  21.1720, 4326), ST_SetSRID(ST_MakePoint(-98.8401, 20.2130), 4326),  160666),
  ('jal','14','Jalisco',                       gis.search_normalize('Jalisco'),                       ARRAY['guadalajara','gdl','zapopan'],             ST_MakeEnvelope(-105.2502, 19.2368, -101.8904, 22.1146, 4326), ST_SetSRID(ST_MakePoint(-103.3642, 20.5937), 4326), 401813),
  ('mex','15','México',                        gis.search_normalize('México'),                        ARRAY['edomex','estado de mexico','edo mex','edo. mex.','toluca','ecatepec','naucalpan'], ST_MakeEnvelope(-100.1596, 18.8425, -98.7568, 19.9748, 4326), ST_SetSRID(ST_MakePoint(-99.2182, 19.4698), 4326), 820853),
  ('mic','16','Michoacán de Ocampo',           gis.search_normalize('Michoacán de Ocampo'),           ARRAY['michoacan','morelia','uruapan'],           ST_MakeEnvelope(-103.1669, 17.9581, -100.2764, 20.3529, 4326), ST_SetSRID(ST_MakePoint(-101.7000, 19.5873), 4326), 287049),
  ('mor','17','Morelos',                       gis.search_normalize('Morelos'),                       ARRAY['cuernavaca'],                              ST_MakeEnvelope(-99.3952,  18.4981, -98.6972,  19.0514, 4326), ST_SetSRID(ST_MakePoint(-99.1010, 18.8308), 4326),  113066),
  ('nay','18','Nayarit',                       gis.search_normalize('Nayarit'),                       ARRAY['tepic','riviera nayarit'],                 ST_MakeEnvelope(-105.6357, 20.6935, -104.3543, 22.5117, 4326), ST_SetSRID(ST_MakePoint(-105.0360, 21.4509), 4326), 73357),
  ('nle','19','Nuevo León',                    gis.search_normalize('Nuevo León'),                    ARRAY['nuevo leon','monterrey','mty','san pedro'], ST_MakeEnvelope(-100.6053, 23.6775, -99.4845, 27.0295, 4326), ST_SetSRID(ST_MakePoint(-100.2561, 25.6920), 4326), 211349),
  ('oax','20','Oaxaca',                        gis.search_normalize('Oaxaca'),                        ARRAY[]::text[],                                  ST_MakeEnvelope(-98.2767,  15.7095, -94.1951,  18.5176, 4326), ST_SetSRID(ST_MakePoint(-96.5398, 16.8918), 4326),  280588),
  ('pue','21','Puebla',                        gis.search_normalize('Puebla'),                        ARRAY[]::text[],                                  ST_MakeEnvelope(-98.7116,  18.0841, -97.1361,  20.4681, 4326), ST_SetSRID(ST_MakePoint(-97.9891, 19.0913), 4326),  410693),
  ('qro','22','Querétaro',                     gis.search_normalize('Querétaro'),                     ARRAY['queretaro','qro','san juan del rio'],      ST_MakeEnvelope(-100.4921, 20.1860, -99.4707,  21.2294, 4326), ST_SetSRID(ST_MakePoint(-100.2413, 20.5910), 4326), 108868),
  ('qroo','23','Quintana Roo',                 gis.search_normalize('Quintana Roo'),                  ARRAY['cancun','playa del carmen','tulum','cozumel','chetumal'], ST_MakeEnvelope(-88.8135, 18.2932, -86.7328, 21.5226, 4326), ST_SetSRID(ST_MakePoint(-87.2784, 20.4449), 4326), 69260),
  ('slp','24','San Luis Potosí',               gis.search_normalize('San Luis Potosí'),               ARRAY['san luis potosi','slp','potosi','san luis'], ST_MakeEnvelope(-102.0811, 21.2490, -98.3743, 23.8198, 4326), ST_SetSRID(ST_MakePoint(-100.4061, 22.1970), 4326), 127613),
  ('sin','25','Sinaloa',                       gis.search_normalize('Sinaloa'),                       ARRAY['culiacan','mazatlan','los mochis'],        ST_MakeEnvelope(-109.2973, 22.7318, -105.7711, 26.7066, 4326), ST_SetSRID(ST_MakePoint(-107.5867, 24.7091), 4326), 138882),
  ('son','26','Sonora',                        gis.search_normalize('Sonora'),                        ARRAY['hermosillo','ciudad obregon','nogales'],   ST_MakeEnvelope(-114.8100, 26.7529, -108.9369, 32.4800, 4326), ST_SetSRID(ST_MakePoint(-110.9866, 29.2863), 4326), 128315),
  ('tab','27','Tabasco',                       gis.search_normalize('Tabasco'),                       ARRAY['villahermosa'],                            ST_MakeEnvelope(-94.0447,  17.4595, -91.1708,  18.5353, 4326), ST_SetSRID(ST_MakePoint(-92.9419, 18.0118), 4326),  95379),
  ('tam','28','Tamaulipas',                    gis.search_normalize('Tamaulipas'),                    ARRAY['tampico','reynosa','matamoros','nuevo laredo'], ST_MakeEnvelope(-99.7132, 22.2129, -97.4469, 27.5145, 4326), ST_SetSRID(ST_MakePoint(-98.3478, 24.7353), 4326), 148882),
  ('tla','29','Tlaxcala',                      gis.search_normalize('Tlaxcala'),                      ARRAY[]::text[],                                  ST_MakeEnvelope(-98.5807,  19.1119, -97.6529,  19.6542, 4326), ST_SetSRID(ST_MakePoint(-98.1836, 19.3286), 4326),  99366),
  ('ver','30','Veracruz',                      gis.search_normalize('Veracruz'),                      ARRAY['xalapa','coatzacoalcos','orizaba','cordoba'], ST_MakeEnvelope(-98.4001, 17.6438, -94.1003, 22.2007, 4326), ST_SetSRID(ST_MakePoint(-96.4546, 19.2360), 4326),  356724),
  ('yuc','31','Yucatán',                       gis.search_normalize('Yucatán'),                       ARRAY['yucatan','merida','valladolid'],           ST_MakeEnvelope(-90.3941,  20.0732, -87.6843,  21.3933, 4326), ST_SetSRID(ST_MakePoint(-89.3037, 20.8427), 4326),  146384),
  ('zac','32','Zacatecas',                     gis.search_normalize('Zacatecas'),                     ARRAY['fresnillo'],                               ST_MakeEnvelope(-103.8801, 21.2604, -101.4181, 24.6143, 4326), ST_SetSRID(ST_MakePoint(-102.7599, 22.8040), 4326), 75130)
ON CONFLICT (slug) DO UPDATE SET
  code = EXCLUDED.code, name_es = EXCLUDED.name_es, name_norm = EXCLUDED.name_norm,
  names_alt = EXCLUDED.names_alt, geom = EXCLUDED.geom, centroid = EXCLUDED.centroid,
  feature_count = EXCLUDED.feature_count;

-- ─── Region seed ───────────────────────────────────────────────────────────
-- v0 region geometry = union of constituent state envelopes.
INSERT INTO gis.gaz_region (id, name_es, name_norm, names_alt, state_slugs, geom, notes) VALUES
  ('reg_huasteca_potosina',  'Huasteca Potosina',     gis.search_normalize('Huasteca Potosina'),     ARRAY['huasteca','la huasteca'],                    ARRAY['slp'],                                   (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['slp'])),                                       'Eastern SLP. v0 = SLP envelope. P2 = real municipio union.'),
  ('reg_valle_de_mexico',    'Valle de México',       gis.search_normalize('Valle de México'),       ARRAY['valle mexico','zmvm','zona metropolitana'],  ARRAY['cmx','mex','hid'],                       (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['cmx','mex','hid'])),                          'CDMX + Edomex + parts of Hidalgo.'),
  ('reg_el_bajio',           'El Bajío',              gis.search_normalize('El Bajío'),              ARRAY['bajio','bajio mexicano'],                    ARRAY['gua','qro','ags'],                       (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['gua','qro','ags'])),                          'Industrial heartland: Gto + Qro + Ags. P2 adds parts of Mic, Jal, SLP.'),
  ('reg_la_mixteca',         'La Mixteca',            gis.search_normalize('La Mixteca'),            ARRAY['mixteca'],                                   ARRAY['oax','pue','gro'],                       (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['oax','pue','gro'])),                          'Cross-state cultural region. v0 = union of 3 states.'),
  ('reg_frontera_norte',     'Frontera Norte',        gis.search_normalize('Frontera Norte'),        ARRAY['frontera mexico-eua','frontera con estados unidos','frontera norte de mexico'], ARRAY['bc','son','chh','coa','nle','tam'],  (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['bc','son','chh','coa','nle','tam'])),         '6 border states with the USA.'),
  ('reg_frontera_sur',       'Frontera Sur',          gis.search_normalize('Frontera Sur'),          ARRAY['frontera con guatemala','frontera con belice'], ARRAY['chp','tab','cam','qroo'],            (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['chp','tab','cam','qroo'])),                   'Southern border with Guatemala + Belize.'),
  ('reg_riviera_maya',       'Riviera Maya',          gis.search_normalize('Riviera Maya'),          ARRAY['caribe mexicano','playa del carmen'],        ARRAY['qroo'],                                  (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['qroo'])),                                     'Tourist corridor in Quintana Roo. v0 = full state.'),
  ('reg_costa_chica',        'Costa Chica',           gis.search_normalize('Costa Chica'),           ARRAY[]::text[],                                    ARRAY['gro','oax'],                             (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['gro','oax'])),                                'Pacific coast SE of Acapulco.'),
  ('reg_costa_grande',       'Costa Grande',          gis.search_normalize('Costa Grande'),          ARRAY[]::text[],                                    ARRAY['gro'],                                   (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['gro'])),                                      'Pacific coast NW of Acapulco.'),
  ('reg_sierra_tarahumara',  'Sierra Tarahumara',     gis.search_normalize('Sierra Tarahumara'),     ARRAY['sierra madre occidental','barranca del cobre'], ARRAY['chh'],                              (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['chh'])),                                      'v0 = Chihuahua envelope.'),
  ('reg_sierra_gorda',       'Sierra Gorda',          gis.search_normalize('Sierra Gorda'),          ARRAY[]::text[],                                    ARRAY['qro','hid','slp'],                       (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['qro','hid','slp'])),                          'Cross-state biosphere: Qro + Hid + SLP.'),
  ('reg_sierra_madre_oriental','Sierra Madre Oriental', gis.search_normalize('Sierra Madre Oriental'), ARRAY[]::text[],                                  ARRAY['nle','tam','coa','slp'],                 (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['nle','tam','coa','slp'])),                    'v0 approx via 4 states.'),
  ('reg_sierra_norte_puebla','Sierra Norte de Puebla', gis.search_normalize('Sierra Norte de Puebla'), ARRAY[]::text[],                                  ARRAY['pue'],                                   (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['pue'])),                                      'v0 = Puebla envelope.'),
  ('reg_peninsula_yucatan',  'Península de Yucatán',  gis.search_normalize('Península de Yucatán'),  ARRAY['peninsula yucateca','yucatan peninsula'],    ARRAY['yuc','qroo','cam'],                      (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['yuc','qroo','cam'])),                         'Yucatán + Quintana Roo + Campeche.'),
  ('reg_norte_de_veracruz',  'Norte de Veracruz',     gis.search_normalize('Norte de Veracruz'),     ARRAY[]::text[],                                    ARRAY['ver'],                                   (SELECT ST_Union(geom) FROM gis.gaz_state WHERE slug = ANY(ARRAY['ver'])),                                      'v0 = Veracruz envelope (full state is broader).')
ON CONFLICT (id) DO UPDATE SET
  name_es = EXCLUDED.name_es, name_norm = EXCLUDED.name_norm, names_alt = EXCLUDED.names_alt,
  state_slugs = EXCLUDED.state_slugs, geom = EXCLUDED.geom, notes = EXCLUDED.notes;

-- ─── Activity synonyms ───────────────────────────────────────────────────
-- NL phrase → SCIAN 2018 code prefixes. Audited against the corpus 2026-05-27.
INSERT INTO gis.activity_synonym (id, phrase, phrase_norm, codigo_prefixes, source, notes) VALUES
  -- Restaurants & food (SCIAN 722)
  ('syn_restaurantes',         'restaurantes',           gis.search_normalize('restaurantes'),         ARRAY['722'],                              'manual', 'All restaurants + bars'),
  ('syn_comida',               'comida',                 gis.search_normalize('comida'),               ARRAY['722'],                              'manual', NULL),
  ('syn_comida_rapida',        'comida rápida',          gis.search_normalize('comida rápida'),        ARRAY['722513','722514','722517','722518'],'manual', 'Tacos + antojitos + pizzas/hamburguesas + comida para llevar'),
  ('syn_fonditas',             'fonditas',               gis.search_normalize('fonditas'),             ARRAY['722511'],                           'manual', 'Restaurantes a la carta / comida corrida'),
  ('syn_taquerias',            'taquerías',              gis.search_normalize('taquerías'),            ARRAY['722513'],                           'manual', 'Restaurantes de tacos y tortas'),
  ('syn_panaderias',           'panaderías',             gis.search_normalize('panaderías'),           ARRAY['31181'],                            'manual', 'Panificación tradicional'),
  ('syn_tortillerias',         'tortillerías',           gis.search_normalize('tortillerías'),         ARRAY['31183'],                            'manual', NULL),
  -- carnicerías intentionally absent: 4621 = minisupers; no clean butcher
  -- code in SCIAN 2018, so it falls through to a nom_estab name search.

  -- Textile manufacturing (313 + 314 + 315)
  ('syn_fabricas_de_telas',    'fábricas de telas',      gis.search_normalize('fábricas de telas'),    ARRAY['313','314'],                        'manual', 'Textile mills + textile products'),
  ('syn_textileras',           'textileras',             gis.search_normalize('textileras'),           ARRAY['313','314'],                        'manual', NULL),
  ('syn_industria_textil',     'industria textil',       gis.search_normalize('industria textil'),     ARRAY['313','314'],                        'manual', NULL),
  ('syn_fabricas_de_ropa',     'fábricas de ropa',       gis.search_normalize('fábricas de ropa'),     ARRAY['315'],                              'manual', 'Apparel manufacturing'),
  ('syn_maquilas_de_ropa',     'maquilas de ropa',       gis.search_normalize('maquilas de ropa'),     ARRAY['315'],                              'manual', NULL),

  -- Retail (43 + 46)
  ('syn_tiendas',              'tiendas',                gis.search_normalize('tiendas'),              ARRAY['46'],                               'manual', 'Retail trade'),
  ('syn_abarrotes',            'abarrotes',              gis.search_normalize('abarrotes'),            ARRAY['4611'],                             'manual', NULL),
  ('syn_supermercados',        'supermercados',          gis.search_normalize('supermercados'),        ARRAY['46211'],                            'manual', 'Supermercados + minisupers'),
  ('syn_ferreterias',          'ferreterías',            gis.search_normalize('ferreterías'),          ARRAY['467111'],                           'manual', 'Ferreterías y tlapalerías'),
  ('syn_farmacias',            'farmacias',              gis.search_normalize('farmacias'),            ARRAY['4641'],                             'manual', NULL),
  ('syn_florerias',            'florerías',              gis.search_normalize('florerías'),            ARRAY['4659'],                             'manual', NULL),

  -- Health (62)
  ('syn_hospitales',           'hospitales',             gis.search_normalize('hospitales'),           ARRAY['622'],                              'manual', NULL),
  ('syn_clinicas',             'clínicas',               gis.search_normalize('clínicas'),             ARRAY['6211','6213'],                      'manual', NULL),
  ('syn_consultorios',         'consultorios',           gis.search_normalize('consultorios'),         ARRAY['6211','6213'],                      'manual', NULL),
  ('syn_medicos',              'médicos',                gis.search_normalize('médicos'),              ARRAY['6211','6213'],                      'manual', NULL),
  ('syn_dentistas',            'dentistas',              gis.search_normalize('dentistas'),            ARRAY['6212'],                             'manual', NULL),

  -- Education (61)
  ('syn_escuelas',             'escuelas',               gis.search_normalize('escuelas'),             ARRAY['611'],                              'manual', NULL),
  ('syn_primarias',            'primarias',              gis.search_normalize('primarias'),            ARRAY['61112'],                            'manual', 'Primaria (excludes preescolar)'),
  ('syn_universidades',        'universidades',          gis.search_normalize('universidades'),        ARRAY['6113'],                             'manual', NULL),

  -- Other common services (81)
  ('syn_talleres_mecanicos',   'talleres mecánicos',     gis.search_normalize('talleres mecánicos'),   ARRAY['8111'],                             'manual', NULL),
  ('syn_lavanderias',          'lavanderías',            gis.search_normalize('lavanderías'),          ARRAY['81221'],                            'manual', 'Lavanderías y tintorerías'),
  ('syn_esteticas',            'estéticas',              gis.search_normalize('estéticas'),            ARRAY['8121'],                             'manual', NULL),
  ('syn_peluquerias',          'peluquerías',            gis.search_normalize('peluquerías'),          ARRAY['8121'],                             'manual', NULL),

  -- Hotels (721)
  ('syn_hoteles',              'hoteles',                gis.search_normalize('hoteles'),              ARRAY['721'],                              'manual', NULL),
  ('syn_moteles',              'moteles',                gis.search_normalize('moteles'),              ARRAY['7211'],                             'manual', NULL),

  -- Finance (52)
  ('syn_bancos',               'bancos',                 gis.search_normalize('bancos'),               ARRAY['522'],                              'manual', NULL),

  -- Heavy manufacturing + automotive
  ('syn_automotrices',         'automotrices',           gis.search_normalize('automotrices'),         ARRAY['336'],                              'manual', 'Transportation equipment manufacturing'),
  ('syn_ensambladoras',        'ensambladoras',          gis.search_normalize('ensambladoras'),        ARRAY['336'],                              'manual', NULL),
  ('syn_imprentas',            'imprentas',              gis.search_normalize('imprentas'),            ARRAY['323'],                              'manual', NULL),
  ('syn_constructoras',        'constructoras',          gis.search_normalize('constructoras'),        ARRAY['23'],                               'manual', NULL),
  ('syn_gasolineras',          'gasolineras',            gis.search_normalize('gasolineras'),          ARRAY['4684'],                             'manual', 'Comercio de combustibles'),
  ('syn_gasolineria',          'gasolinería',            gis.search_normalize('gasolinería'),          ARRAY['4684'],                             'manual', 'Singular spelling variant'),
  ('syn_agencias_de_autos',    'agencias de autos',      gis.search_normalize('agencias de autos'),    ARRAY['4681','4682'],                      'manual', NULL)
ON CONFLICT (phrase_norm) DO UPDATE SET
  phrase = EXCLUDED.phrase, codigo_prefixes = EXCLUDED.codigo_prefixes,
  source = EXCLUDED.source, notes = EXCLUDED.notes;

-- Sanity output.
SELECT 'gaz_state' AS table_, count(*) AS rows FROM gis.gaz_state
UNION ALL SELECT 'gaz_region', count(*) FROM gis.gaz_region
UNION ALL SELECT 'activity_synonym', count(*) FROM gis.activity_synonym;
