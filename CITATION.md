# Citation

The data in this repository is the **Directorio Estadístico Nacional de
Unidades Económicas (DENUE)** published by the **Instituto Nacional de
Estadística y Geografía (INEGI)** of Mexico.

## Required citation

Any use, derivative work, or redistribution of the data must include a
citation in the form:

> INEGI. *Directorio Estadístico Nacional de Unidades Económicas (DENUE)*.
> {YEAR}. https://www.inegi.org.mx/app/descarga/?ti=6

Where `{YEAR}` is the DENUE vintage (currently **2025**, per
`catalog/states.json → source.vintage`).

In a UI / map viewer, the same citation is appropriate as a permanent
attribution string (e.g., overlaid on the bottom-right of a map, alongside
the OSM attribution if applicable).

## License terms

The DENUE data is published under INEGI's **Términos de Libre Uso de la
Información**:

> https://www.inegi.org.mx/inegi/terminos.html

Key points (this is a paraphrase — the link above is canonical):

1. **Free use, including commercial.** No prior authorization required.
2. **Attribution required.** Cite INEGI as the source as shown above.
3. **No misrepresentation.** Don't imply INEGI endorses your derived work,
   and don't alter the data in ways that misrepresent the source.
4. **No misuse of INEGI's identity.** Don't use INEGI's logos, trademarks,
   or institutional names in a way that suggests official sponsorship.
5. **INEGI is not liable** for any use of the data.

Every snapshot in this repo embeds the license link and citation in
`gis.gis_dataset.metadata` so that downstream consumers carry the
attribution forward by default.

## Scripts vs. data

The **scripts and catalog** in this repository are released under
**Apache 2.0** (see [`LICENSE`](LICENSE)).

The **data** itself (the `.sql.gz` artifacts, anything you derive by
running the scripts) is governed by INEGI's terms above — Apache 2.0
**does not apply** to the data.

## Provenance

This repository does not modify the DENUE data. The pipeline:

1. Downloads INEGI's official `denue_XX_shp.zip` archives.
2. Loads them into PostGIS via `ogr2ogr` with `-t_srs EPSG:4326` (the
   source is already WGS84; this is a sanity reprojection).
3. Serializes the unchanged feature attributes to JSONB.

No attribute filtering, no row deletion, no value normalization.
