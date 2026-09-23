# Quantity-discount banners

Apply `supabase/migrations/20260923100000_promotion_quantity_offers.sql` in Supabase SQL Editor, then refresh the website. No product prices or orders are changed. The migration adds optional banner category/percentage fields and a public read RPC; existing administrator-only banner write policies remain in force.

The migration links the nine existing banner images to the category and percentage printed on them. Seeds match the exact row ID and image URL and only fill empty destinations. Custom external links and configured discount destinations are preserved. New or replaced artwork can be configured in the administrator's advertisement form: choose the category and advertised percentage, leaving the external URL empty. To restore an external link, clear both discount fields.

Clicking a linked banner opens `web-offers.html?promotion=<id>` in the same tab. The RPC reads the active banner and live product tiers, filters to approved factories in its category, and sorts each product's closest qualifying tier by distance from the advertised percentage. Equal distances sort by actual saving, then product ID. Pagination is performed after ranking the entire category, rather than filtering a partial product page.

**Category comes from the factory's `industry` field**, because this catalog does not have a separate product category. Correct factory classifications are therefore required. No unrelated category is substituted if the selected category has no discounts.

A saving compares a cheaper quantity tier with a higher-priced tier available at a smaller purchasable quantity. Prices are per unit. The card displays both quantities and both prices; the comparison price is not presented as a historical sale price. The minimum order quantity is respected. Overlapping tiers are split into effective ranges using the highest minimum, matching checkout; ambiguous duplicate thresholds with differing prices are omitted. The nearest tier per product is chosen, which may differ from that product's largest discount. Savings are truncated to one decimal place. Zero-price, single-price, malformed, and non-discounted tiers do not create offers.

Empty results, unavailable banners, and network errors have separate states. Retry preserves the paging offset. Back navigation refreshes the results. Existing banner artwork stays visible while the migration is pending; quantity-offer links become active after installation. The RPC is `security invoker` and returns public catalog fields only.

Validation:

```powershell
node scripts/test_web_promotions.mjs
node scripts/test_quantity_offers_client.mjs
node scripts/test_promotion_quantity_offers.mjs app_flutter/build/video-ad-validation
node scripts/gen_i18n.mjs
node scripts/check_flutter_integrity.mjs
```

The database test runs in an isolated PGlite database and does not modify the live project. Browser visual testing and the live RPC require the migration to be applied to the connected Supabase project.
