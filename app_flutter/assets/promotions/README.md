# App banner artwork

The nine `*-landscape.png` files are mobile landscape adaptations of the
existing published campaigns, approximately 2.5:1. Created with the built-in
image generation tool from each original portrait image. The website images
and database records are unchanged.

`lib/widgets/promotion_artwork.dart` matches the exact original image URL.
The campaign remains controlled by the live promotion record: hiding or
deleting it removes it from the app; replacing its source image uses the new
image instead of this bundled artwork. New campaigns retain their uploaded images.

Generation prompt for `personal-care-landscape.png` (45%):

The other eight prompts are recorded in [GENERATION_PROMPTS.md](GENERATION_PROMPTS.md).
The app displays these designed assets in a fixed 2.5:1 frame. Minor export
ratio differences trim only the background within the artwork's safe margins.

Edit the supplied vertical personal-care advertisement into a finished wide landscape mobile-app banner, exact aspect ratio 2.5:1, ideally 1600x640. Output only the banner artwork edge to edge, no device mockup or surrounding UI. Preserve the same warm peach travertine spa setting, dark forest green and gold palette, photorealistic unbranded cream pump bottle, sage green bottle, serum dropper, open cream jar, stacked soap bars, rolled towel, olive foliage and small white flowers. Rearrange rather than stretching or cropping the vertical image: arrange the complete products elegantly on low stone plinths in the left half, and set very legible big Arabic headline and discount in the right half, with CTA beneath. Exact text and no additional text: 'العناية الشخصية', 'خصم', '45%', 'تسوق الآن'. Keep all text, discount and CTA inside safe margins. Dark green headline, gold discount, dark green rounded CTA with white Arabic text and thin gold rim. Optimize type so easily legible at displayed size 430x172. Product silhouettes fully visible. Continuous peach background fills the entire wide canvas; no white side bars, no letterboxing, no missing text, no distorted objects, no extra logos. This is a recomposition of the same offer, preserve every meaning and the 45% discount.
