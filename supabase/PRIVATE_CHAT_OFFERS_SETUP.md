# Private chat offers

The web chat now lets an approved factory owner send a negotiated offer to the
customer in the active conversation. The owner selects an existing product,
quantity, unit price in SAR, validity (1–30 days), and optional notes. The product's
public price and tiers are never updated. A private offer is single-use; it does
not install a permanent customer price in `custom_prices` or alter the cart.

The recipient reviews all totals and confirms before an `awaiting_payment` order
is created. No payment is charged by accepting. The order appears in the existing
orders page for both parties. The customer can decline, and the sender can withdraw
an unaccepted offer. The server rejects expired offers and unavailable products.

## Database

Migration `migrations/20260914120000_private_chat_offers.sql` was applied to the
linked project on 2026-09-14. It adds a private RLS table and three authenticated
RPCs. It does not send real messages or create customer orders during deployment.

- Read access is limited to the offer's sender and recipient. Direct client
  insert/update/delete access is revoked, including attempts to edit prices.
- Creation derives the buyer and factory from the conversation and checks factory
  ownership, approval, account confirmation, and product ownership.
- Creation uses a draft idempotency key and a transaction advisory lock. Retrying
  the same request cannot send multiple messages. Changing its payload is rejected.
- Acceptance locks the offer and returns an existing order on retry. All order
  fields are copied from the server's offer snapshot; no client totals are accepted.
- Public product deletion prevents acceptance; accepted order snapshots survive.
- Realtime offer changes refresh the open chat. Returning to the window also
  refreshes statuses. The existing messages table handles unread counts.

Charges match the checkout RPC verified at deployment: SAR 30 shipping, 1% payment
fee on products plus shipping, then 15% VAT on products plus shipping plus fee.
They are shown before sending/accepting and frozen in the offer. If the platform's
pricing policy changes, update both checkout and offer calculations together.

## Validation

Run:

```
node scripts/test_private_offers.mjs <isolated-pglite-package-directory>
node scripts/test_private_offer_client.mjs
```

Database tests cover RLS and permissions, sender/buyer identity, cross-factory
products, invalid amounts, unconfirmed accounts, factory rejection, expiration,
withdrawal/decline, unchanged catalogue prices, frozen totals, and single-order
acceptance. Browser fixtures verify creation/retry, confirmation, successful order
rendering, sender-only controls, English/Arabic, and narrow screens without using
real customer data. `diagnostics/private_chat_offers_verify.sql` checks deployment
permissions and publication metadata without reading customer rows.

This change adds the complete offer UI to `web-messages.html`. Flutter translations
are generated from the shared dictionary; a native Flutter offer UI is not part of
this web-chat change.
