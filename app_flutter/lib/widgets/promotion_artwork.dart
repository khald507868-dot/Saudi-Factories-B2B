import 'package:flutter/painting.dart';

/// App-only landscape artwork for the published campaigns.
/// Match exact source revisions so replacements uploaded by the admin
/// automatically take precedence. Visibility and links still come from the
/// live promotions; these do not create standalone or permanent adverts.
ImageProvider<Object> promotionImageProvider(String sourceUrl) {
  const landscapeArtwork = {
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/113c9df0-2d9f-440d-8e6d-64d6f94c2548.png':
        'assets/promotions/cleaning-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/8936d669-60a2-4e9a-89ab-2fae15085cef.png':
        'assets/promotions/plastics-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/cb537159-8914-45fe-99e3-b9a4ef69ac68.png':
        'assets/promotions/packaging-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/89d24e90-f9eb-47be-8e96-87435af7f392.png':
        'assets/promotions/food-drinks-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/4287fb7c-4d67-41e6-a5b7-600b3e748713.png':
        'assets/promotions/clothing-textiles-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/c6d14284-7a8b-45bb-a5f4-4b96c7eb4dad.png':
        'assets/promotions/electronics-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/17fbad53-40f1-422c-b741-3034f9fc0910.png':
        'assets/promotions/personal-care-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/db4b5564-4a40-4b59-8c30-06c72e240aba.png':
        'assets/promotions/building-materials-landscape.png',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/93887d65-b2c1-4114-9225-8a62488f17ff.png':
        'assets/promotions/furniture-landscape.png',
  };
  final asset = landscapeArtwork[sourceUrl];
  return asset == null ? NetworkImage(sourceUrl) : AssetImage(asset);
}
