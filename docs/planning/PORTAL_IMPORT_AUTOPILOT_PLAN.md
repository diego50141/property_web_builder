# Plan: "Autopilot de importación desde portal"

> Pega el link de tu agencia en un portal inmobiliario (Metrocuadrado) → se crea
> tu sitio web y se cargan tus propiedades automáticamente.

Estado: propuesta / plan. Basado en una prueba de concepto real contra
`https://www.metrocuadrado.com/inmobiliaria/llanocasa/7157` (julio 2026).

## Objetivo de producto

Bajar el onboarding de una inmobiliaria de **horas a minutos**. Es un gancho de
venta fuerte y encaja con el caso real de **Llano Casa** (importa *sus propios*
anuncios → más defendible legalmente que scrapear a terceros).

## Hallazgos de la PoC (evidencia)

- La página de la agencia responde HTTP 200 con OpenGraph + JSON-LD (breadcrumb
  indica "Más de 20 inmuebles").
- Se extraen ~20-23 URLs de inmuebles de la agencia desde el HTML.
- Los datos existen (precios, área en m2, habitaciones), pero **Metrocuadrado es
  una SPA Next.js con streaming RSC** (`self.__next_f`): NO hay JSON-LD limpio de
  cada propiedad ni una API JSON expuesta en el HTML inicial.
- Conclusión inicial: factible, esfuerzo medio (Playwright o API interna).

### PoC de UNA propiedad (URL individual) — de-riesga la Fase A

Probado contra `.../16573-M5010348` (una casa de Llano Casa en Restrepo). Con
**HTTP simple + OpenGraph + regex, sin Playwright**, se extrajo:

- Título, descripción, URL (OpenGraph, limpio y fiable)
- Precio venta `$ 1.750.000.000` COP + admón `$ 700.000`
- Habitaciones (5), baños (5), garajes (4), estrato (5), zona (Restrepo)
- **20 fotos** con patrón de URL predecible:
  `https://multimedia.metrocuadrado.com/<ID>/<ID>_<n>_x.jpg` (enumerables)
- Falta por HTTP: **área en m²** y campos finos → requieren la API interna o
  Playwright.

Endpoints detectados: API JSON en `commons-api.metrocuadrado.com/v1/api/commons`
(403 sin credenciales — es lo que consume la SPA); imágenes en
`multimedia.metrocuadrado.com`.

**Conclusión revisada:** el conector base de UNA propiedad es **"fácil"**
(HTTP+OG cubre ~80% + fotos). Solo los campos finos empujan a "medio".

### Spike A1 (resultado) — el conector es FÁCIL, sin Playwright ni API

Se descartó reversar la API cliente (`commons-api.metrocuadrado.com`): CloudFront
devuelve la cáscara SPA ante pedidos directos de chunks/endpoints desde el
servidor, así que descubrirla exige un navegador real. **No es necesario.**

La página HTML de la propiedad **incrusta un objeto JSON completo** en el payload
de streaming de Next.js (`self.__next_f`). Con un simple GET se obtienen TODOS
los campos, ejemplo real (casa M5010348):

```
"area":2600 (lote m²), "areac":593 (construida m²), "rooms":"5",
"bathrooms":"5", "garages":"4", "stratum":"5", "salePrice":1750000000 (COP),
"rentPrice":0, "neighborhood", "city", "propertyType"
```

Más: antigüedad, administración, descripción larga y 20 fotos (patrón
`multimedia.metrocuadrado.com/<ID>/<ID>_<n>_x.jpg`).

**Implicación:** `Pwb::Pasarelas::Metrocuadrado` se reduce a: (1) GET a la URL,
(2) extraer el JSON del payload RSC, (3) enumerar fotos por patrón, (4) mapear a
`RealtyAsset`+listing. **Sin Playwright, sin API key, sin infra extra.** Fase A
baja de "medio" a **"fácil"** (~2-3 días). El riesgo pasa a ser sólo la
estabilidad del formato RSC ante cambios de Metrocuadrado.

## Piezas que YA existen en PWB (no construir)

- Conector **Playwright**: `app/services/pwb/scraper_connectors/playwright.rb`
- **Batch import**: `app/services/pwb/batch_url_import_service.rb`
- Staging + dedup: modelo `Pwb::ScrapedProperty`
- Framework de **pasarelas** (conectores por portal):
  `app/services/pwb/pasarelas/base.rb` (+ idealista/rightmove/zoopla/generic)
