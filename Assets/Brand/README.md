# Tero brand assets

The Modern T identity, v3. Every SVG is self-contained: gradients, paths and the outlined wordmark are inline, with no fonts or external references.

| File | Use |
|---|---|
| `tero-horizontal-tagline.svg` | Logo with the tagline, for **dark** backgrounds |
| `tero-horizontal-tagline-light.svg` | Logo with the tagline, for **light** backgrounds |
| `tero-horizontal.svg` | Logo without the tagline, for **dark** backgrounds |
| `tero-horizontal-light.svg` | Logo without the tagline, for **light** backgrounds |
| `tero-icon.svg` | Square icon on its own tile; works on any background |
| `tero-symbol.svg` | The T glyph alone, on a transparent background |
| `tero-icon-1024.png` | The square icon as a raster, for places that do not take SVG |
| `tero-social-preview.png` | 1280×640 card for the repository's social preview |

The wordmark of a dark-background logo is nearly white and disappears on a light page, and the reverse is true of the light versions. Where the page can be either, switch on the colour scheme, as the READMEs do:

~~~html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Assets/Brand/tero-horizontal-tagline.svg">
  <source media="(prefers-color-scheme: light)" srcset="Assets/Brand/tero-horizontal-tagline-light.svg">
  <img src="Assets/Brand/tero-horizontal-tagline-light.svg" alt="Tero — Navigation, on Your Terms." width="440">
</picture>
~~~

The horizontal logos have equal margins left and right, so they centre correctly; their canvases were trimmed from the 1060-unit width of the original export, with no change to the artwork.
