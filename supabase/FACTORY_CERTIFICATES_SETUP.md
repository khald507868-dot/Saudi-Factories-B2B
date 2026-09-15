# Factory certificates gallery

`web-factory.html` displays Certificates & Licenses between Overview and Posts.
The approved factory owner can upload multiple JPG, PNG or WebP images, up to
5 MiB each, and delete images after confirmation. Visitors see images only;
an empty visitor gallery is hidden. Images retain their full aspect ratio.
Click an image to open a native, keyboard-accessible viewer.

Two or more images loop horizontally, including galleries shorter than the
viewport. Hover, touch, focus and the image viewer pause automatic movement.
A pause button and reduced-motion preference are supported. One image is static.
`bestsellers-scroll.js` retains its original defaults for the home catalogue.

Apply `migrations/20260915100000_factory_certificates.sql` to enable persistence.
It was applied to the linked project on 2026-09-15; the schema and permissions
were verified with `diagnostics/factory_certificates_verify.sql`.
It creates a public image-only Storage bucket and `factory_certificates` table.
RLS and insert validation restrict writes to the confirmed, approved factory
owner and require an existing image under that owner's factory upload path.
Direct row updates are disabled. Public reads expose approved factories only.
Images are intentionally public assets; the gallery does not certify their
authenticity or change the factory's approval status.

The client decodes images before upload and removes uploaded files when row
insertion explicitly fails. Deletion removes the row, then the Storage object;
a cleanup failure is reported. The account deletion media inventory already
covers owner media in this bucket. No example certificates are uploaded.

Verification:

```text
node scripts/test_factory_certificates.mjs <directory-containing-pglite>
node scripts/test_factory_certificates_ui.mjs
```

The database test uses isolated PostgreSQL. The UI test uses native headless
Chrome with an isolated profile, mocked storage and generated test images.
It verifies owner/visitor controls, image validation, persistence requests,
confirmation, retry, sizing, ordering, viewer and loop controls in Arabic and
English. `diagnostics/factory_certificates_verify.sql` checks deployed schema
and permissions without reading customer data. This feature targets the web
factory page; Flutter receives shared translation keys only.