- Conversión scrape → propiedad: `app/services/pwb/property_import_from_scrape_service.rb`
- Import por URL (single) con preview: `SiteAdmin::PropertyUrlImportController`
- Onboarding, media library, import de fotos (ActiveStorage/R2)

## Lo que hay que construir

### Fase A — Conector Metrocuadrado (el corazón)

- **A1. Spike de datos (~1 día, decide todo):** inspeccionar con Playwright/
  DevTools la API interna que llama la SPA de Metrocuadrado.
  - Si existe API JSON limpia → extracción fácil y rápida.
  - Si no → Playwright renderiza y se lee el DOM (más frágil pero viable).
- **A2.** Escribir `Pwb::Pasarelas::Metrocuadrado` (`extract_data` →
  `asset_data` / `listing_data` / `images`): mapear precio COP, tipo, hab/baños,
  área, ciudad/barrio, fotos, descripción.
- **A3.** Mapping en `config/scraper_mappings/metrocuadrado.json`.
- Esfuerzo: 3–5 días. Riesgo: fragilidad ante cambios de MC, rate-limit.

### Fase B — Crawler de agencia

- Dado el link de agencia → Playwright → extraer las URLs de inmuebles (+
  paginación) → alimentar el batch import existente.
- Esfuerzo: 2–3 días. (Los links ya se demostraron extraíbles.)

### Fase C — Auto-provisión del sitio ✅ (implementada, julio 2026)

- Extraer datos de la agencia (nombre, logo, teléfono, ciudad) → crear el
  tenant/website + branding básico → disparar B+A → importar fotos.
- **Hallazgo:** la ficha de cualquier propiedad incrusta el bloque completo de
  la empresa en el payload RSC: `companyName`, `companyImage` (logo),
  `companyAddress`, `companySeoUrl` (candidato a subdominio), `contactPhone` y
  `whatsapp`. La ciudad se infiere por mayoría de `mciudad` en los listados de
  la página de agencia. Sin Playwright.
- **Implementación:**
  - `Pwb::Metrocuadrado::AgencyExtractor` — datos de la agencia.
  - `Pwb::Metrocuadrado::AutoProvisioner` — subdominio (slug del portal, con
    validación), website live con defaults LATAM (es/COP), seed pack `base`
    (sin propiedades/usuarios demo), `Pwb::Agency` + dirección, logo vía
    `main_logo_url` (con fallback nuevo en `Website#logo_url`), e import
    completo. Idempotente: re-ejecutar actualiza el mismo tenant.
  - UI: panel super-admin → "Crear desde Metrocuadrado"
    (`tenant_admin/metrocuadrado_provision`).
  - Rake: `rake 'latam:provision_metrocuadrado[URL,subdominio]'`.

### Fase D — Pulido

- Preview antes de publicar, resincronización periódica, manejo de errores/
  límites.
- Esfuerzo: 2–3 días.

## Consideraciones transversales

- **Legal / ToS:** enmarcar como "importa TUS propios anuncios" + consentimiento
  del dueño; buscar si Metrocuadrado ofrece un **feed oficial** (lo ideal).
- **Infra:** Playwright en producción necesita navegadores instalados en la
  imagen Docker (añadir al `Dockerfile`).
- **Mantenimiento:** los scrapers se rompen con el tiempo; presupuestarlo.
- **Rate-limit / caché** para no golpear el portal.

## MVP recomendado (validar con Llano Casa) — ~1 semana

Una sola acción **"Importar desde Metrocuadrado"**: toma la URL de la agencia →
importa sus ~20 propiedades al tenant demo → se ven en el sitio. Sin
auto-provisión de sitio nuevo al inicio (se usa el tenant existente).

= Fase A (mínima) + Fase B. El spike **A1** es lo primero: determina si es
"fácil" (API interna) o "medio" (Playwright).

## Relacionado

- Proyecto propio `llanocasa_metrocuadrado` (Python): captura **leads** de
  Metrocuadrado por IMAP; no scrapea listados, pero su captura de leads es
  reutilizable como feature de CRM aparte.
