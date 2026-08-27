/* Cart/order client facade. Totals are calculated only in PostgreSQL RPCs. */
(function (root) {
  "use strict";
  function ready() {
    if (!root.sb || !root.SF_USER) return Promise.reject(new Error("يجب تسجيل الدخول للتسوق"));
    return Promise.resolve();
  }
  root.SFCommerce = {
    loadCart: function () {
      return ready().then(function () {
        return root.sb.rpc("get_or_create_cart");
      }).then(function (cartRes) {
        if (cartRes.error) throw cartRes.error;
        var cart = cartRes.data;
        return root.sb.from("cart_items")
          .select("id, product_id, quantity, products(id, factory_id, name, price, image, images, factories(name))")
          .eq("cart_id", cart.id)
          .order("created_at");
      }).then(function (itemsRes) {
        if (itemsRes.error) throw itemsRes.error;
        return itemsRes.data || [];
      });
    },
    addToCart: function (productId, quantity) {
      return ready().then(function () {
        return root.sb.rpc("add_to_cart", { p_product_id: Number(productId), p_quantity: Number(quantity || 1) });
      }).then(function (res) {
        if (res.error) throw res.error;
        return res.data;
      });
    },
    createOrder: function (factoryId) {
      return ready().then(function () {
        return root.sb.rpc("create_order_from_cart", {
          p_factory_id: Number(factoryId),
          p_idempotency_key: root.crypto && root.crypto.randomUUID ? root.crypto.randomUUID() : undefined
        });
      }).then(function (res) {
        if (res.error) throw res.error;
        return res.data;
      });
    }
  };
}(window));
